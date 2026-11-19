import { describe, expect, it } from "vitest";
import {
  CredentialDecryptionError,
  decryptCredentialSecret,
  encryptCredentialSecret,
  type CredentialKeyProvider,
} from "./credential-vault-crypto.js";

const context = {
  credentialId: "credential-1",
  branchId: "branch-1",
  assetId: "asset-1",
  kind: "SNMPV3_AUTH_PRIV",
};

class MemoryKeyProvider implements CredentialKeyProvider {
  constructor(private readonly keys: Map<string, Buffer>, private currentVersion: string) {}
  async getCurrentKey() {
    const key = this.keys.get(this.currentVersion);
    if (!key) throw new Error("No active test key.");
    return { version: this.currentVersion, key: Buffer.from(key) };
  }
  async getKey(version: string) {
    const key = this.keys.get(version);
    return key ? Buffer.from(key) : null;
  }
  rotate(version: string, key: Buffer) {
    this.keys.set(version, Buffer.from(key));
    this.currentVersion = version;
  }
}

function provider() {
  return new MemoryKeyProvider(new Map([["test-kek-v1", Buffer.alloc(32, 7)]]), "test-kek-v1");
}

describe("credential vault cryptographic envelope", () => {
  it("round-trips secrets while storing only authenticated ciphertext", async () => {
    const keys = provider();
    const secret = "router-super-secret";
    const encrypted = await encryptCredentialSecret(secret, context, keys);
    expect(encrypted.formatVersion).toBe(1);
    expect(encrypted.ciphertext).not.toContain(secret);
    expect(await decryptCredentialSecret(encrypted, context, keys)).toBe(secret);
  });

  it("uses fresh data keys and nonces for every encryption", async () => {
    const keys = provider();
    const first = await encryptCredentialSecret("same-secret", context, keys);
    const second = await encryptCredentialSecret("same-secret", context, keys);
    expect(first.ciphertext).not.toBe(second.ciphertext);
    expect(first.nonce).not.toBe(second.nonce);
    expect(first.wrappedDataKey).not.toBe(second.wrappedDataKey);
  });

  it("authenticates the credential identity and refuses cross-asset substitution", async () => {
    const keys = provider();
    const encrypted = await encryptCredentialSecret("secret", context, keys);
    await expect(decryptCredentialSecret(encrypted, { ...context, assetId: "asset-2" }, keys))
      .rejects.toBeInstanceOf(CredentialDecryptionError);
  });

  it("rejects ciphertext, tag and wrapped-key tampering", async () => {
    const keys = provider();
    const encrypted = await encryptCredentialSecret("secret", context, keys);
    const tampered = { ...encrypted, ciphertext: Buffer.from("attacker").toString("base64") };
    await expect(decryptCredentialSecret(tampered, context, keys)).rejects.toBeInstanceOf(CredentialDecryptionError);
    const badTag = { ...encrypted, authTag: Buffer.alloc(16).toString("base64") };
    await expect(decryptCredentialSecret(badTag, context, keys)).rejects.toBeInstanceOf(CredentialDecryptionError);
    const badWrap = { ...encrypted, wrappedDataKey: Buffer.alloc(32, 1).toString("base64") };
    await expect(decryptCredentialSecret(badWrap, context, keys)).rejects.toBeInstanceOf(CredentialDecryptionError);
  });

  it("retains old key versions for decryption during rotation", async () => {
    const keys = provider();
    const encrypted = await encryptCredentialSecret("secret", context, keys);
    keys.rotate("test-kek-v2", Buffer.alloc(32, 9));
    expect(await decryptCredentialSecret(encrypted, context, keys)).toBe("secret");
    const fresh = await encryptCredentialSecret("new-secret", context, keys);
    expect(fresh.keyVersion).toBe("test-kek-v2");
  });

  it("fails closed when the referenced key version is unavailable", async () => {
    const keys = provider();
    const encrypted = await encryptCredentialSecret("secret", context, keys);
    const empty = new MemoryKeyProvider(new Map(), "missing");
    await expect(decryptCredentialSecret(encrypted, context, empty)).rejects.toBeInstanceOf(CredentialDecryptionError);
  });

  it("accepts ordinary identifiers and rejects control characters in context", async () => {
    const keys = provider();
    await expect(encryptCredentialSecret("secret", context, keys)).resolves.toMatchObject({ formatVersion: 1 });
    await expect(encryptCredentialSecret("secret", { ...context, assetId: "asset-\\u0001" }, keys))
      .rejects.toThrow("Invalid credential context: assetId.");
  });

  it("rejects empty and oversized secrets before encryption", async () => {
    const keys = provider();
    await expect(encryptCredentialSecret("", context, keys)).rejects.toThrow();
    await expect(encryptCredentialSecret("x".repeat(65 * 1024), context, keys)).rejects.toThrow();
  });
});