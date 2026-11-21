import { hostname } from "node:os";
import { createInterface } from "node:readline";
import { prisma } from "@platform/database";
import { claimNextDiscoveryRun, recoverExpiredLeases } from "./queue.js";
import { startWorkerHealthServer, type WorkerHealthServer } from "./health-server.js";
const workerId = (process.env.WORKER_ID ?? "worker-" + hostname() + "-" + process.pid).slice(0, 128);
const pollIntervalMs = Number(process.env.WORKER_POLL_INTERVAL_MS ?? "2000");
const supportedSources: string[] = [];
if (!Number.isInteger(pollIntervalMs) || pollIntervalMs < 500 || pollIntervalMs > 30_000) throw new Error("WORKER_POLL_INTERVAL_MS must be between 500 and 30000.");
let stopping = false; let timer: NodeJS.Timeout | undefined; let wakeDelay: (() => void) | undefined;
let health: WorkerHealthServer | undefined; let shutdownPromise: Promise<void> | undefined;
const control = createInterface({ input: process.stdin, crlfDelay: Infinity });
function requestStop(): void { stopping = true; if (timer) clearTimeout(timer); timer = undefined; wakeDelay?.(); wakeDelay = undefined; control.close(); }
control.on("line", (line) => { if (line === "SHUTDOWN") requestStop(); });
async function tick(): Promise<void> {
  if (stopping) return;
  await recoverExpiredLeases(prisma);
  // No source handlers are registered. The empty allow-list prevents claiming or acknowledging discovery work.
  const run = await claimNextDiscoveryRun(prisma, workerId, supportedSources);
  if (run) throw new Error("No handler registered for claimed discovery source: " + run.source);
}
async function loop(): Promise<void> {
  while (!stopping) {
    try { await tick(); } catch (error) { const message = error instanceof Error ? error.message : "Unknown worker error"; process.stderr.write("[worker] tick failed: " + message + "\n"); }
    if (!stopping) await new Promise<void>((resolve) => { wakeDelay = resolve; timer = setTimeout(() => { wakeDelay = undefined; timer = undefined; resolve(); }, pollIntervalMs); });
  }
}
async function shutdown(signal: string): Promise<void> {
  if (shutdownPromise) return shutdownPromise;
  requestStop();
  shutdownPromise = (async () => { process.stdout.write("[worker] received " + signal + "; shutting down\n"); if (health) { await health.close(); health = undefined; } await prisma.$disconnect(); })();
  return shutdownPromise;
}
await prisma.$queryRaw`SELECT 1`;
health = await startWorkerHealthServer({ port: 13002, isReady: async () => { if (stopping) return false; await prisma.$queryRaw`SELECT 1`; return true; } });
process.stdout.write("[worker] ready as " + workerId + "; health: http://127.0.0.1:13002/health/ready; discovery handlers: none (queue remains unclaimed)\n");
process.once("SIGINT", requestStop); process.once("SIGTERM", requestStop);
try { await loop(); } finally { await shutdown("process-exit"); }