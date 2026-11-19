import { describe, expect, it } from "vitest";
import { CredentialKeyring, type CredentialKeyringStorage, type DpapiKeyProtector } from "./credential-keyring.js";

class MemoryStorage implements CredentialKeyringStorage {
  value: string | null = null;
  private tail: Promise<void> = Promise.resolve();
  async withExclusiveLock<T>(operation: () => Promise<T>): Promise<T> {
    const previous = this.tail;
    let release!: () => void;
    this.tail = new Promise<void>((resolve) => { release = resolve; });
    await previous;
    try { return await operation(); } finally { release(); }
  }
  async read() { return this.value; }
  async writeAtomic(contents: string) { this.value = contents; }
}
class TestProtector implements DpapiKeyProtector {
  async protect(key: Buffer) { return Buffer.concat([Buffer.from("test:"), key]); }
  async unprotect(blob: Buffer) {
    if (blob.length !== 37 || blob.subarray(0, 5).toString() !== "test:") throw new Error("protected blob rejected");
    return Buffer.from(blob.subarray(5));
  }
}

describe("credential keyring core", () => {
  it("initializes idempotently and returns caller-owned key buffers", async () => {
    const storage = new MemoryStorage();
    const ring = new CredentialKeyring(storage, new TestProtector());
    await ring.initialize();
    const first = storage.value;
    await ring.initialize();
    expect(storage.value).toBe(first);
    const key = await ring.getCurrentKey();
    expect(key.version).toBe("k000001");
    expect(key.key).toHaveLength(32);
    key.key.fill(0);
  });
  it("rotates while retaining old versions", async () => {
    const ring = new CredentialKeyring(new MemoryStorage(), new TestProtector());
    await ring.initialize();
    const original = await ring.getCurrentKey();
    const oldBytes = Buffer.from(original.key);
    original.key.fill(0);
    expect(await ring.rotate()).toBe("k000002");
    const old = await ring.getKey("k000001");
    const current = await ring.getCurrentKey();
    expect(old).toEqual(oldBytes);
    expect(current.version).toBe("k000002");
    old?.fill(0); current.key.fill(0); oldBytes.fill(0);
  });
  it("serializes concurrent rotations", async () => {
    const storage = new MemoryStorage();
    const ring = new CredentialKeyring(storage, new TestProtector());
    await ring.initialize();
    const versions = await Promise.all([ring.rotate(), ring.rotate()]);
    expect(versions.sort()).toEqual(["k000002", "k000003"]);
  });
  it("fails closed for missing and malformed registries", async () => {
    const storage = new MemoryStorage();
    const ring = new CredentialKeyring(storage, new TestProtector());
    await expect(ring.getCurrentKey()).rejects.toThrow("not been initialized");
    storage.value = JSON.stringify({ formatVersion: 1, activeVersion: "k000001", keys: [] });
    await expect(ring.getCurrentKey()).rejects.toThrow("invalid or corrupted");
  });
  it("does not discard old versions when capacity is reached", async () => {
    const ring = new CredentialKeyring(new MemoryStorage(), new TestProtector());
    await ring.initialize();
    for (let index = 0; index < 63; index += 1) await ring.rotate();
    await expect(ring.rotate()).rejects.toThrow("keyring is full");
  });
});
