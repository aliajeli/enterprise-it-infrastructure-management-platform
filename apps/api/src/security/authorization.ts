import type { FastifyReply, FastifyRequest } from "fastify";
import type { PrismaClient } from "@platform/database";
import type { ApiConfig } from "../config.js";
import { canManageUsers, canPerformAction, hasBranchActionAccess, type PlatformAction } from "./access-control.js";
import { resolveSession, type ResolvedSession } from "./session.js";

export async function requireAdmin(
  db: PrismaClient,
  config: ApiConfig,
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<ResolvedSession | null> {
  const session = await resolveSession(db, config, request, reply);
  if (!session) {
    reply.code(401).send({
      error: { code: "UNAUTHENTICATED", message: "Authentication required." },
    });
    return null;
  }

  if (session.user.mustChangePassword) {
    reply.code(403).send({
      error: {
        code: "PASSWORD_CHANGE_REQUIRED",
        message: "Change your password before continuing.",
      },
    });
    return null;
  }

  if (!canManageUsers(session.user.role)) {
    reply.code(403).send({
      error: { code: "FORBIDDEN", message: "Administrator access required." },
    });
    return null;
  }

  return session;
}


export async function requirePlatformAction(
  db: PrismaClient,
  config: ApiConfig,
  request: FastifyRequest,
  reply: FastifyReply,
  action: PlatformAction,
): Promise<ResolvedSession | null> {
  const session = await resolveSession(db, config, request, reply);
  if (!session) {
    reply.code(401).send({
      error: { code: "UNAUTHENTICATED", message: "Authentication required." },
    });
    return null;
  }
  if (session.user.mustChangePassword) {
    reply.code(403).send({
      error: { code: "PASSWORD_CHANGE_REQUIRED", message: "Change your password before continuing." },
    });
    return null;
  }
  if (!canPerformAction(session.user.role, action)) {
    reply.code(403).send({
      error: { code: "FORBIDDEN", message: "This action is not permitted for your role." },
    });
    return null;
  }
  return session;
}

export async function requireBranchAction(
  db: PrismaClient,
  config: ApiConfig,
  request: FastifyRequest,
  reply: FastifyReply,
  branchId: string,
  action: PlatformAction,
): Promise<ResolvedSession | null> {
  const session = await requirePlatformAction(db, config, request, reply, action);
  if (!session) return null;

  const activeBranch = await db.branch.findFirst({
    where: { id: branchId, status: "ACTIVE", deletedAt: null },
    select: { id: true },
  });
  if (!activeBranch) {
    reply.code(404).send({
      error: { code: "RESOURCE_NOT_FOUND", message: "The requested resource was not found." },
    });
    return null;
  }

  const allowed = await hasBranchActionAccess(
    db,
    { id: session.user.id, role: session.user.role },
    branchId,
    action,
  );
  if (!allowed) {
    reply.code(404).send({
      error: { code: "RESOURCE_NOT_FOUND", message: "The requested resource was not found." },
    });
    return null;
  }
  return session;
}
