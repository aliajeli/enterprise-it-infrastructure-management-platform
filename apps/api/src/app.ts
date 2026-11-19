import Fastify, { type FastifyInstance } from "fastify";
import cookie from "@fastify/cookie";
import helmet from "@fastify/helmet";
import rateLimit from "@fastify/rate-limit";
import type { PrismaClient } from "@platform/database";
import type { ApiConfig } from "./config.js";
import { registerAuthRoutes } from "./routes/auth.js";
import { registerHealthRoutes } from "./routes/health.js";
import { registerUserRoutes } from "./routes/users.js";
import { registerBranchRoutes } from "./routes/branches.js";

export interface BuildAppOptions {
  db: PrismaClient;
  config: ApiConfig;
  logger?: boolean;
}

export async function buildApp({
  db,
  config,
  logger = true,
}: BuildAppOptions): Promise<FastifyInstance> {
  const app = Fastify({
    logger,
    trustProxy: "loopback",
    bodyLimit: 16 * 1024,
  });

  await app.register(cookie);
  await app.register(helmet);
  await app.register(rateLimit, {
    max: 120,
    timeWindow: "1 minute",
  });

  app.addHook("onRequest", async (request, reply) => {
    if (!["POST", "PUT", "PATCH", "DELETE"].includes(request.method)) {
      return;
    }

    if (request.headers.origin !== config.publicOrigin) {
      return reply.code(403).send({
        error: {
          code: "ORIGIN_REJECTED",
          message: "Request origin is not allowed.",
        },
      });
    }
  });

  app.setErrorHandler((error, request, reply) => {
    request.log.error(
      { err: error, requestId: request.id },
      "API request failed",
    );

    const candidateStatus =
      typeof error === "object" &&
      error !== null &&
      "statusCode" in error
        ? error.statusCode
        : undefined;
    const status =
      typeof candidateStatus === "number" &&
      candidateStatus >= 400 &&
      candidateStatus < 500
        ? candidateStatus
        : 500;
    const code =
      status === 429
        ? "RATE_LIMITED"
        : status === 400
          ? "INVALID_REQUEST"
          : "INTERNAL_ERROR";

    return reply.code(status).send({
      error: {
        code,
        message:
          status < 500 ? "Request rejected." : "An unexpected error occurred.",
        requestId: request.id,
      },
    });
  });

  app.addHook("onSend", async (request, reply, payload) => {
    if (request.url.startsWith("/api/v1/")) {
      reply.header("cache-control", "no-store, private");
      reply.header("pragma", "no-cache");
    }
    return payload;
  });

  await registerHealthRoutes(app, db);
  await registerAuthRoutes(app, db, config);
  await registerUserRoutes(app, db, config);
  await registerBranchRoutes(app, db, config);
  return app;
}
