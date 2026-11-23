# PostgreSQL runtime privilege inventory and migration ownership gate

Status: source-derived privilege inventory and design gate. This document is not a grant script, role bootstrap implementation, migration runner, or installer acceptance result.

## Scope and evidence

Reviewed the API route and security modules, Worker entry point and queue implementation, Prisma schema, and all four current Prisma migrations at commit `ff84555d4a9f8d961ba94c746abc993c77be4f98`.

The inventory below describes operations visible in the current source tree. It must be regenerated and reviewed whenever API routes, Worker handlers, Prisma models, raw SQL, or migrations change. It does not replace PostgreSQL integration tests against the exact deployed schema.

## Current API data access

| Database object | Source evidence | Candidate API privileges | Notes |
|---|---|---|---|
| `users` | Authentication, user administration, session resolution, bootstrap CLI | SELECT, INSERT, UPDATE | API reads user records, creates managed users, updates account/password/lockout state. The one-time bootstrap CLI is a separate deployment operation and must not run under the API runtime identity. |
| `sessions` | Authentication and session lifecycle | SELECT, INSERT, UPDATE | Login creates; session resolution reads; logout/password/status changes revoke/update. No DELETE path was identified. |
| `branches` | Branch administration and inventory authorization | SELECT, INSERT, UPDATE | API reads and manages branches; no hard-delete path was identified. |
| `user_branch_access` | User and branch administration, authorization checks | SELECT, INSERT, UPDATE | Nested Prisma relation writes and revocation/update paths are present. |
| `audit_events` | Authentication, user, branch and inventory audit writes | INSERT | The migration installs an append-only trigger. Current reviewed API paths write audit events; no API read path was identified. Do not grant UPDATE or DELETE. |
| `assets` | Inventory routes and branch-scoped asset lookup/management | SELECT, INSERT, UPDATE | Soft-delete/status and metadata changes are represented as updates; no hard-delete path was identified. |
| `switch_profiles` | Inventory relation reads and nested switch-profile creation | SELECT, INSERT, UPDATE | Verify exact nested-write behavior against Prisma-generated SQL before finalizing grants. |
| `switch_ports` | Inventory port metadata routes | SELECT, INSERT, UPDATE | Metadata is created and updated with optimistic version checks. |
| `port_observations` | Inventory observation reads and writes | SELECT, INSERT | The migration installs an append-only trigger. Do not grant UPDATE or DELETE. |
| `discovery_runs` | Inventory discovery lifecycle and API queue management | SELECT, INSERT, UPDATE | API creates/reads runs and updates lifecycle/cancellation state. Do not grant DELETE without a new source-level requirement. |
| `recovery_codes` | Prisma model and migration only | No grant identified | No current API/Worker code path references the model. Keep inaccessible until a feature and tests require it. |

The API candidate set is intentionally narrower than broad table-level CRUD. In particular, the append-only tables must not receive UPDATE/DELETE, and no current source path justifies TRUNCATE, REFERENCES, TRIGGER, CREATE, or ownership privileges for the API runtime.

## Current Worker data access

The Worker entry point calls `recoverExpiredLeases` and `claimNextDiscoveryRun`. The source allow-list is currently empty, so no discovery job is claimed. No discovery handlers are registered.

The current queue recovery operations UPDATE `discovery_runs`; the claim query, when an allow-list is later enabled, reads and updates that same table using `FOR UPDATE SKIP LOCKED`. PostgreSQL UPDATE statements also need SELECT rights for columns read by predicates/expressions. The narrow candidate Worker privilege is therefore:

- `USAGE` on the application schema and `CONNECT` on the application database.
- `SELECT, UPDATE` on `discovery_runs` only.
- No INSERT/DELETE/TRUNCATE, no schema CREATE, no migration metadata ownership, no superuser/CREATEDB/CREATEROLE.
- No privileges on users, sessions, branches, assets, switch profiles, switch ports, audit events, port observations or recovery codes based on current Worker source.

This is a current-source baseline, not a promise about future discovery handlers. Before enabling any source handler, inventory its Prisma delegates and raw SQL, add only the required table/column privileges, and add positive/negative tests.

## PostgreSQL object and schema considerations

- The current migrations create UUID primary keys in application code and do not declare serial/identity sequences. No sequence grants are justified by the current migration set.
- The migration set creates PostgreSQL enum types, tables, indexes, foreign keys, check constraints, and two PL/pgSQL trigger functions. Migration execution therefore needs DDL capabilities unavailable to API/Worker runtime roles.
- Foreign-key relationships and Prisma nested writes must be tested under the candidate API role; do not infer that table grants alone are sufficient without running the actual integration suite.
- The API readiness check only tests connectivity and `to_regclass('public.users')`; it does not prove that API queries have all required grants or that migrations are current.
- The API's interactive administrator bootstrap CLI creates the initial user and audit event. It is a separate one-time operational task; do not silently run it from API service startup or grant the API runtime migration/owner privileges for it.

## Migration ownership blocker

The intended separation remains:

1. `platform_admin`: one-time cluster/database/role administration only.
2. Schema owner: owns the application schema and migration-created objects.
3. Migration login: short-lived deployment identity only.
4. API runtime login: the API candidate privileges above.
5. Worker runtime login: the Worker candidate privileges above.

The Prisma role-default mechanism has a disposable PostgreSQL 18 / Prisma 7.10.1 CI proof-of-concept; production deployment suitability, secure credential transport and Windows acceptance remain unvalidated. PostgreSQL role membership/inherited privileges do not by themselves establish the desired object ownership. The deployment must prove which database role is `current_user` for every migration connection and for creation of `_prisma_migrations`, tables, enum types, indexes, and trigger functions.

Do not implement a role bootstrap based on an assumed `SET ROLE` behavior or an unverified connection-string startup option. Before implementation, run a disposable PostgreSQL 18 integration experiment using the exact pinned Prisma CLI/engine and prove:

1. Migration login authentication succeeds without embedding the secret in process arguments, logs, persistent environment variables or service configuration.
2. Migration DDL is executed with the intended owner identity on every connection.
3. `_prisma_migrations` and all created objects have the intended owner.
4. Repeated `prisma migrate deploy` is a no-op and preserves ownership.
5. A failed/interrupted migration can be retried without destructive database recreation.
6. API and Worker runtime roles pass all required application tests and fail explicit DDL, migration-table mutation, and unauthorized-table tests.
7. The bootstrap/migration credentials never enter API/Worker DPAPI configuration.

If Prisma Migrate cannot satisfy the ownership contract using a supported and tested mechanism, revise the identity design explicitly rather than granting the migration login permanent schema ownership or broad runtime privileges.

## Required acceptance tests before grants are frozen

- Run API integration tests using only the API runtime login and the candidate privilege matrix.
- Run Worker queue tests using only the Worker runtime login; assert it cannot read/write unrelated application tables.
- Assert API and Worker cannot CREATE/ALTER/DROP schema objects, alter roles, create databases, access migration metadata, or assume ownership.
- Assert API can INSERT but cannot UPDATE/DELETE `audit_events` or `port_observations`.
- Assert no runtime role can TRUNCATE tables or assume ownership.
- Capture effective grants and object owners after clean install and after repeated migration deployment.
- Re-run this inventory whenever source routes, Worker handlers, raw SQL or Prisma migrations change.

## Current status

This is documentation based on source inspection. No database role, grant, ownership, migration runner, secret transport, or installer behavior changed. The PostgreSQL first-install and migration blockers remain open; no production-ready installer or Release is claimed.

## Automated migration-owner experiment

The validation workflow now includes a disposable PostgreSQL 18 experiment using the exact repository-pinned Prisma CLI (7.10.1). It creates a non-login schema owner and a separate deployment login, grants explicit `SET` membership, configures the login's session role, verifies `session_user` differs from `current_user`, runs `prisma migrate deploy` twice, and checks database, migration table, tables/indexes/sequences/views, enum types and functions for owner consistency.

**Result: passed on exact head `bc21475f04338c52c279c0b3366906209c52db43`.** Push run `45148082967` and PR-event run `45148094311` completed successfully. The experiment log reports `session_user=platform_migrator`, `current_user=platform_schema_owner`, database/schema/migration-object ownership by `platform_schema_owner`, and successful repeated `prisma migrate deploy`.

This closes only the disposable PostgreSQL 18 / Prisma 7.10.1 proof-of-concept for the role-default ownership mechanism. It does not establish production suitability or test Windows secret transport, clean Windows Server deployment, runtime API/Worker grants, interrupted migration recovery, or installer integration. Production use remains blocked until those separate acceptance gates pass.


## Automated runtime privilege-boundary experiment

The validation workflow now runs `scripts/database/test-runtime-privilege-matrix.sh` after the baseline migrations. It creates disposable API and Worker login roles, applies the current source-derived candidate grants, and connects as each role to verify allowed and denied SQL operations. The API test covers candidate table reads/writes, append-only table mutation denial, unlisted recovery-code and migration-metadata denial, and DDL/TRUNCATE/database-creation denial. The Worker test verifies SELECT/UPDATE on `discovery_runs` only and denies access to other application tables, queue INSERT/DELETE, migration metadata and administrative DDL.

This is a SQL-level CI experiment, not production role provisioning. It does not yet execute the API's Prisma route/integration suite using the restricted API login or the Worker queue integration suite using the restricted Worker login. It also does not prove production connection configuration, secure credential transport, migration interruption/retry, or Windows Server virtual-account acceptance. Keep the candidate matrix provisional until those tests pass.


## Restricted Prisma integration execution

The runtime privilege CI script now invokes the API and Worker workspace integration suites before its cleanup trap removes the disposable roles. API route operations use the API candidate login; a separate administrator fixture connection is limited to audit-event assertions. Worker queue operations use the Worker candidate login; a separate fixture connection creates and removes test branches and queue rows. The Worker runtime identity remains restricted to SELECT/UPDATE on discovery_runs. This implementation of the integration-test gate remains pending exact-head CI. It does not provision production roles or credentials.
