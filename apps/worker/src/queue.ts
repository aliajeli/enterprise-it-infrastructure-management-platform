import type { PrismaClient } from "@platform/database";

export interface ClaimedDiscoveryRun {
  id: string;
  branch_id: string;
  target_asset_id: string | null;
  source: string;
  attempt_count: number;
  max_attempts: number;
  lease_expires_at: Date;
}

export async function recoverExpiredLeases(db: PrismaClient): Promise<number> {
  // Cancellation takes precedence over retry exhaustion when a lease expires.
  const cancelled = await db.$executeRaw`
    UPDATE discovery_runs
    SET status = 'CANCELLED',
        completed_at = NOW(),
        lease_owner = NULL,
        lease_expires_at = NULL,
        heartbeat_at = NULL
    WHERE status = 'RUNNING'
      AND lease_expires_at <= NOW()
      AND cancel_requested_at IS NOT NULL
  `;
  const requeued = await db.$executeRaw`
    UPDATE discovery_runs
    SET status = 'QUEUED',
        lease_owner = NULL,
        lease_expires_at = NULL,
        heartbeat_at = NULL,
        next_attempt_at = NOW(),
        error_code = 'WORKER_LEASE_EXPIRED',
        error_message = 'Worker lease expired; the run was returned to the queue.'
    WHERE status = 'RUNNING'
      AND lease_expires_at <= NOW()
      AND attempt_count < max_attempts
      AND cancel_requested_at IS NULL
  `;
  const exhausted = await db.$executeRaw`
    UPDATE discovery_runs
    SET status = 'FAILED',
        completed_at = NOW(),
        lease_owner = NULL,
        lease_expires_at = NULL,
        heartbeat_at = NULL,
        error_code = 'WORKER_LEASE_EXHAUSTED',
        error_message = 'Worker lease expired after the maximum number of attempts.'
    WHERE status = 'RUNNING'
      AND lease_expires_at <= NOW()
      AND attempt_count >= max_attempts
      AND cancel_requested_at IS NULL
  `;
  return Number(requeued) + Number(exhausted) + Number(cancelled);
}

export async function claimNextDiscoveryRun(
  db: PrismaClient,
  workerId: string,
  supportedSources: readonly string[],
  leaseMs = 30_000,
): Promise<ClaimedDiscoveryRun | null> {
  if (supportedSources.length === 0) return null;
  if (!workerId.trim() || workerId.length > 128) throw new Error("Invalid worker identity.");
  if (!Number.isInteger(leaseMs) || leaseMs < 5_000 || leaseMs > 300_000) {
    throw new Error("Lease duration must be between 5000 and 300000 milliseconds.");
  }

  const rows = await db.$queryRaw<ClaimedDiscoveryRun[]> `
    WITH candidate AS (
      SELECT id
      FROM discovery_runs
      WHERE status = 'QUEUED'
        AND source = ANY(${[...supportedSources]}::discovery_source[])
        AND next_attempt_at <= NOW()
        AND cancel_requested_at IS NULL
      ORDER BY next_attempt_at ASC, created_at ASC
      FOR UPDATE SKIP LOCKED
      LIMIT 1
    )
    UPDATE discovery_runs AS run
    SET status = 'RUNNING',
        lease_owner = ${workerId},
        lease_expires_at = NOW() + (${leaseMs} * INTERVAL '1 millisecond'),
        heartbeat_at = NOW(),
        started_at = COALESCE(started_at, NOW()),
        attempt_count = attempt_count + 1
    FROM candidate
    WHERE run.id = candidate.id
    RETURNING run.id, run.branch_id, run.target_asset_id, run.source,
              run.attempt_count, run.max_attempts, run.lease_expires_at
  `;
  return rows[0] ?? null;
}

export async function heartbeatDiscoveryRun(
  db: PrismaClient,
  runId: string,
  workerId: string,
  leaseMs = 30_000,
): Promise<boolean> {
  const updated = await db.$executeRaw`
    UPDATE discovery_runs
    SET heartbeat_at = NOW(),
        lease_expires_at = NOW() + (${leaseMs} * INTERVAL '1 millisecond')
    WHERE id = ${runId}::uuid
      AND status = 'RUNNING'
      AND lease_owner = ${workerId}
      AND lease_expires_at > NOW()
      AND cancel_requested_at IS NULL
  `;
  return Number(updated) === 1;
}

export async function completeDiscoveryRun(
  db: PrismaClient,
  runId: string,
  workerId: string,
  status: "SUCCEEDED" | "PARTIAL",
): Promise<boolean> {
  const updated = await db.$executeRaw`
    UPDATE discovery_runs
    SET status = ${status}::discovery_status,
        completed_at = NOW(),
        lease_owner = NULL,
        lease_expires_at = NULL,
        heartbeat_at = NULL
    WHERE id = ${runId}::uuid
      AND status = 'RUNNING'
      AND lease_owner = ${workerId}
      AND lease_expires_at > NOW()
      AND cancel_requested_at IS NULL
  `;
  return Number(updated) === 1;
}

export async function failDiscoveryRun(
  db: PrismaClient,
  runId: string,
  workerId: string,
  errorCode: string,
  safeMessage: string,
): Promise<"REQUEUED" | "FAILED" | "LEASE_LOST"> {
  const rows = await db.$queryRaw<Array<{ outcome: string }>> `
    UPDATE discovery_runs
    SET status = CASE WHEN attempt_count < max_attempts THEN 'QUEUED'::discovery_status
                      ELSE 'FAILED'::discovery_status END,
        next_attempt_at = NOW() + (
          LEAST(300000, 5000 * power(2, GREATEST(0, attempt_count - 1))) * INTERVAL '1 millisecond'
        ),
        completed_at = CASE WHEN attempt_count < max_attempts THEN NULL ELSE NOW() END,
        lease_owner = NULL,
        lease_expires_at = NULL,
        heartbeat_at = NULL,
        error_code = LEFT(${errorCode}, 100),
        error_message = LEFT(${safeMessage}, 1000)
    WHERE id = ${runId}::uuid
      AND status = 'RUNNING'
      AND lease_owner = ${workerId}
      AND lease_expires_at > NOW()
    RETURNING CASE WHEN status = 'QUEUED' THEN 'REQUEUED' ELSE 'FAILED' END AS outcome
  `;
  return (rows[0]?.outcome as "REQUEUED" | "FAILED" | undefined) ?? "LEASE_LOST";
}

export async function acknowledgeCancellation(
  db: PrismaClient,
  runId: string,
  workerId: string,
): Promise<boolean> {
  const updated = await db.$executeRaw`
    UPDATE discovery_runs
    SET status = 'CANCELLED',
        completed_at = NOW(),
        lease_owner = NULL,
        lease_expires_at = NULL,
        heartbeat_at = NULL
    WHERE id = ${runId}::uuid
      AND status = 'RUNNING'
      AND lease_owner = ${workerId}
      AND lease_expires_at > NOW()
      AND cancel_requested_at IS NOT NULL
  `;
  return Number(updated) === 1;
}
