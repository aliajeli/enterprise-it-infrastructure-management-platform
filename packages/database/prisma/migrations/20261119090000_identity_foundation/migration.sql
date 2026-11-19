CREATE TYPE "user_role" AS ENUM ('ADMIN', 'OPERATOR', 'VIEWER');
CREATE TYPE "user_status" AS ENUM ('ACTIVE', 'DISABLED');
CREATE TYPE "branch_status" AS ENUM ('ACTIVE', 'INACTIVE');
CREATE TYPE "audit_actor_type" AS ENUM ('USER', 'SYSTEM', 'AGENT', 'WORKER');
CREATE TYPE "audit_outcome" AS ENUM ('SUCCESS', 'FAILURE', 'DENIED');

CREATE TABLE "users" (
  "id" UUID NOT NULL,
  "username" VARCHAR(64) NOT NULL,
  "username_normalized" VARCHAR(64) NOT NULL,
  "password_hash" VARCHAR(255) NOT NULL,
  "role" "user_role" NOT NULL DEFAULT 'VIEWER',
  "status" "user_status" NOT NULL DEFAULT 'ACTIVE',
  "auth_epoch" INTEGER NOT NULL DEFAULT 0,
  "failed_login_count" INTEGER NOT NULL DEFAULT 0,
  "locked_until" TIMESTAMPTZ(6),
  "password_changed_at" TIMESTAMPTZ(6),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL,
  CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "users_username_normalized_key" ON "users"("username_normalized");
CREATE INDEX "users_status_role_idx" ON "users"("status", "role");

CREATE TABLE "sessions" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "token_hash" CHAR(64) NOT NULL,
  "auth_epoch" INTEGER NOT NULL,
  "expires_at" TIMESTAMPTZ(6) NOT NULL,
  "revoked_at" TIMESTAMPTZ(6),
  "last_seen_at" TIMESTAMPTZ(6),
  "ip_address" INET,
  "user_agent" VARCHAR(512),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "sessions_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "sessions_token_hash_key" ON "sessions"("token_hash");
CREATE INDEX "sessions_user_id_expires_at_idx" ON "sessions"("user_id", "expires_at");
CREATE INDEX "sessions_revoked_at_expires_at_idx" ON "sessions"("revoked_at", "expires_at");

CREATE TABLE "recovery_codes" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "code_hash" CHAR(64) NOT NULL,
  "expires_at" TIMESTAMPTZ(6) NOT NULL,
  "consumed_at" TIMESTAMPTZ(6),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "recovery_codes_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "recovery_codes_code_hash_key" ON "recovery_codes"("code_hash");
CREATE INDEX "recovery_codes_user_id_consumed_at_expires_at_idx" ON "recovery_codes"("user_id", "consumed_at", "expires_at");

CREATE TABLE "branches" (
  "id" UUID NOT NULL,
  "branch_code" VARCHAR(32) NOT NULL,
  "name" VARCHAR(160) NOT NULL,
  "status" "branch_status" NOT NULL DEFAULT 'ACTIVE',
  "deleted_at" TIMESTAMPTZ(6),
  "version" INTEGER NOT NULL DEFAULT 1,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL,
  CONSTRAINT "branches_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "branches_branch_code_deleted_at_idx" ON "branches"("branch_code", "deleted_at");
CREATE INDEX "branches_status_deleted_at_idx" ON "branches"("status", "deleted_at");
CREATE UNIQUE INDEX "branches_active_code_key" ON "branches"("branch_code") WHERE "deleted_at" IS NULL;

CREATE TABLE "user_branch_access" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "branch_id" UUID NOT NULL,
  "granted_by_user_id" UUID,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "revoked_at" TIMESTAMPTZ(6),
  CONSTRAINT "user_branch_access_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "user_branch_access_user_id_revoked_at_idx" ON "user_branch_access"("user_id", "revoked_at");
CREATE INDEX "user_branch_access_branch_id_revoked_at_idx" ON "user_branch_access"("branch_id", "revoked_at");
CREATE UNIQUE INDEX "user_branch_access_active_key" ON "user_branch_access"("user_id", "branch_id") WHERE "revoked_at" IS NULL;

CREATE TABLE "audit_events" (
  "id" UUID NOT NULL,
  "occurred_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "actor_user_id" UUID,
  "actor_type" "audit_actor_type" NOT NULL,
  "action" VARCHAR(100) NOT NULL,
  "object_type" VARCHAR(100) NOT NULL,
  "object_id" VARCHAR(128),
  "outcome" "audit_outcome" NOT NULL,
  "request_id" VARCHAR(128),
  "source_ip" INET,
  "metadata" JSONB,
  CONSTRAINT "audit_events_pkey" PRIMARY KEY ("id")
);
CREATE INDEX "audit_events_occurred_at_idx" ON "audit_events"("occurred_at" DESC);
CREATE INDEX "audit_events_object_type_object_id_occurred_at_idx" ON "audit_events"("object_type", "object_id", "occurred_at" DESC);
CREATE INDEX "audit_events_actor_user_id_occurred_at_idx" ON "audit_events"("actor_user_id", "occurred_at" DESC);

ALTER TABLE "sessions"
  ADD CONSTRAINT "sessions_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "recovery_codes"
  ADD CONSTRAINT "recovery_codes_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "user_branch_access"
  ADD CONSTRAINT "user_branch_access_user_id_fkey"
  FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "user_branch_access"
  ADD CONSTRAINT "user_branch_access_branch_id_fkey"
  FOREIGN KEY ("branch_id") REFERENCES "branches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "user_branch_access"
  ADD CONSTRAINT "user_branch_access_granted_by_user_id_fkey"
  FOREIGN KEY ("granted_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "audit_events"
  ADD CONSTRAINT "audit_events_actor_user_id_fkey"
  FOREIGN KEY ("actor_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE FUNCTION prevent_audit_event_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_events is append-only';
END;
$$;
CREATE TRIGGER "audit_events_append_only"
  BEFORE UPDATE OR DELETE ON "audit_events"
  FOR EACH ROW EXECUTE FUNCTION prevent_audit_event_mutation();
