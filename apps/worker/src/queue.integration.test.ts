import { randomUUID } from "node:crypto";
import type { PrismaClient } from "@platform/database";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  acknowledgeCancellation,
  claimNextDiscoveryRun,
  completeDiscoveryRun,
  failDiscoveryRun,
  heartbeatDiscoveryRun,
  recoverExpiredLeases,
} from "./queue.js";

const isDisposableTestDatabase =
  process.env.DATABASE_URL?.includes("/platform_test") ?? false;

describe.skipIf(!isDisposableTestDatabase)(
  "PostgreSQL discovery worker queue integration",
  () => {
    let db: PrismaClient | undefined;
    let branchId = "";

    beforeAll(async () => {
      const databaseModule = await import("@platform/database");
      db = databaseModule.prisma;
      const branch = await db.branch.create({
        data: {
          branchCode: `WQ-${randomUUID().slice(0, 8)}`,
          name: "Worker queue integration branch",
        },
      });
      branchId = branch.id;
    }, 30_000);

    beforeEach(async () => {
      if (db && branchId) {
        await db.discoveryRun.deleteMany({ where: { branchId } });
      }
    });

    afterAll(async () => {
      if (db && branchId) {
        await db.discoveryRun.deleteMany({ where: { branchId } });
        await db.branch.delete({ where: { id: branchId } });
      }
      await db?.$disconnect();
    });

    async function createRun(options: {
      maxAttempts?: number;
      attemptCount?: number;
      cancelRequested?: boolean;
    } = {}): Promise<string> {
      if (!db) throw new Error("Database integration was not initialized.");
      const run = await db.discoveryRun.create({
        data: {
          branchId,
          source: "SNMP",
          status: "QUEUED",
          maxAttempts: options.maxAttempts ?? 3,
          attemptCount: options.attemptCount ?? 0,
          cancelRequestedAt: options.cancelRequested ? new Date() : null,
        },
      });
      return run.id;
    }

    async function expireLease(runId: string): Promise<void> {
      if (!db) throw new Error("Database integration was not initialized.");
      await db.$executeRaw`
        UPDATE discovery_runs
        SET lease_expires_at = NOW() - INTERVAL '1 second'
        WHERE id = ${runId}::uuid
      `;
    }

    it("allows only one worker to claim a single queued run", async () => {
      if (!db) throw new Error("Database integration was not initialized.");
      const runId = await createRun();
      const claims = await Promise.all([
        claimNextDiscoveryRun(db, "worker-a", ["SNMP"]),
        claimNextDiscoveryRun(db, "worker-b", ["SNMP"]),
      ]);
      expect(claims.filter(Boolean)).toHaveLength(1);
      expect(claims.find(Boolean)?.id).toBe(runId);
    });

    it("binds heartbeat and completion to the live lease owner", async () => {
      if (!db) throw new Error("Database integration was not initialized.");
      const runId = await createRun();
      const claim = await claimNextDiscoveryRun(db, "owner-a", ["SNMP"]);
      expect(claim?.id).toBe(runId);
      expect(await heartbeatDiscoveryRun(db, runId, "owner-b")).toBe(false);
      expect(await completeDiscoveryRun(db, runId, "owner-b", "SUCCEEDED")).toBe(false);
      expect(await completeDiscoveryRun(db, runId, "owner-a", "SUCCEEDED")).toBe(true);
    });

    it("rejects heartbeat and completion from a worker whose lease expired", async () => {
      if (!db) throw new Error("Database integration was not initialized.");
      const runId = await createRun();
      expect((await claimNextDiscoveryRun(db, "stale-worker", ["SNMP"]))?.id).toBe(runId);
      await expireLease(runId);
      expect(await heartbeatDiscoveryRun(db, runId, "stale-worker")).toBe(false);
      expect(await completeDiscoveryRun(db, runId, "stale-worker", "SUCCEEDED")).toBe(false);
      expect(await acknowledgeCancellation(db, runId, "stale-worker")).toBe(false);
    });

    it("recovers an expired lease and permits a new owner to claim it", async () => {
      if (!db) throw new Error("Database integration was not initialized.");
      const runId = await createRun();
      expect((await claimNextDiscoveryRun(db, "crashed-worker", ["SNMP"]))?.id).toBe(runId);
      await expireLease(runId);
      expect(await recoverExpiredLeases(db)).toBeGreaterThanOrEqual(1);
      const recovered = await db.discoveryRun.findUniqueOrThrow({ where: { id: runId } });
      expect(recovered.status).toBe("QUEUED");
      expect(recovered.leaseOwner).toBeNull();
      expect((await claimNextDiscoveryRun(db, "replacement-worker", ["SNMP"]))?.id).toBe(runId);
    });

    it("retries with bounded backoff and fails after max attempts", async () => {
      if (!db) throw new Error("Database integration was not initialized.");
      const runId = await createRun({ maxAttempts: 2 });
      expect((await claimNextDiscoveryRun(db, "retry-worker", ["SNMP"]))?.id).toBe(runId);
      expect(await failDiscoveryRun(db, runId, "retry-worker", "TEST_FAILURE", "safe test failure")).toBe("REQUEUED");
      await db.$executeRaw`
        UPDATE discovery_runs SET next_attempt_at = NOW()
        WHERE id = ${runId}::uuid
      `;
      expect((await claimNextDiscoveryRun(db, "retry-worker", ["SNMP"]))?.id).toBe(runId);
      expect(await failDiscoveryRun(db, runId, "retry-worker", "TEST_FAILURE", "safe test failure")).toBe("FAILED");
      const failed = await db.discoveryRun.findUniqueOrThrow({ where: { id: runId } });
      expect(failed.status).toBe("FAILED");
      expect(failed.completedAt).not.toBeNull();
      expect(failed.attemptCount).toBe(2);
    });

    it("does not let failure handling override an active cancellation request", async () => {
      if (!db) throw new Error("Database integration was not initialized.");
      const runId = await createRun();
      expect((await claimNextDiscoveryRun(db, "cancel-owner", ["SNMP"]))?.id).toBe(runId);
      await db.$executeRaw`
        UPDATE discovery_runs SET cancel_requested_at = NOW()
        WHERE id = ${runId}::uuid
      `;
      expect(await failDiscoveryRun(db, runId, "cancel-owner", "TEST_FAILURE", "safe test failure")).toBe("LEASE_LOST");
      expect(await acknowledgeCancellation(db, runId, "cancel-owner")).toBe(true);
      const cancelled = await db.discoveryRun.findUniqueOrThrow({ where: { id: runId } });
      expect(cancelled.status).toBe("CANCELLED");
    });

    it("gives cancellation precedence over retry exhaustion on expired leases", async () => {
      if (!db) throw new Error("Database integration was not initialized.");
      const runId = await createRun({ maxAttempts: 1, attemptCount: 0 });
      expect((await claimNextDiscoveryRun(db, "cancel-worker", ["SNMP"]))?.id).toBe(runId);
      await db.$executeRaw`
        UPDATE discovery_runs
        SET cancel_requested_at = NOW(),
            lease_expires_at = NOW() - INTERVAL '1 second'
        WHERE id = ${runId}::uuid
      `;
      expect(await recoverExpiredLeases(db)).toBe(1);
      const cancelled = await db.discoveryRun.findUniqueOrThrow({ where: { id: runId } });
      expect(cancelled.status).toBe("CANCELLED");
      expect(cancelled.leaseOwner).toBeNull();
    });

    it("rolls back queue mutations when the surrounding transaction aborts", async () => {
      if (!db) throw new Error("Database integration was not initialized.");
      const runId = await createRun();
      await expect(db.$transaction(async (tx) => {
        await tx.$executeRaw`
          UPDATE discovery_runs SET status = 'FAILED'
          WHERE id = ${runId}::uuid
        `;
        throw new Error("force rollback");
      })).rejects.toThrow("force rollback");
      const unchanged = await db.discoveryRun.findUniqueOrThrow({ where: { id: runId } });
      expect(unchanged.status).toBe("QUEUED");
    });
  },
);
