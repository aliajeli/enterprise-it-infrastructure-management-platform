import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { WindowsDpapiProtector } from "./windows-dpapi-protector.js";

const helperPath = resolve(
  process.cwd(),
  "windows/dpapi-helper/bin/Release/net10.0-windows/CredentialVault.DpapiHelper.exe",
);
const canRunWindowsHelper = process.platform === "win32" && existsSync(helperPath);

describe("Windows DPAPI helper boundary", () => {
  it("rejects non-Windows execution and invalid key lengths", async () => {
    const protector = new WindowsDpapiProtector(
      "C:\\CredentialVault.DpapiHelper.exe",
      "a2c4b6d8-1234-4abc-8def-1234567890ab",
      "linux",
    );
    await expect(protector.protect(Buffer.alloc(32))).rejects.toThrow("only on Windows");
    const windows = new WindowsDpapiProtector(
      "C:\\CredentialVault.DpapiHelper.exe",
      "a2c4b6d8-1234-4abc-8def-1234567890ab",
      "win32",
    );
    await expect(windows.protect(Buffer.alloc(16))).rejects.toThrow("exactly one 32-byte key");
  });

  it.skipIf(!canRunWindowsHelper)("protects and unprotects a KEK, and binds it to installation identity", async () => {
    const installationId = "a2c4b6d8-1234-4abc-8def-1234567890ab";
    const key = Buffer.alloc(32, 0x5a);
    const protector = new WindowsDpapiProtector(helperPath, installationId);
    const protectedKey = await protector.protect(key);
    expect(protectedKey).not.toEqual(key);
    const restored = await protector.unprotect(protectedKey);
    expect(restored).toEqual(key);

    const otherInstallation = new WindowsDpapiProtector(
      helperPath,
      "b3d5c7e9-2345-4bcd-9efa-2345678901bc",
    );
    await expect(otherInstallation.unprotect(protectedKey)).rejects.toThrow("DPAPI helper failed.");

    key.fill(0);
    restored.fill(0);
    protectedKey.fill(0);
  });
});
