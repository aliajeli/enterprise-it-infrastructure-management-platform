#!/usr/bin/env bash
set -euo pipefail

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-platform}"
PGDATABASE="${PGDATABASE:-platform_test}"
export PGHOST PGPORT

admin_password="${PGPASSWORD:?PGPASSWORD must contain the disposable CI administrator password}"
database="platform_migrate_owner_test"
owner="platform_schema_owner"
migrator="platform_migrator"
migrator_password="migration_test_password"

admin_psql() {
  PGPASSWORD="$admin_password" psql --no-psqlrc --set ON_ERROR_STOP=1 --host "$PGHOST" --port "$PGPORT" --username "$PGUSER" --dbname "$PGDATABASE" "$@"
}

# This runs only against the disposable PostgreSQL service used by CI.
admin_psql --command "DROP DATABASE IF EXISTS \"$database\" WITH (FORCE)"
admin_psql --command "DROP ROLE IF EXISTS \"$migrator\""
admin_psql --command "DROP ROLE IF EXISTS \"$owner\""
admin_psql --command "CREATE ROLE \"$owner\" NOLOGIN"
admin_psql --command "CREATE ROLE \"$migrator\" LOGIN NOINHERIT PASSWORD '$migrator_password'"
admin_psql --command "GRANT \"$owner\" TO \"$migrator\" WITH INHERIT FALSE, SET TRUE"
admin_psql --command "ALTER ROLE \"$migrator\" SET role = '$owner'"
admin_psql --command "CREATE DATABASE \"$database\" OWNER \"$owner\""

# Prove the login identity is distinct while effective current_user is the schema owner.
identity="$(PGPASSWORD="$migrator_password" psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --host "$PGHOST" --port "$PGPORT" --username "$migrator" --dbname "$database" --command 'SELECT session_user || "|" || current_user')"
if [[ "$identity" != "$migrator|$owner" ]]; then
  printf 'Unexpected migration identity: %s\n' "$identity" >&2
  exit 1
fi

migration_url="postgresql://$migrator:$migrator_password@$PGHOST:$PGPORT/$database?schema=public"
DATABASE_URL="$migration_url" npm run db:migrate:deploy
DATABASE_URL="$migration_url" npm run db:migrate:deploy

verify_ownership() {
  local query
  query="SELECT
    (SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = current_database()) = '$owner'
    AND (SELECT pg_get_userbyid(c.relowner) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname='_prisma_migrations') = '$owner'
    AND NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relkind IN ('r','p','i','S','v','m','f')
        AND pg_get_userbyid(c.relowner) <> '$owner'
    )
    AND NOT EXISTS (
      SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname='public' AND t.typtype='e'
        AND pg_get_userbyid(t.typowner) <> '$owner'
    )
    AND NOT EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND pg_get_userbyid(p.proowner) <> '$owner'
    )"
  local result
  result="$(PGPASSWORD="$migrator_password" psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 --host "$PGHOST" --port "$PGPORT" --username "$migrator" --dbname "$database" --command "$query")"
  if [[ "$result" != "t" ]]; then
    printf 'Prisma migration objects are not consistently owned by %s (result=%s).\n' "$owner" "$result" >&2
    exit 1
  fi
}
verify_ownership
printf 'Prisma Migrate ownership experiment passed: session_user=%s, current_user=%s, database/schema/migration objects owner=%s; repeated deploy succeeded.\n' "$migrator" "$owner" "$owner"
