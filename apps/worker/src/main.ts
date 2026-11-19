import { hostname } from "node:os";
import { prisma } from "@platform/database";
import {
  claimNextDiscoveryRun,
  recoverExpiredLeases,
} from "./queue.js";

const workerId = (process.env.WORKER_ID ?? `worker-${hostname()}-${process.pid}`).slice(0, 128);
const pollIntervalMs = Number(process.env.WORKER_POLL_INTERVAL_MS ?? "2000");
const supportedSources: string[] = [];

if (!Number.isInteger(pollIntervalMs) || pollIntervalMs < 500 || pollIntervalMs > 30_000) {
  throw new Error("WORKER_POLL_INTERVAL_MS must be between 500 and 30000.");
}

let stopping = false;
let timer: NodeJS.Timeout | undefined;

async function tick(): Promise<void> {
  if (stopping) return;
  await recoverExpiredLeases(prisma);

  // Deliberately no source handlers are registered in this milestone.
  // An empty allow-list prevents the worker from claiming work it cannot execute.
  const run = await claimNextDiscoveryRun(prisma, workerId, supportedSources);
  if (run) {
    throw new Error(`No handler registered for claimed discovery source: ${run.source}`);
  }
}

async function loop(): Promise<void> {
  while (!stopping) {
    try {
      await tick();
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown worker error";
      process.stderr.write(`[worker] tick failed: ${message}\n`);
    }
    if (!stopping) {
      await new Promise<void>((resolve) => {
        timer = setTimeout(resolve, pollIntervalMs);
      });
    }
  }
}

async function shutdown(signal: string): Promise<void> {
  if (stopping) return;
  stopping = true;
  if (timer) clearTimeout(timer);
  process.stdout.write(`[worker] received ${signal}; shutting down\n`);
  await prisma.$disconnect();
}

await prisma.$queryRaw`SELECT 1`;
process.stdout.write(`[worker] ready as ${workerId}; discovery handlers: none (queue remains unclaimed)\n`);
process.once("SIGINT", () => void shutdown("SIGINT"));
process.once("SIGTERM", () => void shutdown("SIGTERM"));
await loop();
await prisma.$disconnect();
