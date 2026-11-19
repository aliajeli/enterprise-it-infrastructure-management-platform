import {
  Algorithm,
  hash,
  verify,
} from "@node-rs/argon2";

const ARGON2_OPTIONS = {
  algorithm: Algorithm.Argon2id,
  memoryCost: 19_456,
  timeCost: 2,
  parallelism: 1,
  outputLen: 32,
  saltLen: 16,
};

export function normalizeUsername(value: string): string | null {
  const normalized = value.normalize("NFKC").trim().toLowerCase();
  return /^[a-z0-9][a-z0-9._-]{2,63}$/.test(normalized)
    ? normalized
    : null;
}

export function isValidPassword(value: string): boolean {
  const length = Array.from(value).length;
  return (
    length >= 14 &&
    length <= 128 &&
    Buffer.byteLength(value, "utf8") <= 1_024 &&
    !/[\u0000-\u001f\u007f]/u.test(value)
  );
}

export async function hashPassword(password: string): Promise<string> {
  if (!isValidPassword(password)) {
    throw new Error("Password does not meet the platform password policy.");
  }

  return hash(password, ARGON2_OPTIONS);
}

export async function verifyPassword(
  password: string,
  encodedHash: string,
): Promise<boolean> {
  try {
    return await verify(encodedHash, password);
  } catch {
    return false;
  }
}
