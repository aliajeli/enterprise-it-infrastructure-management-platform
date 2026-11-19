import type { FastifyReply, FastifyRequest } from "fastify";
import type { PrismaClient } from "@platform/database";
import type { ApiConfig } from "../config.js";
import { clearSessionCookie, sessionCookieName } from "./session-cookie.js";
import { digestSessionToken } from "./session-token.js";

export interface AuthenticatedPrincipal {
  id: string;
  username: string;
  role: "ADMIN" | "OPERATOR" | "VIEWER";
  status: "ACTIVE" | "DISABLED";
  authEpoch: number;
  mustChangePassword: boolean;
}

export interface ResolvedSession {
  id: string;
  userId: string;
  tokenHash: string;
  authEpoch: number;
  expiresAt: Date;
  revokedAt: Date | null;
  lastSeenAt: Date | null;
  user: AuthenticatedPrincipal;
}

export async function resolveSession(
  db: PrismaClient,
  config: ApiConfig,
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<ResolvedSession | null> {
  const token = request.cookies[sessionCookieName(config)];
  if (!token) return null;

  const session = await db.session.findUnique({
    where: { tokenHash: digestSessionToken(token) },
    include: { user: true },
  });
  const now = new Date();

  if (
    !session ||
    session.revokedAt ||
    session.expiresAt <= now ||
    session.user.status !== "ACTIVE" ||
    session.authEpoch !== session.user.authEpoch
  ) {
    if (session && !session.revokedAt) {
      await db.session.updateMany({
        where: { id: session.id, revokedAt: null },
        data: { revokedAt: now },
      });
    }
    clearSessionCookie(reply, config);
    return null;
  }

  if (
    !session.lastSeenAt ||
    now.getTime() - session.lastSeenAt.getTime() >= 5 * 60 * 1_000
  ) {
    await db.session.update({
      where: { id: session.id },
      data: { lastSeenAt: now },
    });
  }

  return session;
}
