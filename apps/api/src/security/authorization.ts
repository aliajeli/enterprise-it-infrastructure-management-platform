import type { FastifyReply, FastifyRequest } from "fastify";
import type { PrismaClient } from "@platform/database";
import type { ApiConfig } from "../config.js";
import { canManageUsers } from "./access-control.js";
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
