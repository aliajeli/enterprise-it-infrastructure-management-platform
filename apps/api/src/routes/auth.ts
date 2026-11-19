import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import type { PrismaClient } from "@platform/database";
import type { ApiConfig } from "../config.js";
import {
  hashPassword,
  normalizeUsername,
  verifyPassword,
} from "../security/credentials.js";
import {
  digestIdentifier,
  digestSessionToken,
  issueSessionToken,
} from "../security/session-token.js";

const SESSION_COOKIE_PRODUCTION = "__Host-platform_session";
const SESSION_COOKIE_DEVELOPMENT = "platform_session";
const DUMMY_PASSWORD = "Dummy-Password-For-Timing-Equalization-Only-2026!";
const dummyPasswordHash = hashPassword(DUMMY_PASSWORD);

interface LoginBody {
  username: string;
  password: string;
}

function sessionCookieName(config: ApiConfig): string {
  return config.cookieSecure
    ? SESSION_COOKIE_PRODUCTION
    : SESSION_COOKIE_DEVELOPMENT;
}

function setSessionCookie(
  reply: FastifyReply,
  config: ApiConfig,
  token: string,
  expiresAt: Date,
): void {
  reply.setCookie(sessionCookieName(config), token, {
    httpOnly: true,
    secure: config.cookieSecure,
    sameSite: "lax",
    path: "/",
    expires: expiresAt,
    maxAge: config.sessionTtlSeconds,
  });
}

function clearSessionCookie(reply: FastifyReply, config: ApiConfig): void {
  reply.clearCookie(sessionCookieName(config), {
    httpOnly: true,
    secure: config.cookieSecure,
    sameSite: "lax",
    path: "/",
  });
}

function invalidCredentials(reply: FastifyReply) {
  return reply.code(401).send({
    error: {
      code: "INVALID_CREDENTIALS",
      message: "Invalid username or password.",
    },
  });
}

function publicUser(user: {
  id: string;
  username: string;
  role: string;
}) {
  return {
    id: user.id,
    username: user.username,
    role: user.role,
  };
}

async function writeLoginFailure(
  db: PrismaClient,
  userId: string | null,
  subjectHash: string,
  request: FastifyRequest,
  config: ApiConfig,
  countFailure: boolean,
): Promise<void> {
  await db.$transaction(async (tx) => {
    if (userId && countFailure) {
      await tx.$executeRaw`
        UPDATE "users"
        SET
          "failed_login_count" = "failed_login_count" + 1,
          "locked_until" = CASE
            WHEN "failed_login_count" + 1 >= ${config.loginLockoutThreshold}
            THEN NOW() + (${config.loginLockoutMs} * INTERVAL '1 millisecond')
            ELSE "locked_until"
          END,
          "updated_at" = NOW()
        WHERE "id" = ${userId}::uuid
      `;
    }

    await tx.auditEvent.create({
      data: {
        actorType: "SYSTEM",
        action: "AUTH_LOGIN_FAILED",
        objectType: "user",
        objectId: userId,
        outcome: "FAILURE",
        requestId: request.id,
        sourceIp: request.ip,
        metadata: { subjectHash },
      },
    });
  });
}

export async function registerAuthRoutes(
  app: FastifyInstance,
  db: PrismaClient,
  config: ApiConfig,
): Promise<void> {
  app.post<{ Body: LoginBody }>(
    "/api/v1/auth/login",
    {
      config: {
        rateLimit: {
          max: 5,
          timeWindow: "15 minutes",
        },
      },
      schema: {
        body: {
          type: "object",
          required: ["username", "password"],
          additionalProperties: false,
          properties: {
            username: { type: "string", minLength: 1, maxLength: 64 },
            password: { type: "string", minLength: 1, maxLength: 128 },
          },
        },
      },
    },
    async (request, reply) => {
      const normalizedUsername = normalizeUsername(request.body.username);
      const user = normalizedUsername
        ? await db.user.findUnique({
            where: { usernameNormalized: normalizedUsername },
          })
        : null;

      const candidateHash = user?.passwordHash ?? (await dummyPasswordHash);
      const passwordMatches = await verifyPassword(
        request.body.password,
        candidateHash,
      );
      const now = new Date();
      const isLocked = Boolean(user?.lockedUntil && user.lockedUntil > now);

      if (
        !user ||
        !passwordMatches ||
        user.status !== "ACTIVE" ||
        isLocked
      ) {
        await writeLoginFailure(
          db,
          user?.id ?? null,
          digestIdentifier(request.body.username),
          request,
          config,
          Boolean(user && !isLocked),
        );
        return invalidCredentials(reply);
      }

      const { token, tokenHash } = issueSessionToken();
      const expiresAt = new Date(
        now.getTime() + config.sessionTtlSeconds * 1_000,
      );
      const userAgent = request.headers["user-agent"];

      await db.$transaction(async (tx) => {
        await tx.user.update({
          where: { id: user.id },
          data: {
            failedLoginCount: 0,
            lockedUntil: null,
          },
        });

        const createdSession = await tx.session.create({
          data: {
            userId: user.id,
            tokenHash,
            authEpoch: user.authEpoch,
            expiresAt,
            ipAddress: request.ip,
            userAgent:
              typeof userAgent === "string"
                ? userAgent.slice(0, 512)
                : null,
          },
        });

        await tx.auditEvent.create({
          data: {
            actorUserId: user.id,
            actorType: "USER",
            action: "AUTH_LOGIN_SUCCEEDED",
            objectType: "session",
            objectId: createdSession.id,
            outcome: "SUCCESS",
            requestId: request.id,
            sourceIp: request.ip,
          },
        });
      });

      setSessionCookie(reply, config, token, expiresAt);
      return reply.code(200).send({ user: publicUser(user), expiresAt });
    },
  );

  app.get("/api/v1/session", async (request, reply) => {
    const token = request.cookies[sessionCookieName(config)];
    if (!token) {
      return reply.code(401).send({
        error: { code: "UNAUTHENTICATED", message: "Authentication required." },
      });
    }

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
      return reply.code(401).send({
        error: { code: "UNAUTHENTICATED", message: "Authentication required." },
      });
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

    return reply.send({
      user: publicUser(session.user),
      expiresAt: session.expiresAt,
    });
  });

  app.post("/api/v1/auth/logout", async (request, reply) => {
    const token = request.cookies[sessionCookieName(config)];
    if (token) {
      const session = await db.session.findUnique({
        where: { tokenHash: digestSessionToken(token) },
        include: { user: true },
      });

      if (session && !session.revokedAt) {
        const now = new Date();
        await db.$transaction(async (tx) => {
          await tx.session.updateMany({
            where: { id: session.id, revokedAt: null },
            data: { revokedAt: now },
          });
          await tx.auditEvent.create({
            data: {
              actorUserId: session.userId,
              actorType: "USER",
              action: "AUTH_LOGOUT",
              objectType: "session",
              objectId: session.id,
              outcome: "SUCCESS",
              requestId: request.id,
              sourceIp: request.ip,
            },
          });
        });
      }
    }

    clearSessionCookie(reply, config);
    return reply.code(204).send();
  });
}
