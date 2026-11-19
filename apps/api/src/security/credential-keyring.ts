import { randomBytes } from "node:crypto";
import type { CredentialKey, CredentialKeyProvider } from "./credential-vault-crypto.js";

const KEY_BYTES = 32;
const MAX_KEYS = 64;
const FORMAT_VERSION = 1 as const;
const VERSION_PATTERN = /^k[0-9]{6}$/;

export interface DpapiKeyProtector {
  protect(key: Buffer): Promise<Buffer>;
  unprotect(protectedKey: Buffer): Promise<Buffer>;
}

/**
 * A production storage adapter must implement a process-safe exclusive lock,
 * durable same-directory atomic replacement, and strict Windows owner/DACL
 * verification before every read/write. No adapter is registered yet.
 */
export interface CredentialKeyringStorage {
  withExclusiveLock<T>(operation: () => Promise<T>): Promise<T>;
  read(): Promise<string | null>;
  writeAtomic(contents: string): Promise<void>;
}

interface KeyEntry {
  version: string;
  protectedKey: string;
  createdAt: string;
}
interface KeyringDocument {
  formatVersion: 1;
  activeVersion: string;
  keys: KeyEntry[];
}

function validateDocument(value: unknown): KeyringDocument {
  if (!value || typeof value !== "object") throw new Error("invalid");
  const doc = value as Partial<KeyringDocument>;
  if (doc.formatVersion !== FORMAT_VERSION || typeof doc.activeVersion !== "string" ||
      !Array.isArray(doc.keys) || doc.keys.length < 1 || doc.keys.length > MAX_KEYS) throw new Error("invalid");
  const versions = new Set<string>();
  for (const entry of doc.keys) {
    if (!entry || typeof entry.version !== "string" || !VERSION_PATTERN.test(entry.version) ||
        typeof entry.protectedKey !== "string" ||
        !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(entry.protectedKey) ||
        typeof entry.createdAt !== "string" || !Number.isFinite(Date.parse(entry.createdAt)) ||
        versions.has(entry.version)) throw new Error("invalid");
    const blob = Buffer.from(entry.protectedKey, "base64");
    const valid = blob.toString("base64") === entry.protectedKey && blob.length >= KEY_BYTES;
    blob.fill(0);
    if (!valid) throw new Error("invalid");
    versions.add(entry.version);
  }
  if (!versions.has(doc.activeVersion)) throw new Error("invalid");
  return doc as KeyringDocument;
}

export class CredentialKeyring implements CredentialKeyProvider {
  constructor(
    private readonly storage: CredentialKeyringStorage,
    private readonly protector: DpapiKeyProtector,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async initialize(): Promise<void> {
    await this.storage.withExclusiveLock(async () => {
      const existing = await this.storage.read();
      if (existing !== null) {
        try { validateDocument(JSON.parse(existing) as unknown); }
        catch { throw new Error("Credential keyring is invalid or corrupted."); }
        return;
      }
      const key = randomBytes(KEY_BYTES);
      let protectedKey: Buffer | undefined;
      try {
        protectedKey = await this.protector.protect(key);
        if (protectedKey.length < KEY_BYTES) throw new Error("DPAPI returned an invalid protected key.");
        const document: KeyringDocument = {
          formatVersion: FORMAT_VERSION,
          activeVersion: "k000001",
          keys: [{ version: "k000001", protectedKey: protectedKey.toString("base64"), createdAt: this.now().toISOString() }],
        };
        await this.storage.writeAtomic(JSON.stringify(document));
        const persisted = await this.readDocument();
        const entry = persisted.keys.find((item) => item.version === persisted.activeVersion);
        if (!entry) throw new Error("Credential keyring verification failed.");
        const restored = await this.unprotectEntry(entry);
        try {
          if (!restored.equals(key)) throw new Error("Credential keyring verification failed.");
        } finally { restored.fill(0); }
      } finally {
        key.fill(0);
        protectedKey?.fill(0);
      }
    });
  }

  async getCurrentKey(): Promise<CredentialKey> {
    return this.storage.withExclusiveLock(async () => {
      const document = await this.readDocument();
      const entry = document.keys.find((item) => item.version === document.activeVersion);
      if (!entry) throw new Error("Credential keyring active key is missing.");
      return { version: entry.version, key: await this.unprotectEntry(entry) };
    });
  }

  async getKey(version: string): Promise<Buffer | null> {
    if (!VERSION_PATTERN.test(version)) return null;
    return this.storage.withExclusiveLock(async () => {
      const document = await this.readDocument();
      const entry = document.keys.find((item) => item.version === version);
      return entry ? this.unprotectEntry(entry) : null;
    });
  }

  async rotate(): Promise<string> {
    return this.storage.withExclusiveLock(async () => {
      const document = await this.readDocument();
      if (document.keys.length >= MAX_KEYS) {
        throw new Error("Credential keyring is full; referenced versions must be retired through a separate audited operation.");
      }
      const maxVersion = document.keys.reduce((max, entry) => Math.max(max, Number(entry.version.slice(1))), 0);
      if (maxVersion >= 999999) throw new Error("Credential key version space exhausted.");
      const version = `k${String(maxVersion + 1).padStart(6, "0")}`;
      const key = randomBytes(KEY_BYTES);
      let protectedKey: Buffer | undefined;
      try {
        protectedKey = await this.protector.protect(key);
        if (protectedKey.length < KEY_BYTES) throw new Error("DPAPI returned an invalid protected key.");
        const next: KeyringDocument = {
          formatVersion: FORMAT_VERSION,
          activeVersion: version,
          keys: [...document.keys, { version, protectedKey: protectedKey.toString("base64"), createdAt: this.now().toISOString() }],
        };
        await this.storage.writeAtomic(JSON.stringify(next));
        const persisted = await this.readDocument();
        if (persisted.activeVersion !== version) throw new Error("Credential key rotation persistence verification failed.");
        const entry = persisted.keys.find((item) => item.version === version);
        if (!entry) throw new Error("Credential key rotation persistence verification failed.");
        const restored = await this.unprotectEntry(entry);
        try {
          if (!restored.equals(key)) throw new Error("Credential key rotation verification failed.");
        } finally { restored.fill(0); }
        return version;
      } finally {
        key.fill(0);
        protectedKey?.fill(0);
      }
    });
  }

  private async readDocument(): Promise<KeyringDocument> {
    const raw = await this.storage.read();
    if (raw === null) throw new Error("Credential keyring has not been initialized.");
    try { return validateDocument(JSON.parse(raw) as unknown); }
    catch { throw new Error("Credential keyring is invalid or corrupted."); }
  }

  private async unprotectEntry(entry: KeyEntry): Promise<Buffer> {
    const protectedKey = Buffer.from(entry.protectedKey, "base64");
    try {
      const key = await this.protector.unprotect(protectedKey);
      if (key.length !== KEY_BYTES) {
        key.fill(0);
        throw new Error("Credential keyring key has an invalid length.");
      }
      return key;
    } finally { protectedKey.fill(0); }
  }
}
