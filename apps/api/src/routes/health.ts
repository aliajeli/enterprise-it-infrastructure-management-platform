import type { FastifyInstance } from "fastify";
import type { PrismaClient } from "@platform/database";

export async function registerHealthRoutes(
  app: FastifyInstance,
  db: PrismaClient,
): Promise<void> {
  app.get("/health/live", async () => ({ status: "ok" }));

  app.get("/health/ready", async (_request, reply) => {
    try {
      const result = await db.$queryRaw<Array<{ schema_ready: boolean }>>`
        SELECT to_regclass('public.users') IS NOT NULL AS schema_ready
      `;

      if (!result[0]?.schema_ready) {
        return reply.code(503).send({ status: "not_ready" });
      }

      return { status: "ready" };
    } catch {
      return reply.code(503).send({ status: "not_ready" });
    }
  });
}
