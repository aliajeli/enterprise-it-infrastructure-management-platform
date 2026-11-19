import { describe, expect, it } from "vitest";
import {
  hashPassword,
  isValidPassword,
  normalizeUsername,
  verifyPassword,
} from "./credentials.js";

describe("credential primitives", () => {
  it("normalizes usernames consistently and rejects unsupported characters", () => {
    expect(normalizeUsername("  ADMIN.User ")).toBe("admin.user");
    expect(normalizeUsername("Ａｄｍｉｎ")).toBe("admin");
    expect(normalizeUsername("ab")).toBeNull();
    expect(normalizeUsername("admin/../root")).toBeNull();
  });

  it("enforces a passphrase-friendly password length and input policy", () => {
    expect(isValidPassword("Correct Horse Battery Staple")).toBe(true);
    expect(isValidPassword("short")).toBe(false);
    expect(isValidPassword("password\nwith-control")).toBe(false);
    expect(isValidPassword("x".repeat(129))).toBe(false);
  });

  it("hashes passwords with Argon2id and verifies without exposing plaintext", async () => {
    const password = "Correct Horse Battery Staple 2026!";
    const encoded = await hashPassword(password);

    expect(encoded).toContain("$argon2id$");
    expect(await verifyPassword(password, encoded)).toBe(true);
    expect(await verifyPassword("not-the-password", encoded)).toBe(false);
    expect(encoded).not.toContain(password);
  });
});
