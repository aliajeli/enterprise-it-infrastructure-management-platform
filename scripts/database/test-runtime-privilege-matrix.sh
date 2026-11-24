#!/usr/bin/env bash
set -euo pipefail

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-platform}"
PGDATABASE="${PGDATABASE:-platform_test}"
export PGHOST PGPORT

admin_password="${PGPASSWORD:?PGPASSWORD must contain the disposable CI administrator password}"
api_role="platform_api_runtime_test"
worker_role="platform_worker_runtime_test"
api_password="api_runtime_test_password"
worker_password="worker_runtime_test_password"

admin_psql() {
  PGPASSWORD="$admin_password" psql --no-psqlrc --set ON_ERROR_STOP=1 --host "$PGHOST" --port "$PGPORT" --username "$PGUSER" --dbname "$PGDATABASE" "$@"
}

cleanup_roles() {
  for role in "$api_role" "$worker_role"; do
    admin_psql --command "DROP OWNED BY \"$role\"" >/dev/null 2>&1 || true
    admin_psql --command "DROP ROLE IF EXISTS \"$role\"" >/dev/null 2>&1 || true
  done
}
cleanup_roles
trap cleanup_roles EXIT

admin_psql --command "CREATE ROLE \"$api_role\" LOGIN PASSWORD '$api_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS"
admin_psql --command "CREATE ROLE \"$worker_role\" LOGIN PASSWORD '$worker_password' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS"
admin_psql --command "GRANT CONNECT ON DATABASE \"$PGDATABASE\" TO \"$api_role\", \"$worker_role\""
admin_psql --command "REVOKE ALL ON SCHEMA public FROM PUBLIC"
admin_psql --command "GRANT USAGE ON SCHEMA public TO \"$api_role\", \"$worker_role\""
admin_psql --command "REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, \"$api_role\", \"$worker_role\""

for table in users sessions branches user_branch_access assets switch_profiles switch_ports discovery_runs; do
  admin_psql --command "GRANT SELECT, INSERT, UPDATE ON TABLE public.\"$table\" TO \"$api_role\""
done
admin_psql --command "GRANT INSERT ON TABLE public.audit_events TO \"$api_role\""
admin_psql --command "GRANT SELECT, INSERT ON TABLE public.port_observations TO \"$api_role\""
admin_psql --command "GRANT SELECT, UPDATE ON TABLE public.discovery_runs TO \"$worker_role\""

expect_success() {
  local role="$1" password="$2" sql="$3" label="$4"
  if ! PGPASSWORD="$password" psql --no-psqlrc --set ON_ERROR_STOP=1 --host "$PGHOST" --port "$PGPORT" --username "$role" --dbname "$PGDATABASE" --command "$sql" >/dev/null 2>&1; then
    printf 'Expected permitted operation failed for %s: %s\n' "$role" "$label" >&2
    exit 1
  fi
}
expect_denied() {
  local role="$1" password="$2" sql="$3" label="$4" diagnostic
  # An arbitrary error (syntax, missing table, connection failure, etc.) does
  # not prove a privilege boundary. Ask psql for SQLSTATE, check for 42501,
  # and never print the raw diagnostic, which can contain SQL or secrets.
  if diagnostic=$(PGPASSWORD="$password" psql --no-psqlrc --set ON_ERROR_STOP=1 --set VERBOSITY=verbose --host "$PGHOST" --port "$PGPORT" --username "$role" --dbname "$PGDATABASE" --command "$sql" 2>&1); then
    printf 'Unexpectedly permitted operation for %s: %s\n' "$role" "$label" >&2
    exit 1
  fi
  if ! printf '%s\n' "$diagnostic" | grep -Eq 'ERROR:[[:space:]]+42501:'; then
    printf 'Operation failed for a reason other than insufficient privilege for %s: %s\n' "$role" "$label" >&2
    exit 1
  fi
}

# API positive access: all current-source candidate tables and the append-only INSERT path.
for table in users sessions branches user_branch_access assets switch_profiles switch_ports discovery_runs; do
  expect_success "$api_role" "$api_password" "SELECT * FROM public.\"$table\" LIMIT 0" "SELECT $table"
done
expect_success "$api_role" "$api_password" "INSERT INTO public.audit_events (id, actor_type, action, object_type, outcome) VALUES (gen_random_uuid(), 'SYSTEM', 'PRIVILEGE_TEST', 'test', 'SUCCESS')" "INSERT audit_events"
expect_success "$api_role" "$api_password" "SELECT * FROM public.port_observations LIMIT 0" "SELECT port_observations"

# API negative access: append-only mutation, unlisted model, migration metadata and DDL.
expect_denied "$api_role" "$api_password" "UPDATE public.audit_events SET action=action" "UPDATE audit_events"
expect_denied "$api_role" "$api_password" "DELETE FROM public.audit_events" "DELETE audit_events"
expect_denied "$api_role" "$api_password" "UPDATE public.port_observations SET vlan_id=vlan_id" "UPDATE port_observations"
expect_denied "$api_role" "$api_password" "DELETE FROM public.port_observations" "DELETE port_observations"
expect_denied "$api_role" "$api_password" "SELECT * FROM public.recovery_codes LIMIT 0" "SELECT recovery_codes"
expect_denied "$api_role" "$api_password" "SELECT * FROM public._prisma_migrations LIMIT 0" "SELECT migration metadata"
expect_denied "$api_role" "$api_password" "CREATE TABLE public.api_runtime_forbidden(id integer)" "CREATE TABLE"
expect_denied "$api_role" "$api_password" "TRUNCATE public.users" "TRUNCATE users"
expect_denied "$api_role" "$api_password" "CREATE DATABASE api_runtime_forbidden" "CREATE DATABASE"
expect_denied "$api_role" "$api_password" "ALTER TABLE public.users ADD COLUMN privilege_probe integer" "ALTER TABLE users"

# Worker positive access is intentionally limited to the queue table.
expect_success "$worker_role" "$worker_password" "SELECT * FROM public.discovery_runs LIMIT 0" "SELECT discovery_runs"
expect_success "$worker_role" "$worker_password" "UPDATE public.discovery_runs SET heartbeat_at=heartbeat_at WHERE false" "UPDATE discovery_runs"

# Worker must not access application data outside its queue, mutate queue membership,
# inspect migration state, or perform DDL/administrative operations.
for table in users sessions branches user_branch_access assets switch_profiles switch_ports audit_events port_observations recovery_codes; do
  expect_denied "$worker_role" "$worker_password" "SELECT * FROM public.\"$table\" LIMIT 0" "SELECT $table"
done
expect_denied "$worker_role" "$worker_password" "INSERT INTO public.discovery_runs (id, branch_id, source) VALUES (gen_random_uuid(), gen_random_uuid(), 'MANUAL')" "INSERT discovery_runs"
expect_denied "$worker_role" "$worker_password" "DELETE FROM public.discovery_runs" "DELETE discovery_runs"
expect_denied "$worker_role" "$worker_password" "SELECT * FROM public._prisma_migrations LIMIT 0" "SELECT migration metadata"
expect_denied "$worker_role" "$worker_password" "CREATE TABLE public.worker_runtime_forbidden(id integer)" "CREATE TABLE"
expect_denied "$worker_role" "$worker_password" "TRUNCATE public.discovery_runs" "TRUNCATE discovery_runs"
expect_denied "$worker_role" "$worker_password" "CREATE ROLE worker_runtime_forbidden" "CREATE ROLE"
expect_denied "$worker_role" "$worker_password" "ALTER TABLE public.discovery_runs ADD COLUMN privilege_probe integer" "ALTER TABLE discovery_runs"

# Compile the workspace package whose package.json exports point to dist/.
# Prisma client generation creates client sources but does not emit dist/index.js.
npm run build --workspace @platform/database

# Execute the actual Prisma integration suites before the disposable roles are dropped.
# Fixture/admin connections are used only for setup, cleanup and audit verification.
DATABASE_URL="postgresql://${api_role}:${api_password}@${PGHOST}:${PGPORT}/${PGDATABASE}?schema=public" API_TEST_FIXTURE_DATABASE_URL="postgresql://${PGUSER}:${admin_password}@${PGHOST}:${PGPORT}/${PGDATABASE}?schema=public" npm test --workspace @platform/api
DATABASE_URL="postgresql://${worker_role}:${worker_password}@${PGHOST}:${PGPORT}/${PGDATABASE}?schema=public" WORKER_TEST_FIXTURE_DATABASE_URL="postgresql://${PGUSER}:${admin_password}@${PGHOST}:${PGPORT}/${PGDATABASE}?schema=public" npm test --workspace @platform/worker

printf 'Runtime privilege matrix and restricted API/Worker Prisma integration suites passed against disposable PostgreSQL. No production role or grant was created.\n'
