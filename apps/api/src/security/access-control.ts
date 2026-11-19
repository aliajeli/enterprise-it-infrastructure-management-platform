import type { PrismaClient } from "@platform/database";

export type PlatformRole = "ADMIN" | "OPERATOR" | "VIEWER";

export interface Principal {
  id: string;
  role: PlatformRole;
}

export function canManageUsers(role: PlatformRole): boolean {
  return role === "ADMIN";
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
