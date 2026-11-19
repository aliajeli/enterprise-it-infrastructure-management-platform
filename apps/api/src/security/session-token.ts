import { createHash, randomBytes } from "node:crypto";

export function issueSessionToken(): { token: string; tokenHash: string } {
  const token = randomBytes(32).toString("base64url");
  return {
    token,
    tokenHash: digestSessionToken(token),
  };
}

export function digestSessionToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function digestIdentifier(value: string): string {
  return createHash("sha256")
    .update(value.normalize("NFKC").trim().toLowerCase(), "utf8")
    .digest("hex");
}
