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

let shutdownTask: Promise<void> | undefined;

function shutdown(signal: string): Promise<void> {
  shutdownTask ??= (async () => {
    app.log.info({ signal }, "API service shutting down");
    await app.close();
    await prisma.$disconnect();
  })();
  return shutdownTask;
}

process.once("SIGINT", () => void shutdown("SIGINT"));
process.once("SIGTERM", () => void shutdown("SIGTERM"));

// The Windows Service Host owns this process' stdin pipe. It can request a
// graceful stop without relying on console control events or forceful signals.
let hostControlBuffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk: string) => {
  hostControlBuffer += chunk;
  if (hostControlBuffer.length > 64) {
    hostControlBuffer = "";
    return;
  }

  const newline = hostControlBuffer.indexOf("\n");
  if (newline < 0) return;

  const command = hostControlBuffer.slice(0, newline).trim();
  hostControlBuffer = hostControlBuffer.slice(newline + 1);
  if (command === "SHUTDOWN") void shutdown("HOST");
});
