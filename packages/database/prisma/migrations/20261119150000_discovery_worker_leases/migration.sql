ALTER TABLE "discovery_runs"
  ADD COLUMN "lease_owner" VARCHAR(128),
  ADD COLUMN "lease_expires_at" TIMESTAMPTZ(6),
  ADD COLUMN "heartbeat_at" TIMESTAMPTZ(6),
  ADD COLUMN "attempt_count" INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN "max_attempts" INTEGER NOT NULL DEFAULT 3,
  ADD COLUMN "next_attempt_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  ADD COLUMN "cancel_requested_at" TIMESTAMPTZ(6);

ALTER TABLE "discovery_runs"
  ADD CONSTRAINT "discovery_runs_attempts_check"
    CHECK ("attempt_count" >= 0 AND "max_attempts" BETWEEN 1 AND 20 AND "attempt_count" <= "max_attempts"),
  ADD CONSTRAINT "discovery_runs_lease_pair_check"
    CHECK (("lease_owner" IS NULL) = ("lease_expires_at" IS NULL));

CREATE INDEX "discovery_runs_status_next_attempt_created_idx"
  ON "discovery_runs"("status", "next_attempt_at", "created_at");
CREATE INDEX "discovery_runs_lease_expires_at_idx"
  ON "discovery_runs"("lease_expires_at")
  WHERE "status" = 'RUNNING';
