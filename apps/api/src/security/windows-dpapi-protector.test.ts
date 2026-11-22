import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it, vi } from "vitest";
import { WindowsDpapiProtector } from "./windows-dpapi-protector.js";

const helperPath = resolve(
  process.cwd(),
  "windows/dpapi-helper/bin/Release/net10.0-windows/CredentialVault.DpapiHelper.exe",
);
const canRunWindowsHelper = process.platform === "win32" && existsSync(helperPath);
const context = {
  installationId: "a2c4b6d8-1234-4abc-8def-1234567890ab",
  credentialId: "credential-01", branchId: "branch-01", assetId: "asset-01", kind: "SNMPV3_AUTH_PRIV",
};

describe("Windows DPAPI helper boundary", () => {
  it("rejects non-Windows execution and invalid key lengths", async () => {
    const protector = new WindowsDpapiProtector(
      resolve(process.cwd(), "fake-dpapi-helper.exe"),
      "a2c4b6d8-1234-4abc-8def-1234567890ab",
      "linux",
    );
    await expect(protector.protect(Buffer.alloc(32), context)).rejects.toThrow("only on Windows");
    const windows = new WindowsDpapiProtector(
      resolve(process.cwd(), "fake-dpapi-helper.exe"),
      "a2c4b6d8-1234-4abc-8def-1234567890ab",
      "win32",
    );
    await expect(windows.protect(Buffer.alloc(16), context)).rejects.toThrow("Invalid DPAPI payload length.");
  });

  it.skipIf(!canRunWindowsHelper || process.env.CI !== "true")(
    "fails closed when the process token has no dedicated service SID",
    async () => {
      const key = Buffer.alloc(32, 0x5a);
      const protector = new WindowsDpapiProtector(
        helperPath,
        "a2c4b6d8-1234-4abc-8def-1234567890ab",
      );
      await expect(protector.protect(key, context)).rejects.toThrow("DPAPI helper failed.");
      key.fill(0);
    },
  );

  it.skipIf(
    !canRunWindowsHelper || process.env.RUN_PROVISIONED_DPAPI_INTEGRATION !== "1",
  )("protects and unprotects a KEK under the provisioned service SID", async () => {
    const installationId = "a2c4b6d8-1234-4abc-8def-1234567890ab";
    const key = Buffer.alloc(32, 0x5a);
    const protector = new WindowsDpapiProtector(helperPath, installationId);
    const protectedKey = await protector.protect(key, context);
    expect(protectedKey).not.toEqual(key);
    const restored = await protector.unprotect(protectedKey, context);
    expect(restored).toEqual(key);
    key.fill(0);
    restored.fill(0);
    protectedKey.fill(0);
  });

  it("rejects mismatched installation context before starting the helper", async () => {
    const spawnProcess = vi.fn();
    const protector = new WindowsDpapiProtector(
      resolve(process.cwd(), "fake-dpapi-helper.exe"),
      context.installationId,
      "win32",
      spawnProcess as never,
    );
    const wrongContext = { ...context, installationId: "b3d5c7e9-2345-4bcd-8efa-2345678901bc" };
    const key = Buffer.alloc(32, 0x5a);
    const blob = Buffer.from([1, 2, 3, 4]);
    await expect(protector.protect(key, wrongContext)).rejects.toThrow("DPAPI installation context mismatch.");
    await expect(protector.unprotect(blob, wrongContext)).rejects.toThrow("DPAPI installation context mismatch.");
    expect(spawnProcess).not.toHaveBeenCalled();
    key.fill(0);
    blob.fill(0);
  });

});
