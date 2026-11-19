import { randomBytes } from "node:crypto";
import type { FastifyInstance } from "fastify";
import type { PrismaClient } from "@platform/database";
import type { ApiConfig } from "../config.js";
import { normalizeUsername } from "../security/credentials.js";
import { hashPassword } from "../security/credentials.js";
import { requireAdmin } from "../security/authorization.js";

type ManagedRole = "OPERATOR" | "VIEWER";
type ManagedStatus = "ACTIVE" | "DISABLED";

interface CreateUserBody {
  username: string;
  role: ManagedRole;
  branchIds: string[];
}

interface ChangeStatusBody {
  status: ManagedStatus;
}

interface ChangeRoleBody {
  role: ManagedRole;
}

interface ReplaceBranchesBody {
  branchIds: string[];
}

interface UserWithBranches {
  id: string;
  username: string;
  role: string;
  status: string;
  mustChangePassword: boolean;
  lastLoginAt: Date | null;
  createdAt: Date;
  branchAccesses: Array<{
    branch: {
      id: string;
      branchCode: string;
      name: string;
      status: string;
    };
  }>;
}

class BranchSelectionError extends Error {}

function presentUser(user: UserWithBranches) {
  return {
    id: user.id,
    username: user.username,
    role: user.role,
    status: user.status,
    mustChangePassword: user.mustChangePassword,
    lastLoginAt: user.lastLoginAt,
    createdAt: user.createdAt,
    branches: user.branchAccesses.map(({ branch }) => ({
      id: branch.id,
      branchCode: branch.branchCode,
      name: branch.name,
      status: branch.status,
    })),
  };
}

function hasPrismaCode(error: unknown, code: string): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === code
  );
}

const userInclude = {
  branchAccesses: {
    where: { revokedAt: null },
    include: { branch: true },
  },
} as const;

export async function registerUserRoutes(
  app: FastifyInstance,
  db: PrismaClient,
  config: ApiConfig,
): Promise<void> {
  app.get("/api/v1/users", async (request, reply) => {
    const actor = await requireAdmin(db, config, request, reply);
    if (!actor) return;

    const users = await db.user.findMany({
      orderBy: { createdAt: "desc" },
      include: userInclude,
    });

    return reply.send({ users: users.map(presentUser) });
  });

  app.post<{ Body: CreateUserBody }>(
    "/api/v1/users",
    {
      config: { rateLimit: { max: 10, timeWindow: "15 minutes" } },
      schema: {
        body: {
          type: "object",
          required: ["username", "role", "branchIds"],
          additionalProperties: false,
          properties: {
            username: { type: "string", minLength: 3, maxLength: 64 },
            role: { type: "string", enum: ["OPERATOR", "VIEWER"] },
            branchIds: {
              type: "array",
              minItems: 1,
              maxItems: 100,
              uniqueItems: true,
              items: { type: "string", format: "uuid" },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const actor = await requireAdmin(db, config, request, reply);
      if (!actor) return;

      const usernameNormalized = normalizeUsername(request.body.username);
      if (!usernameNormalized) {
        return reply.code(400).send({
          error: { code: "INVALID_USERNAME", message: "Username is invalid." },
        });
      }

      const existing = await db.user.findUnique({
        where: { usernameNormalized },
        select: { id: true },
      });
      if (existing) {
        return reply.code(409).send({
          error: { code: "USERNAME_EXISTS", message: "Username is already in use." },
        });
      }

      const temporaryPassword = randomBytes(32).toString("base64url");
      const passwordHash = await hashPassword(temporaryPassword);

      try {
        const user = await db.$transaction(async (tx) => {
          const branches = await tx.branch.findMany({
            where: {
              id: { in: request.body.branchIds },
              status: "ACTIVE",
              deletedAt: null,
            },
            select: { id: true },
          });
          if (branches.length !== request.body.branchIds.length) {
            throw new BranchSelectionError("One or more branches are unavailable.");
          }

          const created = await tx.user.create({
            data: {
              username: request.body.username.trim(),
              usernameNormalized,
              passwordHash,
              role: request.body.role,
              status: "ACTIVE",
              mustChangePassword: true,
              branchAccesses: {
                create: request.body.branchIds.map((branchId) => ({
                  branchId,
                  grantedByUserId: actor.user.id,
                })),
              },
            },
            include: userInclude,
          });

          await tx.auditEvent.create({
            data: {
              actorUserId: actor.user.id,
              actorType: "USER",
              action: "USER_CREATED",
              objectType: "user",
              objectId: created.id,
              outcome: "SUCCESS",
              requestId: request.id,
              sourceIp: request.ip,
              metadata: {
                role: request.body.role,
                branchIds: request.body.branchIds,
                mustChangePassword: true,
              },
            },
          });

          return created;
        });

        reply.header("cache-control", "no-store");
        return reply.code(201).send({
          user: presentUser(user),
          temporaryPassword,
        });
      } catch (error) {
        if (error instanceof BranchSelectionError) {
          return reply.code(400).send({
            error: {
              code: "INVALID_BRANCH_SELECTION",
              message: "One or more selected branches are unavailable.",
            },
          });
        }
        if (hasPrismaCode(error, "P2002")) {
          return reply.code(409).send({
            error: { code: "USERNAME_EXISTS", message: "Username is already in use." },
          });
        }
        throw error;
      }
    },
  );

  app.patch<{ Params: { userId: string }; Body: ChangeStatusBody }>(
    "/api/v1/users/:userId/status",
    {
      schema: {
        params: {
          type: "object",
          required: ["userId"],
          properties: { userId: { type: "string", format: "uuid" } },
        },
        body: {
          type: "object",
          required: ["status"],
          additionalProperties: false,
          properties: { status: { type: "string", enum: ["ACTIVE", "DISABLED"] } },
        },
      },
    },
    async (request, reply) => {
      const actor = await requireAdmin(db, config, request, reply);
      if (!actor) return;
      if (request.params.userId === actor.user.id) {
        return reply.code(409).send({
          error: {
            code: "SELF_MODIFICATION_NOT_ALLOWED",
            message: "You cannot change your own account status.",
          },
        });
      }

      const target = await db.user.findUnique({
        where: { id: request.params.userId },
      });
      if (!target) {
        return reply.code(404).send({
          error: { code: "USER_NOT_FOUND", message: "User not found." },
        });
      }
      if (target.role === "ADMIN") {
        return reply.code(409).send({
          error: {
            code: "ADMIN_MANAGEMENT_RESTRICTED",
            message: "Administrator accounts require the owner-controlled procedure.",
          },
        });
      }
      if (target.status === request.body.status) {
        return reply.send({ user: { id: target.id, status: target.status } });
      }

      const now = new Date();
      const updated = await db.$transaction(async (tx) => {
        const user = await tx.user.update({
          where: { id: target.id },
          data: {
            status: request.body.status,
            authEpoch: { increment: 1 },
          },
          include: userInclude,
        });
        await tx.session.updateMany({
          where: { userId: target.id, revokedAt: null },
          data: { revokedAt: now },
        });
        await tx.auditEvent.create({
          data: {
            actorUserId: actor.user.id,
            actorType: "USER",
            action: request.body.status === "DISABLED" ? "USER_DISABLED" : "USER_ENABLED",
            objectType: "user",
            objectId: target.id,
            outcome: "SUCCESS",
            requestId: request.id,
            sourceIp: request.ip,
          },
        });
        return user;
      });

      return reply.send({ user: presentUser(updated) });
    },
  );

  app.patch<{ Params: { userId: string }; Body: ChangeRoleBody }>(
    "/api/v1/users/:userId/role",
    {
      schema: {
        params: {
          type: "object",
          required: ["userId"],
          properties: { userId: { type: "string", format: "uuid" } },
        },
        body: {
          type: "object",
          required: ["role"],
          additionalProperties: false,
          properties: { role: { type: "string", enum: ["OPERATOR", "VIEWER"] } },
        },
      },
    },
    async (request, reply) => {
      const actor = await requireAdmin(db, config, request, reply);
      if (!actor) return;
      if (request.params.userId === actor.user.id) {
        return reply.code(409).send({
          error: {
            code: "SELF_MODIFICATION_NOT_ALLOWED",
            message: "You cannot change your own account role.",
          },
        });
      }

      const target = await db.user.findUnique({
        where: { id: request.params.userId },
      });
      if (!target) {
        return reply.code(404).send({
          error: { code: "USER_NOT_FOUND", message: "User not found." },
        });
      }
      if (target.role === "ADMIN") {
        return reply.code(409).send({
          error: {
            code: "ADMIN_MANAGEMENT_RESTRICTED",
            message: "Administrator accounts require the owner-controlled procedure.",
          },
        });
      }

      const now = new Date();
      const updated = await db.$transaction(async (tx) => {
        const user = await tx.user.update({
          where: { id: target.id },
          data: {
            role: request.body.role,
            authEpoch: { increment: 1 },
          },
          include: userInclude,
        });
        await tx.session.updateMany({
          where: { userId: target.id, revokedAt: null },
          data: { revokedAt: now },
        });
        await tx.auditEvent.create({
          data: {
            actorUserId: actor.user.id,
            actorType: "USER",
            action: "USER_ROLE_CHANGED",
            objectType: "user",
            objectId: target.id,
            outcome: "SUCCESS",
            requestId: request.id,
            sourceIp: request.ip,
            metadata: { previousRole: target.role, newRole: request.body.role },
          },
        });
        return user;
      });

      return reply.send({ user: presentUser(updated) });
    },
  );

  app.put<{ Params: { userId: string }; Body: ReplaceBranchesBody }>(
    "/api/v1/users/:userId/branches",
    {
      schema: {
        params: {
          type: "object",
          required: ["userId"],
          properties: { userId: { type: "string", format: "uuid" } },
        },
        body: {
          type: "object",
          required: ["branchIds"],
          additionalProperties: false,
          properties: {
            branchIds: {
              type: "array",
              minItems: 1,
              maxItems: 100,
              uniqueItems: true,
              items: { type: "string", format: "uuid" },
            },
          },
        },
      },
    },
    async (request, reply) => {
      const actor = await requireAdmin(db, config, request, reply);
      if (!actor) return;
      if (request.params.userId === actor.user.id) {
        return reply.code(409).send({
          error: {
            code: "SELF_MODIFICATION_NOT_ALLOWED",
            message: "Administrator branch scope is global and cannot be edited.",
          },
        });
      }

      const target = await db.user.findUnique({
        where: { id: request.params.userId },
      });
      if (!target) {
        return reply.code(404).send({
          error: { code: "USER_NOT_FOUND", message: "User not found." },
        });
      }
      if (target.role === "ADMIN") {
        return reply.code(409).send({
          error: {
            code: "ADMIN_MANAGEMENT_RESTRICTED",
            message: "Administrator accounts have global branch scope.",
          },
        });
      }

      try {
        const branches = await db.$transaction(async (tx) => {
          const available = await tx.branch.findMany({
            where: {
              id: { in: request.body.branchIds },
              status: "ACTIVE",
              deletedAt: null,
            },
            select: { id: true, branchCode: true, name: true },
          });
          if (available.length !== request.body.branchIds.length) {
            throw new BranchSelectionError("One or more branches are unavailable.");
          }

          const now = new Date();
          await tx.userBranchAccess.updateMany({
            where: { userId: target.id, revokedAt: null },
            data: { revokedAt: now },
          });
          await tx.userBranchAccess.createMany({
            data: request.body.branchIds.map((branchId) => ({
              userId: target.id,
              branchId,
              grantedByUserId: actor.user.id,
            })),
          });
          await tx.auditEvent.create({
            data: {
              actorUserId: actor.user.id,
              actorType: "USER",
              action: "USER_BRANCH_GRANTS_REPLACED",
              objectType: "user",
              objectId: target.id,
              outcome: "SUCCESS",
              requestId: request.id,
              sourceIp: request.ip,
              metadata: { branchIds: request.body.branchIds },
            },
          });
          return available;
        });

        return reply.send({ branches });
      } catch (error) {
        if (error instanceof BranchSelectionError) {
          return reply.code(400).send({
            error: {
              code: "INVALID_BRANCH_SELECTION",
              message: "One or more selected branches are unavailable.",
            },
          });
        }
        throw error;
      }
    },
  );
}
