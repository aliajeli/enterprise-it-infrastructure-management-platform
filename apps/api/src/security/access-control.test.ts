import type { PrismaClient } from "@platform/database";
import { describe, expect, it, vi } from "vitest";
import {
  canManageUsers,
  hasBranchScope,
} from "./access-control.js";

describe("server-side access primitives", () => {
  it("restricts user administration to administrators", () => {
    expect(canManageUsers("ADMIN")).toBe(true);
    expect(canManageUsers("OPERATOR")).toBe(false);
    expect(canManageUsers("VIEWER")).toBe(false);
  });

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
});
