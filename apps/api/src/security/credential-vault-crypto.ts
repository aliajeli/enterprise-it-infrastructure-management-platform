import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
} from "node:crypto";

const ALGORITHM = "aes-256-gcm";
const KEY_BYTES = 32;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const MAX_SECRET_BYTES = 64 * 1024;
const FORMAT_VERSION = 1;

export interface CredentialContext {
  credentialId: string;
  branchId: string;
  assetId: string;
  kind: string;
}

export interface CredentialKey {
  version: string;
  key: Buffer;
}

/**
 * The platform-specific provider must return a 32-byte KEK protected at rest
 * by Windows DPAPI (service identity + machine scope) and implement recovery.
 * This interface intentionally has no environment-variable or file fallback.
 */
export interface CredentialKeyProvider {
  getCurrentKey(): Promise<CredentialKey>;
  getKey(version: string): Promise<Buffer | null>;
}

export interface EncryptedCredential {
  formatVersion: 1;
  keyVersion: string;
  ciphertext: string;
  nonce: string;
  authTag: string;
  wrappedDataKey: string;
  wrapNonce: string;
  wrapAuthTag: string;
}

export class CredentialDecryptionError extends Error {
  constructor() {
    super("Credential decryption failed.");
    this.name = "CredentialDecryptionError";
  }
}

function validateContext(context: CredentialContext): void {
  for (const [name, value] of Object.entries(context)) {
    if (typeof value !== "string" || value.length < 1 || value.length > 128 || [...value].some((character) => character.charCodeAt(0) <= 0x1f)) {
      throw new Error(`Invalid credential context: ${name}.`);
    }
  }
}

function validateKeyVersion(version: string): void {
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(version)) {
    throw new Error("Invalid credential key version.");
  }
}

function aad(context: CredentialContext, purpose: "data" | "data-key", keyVersion: string): Buffer {
  // Fixed-order serialization prevents caller-controlled property ordering.
  return Buffer.from(JSON.stringify([
    "enterprise-it-credential",
    FORMAT_VERSION,
    purpose,
    keyVersion,
    context.credentialId,
    context.branchId,
    context.assetId,
    context.kind,
  ]), "utf8");
}

function decodeBase64(value: string, expectedLength?: number): Buffer {
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    throw new CredentialDecryptionError();
  }
  const decoded = Buffer.from(value, "base64");
  if (decoded.toString("base64") !== value || (expectedLength !== undefined && decoded.length !== expectedLength)) {
    throw new CredentialDecryptionError();
  }
  return decoded;
}

function encryptAesGcm(plaintext: Buffer, key: Buffer, nonce: Buffer, associatedData: Buffer) {
  const cipher = createCipheriv(ALGORITHM, key, nonce, { authTagLength: TAG_BYTES });
  cipher.setAAD(associatedData);
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return { ciphertext, authTag: cipher.getAuthTag() };
}

function decryptAesGcm(ciphertext: Buffer, key: Buffer, nonce: Buffer, authTag: Buffer, associatedData: Buffer): Buffer {
  const decipher = createDecipheriv(ALGORITHM, key, nonce, { authTagLength: TAG_BYTES });
  decipher.setAAD(associatedData);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

export async function encryptCredentialSecret(
  plaintext: string,
  context: CredentialContext,
  keyProvider: CredentialKeyProvider,
): Promise<EncryptedCredential> {
  validateContext(context);
  if (typeof plaintext !== "string" || Buffer.byteLength(plaintext, "utf8") < 1 || Buffer.byteLength(plaintext, "utf8") > MAX_SECRET_BYTES) {
    throw new Error("Credential secret must contain between 1 byte and 64 KiB.");
  }

  const current = await keyProvider.getCurrentKey();
  validateKeyVersion(current.version);
  const kek = Buffer.from(current.key);
  const dataKey = randomBytes(KEY_BYTES);
  const dataNonce = randomBytes(NONCE_BYTES);
  const wrapNonce = randomBytes(NONCE_BYTES);
  const plaintextBytes = Buffer.from(plaintext, "utf8");

  try {
    if (kek.length !== KEY_BYTES) throw new Error("Credential KEK must be exactly 32 bytes.");
    const encrypted = encryptAesGcm(plaintextBytes, dataKey, dataNonce, aad(context, "data", current.version));
    const wrapped = encryptAesGcm(dataKey, kek, wrapNonce, aad(context, "data-key", current.version));
    return {
      formatVersion: FORMAT_VERSION,
      keyVersion: current.version,
      ciphertext: encrypted.ciphertext.toString("base64"),
      nonce: dataNonce.toString("base64"),
      authTag: encrypted.authTag.toString("base64"),
      wrappedDataKey: wrapped.ciphertext.toString("base64"),
      wrapNonce: wrapNonce.toString("base64"),
      wrapAuthTag: wrapped.authTag.toString("base64"),
    };
  } finally {
    kek.fill(0);
    dataKey.fill(0);
    plaintextBytes.fill(0);
  }
}

export async function decryptCredentialSecret(
  record: EncryptedCredential,
  context: CredentialContext,
  keyProvider: CredentialKeyProvider,
): Promise<string> {
  validateContext(context);
  let kek: Buffer | undefined;
  let dataKey: Buffer | undefined;
  let plaintext: Buffer | undefined;
  try {
    if (record.formatVersion !== FORMAT_VERSION) throw new CredentialDecryptionError();
    validateKeyVersion(record.keyVersion);
    const resolved = await keyProvider.getKey(record.keyVersion);
    if (!resolved) throw new CredentialDecryptionError();
    kek = Buffer.from(resolved);
    if (kek.length !== KEY_BYTES) throw new CredentialDecryptionError();
    const wrappedDataKey = decodeBase64(record.wrappedDataKey, KEY_BYTES);
    const wrapNonce = decodeBase64(record.wrapNonce, NONCE_BYTES);
    const wrapAuthTag = decodeBase64(record.wrapAuthTag, TAG_BYTES);
    dataKey = decryptAesGcm(wrappedDataKey, kek, wrapNonce, wrapAuthTag, aad(context, "data-key", record.keyVersion));
    if (dataKey.length !== KEY_BYTES) throw new CredentialDecryptionError();
    const ciphertext = decodeBase64(record.ciphertext);
    const nonce = decodeBase64(record.nonce, NONCE_BYTES);
    const authTag = decodeBase64(record.authTag, TAG_BYTES);
    plaintext = decryptAesGcm(ciphertext, dataKey, nonce, authTag, aad(context, "data", record.keyVersion));
    if (plaintext.length < 1 || plaintext.length > MAX_SECRET_BYTES) throw new CredentialDecryptionError();
    return plaintext.toString("utf8");
  } catch {
    throw new CredentialDecryptionError();
  } finally {
    kek?.fill(0);
    dataKey?.fill(0);
    plaintext?.fill(0);
  }
}
