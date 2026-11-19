import "dotenv/config";
import { prisma } from "@platform/database";
import { buildApp } from "./app.js";
import { loadApiConfig } from "./config.js";

const config = loadApiConfig();
const app = await buildApp({ db: prisma, config });

try {
  await app.listen({ host: config.host, port: config.port });
  app.log.info(
    { host: config.host, port: config.port },
    "API service listening",
  );
} catch (error) {
  app.log.error({ err: error }, "API service failed to start");
  await app.close();
  await prisma.$disconnect();
  process.exitCode = 1;
}

async function shutdown(signal: string): Promise<void> {
  app.log.info({ signal }, "API service shutting down");
  await app.close();
  await prisma.$disconnect();
}

process.once("SIGINT", () => void shutdown("SIGINT"));
process.once("SIGTERM", () => void shutdown("SIGTERM"));
