import { constants, createDecipheriv, generateKeyPairSync, privateDecrypt } from "node:crypto";
import { describe, expect, it } from "vitest";
import {
  CredentialEnvelopeV2DecryptionError,
  decryptCredentialSecretV2,
  encryptCredentialSecretV2,
  type CredentialEnvelopeV2Context,
  type LocalDataKeyProtector,
} from "./credential-vault-envelope-v2.js";

const context: CredentialEnvelopeV2Context = {
  installationId: "installation-01",
  credentialId: "credential-01",
  branchId: "branch-01",
  assetId: "asset-01",
  kind: "SNMPV3_AUTH_PRIV",
};
const rsa = generateKeyPairSync("rsa", { modulusLength: 3072, publicExponent: 0x10001 });
const weakRsa = generateKeyPairSync("rsa", { modulusLength: 2048, publicExponent: 0x10001 });

class TestProtector implements LocalDataKeyProtector {
  async protect(key: Buffer): Promise<Buffer> { return Buffer.from(key); }
  async unprotect(blob: Buffer): Promise<Buffer> { return Buffer.from(blob); }
}
const recoveryProvider = {
  async getCurrentPublicKey() {
    return { keyId: "recovery-2026-01", keyVersion: "dek-v1", publicKey: rsa.publicKey };
  },
};

function recoverForTest(envelope: Awaited<ReturnType<typeof encryptCredentialSecretV2>>): string {
  const key = privateDecrypt({
    key: rsa.privateKey,
    padding: constants.RSA_PKCS1_OAEP_PADDING,
    oaepHash: "sha256",
  }, Buffer.from(envelope.recoveryWrappedDataKey, "base64"));
  const associatedData = Buffer.from(JSON.stringify([
    "enterprise-it-credential", 2, context.installationId, context.credentialId,
    context.branchId, context.assetId, context.kind, envelope.keyVersion,
  ]), "utf8");
  const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(envelope.nonce, "base64"), { authTagLength: 16 });
  decipher.setAAD(associatedData);
  decipher.setAuthTag(Buffer.from(envelope.authTag, "base64"));
  const clear = Buffer.concat([
    decipher.update(Buffer.from(envelope.ciphertext, "base64")),
    decipher.final(),
  ]);
  key.fill(0);
  return clear.toString("utf8");
}

describe("credential vault dual-wrapper envelope v2", () => {
  it("round-trips with the local protector and independently unwraps the RSA recovery wrapper", async () => {
    const protector = new TestProtector();
    const envelope = await encryptCredentialSecretV2("router-secret", context, protector, recoveryProvider);
    expect(envelope.formatVersion).toBe(2);
    expect(envelope.installationId).toBe(context.installationId);
    expect(envelope.recoveryKeyId).toBe("recovery-2026-01");
    expect(await decryptCredentialSecretV2(envelope, context, protector)).toBe("router-secret");
    expect(recoverForTest(envelope)).toBe("router-secret");
  });

  it("generates a fresh DEK and nonce for each secret envelope", async () => {
    const protector = new TestProtector();
    const a = await encryptCredentialSecretV2("same", context, protector, recoveryProvider);
    const b = await encryptCredentialSecretV2("same", context, protector, recoveryProvider);
    expect(a.ciphertext).not.toBe(b.ciphertext);
    expect(a.nonce).not.toBe(b.nonce);
    expect(a.recoveryWrappedDataKey).not.toBe(b.recoveryWrappedDataKey);
  });

  it("rejects installation and context substitution and authenticated ciphertext tampering", async () => {
    const protector = new TestProtector();
    const envelope = await encryptCredentialSecretV2("secret", context, protector, recoveryProvider);
    await expect(decryptCredentialSecretV2(envelope, { ...context, installationId: "other" }, protector))
      .rejects.toBeInstanceOf(CredentialEnvelopeV2DecryptionError);
    await expect(decryptCredentialSecretV2(envelope, { ...context, assetId: "other" }, protector))
      .rejects.toBeInstanceOf(CredentialEnvelopeV2DecryptionError);
    await expect(decryptCredentialSecretV2({ ...envelope, ciphertext: Buffer.from("bad").toString("base64") }, context, protector))
      .rejects.toBeInstanceOf(CredentialEnvelopeV2DecryptionError);
  });

  it("rejects recovery public keys weaker than RSA-3072", async () => {
    const weakProvider = {
      async getCurrentPublicKey() {
        return { keyId: "weak", keyVersion: "dek-v1", publicKey: weakRsa.publicKey };
      },
    };
    await expect(encryptCredentialSecretV2("secret", context, new TestProtector(), weakProvider))
      .rejects.toThrow("Recovery public key must be RSA-3072.");
  });

  it("fails closed when the local protector refuses to unwrap the DPAPI wrapper", async () => {
    const protector = new TestProtector();
    const envelope = await encryptCredentialSecretV2("secret", context, protector, recoveryProvider);
    const denied: LocalDataKeyProtector = {
      async protect(key) { return Buffer.from(key); },
      async unprotect() { throw new Error("access denied"); },
    };
    await expect(decryptCredentialSecretV2(envelope, context, denied))
      .rejects.toBeInstanceOf(CredentialEnvelopeV2DecryptionError);
  });
});
