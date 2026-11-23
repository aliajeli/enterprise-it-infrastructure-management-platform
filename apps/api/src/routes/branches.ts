import type { FastifyInstance } from "fastify";
import type { PrismaClient } from "@platform/database";
import { appendAuditEvent } from "../security/audit-events.js";
import type { ApiConfig } from "../config.js";
import { requireAdmin, requirePlatformAction } from "../security/authorization.js";

interface CreateBranchBody {
  branchCode: string;
  name: string;
}

interface UpdateBranchBody extends CreateBranchBody {
  version: number;
}

interface BranchVersionBody {
  version: number;
}

function hasPrismaCode(error: unknown, code: string): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === code
  );
}

const branchSelect = {
  id: true,
  branchCode: true,
  name: true,
  status: true,
  deletedAt: true,
  version: true,
  createdAt: true,
  updatedAt: true,
} as const;

function validateBranch(branchCodeValue: string, nameValue: string) {
  const branchCode = branchCodeValue.trim().toUpperCase();
  const name = nameValue.trim();
  if (!/^[A-Z0-9][A-Z0-9-]{1,31}$/.test(branchCode) || name.length < 2) {
    return null;
  }
  return { branchCode, name };
}

export async function registerBranchRoutes(
  app: FastifyInstance,
  db: PrismaClient,
  config: ApiConfig,
): Promise<void> {
  app.get("/api/v1/branches", async (request, reply) => {
    const actor = await requireAdmin(db, config, request, reply);
    if (!actor) return;

    const branches = await db.branch.findMany({
      orderBy: [{ deletedAt: "asc" }, { branchCode: "asc" }],
      select: branchSelect,
    });
    return reply.send({ branches });
  });

  // Return only active branches visible to the signed-in inventory user.
  app.get("/api/v1/branches/accessible", async (request, reply) => {
    const actor = await requirePlatformAction(db, config, request, reply, "inventory.read");
    if (!actor) return;

    const branches = await db.branch.findMany({
      where: {
        status: "ACTIVE",
        deletedAt: null,
        ...(actor.user.role === "ADMIN"
          ? {}
          : { accesses: { some: { userId: actor.user.id, revokedAt: null } } }),
      },
      orderBy: { branchCode: "asc" },
      select: branchSelect,
    });
    return reply.send({ branches });
  });

  app.post<{ Body: CreateBranchBody }>(
    "/api/v1/branches",
    {
      config: { rateLimit: { max: 20, timeWindow: "15 minutes" } },
      schema: {
        body: {
          type: "object",
          required: ["branchCode", "name"],
          additionalProperties: false,
          properties: {
            branchCode: { type: "string", minLength: 2, maxLength: 32 },
            name: { type: "string", minLength: 2, maxLength: 160 },
          },
        },
      },
    },
    async (request, reply) => {
      const actor = await requireAdmin(db, config, request, reply);
      if (!actor) return;

      const values = validateBranch(request.body.branchCode, request.body.name);
      if (!values) {
        return reply.code(400).send({
          error: { code: "INVALID_BRANCH", message: "Branch code or name is invalid." },
        });
      }

      try {
        const branch = await db.$transaction(async (tx) => {
          const created = await tx.branch.create({
            data: { ...values, status: "ACTIVE" },
            select: branchSelect,
          });
          await appendAuditEvent(tx,{
            data: {
              actorUserId: actor.user.id,
              actorType: "USER",
              action: "BRANCH_CREATED",
              objectType: "branch",
              objectId: created.id,
              outcome: "SUCCESS",
              requestId: request.id,
              sourceIp: request.ip,
              metadata: { branchCode: values.branchCode },
            },
          });
          return created;
        });
        return reply.code(201).send({ branch });
      } catch (error) {
        if (hasPrismaCode(error, "P2002")) {
          return reply.code(409).send({
            error: {
              code: "BRANCH_CODE_EXISTS",
              message: "A branch already uses this code. Restore it or choose another code.",
            },
          });
        }
        throw error;
      }
    },
  );

  app.patch<{ Params: { branchId: string }; Body: UpdateBranchBody }>(
    "/api/v1/branches/:branchId",
    {
      schema: {
        params: {
          type: "object",
          required: ["branchId"],
          properties: { branchId: { type: "string", format: "uuid" } },
        },
        body: {
          type: "object",
          required: ["branchCode", "name", "version"],
          additionalProperties: false,
          properties: {
            branchCode: { type: "string", minLength: 2, maxLength: 32 },
            name: { type: "string", minLength: 2, maxLength: 160 },
            version: { type: "integer", minimum: 1 },
          },
        },
      },
    },
    async (request, reply) => {
      const actor = await requireAdmin(db, config, request, reply);
      if (!actor) return;
      const values = validateBranch(request.body.branchCode, request.body.name);
      if (!values) {
        return reply.code(400).send({
          error: { code: "INVALID_BRANCH", message: "Branch code or name is invalid." },
        });
      }

      try {
        const result = await db.$transaction(async (tx) => {
          const updated = await tx.branch.updateMany({
            where: {
              id: request.params.branchId,
              version: request.body.version,
              deletedAt: null,
            },
            data: { ...values, version: { increment: 1 } },
          });
          if (updated.count !== 1) return null;
          const branch = await tx.branch.findUniqueOrThrow({
            where: { id: request.params.branchId },
            select: branchSelect,
          });
          await appendAuditEvent(tx,{
            data: {
              actorUserId: actor.user.id,
              actorType: "USER",
              action: "BRANCH_UPDATED",
              objectType: "branch",
              objectId: branch.id,
              outcome: "SUCCESS",
              requestId: request.id,
              sourceIp: request.ip,
              metadata: {
                branchCode: values.branchCode,
                name: values.name,
                version: branch.version,
              },
            },
          });
          return branch;
        });
        if (!result) {
          const exists = await db.branch.findUnique({
            where: { id: request.params.branchId },
            select: { id: true, deletedAt: true },
          });
          if (!exists || exists.deletedAt) {
            return reply.code(404).send({
              error: { code: "BRANCH_NOT_FOUND", message: "Active branch not found." },
            });
          }
          return reply.code(409).send({
            error: { code: "BRANCH_VERSION_CONFLICT", message: "Branch changed. Refresh and retry." },
          });
        }
        return reply.send({ branch: result });
      } catch (error) {
        if (hasPrismaCode(error, "P2002")) {
          return reply.code(409).send({
            error: { code: "BRANCH_CODE_EXISTS", message: "Branch code is already in use." },
          });
        }
        throw error;
      }
    },
  );

  app.post<{ Params: { branchId: string }; Body: BranchVersionBody }>(
    "/api/v1/branches/:branchId/archive",
    {
      schema: {
        params: {
          type: "object",
          required: ["branchId"],
          properties: { branchId: { type: "string", format: "uuid" } },
        },
        body: {
          type: "object",
          required: ["version"],
          additionalProperties: false,
          properties: { version: { type: "integer", minimum: 1 } },
        },
      },
    },
    async (request, reply) => {
      const actor = await requireAdmin(db, config, request, reply);
      if (!actor) return;
      const now = new Date();
      const archived = await db.$transaction(async (tx) => {
        const changed = await tx.branch.updateMany({
          where: {
            id: request.params.branchId,
            version: request.body.version,
            deletedAt: null,
          },
          data: {
            status: "INACTIVE",
            deletedAt: now,
            version: { increment: 1 },
          },
        });
        if (changed.count !== 1) return false;

        // Archived branch grants are revoked, not silently reactivated on restore.
        await tx.userBranchAccess.updateMany({
          where: { branchId: request.params.branchId, revokedAt: null },
          data: { revokedAt: now },
        });
        await appendAuditEvent(tx,{
          data: {
            actorUserId: actor.user.id,
            actorType: "USER",
            action: "BRANCH_ARCHIVED",
            objectType: "branch",
            objectId: request.params.branchId,
            outcome: "SUCCESS",
            requestId: request.id,
            sourceIp: request.ip,
            metadata: { version: request.body.version + 1, grantsRevoked: true },
          },
        });
        return true;
      });
      if (!archived) {
        const existing = await db.branch.findUnique({
          where: { id: request.params.branchId },
          select: { id: true, deletedAt: true },
        });
        if (!existing || existing.deletedAt) {
          return reply.code(404).send({
            error: { code: "BRANCH_NOT_FOUND", message: "Active branch not found." },
          });
        }
        return reply.code(409).send({
          error: { code: "BRANCH_VERSION_CONFLICT", message: "Branch changed. Refresh and retry." },
        });
      }
      return reply.code(204).send();
    },
  );

  app.post<{ Params: { branchId: string }; Body: BranchVersionBody }>(
    "/api/v1/branches/:branchId/restore",
    {
      schema: {
        params: {
          type: "object",
          required: ["branchId"],
          properties: { branchId: { type: "string", format: "uuid" } },
        },
        body: {
          type: "object",
          required: ["version"],
          additionalProperties: false,
          properties: { version: { type: "integer", minimum: 1 } },
        },
      },
    },
    async (request, reply) => {
      const actor = await requireAdmin(db, config, request, reply);
      if (!actor) return;
      let restored;
      try {
        restored = await db.$transaction(async (tx) => {
        const changed = await tx.branch.updateMany({
          where: {
            id: request.params.branchId,
            version: request.body.version,
            deletedAt: { not: null },
          },
          data: {
            status: "ACTIVE",
            deletedAt: null,
            version: { increment: 1 },
          },
        });
        if (changed.count !== 1) return null;
        const branch = await tx.branch.findUniqueOrThrow({
          where: { id: request.params.branchId },
          select: branchSelect,
        });
        await appendAuditEvent(tx,{
          data: {
            actorUserId: actor.user.id,
            actorType: "USER",
            action: "BRANCH_RESTORED",
            objectType: "branch",
            objectId: branch.id,
            outcome: "SUCCESS",
            requestId: request.id,
            sourceIp: request.ip,
            metadata: {
              version: branch.version,
              grantsRestored: false,
            },
          },
        });
        return branch;
      });
      } catch (error) {
        if (hasPrismaCode(error, "P2002")) {
          return reply.code(409).send({
            error: {
              code: "BRANCH_CODE_EXISTS",
              message: "Another active branch is using this code. Rename that branch or choose a new code before restoring.",
            },
          });
        }
        throw error;
      }
      if (!restored) {
        const existing = await db.branch.findUnique({
          where: { id: request.params.branchId },
          select: { id: true, deletedAt: true },
        });
        if (!existing) {
          return reply.code(404).send({
            error: { code: "BRANCH_NOT_FOUND", message: "Branch not found." },
          });
        }
        return reply.code(409).send({
          error: {
            code: "BRANCH_NOT_ARCHIVED_OR_VERSION_CONFLICT",
            message: "Branch is not archived or its version changed. Refresh and retry.",
          },
        });
      }
      return reply.send({ branch: restored });
    },
  );
}
