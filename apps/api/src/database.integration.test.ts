import { randomUUID } from "node:crypto";
import type { PrismaClient } from "@platform/database";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const isDisposableTestDatabase =
  process.env.DATABASE_URL?.includes("/platform_test") ?? false;

describe.skipIf(!isDisposableTestDatabase)(
  "PostgreSQL 18 migration integration",
  () => {
    let db: PrismaClient | undefined;
    let userId: string;
    let branchId: string;

    beforeAll(async () => {
      const databaseModule = await import("@platform/database");
      db = databaseModule.prisma;

      const suffix = randomUUID().replaceAll("-", "").slice(0, 12);
      const user = await db.user.create({
        data: {
          username: `ci_${suffix}`,
          usernameNormalized: `ci_${suffix}`,
          passwordHash: "$argon2id$schema-integration-placeholder",
          role: "VIEWER",
          status: "ACTIVE",
        },
      });
      userId = user.id;

      const branch = await db.branch.create({
        data: {
          branchCode: `CI${suffix}`,
          name: "Disposable CI branch",
        },
      });
      branchId = branch.id;
    });

    afterAll(async () => {
      await db?.$disconnect();
    });

    it("enforces active branch grants and append-only audit events", async () => {
      if (!db) throw new Error("Test database was not initialized.");

      const grant = await db.userBranchAccess.create({
        data: { userId, branchId },
      });

      await expect(
        db.userBranchAccess.create({
          data: { userId, branchId },
        }),
      ).rejects.toThrow();

      await db.userBranchAccess.update({
        where: { id: grant.id },
        data: { revokedAt: new Date() },
      });

      await expect(
        db.userBranchAccess.create({
          data: { userId, branchId },
        }),
      ).resolves.toMatchObject({ userId, branchId });

      const event = await db.auditEvent.create({
        data: {
          actorUserId: userId,
          actorType: "USER",
          action: "CI_AUDIT_IMMUTABILITY_TEST",
          objectType: "user",
          objectId: userId,
          outcome: "SUCCESS",
        },
      });

      await expect(
        db.auditEvent.update({
          where: { id: event.id },
          data: { action: "MUTATED_BY_TEST" },
        }),
      ).rejects.toThrow();
    });
  },
);
