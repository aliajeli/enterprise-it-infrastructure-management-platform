import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import { describe, expect, it } from "vitest";
import { WindowsKeyringStorageClient } from "./windows-keyring-storage-client.js";
import { decodeKeyringFrame, encodeKeyringFrame, KeyringOpcode } from "./windows-keyring-protocol.js";

class FakeHelper extends EventEmitter {
  readonly stdin = new PassThrough();
  readonly stdout = new PassThrough();
  killed = false;
  ended = false;
  private transaction = false;

  constructor() {
    super();
    this.stdin.on("data", (frame: Buffer) => {
      try {
        const request = decodeKeyringFrame(frame);
        let response: Buffer;
        switch (request.opcode) {
          case KeyringOpcode.BEGIN_TRANSACTION:
            if (this.transaction) throw new Error("bad state");
            this.transaction = true;
            response = encodeKeyringFrame(KeyringOpcode.BEGIN_OK);
            break;
          case KeyringOpcode.READ_REGISTRY:
            if (!this.transaction) throw new Error("outside transaction");
            response = encodeKeyringFrame(KeyringOpcode.READ_RESULT, Buffer.from([1]));
            break;
          case KeyringOpcode.WRITE_REGISTRY_ATOMIC:
            if (!this.transaction) throw new Error("outside transaction");
            response = encodeKeyringFrame(KeyringOpcode.WRITE_OK);
            break;
          case KeyringOpcode.END_TRANSACTION:
            if (!this.transaction) throw new Error("bad end");
            this.transaction = false;
            this.ended = true;
            response = encodeKeyringFrame(KeyringOpcode.END_OK);
            break;
          default: throw new Error("unknown");
        }
        this.stdout.write(response);
        request.payload.fill(0);
      } catch {
        this.stdout.write(encodeKeyringFrame(KeyringOpcode.ERROR, Buffer.from([1])));
      }
    });
  }

  kill(): boolean {
    this.killed = true;
    this.emit("close", 0);
    return true;
  }
}

describe("Windows keyring storage helper transport", () => {
  it("keeps read and atomic write inside one helper transaction", async () => {
    const helper = new FakeHelper();
    const client = new WindowsKeyringStorageClient("C:\\Program Files\\EnterpriseIT\\keyring-helper.exe", "win32", () => helper);
    await client.withExclusiveLock(async () => {
      expect(await client.read()).toBeNull();
      await client.writeAtomic('{"formatVersion":1}');
    });
    expect(helper.killed).toBe(false);
    expect(helper.ended).toBe(true);
  });

  it("rejects access outside a transaction and nested transactions", async () => {
    const helper = new FakeHelper();
    const client = new WindowsKeyringStorageClient("C:\\Program Files\\EnterpriseIT\\keyring-helper.exe", "win32", () => helper);
    await expect(client.read()).rejects.toThrow("active transaction");
    await client.withExclusiveLock(async () => {
      await expect(client.withExclusiveLock(async () => undefined)).rejects.toThrow("Nested");
    });
  });

  it("validates helper paths with Windows path semantics on every host", () => {
    expect(() => new WindowsKeyringStorageClient("C:\\\\Program Files\\\\EnterpriseIT\\\\keyring-helper.exe", "win32", () => new FakeHelper())).not.toThrow();
    expect(() => new WindowsKeyringStorageClient("relative\\\\helper.exe", "win32")).toThrow("absolute");
  });

  it("fails closed on non-Windows platforms and relative helper paths", () => {
    expect(() => new WindowsKeyringStorageClient("/tmp/helper", "linux")).toThrow("only on Windows");
    expect(() => new WindowsKeyringStorageClient("helper.exe", "win32")).toThrow("absolute");
  });
});
