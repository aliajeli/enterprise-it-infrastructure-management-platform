import { randomUUID } from "node:crypto";
import type { PrismaClient } from "@platform/database";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { buildApp } from "../app.js";
import type { ApiConfig } from "../config.js";
import { hashPassword } from "../security/credentials.js";

const password = "Correct Horse Battery Staple 2026!";
const publicOrigin = "https://platform.example.test";
const config: ApiConfig = {
  host: "127.0.0.1",
  port: 13001,
  publicOrigin,
  cookieSecure: true,
  sessionTtlSeconds: 43_200,
  loginLockoutThreshold: 5,
  loginLockoutMs: 900_000,
};

function createFakeDatabase(user: Record<string, unknown>) {
  const sessions = new Map<string, Record<string, unknown>>();

  const transactionClient = {
    user: {
      update: vi.fn(async ({ data }: { data: Record<string, unknown> }) => {
        Object.assign(user, data);
        return user;
      }),
    },
    session: {
      create: vi.fn(async ({ data }: { data: Record<string, unknown> }) => {
        const created = {
          id: randomUUID(),
          revokedAt: null,
          lastSeenAt: null,
          createdAt: new Date(),
          ...data,
        };
        sessions.set(String(data.tokenHash), created);
        return created;
      }),
      updateMany: vi.fn(async ({
        where,
        data,
      }: {
        where: { id: string; revokedAt: null };
        data: Record<string, unknown>;
      }) => {
        const found = [...sessions.values()].find(
          (entry) => entry.id === where.id && entry.revokedAt === null,
        );
        if (found) Object.assign(found, data);
        return { count: found ? 1 : 0 };
      }),
    },
    auditEvent: {
      create: vi.fn(async ({ data }: { data: Record<string, unknown> }) => data),
    },
    $executeRaw: vi.fn(async () => 1),
  };

  const database = {
    user: {
      findUnique: vi.fn(async ({
        where,
      }: {
        where: { usernameNormalized: string };
      }) =>
        where.usernameNormalized === user.usernameNormalized ? user : null,
      ),
    },
    session: {
      findUnique: vi.fn(async ({
        where,
      }: {
        where: { tokenHash: string };
      }) => {
        const found = sessions.get(where.tokenHash);
        return found ? { ...found, user } : null;
      }),
      update: vi.fn(async ({
        where,
        data,
      }: {
        where: { id: string };
        data: Record<string, unknown>;
      }) => {
        const found = [...sessions.values()].find(
          (entry) => entry.id === where.id,
        );
        if (found) Object.assign(found, data);
        return found;
      }),
      updateMany: transactionClient.session.updateMany,
    },
    $transaction: vi.fn(async <T>(
      callback: (tx: typeof transactionClient) => Promise<T>,
    ) => callback(transactionClient)),
    $queryRaw: vi.fn(async () => [{ schema_ready: true }]),
  };

  return { db: database as unknown as PrismaClient, sessions };
}

describe("authentication API", () => {
  let app: Awaited<ReturnType<typeof buildApp>>;

  beforeAll(async () => {
    const passwordHash = await hashPassword(password);
    const user = {
      id: randomUUID(),
      username: "operator.one",
      usernameNormalized: "operator.one",
      passwordHash,
      role: "VIEWER",
      status: "ACTIVE",
      authEpoch: 0,
      mustChangePassword: false,
      lastLoginAt: null,
      failedLoginCount: 0,
      lockedUntil: null,
    };
    const fake = createFakeDatabase(user);
    app = await buildApp({ db: fake.db, config, logger: false });
  });

  afterAll(async () => {
    await app.close();
  });

  it("rejects unsafe requests without an exact trusted Origin", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { username: "operator.one", password },
    });

    expect(response.statusCode).toBe(403);
    expect(response.json().error.code).toBe("ORIGIN_REJECTED");
  });

  it("issues an opaque HttpOnly Secure session and supports logout", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      headers: { origin: publicOrigin },
      payload: { username: "operator.one", password },
    });

    expect(login.statusCode).toBe(200);
    expect(login.json().user).toEqual({
      id: expect.any(String),
      username: "operator.one",
      role: "VIEWER",
      mustChangePassword: false,
    });
    expect(login.json().user).not.toHaveProperty("passwordHash");

    const setCookieHeader = login.headers["set-cookie"];
    const setCookie = Array.isArray(setCookieHeader)
      ? setCookieHeader[0]
      : setCookieHeader;
    expect(setCookie).toContain("__Host-platform_session=");
    expect(setCookie).toContain("HttpOnly");
    expect(setCookie).toContain("Secure");
    expect(setCookie).toContain("SameSite=Lax");
    expect(setCookie).toContain("Path=/");

    const cookie = (setCookie ?? "").split(";")[0];
    const currentSession = await app.inject({
      method: "GET",
      url: "/api/v1/session",
      headers: { cookie },
    });
    expect(currentSession.statusCode).toBe(200);
    expect(currentSession.json().user.username).toBe("operator.one");

    const logout = await app.inject({
      method: "POST",
      url: "/api/v1/auth/logout",
      headers: { origin: publicOrigin, cookie },
    });
    expect(logout.statusCode).toBe(204);

    const afterLogout = await app.inject({
      method: "GET",
      url: "/api/v1/session",
      headers: { cookie },
    });
    expect(afterLogout.statusCode).toBe(401);
  });

  it("returns the same generic error for an unknown username", async () => {
    const response = await app.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      headers: { origin: publicOrigin },
      payload: {
        username: "unknown.user",
        password: "Incorrect Password 2026!",
      },
    });

    expect(response.statusCode).toBe(401);
    expect(response.json().error.code).toBe("INVALID_CREDENTIALS");
    expect(response.json().error.message).toBe(
      "Invalid username or password.",
    );
  });
});
