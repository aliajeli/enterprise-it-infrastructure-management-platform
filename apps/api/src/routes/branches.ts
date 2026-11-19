import type { FastifyInstance } from "fastify";
import type { PrismaClient } from "@platform/database";
import type { ApiConfig } from "../config.js";
import { requireAdmin } from "../security/authorization.js";

interface CreateBranchBody {
  branchCode: string;
  name: string;
}

function hasPrismaCode(error: unknown, code: string): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === code
  );
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
      where: { deletedAt: null },
      orderBy: { branchCode: "asc" },
      select: {
        id: true,
        branchCode: true,
        name: true,
        status: true,
        createdAt: true,
      },
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

      const branchCode = request.body.branchCode.trim().toUpperCase();
      const name = request.body.name.trim();
      if (!/^[A-Z0-9][A-Z0-9-]{1,31}$/.test(branchCode) || name.length < 2) {
        return reply.code(400).send({
          error: { code: "INVALID_BRANCH", message: "Branch code or name is invalid." },
        });
      }

      try {
        const branch = await db.$transaction(async (tx) => {
          const created = await tx.branch.create({
            data: { branchCode, name, status: "ACTIVE" },
            select: {
              id: true,
              branchCode: true,
              name: true,
              status: true,
              createdAt: true,
            },
          });
          await tx.auditEvent.create({
            data: {
              actorUserId: actor.user.id,
              actorType: "USER",
              action: "BRANCH_CREATED",
              objectType: "branch",
              objectId: created.id,
              outcome: "SUCCESS",
              requestId: request.id,
              sourceIp: request.ip,
              metadata: { branchCode },
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
              message: "An active branch already uses this code.",
            },
          });
        }
        throw error;
      }
    },
  );
}
