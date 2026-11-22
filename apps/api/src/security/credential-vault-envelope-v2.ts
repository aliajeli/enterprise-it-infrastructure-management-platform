import {
  constants,
  createCipheriv,
  createDecipheriv,
  createHash,
  createPublicKey,
  KeyObject,
  publicEncrypt,
  randomBytes,
  type KeyObject as KeyObjectType,
} from "node:crypto";

const KEY_BYTES = 32;
const NONCE_BYTES = 12;
const TAG_BYTES = 16;
const MAX_SECRET_BYTES = 64 * 1024;
const MAX_DPAPI_BLOB_BYTES = 16 * 1024;
const RSA_WRAPPED_KEY_BYTES = 384;

export interface CredentialEnvelopeV2Context {
  installationId: string;
  credentialId: string;
  branchId: string;
  assetId: string;
  kind: string;
}

export interface CredentialEnvelopeV2 {
  formatVersion: 2;
  installationId: string;
  keyVersion: string;
  recoveryKeyId: string;
  ciphertext: string;
  nonce: string;
  authTag: string;
  dpapiWrappedDataKey: string;
  recoveryWrappedDataKey: string;
}

export interface LocalDataKeyProtector {
  protect(dataKey: Buffer, context: CredentialEnvelopeV2Context): Promise<Buffer>;
  unprotect(protectedDataKey: Buffer, context: CredentialEnvelopeV2Context): Promise<Buffer>;
}

export interface CredentialRecoveryPublicKeyProvider {
  getCurrentPublicKey(): Promise<{
    keyId: string;
    keyVersion: string;
    publicKey: string | Buffer | KeyObjectType;
  }>;
}

export class CredentialEnvelopeV2DecryptionError extends Error {
  constructor() {
    super("Credential decryption failed.");
    this.name = "CredentialEnvelopeV2DecryptionError";
  }
}

function validateIdentifier(name: string, value: string): void {
  if (typeof value !== "string" || value.length < 1 || value.length > 128 ||
      [...value].some((character) => character.charCodeAt(0) <= 0x1f)) {
    throw new Error("Invalid credential envelope context: " + name + ".");
  }
}

function validateContext(context: CredentialEnvelopeV2Context): void {
  for (const [name, value] of Object.entries(context)) validateIdentifier(name, value);
}

function validateVersion(value: string): void {
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(value)) throw new Error("Invalid credential key version.");
}

function validateKeyId(value: string): void {
  if (!/^[A-Za-z0-9._-]{1,128}$/.test(value)) throw new Error("Invalid recovery key identifier.");
}

function sha256(value: Buffer): Buffer {
  return createHash("sha256").update(value).digest();
}

function aad(
  context: CredentialEnvelopeV2Context,
  keyVersion: string,
  recoveryKeyId: string,
  dpapiWrapped: Buffer,
  recoveryWrapped: Buffer,
): Buffer {
  return Buffer.from(JSON.stringify([
    "enterprise-it-credential",
    2,
    context.installationId,
    context.credentialId,
    context.branchId,
    context.assetId,
    context.kind,
    keyVersion,
    recoveryKeyId,
    sha256(dpapiWrapped).toString("hex"),
    sha256(recoveryWrapped).toString("hex"),
  ]), "utf8");
}

function decodeBase64(value: string, expectedLength?: number, maximumLength?: number): Buffer {
  if (typeof value !== "string") throw new CredentialEnvelopeV2DecryptionError();
  const maximumEncodedLength = expectedLength !== undefined
    ? Math.ceil(expectedLength / 3) * 4
    : maximumLength !== undefined
      ? Math.ceil(maximumLength / 3) * 4
      : 0;
  if (maximumEncodedLength > 0 && value.length > maximumEncodedLength) {
    throw new CredentialEnvelopeV2DecryptionError();
  }
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    throw new CredentialEnvelopeV2DecryptionError();
  }
  const decoded = Buffer.from(value, "base64");
  if (decoded.toString("base64") !== value ||
      (expectedLength !== undefined && decoded.length !== expectedLength) ||
      (maximumLength !== undefined && decoded.length > maximumLength)) {
    decoded.fill(0);
    throw new CredentialEnvelopeV2DecryptionError();
  }
  return decoded;
}

function encryptAesGcm(plaintext: Buffer, key: Buffer, nonce: Buffer, associatedData: Buffer) {
  const cipher = createCipheriv("aes-256-gcm", key, nonce, { authTagLength: TAG_BYTES });
  cipher.setAAD(associatedData);
  return {
    ciphertext: Buffer.concat([cipher.update(plaintext), cipher.final()]),
    authTag: cipher.getAuthTag(),
  };
}

function decryptAesGcm(ciphertext: Buffer, key: Buffer, nonce: Buffer, authTag: Buffer, associatedData: Buffer): Buffer {
  const decipher = createDecipheriv("aes-256-gcm", key, nonce, { authTagLength: TAG_BYTES });
  decipher.setAAD(associatedData);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]);
}

function validatedPublicKey(material: string | Buffer | KeyObjectType): KeyObjectType {
  let key: KeyObjectType;
  try {
    if (material instanceof KeyObject) {
      if (material.type !== "public") throw new Error("Expected a public key.");
      key = material;
    } else {
      key = createPublicKey(material);
    }
  } catch {
    throw new Error("Recovery public key is invalid.");
  }
  if (key.asymmetricKeyType !== "rsa" || key.asymmetricKeyDetails?.modulusLength !== 3072) {
    throw new Error("Recovery public key must be RSA-3072.");
  }
  return key;
}

export async function encryptCredentialSecretV2(
  plaintext: string,
  context: CredentialEnvelopeV2Context,
  localProtector: LocalDataKeyProtector,
  recoveryProvider: CredentialRecoveryPublicKeyProvider,
): Promise<CredentialEnvelopeV2> {
  validateContext(context);
  if (typeof plaintext !== "string" || Buffer.byteLength(plaintext, "utf8") < 1 ||
      Buffer.byteLength(plaintext, "utf8") > MAX_SECRET_BYTES) {
    throw new Error("Credential secret must contain between 1 byte and 64 KiB.");
  }

  const current = await recoveryProvider.getCurrentPublicKey();
  validateVersion(current.keyVersion);
  validateKeyId(current.keyId);
  const publicKey = validatedPublicKey(current.publicKey);
  const dataKey = randomBytes(KEY_BYTES);
  const dataNonce = randomBytes(NONCE_BYTES);
  const plaintextBytes = Buffer.from(plaintext, "utf8");
  let dpapiWrapped: Buffer | undefined;
  let recoveryWrapped: Buffer | undefined;

  try {
    dpapiWrapped = await localProtector.protect(dataKey, context);
    if (!Buffer.isBuffer(dpapiWrapped) || dpapiWrapped.length < 1 ||
        dpapiWrapped.length > MAX_DPAPI_BLOB_BYTES) {
      throw new Error("DPAPI provider returned an invalid protected key blob.");
    }
    recoveryWrapped = publicEncrypt({
      key: publicKey,
      padding: constants.RSA_PKCS1_OAEP_PADDING,
      oaepHash: "sha256",
    }, dataKey);
    if (recoveryWrapped.length !== RSA_WRAPPED_KEY_BYTES) {
      throw new Error("Unexpected RSA recovery wrapper length.");
    }
    const encrypted = encryptAesGcm(
      plaintextBytes,
      dataKey,
      dataNonce,
      aad(context, current.keyVersion, current.keyId, dpapiWrapped, recoveryWrapped),
    );
    return {
      formatVersion: 2,
      installationId: context.installationId,
      keyVersion: current.keyVersion,
      recoveryKeyId: current.keyId,
      ciphertext: encrypted.ciphertext.toString("base64"),
      nonce: dataNonce.toString("base64"),
      authTag: encrypted.authTag.toString("base64"),
      dpapiWrappedDataKey: dpapiWrapped.toString("base64"),
      recoveryWrappedDataKey: recoveryWrapped.toString("base64"),
    };
  } finally {
    dataKey.fill(0);
    plaintextBytes.fill(0);
    dpapiWrapped?.fill(0);
    recoveryWrapped?.fill(0);
  }
}

/** Service-path decryption: intentionally accepts no recovery private key. */
export async function decryptCredentialSecretV2(
  record: CredentialEnvelopeV2,
  context: CredentialEnvelopeV2Context,
  localProtector: LocalDataKeyProtector,
): Promise<string> {
  validateContext(context);
  let dpapiWrapped: Buffer | undefined;
  let recoveryWrapped: Buffer | undefined;
  let dataKey: Buffer | undefined;
  let ciphertext: Buffer | undefined;
  let nonce: Buffer | undefined;
  let authTag: Buffer | undefined;
  let plaintext: Buffer | undefined;

  try {
    if (record.formatVersion !== 2 || record.installationId !== context.installationId) {
      throw new CredentialEnvelopeV2DecryptionError();
    }
    validateVersion(record.keyVersion);
    validateKeyId(record.recoveryKeyId);
    dpapiWrapped = decodeBase64(record.dpapiWrappedDataKey, undefined, MAX_DPAPI_BLOB_BYTES);
    if (dpapiWrapped.length < 1) throw new CredentialEnvelopeV2DecryptionError();
    recoveryWrapped = decodeBase64(record.recoveryWrappedDataKey, RSA_WRAPPED_KEY_BYTES);
    dataKey = await localProtector.unprotect(dpapiWrapped, context);
    if (!Buffer.isBuffer(dataKey) || dataKey.length !== KEY_BYTES) {
      throw new CredentialEnvelopeV2DecryptionError();
    }
    ciphertext = decodeBase64(record.ciphertext, undefined, MAX_SECRET_BYTES);
    if (ciphertext.length < 1) throw new CredentialEnvelopeV2DecryptionError();
    nonce = decodeBase64(record.nonce, NONCE_BYTES);
    authTag = decodeBase64(record.authTag, TAG_BYTES);
    plaintext = decryptAesGcm(
      ciphertext,
      dataKey,
      nonce,
      authTag,
      aad(context, record.keyVersion, record.recoveryKeyId, dpapiWrapped, recoveryWrapped),
    );
    if (plaintext.length < 1 || plaintext.length > MAX_SECRET_BYTES) {
      throw new CredentialEnvelopeV2DecryptionError();
    }
    return plaintext.toString("utf8");
  } catch {
    throw new CredentialEnvelopeV2DecryptionError();
  } finally {
    dpapiWrapped?.fill(0);
    recoveryWrapped?.fill(0);
    dataKey?.fill(0);
    ciphertext?.fill(0);
    nonce?.fill(0);
    authTag?.fill(0);
    plaintext?.fill(0);
  }
}
