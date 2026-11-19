import { randomUUID } from "node:crypto";
import type { PrismaClient } from "@platform/database";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import type { ApiConfig } from "./config.js";
import { hashPassword } from "./security/credentials.js";
import { issueSessionToken } from "./security/session-token.js";

const isDisposableTestDatabase =
  process.env.DATABASE_URL?.includes("/platform_test") ?? false;
const publicOrigin = "http://127.0.0.1:3000";
const config: ApiConfig = {
  host: "127.0.0.1",
  port: 13001,
  publicOrigin,
  cookieSecure: false,
  sessionTtlSeconds: 43_200,
  loginLockoutThreshold: 5,
  loginLockoutMs: 900_000,
};

function sessionCookie(response: {
  headers: { "set-cookie"?: unknown };
}): string {
  const header = response.headers["set-cookie"];
  const value = Array.isArray(header)
    ? header[0]
    : typeof header === "string"
      ? header
      : "";
  return (value ?? "").split(";")[0] ?? "";
}

describe.skipIf(!isDisposableTestDatabase)(
  "PostgreSQL 18 identity and user-lifecycle integration",
  () => {
    let db: PrismaClient | undefined;
    let app: Awaited<ReturnType<typeof buildApp>> | undefined;
    let adminCookie = "";
    let adminId = "";
    let initialBranchId = "";

    beforeAll(async () => {
      const databaseModule = await import("@platform/database");
      db = databaseModule.prisma;

      const suffix = randomUUID().replaceAll("-", "").slice(0, 12);
      const admin = await db.user.create({
        data: {
          username: `ci_admin_${suffix}`,
          usernameNormalized: `ci_admin_${suffix}`,
          passwordHash: await hashPassword("CI Admin Integration Password 2026!"),
          role: "ADMIN",
          status: "ACTIVE",
        },
      });
      adminId = admin.id;

      const branch = await db.branch.create({
        data: {
          branchCode: `CI${suffix}`,
          name: "Disposable integration branch",
        },
      });
      initialBranchId = branch.id;

      const issued = issueSessionToken();
      await db.session.create({
        data: {
          userId: admin.id,
          tokenHash: issued.tokenHash,
          authEpoch: admin.authEpoch,
          expiresAt: new Date(Date.now() + config.sessionTtlSeconds * 1_000),
        },
      });
      adminCookie = `platform_session=${issued.token}`;

      app = await buildApp({ db, config, logger: false });
    }, 30_000);

    afterAll(async () => {
      await app?.close();
      await db?.$disconnect();
    });

    it("provisions users, forces password change, scopes branches and revokes sessions", async () => {
      if (!db || !app) throw new Error("PostgreSQL integration was not initialized.");

      const branchResponse = await app.inject({
        method: "POST",
        url: "/api/v1/branches",
        headers: { origin: publicOrigin, cookie: adminCookie },
        payload: {
          branchCode: `API-${randomUUID().slice(0, 8)}`,
          name: "API-created branch",
        },
      });
      expect(branchResponse.statusCode).toBe(201);
      const secondBranchId = branchResponse.json().branch.id as string;

      const createUser = await app.inject({
        method: "POST",
        url: "/api/v1/users",
        headers: { origin: publicOrigin, cookie: adminCookie },
        payload: {
          username: `operator_${randomUUID().slice(0, 8)}`,
          role: "OPERATOR",
          branchIds: [initialBranchId],
        },
      });
      expect(createUser.statusCode).toBe(201);
      expect(createUser.headers["cache-control"]).toContain("no-store");
      const created = createUser.json();
      const userId = created.user.id as string;
      const temporaryPassword = created.temporaryPassword as string;
      expect(created.user.mustChangePassword).toBe(true);
      expect(created.user).not.toHaveProperty("passwordHash");
      expect(temporaryPassword).toHaveLength(43);

      const adminList = await app.inject({
        method: "GET",
        url: "/api/v1/users",
        headers: { cookie: adminCookie },
      });
      expect(adminList.statusCode).toBe(200);
      expect(adminList.json().users[0]).not.toHaveProperty("passwordHash");

      const temporaryLogin = await app.inject({
        method: "POST",
        url: "/api/v1/auth/login",
        headers: { origin: publicOrigin },
        payload: {
          username: created.user.username,
          password: temporaryPassword,
        },
      });
      expect(temporaryLogin.statusCode).toBe(200);
      expect(temporaryLogin.json().user.mustChangePassword).toBe(true);
      const temporaryCookie = sessionCookie(temporaryLogin);
      expect(temporaryCookie).toContain("platform_session=");

      const operatorDenied = await app.inject({
        method: "GET",
        url: "/api/v1/users",
        headers: { cookie: temporaryCookie },
      });
      expect(operatorDenied.statusCode).toBe(403);

      const passwordChange = await app.inject({
        method: "POST",
        url: "/api/v1/auth/change-password",
        headers: { origin: publicOrigin, cookie: temporaryCookie },
        payload: {
          currentPassword: temporaryPassword,
          newPassword: "New Operator Password 2026!",
        },
      });
      expect(passwordChange.statusCode).toBe(204);

      const revokedTemporarySession = await app.inject({
        method: "GET",
        url: "/api/v1/session",
        headers: { cookie: temporaryCookie },
      });
      expect(revokedTemporarySession.statusCode).toBe(401);

      const newLogin = await app.inject({
        method: "POST",
        url: "/api/v1/auth/login",
        headers: { origin: publicOrigin },
        payload: {
          username: created.user.username,
          password: "New Operator Password 2026!",
        },
      });
      expect(newLogin.statusCode).toBe(200);
      expect(newLogin.json().user.mustChangePassword).toBe(false);
      const newCookie = sessionCookie(newLogin);

      const branchReplacement = await app.inject({
        method: "PUT",
        url: `/api/v1/users/${userId}/branches`,
        headers: { origin: publicOrigin, cookie: adminCookie },
        payload: { branchIds: [secondBranchId] },
      });
      expect(branchReplacement.statusCode).toBe(200);
      expect(branchReplacement.json().branches).toHaveLength(1);
      expect(branchReplacement.json().branches[0].id).toBe(secondBranchId);

      const activeGrant = await db.userBranchAccess.findFirst({
        where: { userId, revokedAt: null },
      });
      if (!activeGrant) throw new Error("Active branch grant was not created.");
      await expect(
        db.userBranchAccess.create({
          data: { userId, branchId: secondBranchId, grantedByUserId: adminId },
        }),
      ).rejects.toThrow();

      const roleChange = await app.inject({
        method: "PATCH",
        url: `/api/v1/users/${userId}/role`,
        headers: { origin: publicOrigin, cookie: adminCookie },
        payload: { role: "VIEWER" },
      });
      expect(roleChange.statusCode).toBe(200);
      expect(roleChange.json().user.role).toBe("VIEWER");

      const revokedAfterRoleChange = await app.inject({
        method: "GET",
        url: "/api/v1/session",
        headers: { cookie: newCookie },
      });
      expect(revokedAfterRoleChange.statusCode).toBe(401);

      const statusChange = await app.inject({
        method: "PATCH",
        url: `/api/v1/users/${userId}/status`,
        headers: { origin: publicOrigin, cookie: adminCookie },
        payload: { status: "DISABLED" },
      });
      expect(statusChange.statusCode).toBe(200);
      expect(statusChange.json().user.status).toBe("DISABLED");

      const selfDisable = await app.inject({
        method: "PATCH",
        url: `/api/v1/users/${adminId}/status`,
        headers: { origin: publicOrigin, cookie: adminCookie },
        payload: { status: "DISABLED" },
      });
      expect(selfDisable.statusCode).toBe(409);

      const auditEvent = await db.auditEvent.findFirst({
        where: { action: "USER_CREATED", objectId: userId },
      });
      if (!auditEvent) throw new Error("User creation audit event is missing.");
      await expect(
        db.auditEvent.update({
          where: { id: auditEvent.id },
          data: { action: "AUDIT_TAMPER_ATTEMPT" },
        }),
      ).rejects.toThrow();
    }, 30_000);
  },
);
