import type { PrismaClient } from "@platform/database";

export type PlatformRole = "ADMIN" | "OPERATOR" | "VIEWER";

export interface Principal {
  id: string;
  role: PlatformRole;
}

/**
 * Application capabilities are deliberately independent from UI navigation.
 * Every operational API must check this policy on the server.
 */
export type PlatformAction =
  | "inventory.read"
  | "inventory.write"
  | "switch.metadata.read"
  | "switch.metadata.write"
  | "inventory.discovery.run"
  | "inventory.sync.run"
  | "device.configuration.write"
  | "remote.session.start"
  | "credential.use"
  | "deployment.create"
  | "deployment.execute"
  | "store.force_close"
  | "users.manage"
  | "branches.manage"
  | "settings.manage";

const roleActions: Readonly<Record<PlatformRole, readonly PlatformAction[]>> = {
  ADMIN: [
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
  ],
  OPERATOR: [
    "inventory.read",
    "inventory.write",
    "switch.metadata.read",
    "switch.metadata.write",
    "inventory.discovery.run",
    "inventory.sync.run",
  ],
  VIEWER: ["inventory.read", "switch.metadata.read"],
};

export function canManageUsers(role: PlatformRole): boolean {
  return role === "ADMIN";
}

export function canPerformAction(
  role: PlatformRole,
  action: PlatformAction,
): boolean {
  return roleActions[role].includes(action);
}

export async function hasBranchScope(
  db: PrismaClient,
  principal: Principal,
  branchId: string,
): Promise<boolean> {
  if (principal.role === "ADMIN") return true;

  const grant = await db.userBranchAccess.findFirst({
    where: {
      userId: principal.id,
      branchId,
      revokedAt: null,
      branch: {
        is: {
          status: "ACTIVE",
          deletedAt: null,
        },
      },
    },
    select: { id: true },
  });

  return grant !== null;
}

/**
 * Use for branch-owned resources: role capability AND active branch grant
 * are both required. Global ADMIN actions should use canPerformAction.
 */
export async function hasBranchActionAccess(
  db: PrismaClient,
  principal: Principal,
  branchId: string,
  action: PlatformAction,
): Promise<boolean> {
  if (!canPerformAction(principal.role, action)) return false;
  return hasBranchScope(db, principal, branchId);
}
