import type { PrismaClient } from "@platform/database";
import { describe, expect, it, vi } from "vitest";
import {
  canManageUsers,
  canPerformAction,
  hasBranchActionAccess,
  hasBranchScope,
} from "./access-control.js";

describe("server-side role policy", () => {
  it("restricts user administration to administrators", () => {
    expect(canManageUsers("ADMIN")).toBe(true);
    expect(canManageUsers("OPERATOR")).toBe(false);
    expect(canManageUsers("VIEWER")).toBe(false);
  });

  it("allows operators only inventory, metadata and non-destructive discovery/sync actions", () => {
    for (const action of [
      "inventory.read",
      "inventory.write",
      "switch.metadata.read",
      "switch.metadata.write",
      "inventory.discovery.run",
      "inventory.sync.run",
    ] as const) {
      expect(canPerformAction("OPERATOR", action)).toBe(true);
    }

    for (const action of [
      "device.configuration.write",
      "remote.session.start",
      "credential.use",
      "deployment.create",
      "deployment.execute",
      "store.force_close",
      "users.manage",
      "branches.manage",
      "settings.manage",
    ] as const) {
      expect(canPerformAction("OPERATOR", action)).toBe(false);
    }
  });

  it("keeps viewers read-only", () => {
    expect(canPerformAction("VIEWER", "inventory.read")).toBe(true);
    expect(canPerformAction("VIEWER", "switch.metadata.read")).toBe(true);

    for (const action of [
      "inventory.write",
      "switch.metadata.write",
      "inventory.discovery.run",
      "inventory.sync.run",
      "device.configuration.write",
      "remote.session.start",
      "credential.use",
      "deployment.create",
      "deployment.execute",
      "store.force_close",
      "users.manage",
      "branches.manage",
      "settings.manage",
    ] as const) {
      expect(canPerformAction("VIEWER", action)).toBe(false);
    }
  });

  it("allows administrators all declared actions", () => {
    for (const action of [
      "inventory.read",
      "inventory.write",
      "switch.metadata.read",
      "switch.metadata.write",
      "inventory.discovery.run",
      "inventory.sync.run",
      "device.configuration.write",
      "remote.session.start",
      "credential.use",
      "deployment.create",
      "deployment.execute",
      "store.force_close",
      "users.manage",
      "branches.manage",
      "settings.manage",
    ] as const) {
      expect(canPerformAction("ADMIN", action)).toBe(true);
    }
  });
});

describe("branch-scoped authorization", () => {
  it("grants administrators global branch scope without a database lookup", async () => {
    const findFirst = vi.fn();
    const db = {
      userBranchAccess: { findFirst },
    } as unknown as PrismaClient;

    await expect(
      hasBranchScope(db, { id: "admin-id", role: "ADMIN" }, "branch-id"),
    ).resolves.toBe(true);
    expect(findFirst).not.toHaveBeenCalled();
  });

  it("requires an active branch grant for operators and viewers", async () => {
    const findFirst = vi.fn().mockResolvedValue({ id: "grant-id" });
    const db = {
      userBranchAccess: { findFirst },
    } as unknown as PrismaClient;

    await expect(
      hasBranchScope(db, { id: "operator-id", role: "OPERATOR" }, "branch-id"),
    ).resolves.toBe(true);
    expect(findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          userId: "operator-id",
          branchId: "branch-id",
          revokedAt: null,
        }),
      }),
    );

    findFirst.mockResolvedValueOnce(null);
    await expect(
      hasBranchScope(db, { id: "viewer-id", role: "VIEWER" }, "branch-id"),
    ).resolves.toBe(false);
  });

  it("requires both an allowed action and an active branch grant", async () => {
    const findFirst = vi.fn().mockResolvedValue({ id: "grant-id" });
    const db = {
      userBranchAccess: { findFirst },
    } as unknown as PrismaClient;

    await expect(
      hasBranchActionAccess(
        db,
        { id: "operator-id", role: "OPERATOR" },
        "branch-id",
        "inventory.write",
      ),
    ).resolves.toBe(true);

    await expect(
      hasBranchActionAccess(
        db,
        { id: "operator-id", role: "OPERATOR" },
        "branch-id",
        "remote.session.start",
      ),
    ).resolves.toBe(false);
    expect(findFirst).toHaveBeenCalledTimes(1);

    findFirst.mockResolvedValueOnce(null);
    await expect(
      hasBranchActionAccess(
        db,
        { id: "viewer-id", role: "VIEWER" },
        "branch-id",
        "inventory.read",
      ),
    ).resolves.toBe(false);
  });
});
