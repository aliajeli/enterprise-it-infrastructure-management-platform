import { randomUUID } from "node:crypto";
import type { PrismaClient } from "@platform/database";

type AuditEventExecutor = Pick<PrismaClient, "$executeRaw">;

interface AuditEventInput {
  actorUserId?: string | null;
  actorType: "USER" | "SYSTEM" | "AGENT" | "WORKER";
  action: string;
  objectType: string;
  objectId?: string | null;
  outcome: "SUCCESS" | "FAILURE" | "DENIED";
  requestId?: string | null;
  sourceIp?: string | null;
  metadata?: unknown;
}

/**
 * Append an audit event without requiring SELECT on the append-only audit table.
 * Prisma create() emits INSERT ... RETURNING, which requires SELECT privileges
 * and would silently widen the API runtime role beyond its intended INSERT-only grant.
 */
export async function appendAuditEvent(
  tx: AuditEventExecutor,
  input: { data: AuditEventInput },
): Promise<void> {
  const data = input.data;
  const metadata = data.metadata == null ? null : JSON.stringify(data.metadata);
  if (metadata === undefined) {
    throw new TypeError("Audit metadata must be JSON serializable.");
  }

  const inserted = await tx.$executeRaw`
    INSERT INTO public.audit_events (
      id,
      actor_user_id,
      actor_type,
      action,
      object_type,
      object_id,
      outcome,
      request_id,
      source_ip,
      metadata
    )
    VALUES (
      ${randomUUID()}::uuid,
      ${data.actorUserId ?? null}::uuid,
      ${data.actorType}::public.audit_actor_type,
      ${data.action},
      ${data.objectType},
      ${data.objectId ?? null},
      ${data.outcome}::public.audit_outcome,
      ${data.requestId ?? null},
      ${data.sourceIp ?? null}::inet,
      ${metadata}::jsonb
    )
  `;

  if (inserted !== 1) {
    throw new Error("Audit event append did not insert exactly one row.");
  }
}
