# Windows PostgreSQL first-install and migration contract

> **Implementation update (0.1.233): Hosted CI confirmed that the isolated-account probe previously failed because its caller was an elevated Local Administrator; under the selected threat model that access is trusted and expected. The probe now classifies that caller as a positive control and reserves denial assertions for non-administrator callers. This is a test correction only: it does not demonstrate a standard-user attack against the dedicated service identity. The real initdb re-exec PROCESS_DUP_HANDLE probe, same-user synthetic handle interception, and real named-pipe PID mismatch remain unresolved. **
>
> **Implementation update (0.1.231): hosted synthetic stdin works functionally but same-user handle interception is reproducible; the real named-pipe client PID mismatch fails closed, and a separate test user did not isolate it from an elevated runner. Neither transport is approved for production. The 0.1.224 experimental pipe delays credential materialization and clears temporary buffers, but does not solve identity or handle interception. An additional no-secret process-object DACL/debug-privilege experiment showed that a protected System-owned process DACL denied same-user access with debug privilege disabled, but an elevated same-user process with debug privilege enabled obtained PROCESS_DUP_HANDLE; no initdb, credential or handle duplication was tested and it is not an approved channel. Disposable migrations passed on hosted Windows but do not establish cluster identity, production grants, bootstrap, migration or supported-server acceptance. See [HANDOVER](HANDOVER.md).**


Status: design/acceptance contract for the five-service Windows deployment workstream. This document does not claim that first-install database bootstrap or migrations are implemented.

**Safety correction (0.1.180):** The prior initializer wrote a temporary plaintext password file despite an ACL; this contradicts the owner instruction prohibiting such files. Its mutation path is now disabled. `experimental-initdb-pipe.ps1` is an isolated, synthetic-test-only candidate, not a reviewed or approved production credential channel; it is not integrated into the initializer or orchestration. Real Windows PostgreSQL, unauthorized-client, logging, crash and secure-custody acceptance remain mandatory.

## Verified current behavior

- `initialize-postgresql-cluster.ps1` currently fails closed before mutation; it does not initialize a cluster. The earlier implementation intended PostgreSQL 18 with SCRAM, `platform_admin` and loopback-only listening but was disabled because its credential transport violated policy.
- Historical initializer accepted a `SecureString` but wrote a temporary plaintext password file. That violated owner policy and its mutation path is disabled in 0.1.180; no claim is made that initialization is currently functional.
- `provision-postgresql-service.ps1` registers PostgreSQL under `NT SERVICE\\EnterpriseITPostgreSQL`, applies a dedicated service SID and data ACL, and deliberately does not start the service.
- `orchestrate-windows-services.ps1` contains service deployment and ordering code, but currently fails closed before mutation pending cluster ownership verification; it does not currently provision or start those services.
- The orchestrator does not invoke cluster initialization, create database roles, create the application database, execute Prisma migrations, or validate that the supplied API/Worker credentials exist and have the intended grants.
- API readiness checks database connectivity and the presence of `public.users`; this detects a missing baseline table but does not apply migrations.

## Required database identity separation

| Identity | Purpose | Required boundary |
|---|---|---|
| `platform_admin` | One-time cluster bootstrap and role/database administration | PostgreSQL superuser; never used by API, Worker or Web; credential must not be persisted in service configuration |
| Schema owner | Owns application schema objects and migration-created objects | Not used by API/Worker at runtime; ownership and default privileges must be deterministic |
| Migration identity | Executes the versioned Prisma migration set during an explicit deployment operation | Deployment-only credential; no service DPAPI config; no interactive application login |
| API runtime identity | Normal API data access | No superuser, CREATEDB, CREATEROLE, schema CREATE or migration-table ownership |
| Worker runtime identity | Worker queue/job data access | No superuser, CREATEDB, CREATEROLE, schema CREATE or migration-table ownership; grants limited to actual Worker queries |

The exact API and Worker table/sequence/function grants must be derived from Prisma and raw SQL access paths. Do not grant database-owner or superuser privileges merely to make installation pass. Existing append-only triggers and application authorization remain in force.

## Required first-install sequence

1. Verify elevation, supported Windows Server build, architecture, disk, versioned immutable payload, PostgreSQL binaries and port availability.
2. Verify the target data directory is absent/empty and installer-owned, or a recognized existing Enterprise IT PostgreSQL 18 cluster. Never reinitialize, delete, replace or silently adopt an unknown cluster.
3. Initialize only a new cluster using a future reviewed SCRAM-protected implementation and a one-time bootstrap secret supplied through a protected input channel. Keep it out of command-line arguments, logs, transcripts, persistent environment variables and installer manifests.
4. Provision PostgreSQL SCM identity, service SID and NTFS ACLs. Start PostgreSQL only after service configuration and data access are verified.
5. Wait for readiness on loopback. Verify major version, expected cluster identity, SCRAM policy, effective listener and absence of remote listener exposure.
6. Through a separately reviewed bounded bootstrap operation, create the application database, schema owner, migration identity, API runtime identity and Worker runtime identity. Apply explicit grants and default privileges; verify effective privileges from each runtime identity.
7. Apply Prisma migrations using the controlled migration identity. Migration failure must stop deployment before API or Worker starts; do not attempt destructive automatic rollback of a partially applied schema.
8. Validate migration state and required schema objects, then provision API/Worker DPAPI configuration from the separately supplied runtime credentials. Reject cross-service credential substitution.
9. Start API and Worker only after database readiness and migration verification. Continue with Web and Edge after upstream readiness checks.
10. Record non-secret installation state and migration outcome for safe retry. Never record passwords, connection URLs, DPAPI plaintext, private keys or recovery material.

## Secret transport and lifecycle requirements

- The initializer's `SecureString` parameter is not a complete bootstrap credential lifecycle. The orchestrator has no corresponding parameter and does not call the initializer.
- Never place a PostgreSQL password in process arguments, PowerShell transcripts, verbose/debug output, CI logs, persistent machine environment variables, generated manifests or service logs.
- A candidate local bootstrap transport must not use a plaintext password file, even temporarily. A native helper or other non-file channel must be threat-reviewed and tested on supported Windows Server versions; current synthetic stdin and pipe experiments are not approved.
- Never store the `platform_admin` password in API/Worker DPAPI files or use either runtime identity as a bootstrap/migration identity.
- Do not claim that deleting a temporary file securely erases NTFS/SSD historical data. The boundary is access control and short exposure, not guaranteed physical erasure.
- A generated random bootstrap credential and its one-time custody/recovery policy, or an explicit administrator-supplied credential flow, must be approved before implementation. This design note does not approve either custody behavior.

## Idempotency, retry and failure semantics

- Initialize only an absent/empty data directory within the fixed version-specific ProgramData root.
- Verify recognized existing clusters; never reinitialize them. Unknown identity, unexpected owner/ACL, unsupported major version, non-SCRAM authentication, remote binding or occupied port is a fail-closed preflight error.
- Role/database creation must be transactional where PostgreSQL permits it. Non-transactional operations require explicit existence checks and postcondition verification.
- A retry resumes only from verified durable state. It must not rotate credentials, replace roles, reset passwords, overwrite a database or drop schema objects implicitly.
- Migration failure preserves cluster and migration evidence. Stop dependent services and report sanitized diagnostics; never drop/recreate the database as rollback.
- `-WhatIf` must perform no filesystem, ACL, SCM, database, credential or network mutation. Tests must prove this.
- Rollback stops only services started by the current invocation. It never removes PostgreSQL data, roles, databases, existing service registrations or user data.

## Acceptance tests required before Orchestrator integration

1. Fresh Windows Server VM: initialize cluster, provision service identity/ACL, start/stop PostgreSQL and verify loopback-only SCRAM.
2. Existing-cluster protection: refuse a populated/unknown cluster without changing sentinel files, database, role, configuration or service.
3. Secret handling: prove no secret appears in process arguments, logs, transcripts, errors, persistent environment or CI artifacts; verify ACL-before-write and cleanup.
4. Role isolation: connect separately as API and Worker and assert allowed/denied SQL operations, including CREATE/ALTER/DROP, migration metadata, sequences and append-only tables.
5. Migration lifecycle: clean install, repeated deploy, no-op deploy, interrupted migration, retry, schema drift and unsupported migration state.
6. Credential handoff: verify API/Worker URLs map to intended roles and are DPAPI-protected for the corresponding actual virtual service SID.
7. Orchestration: migration failure prevents API/Worker/Web/Edge startup; success starts services in dependency order; rollback affects only services started by this invocation.
8. Upgrade/backup/restore: preserve existing data and prove backup/restore before schema or PostgreSQL major-version upgrade.

## Current blockers (must remain open)

- No approved secure transport for the one-time PostgreSQL bootstrap credential across initialization, role provisioning and migration.
- No implemented database/application role bootstrap or least-privilege grant matrix.
- No migration runner integrated into Windows deployment.
- No clean supported Windows Server acceptance for PostgreSQL virtual-account ownership, role bootstrap, migrations, backup/restore or upgrade/rollback.
- No complete installer repair/uninstall or signed release.

Until these gates pass, the five-service Windows deployment remains a foundation, not a production-ready installer or a completed milestone.


## Owner-selected threat model and implementation direction (0.1.232)

The owner selected **Scenario 1**: Standard Users and ordinary unprivileged processes are untrusted; Local Administrators and SYSTEM are trusted. The system is not required to preserve secret confidentiality against a hostile elevated administrator with `SeDebugPrivilege`. This does not permit unnecessary exposure through files, command lines, environment variables, logs, transcripts or error output.

The current experimental pipe is not suitable for production: it runs `initdb` as a child of the invoking process, grants the current user SID, and fails closed when PostgreSQL's re-exec child PID differs. Do not infer that parent PID or executable path authenticates the client, and do not send a secret on that basis.

The candidate architecture is a dedicated `EnterpriseITPostgreSQLBootstrap` Windows Service with a dedicated virtual service identity and enabled service SID. The elevated installer sends a bounded request to an installer-facing pipe whose DACL admits only SYSTEM and Administrators. The service validates the caller token, performs fixed-path and cluster-state preflight, then starts `initdb` under its own service token. The `initdb` password channel must be a separate service-owned pipe restricted to the bootstrap service SID; the connected client must be authenticated by querying its process token and requiring the enabled bootstrap service SID. PID equality is not an authorization condition because PostgreSQL may re-exec under a restricted token. The installer-facing protocol must never return the secret.

This architecture is a design direction, not an implementation or approval. Before enabling it, tests must demonstrate (1) real PostgreSQL 18.7 `initdb` accepts the selected Windows pipe path and reads the complete secret, (2) the restricted child retains the enabled service SID, (3) a separate Standard User cannot connect, inspect or duplicate relevant handles, (4) no secret appears in process arguments, environment, logs, errors or artifacts, and (5) timeout, cancellation, service crash and retry leave no initialized partial cluster falsely reported as success. If any condition cannot be proved, initialization stays fail-closed.


## 2026-11-25 — candidate service implementation (0.1.234)

A dedicated Windows Service candidate now exists at `apps/api/windows/postgresql-bootstrap`. The service identity is `NT SERVICE\\EnterpriseITPostgreSQLBootstrap`; the service is responsible for creating the installer-facing pipe and for creating the real `initdb.exe` process. The pipe DACL grants SYSTEM and local Administrators only. Client authorization uses the impersonated Windows token and requires SYSTEM or an enabled local-administrator membership. The client PID is deliberately not used as the authorization primitive.

The installer-facing protocol uses a server preflight status byte before any secret is transmitted: status 0 confirms the service has authenticated the connected SYSTEM/Administrator token; status 1 rejects the caller. Only after status 0 does the client send a four-byte big-endian length followed by bounded UTF-8 password bytes. The service returns a separate final status byte after initialization. This prevents clients from sending credential bytes to a service instance that has not authorized them. The service invokes only the fixed PostgreSQL 18.7 executable beneath the versioned Program Files payload, uses a fixed ProgramData cluster path, and sends the password twice through inherited anonymous stdin to PostgreSQL's prompt path. The secret is not put in argv, environment, a temporary file, or logs. Child stdout/stderr are drained and discarded. A bounded request timeout and process-tree termination are implemented.

The service is not yet production-approved. The hosted Windows SCM fixture now verifies Administrator preflight, malformed-frame rejection, Standard User pipe denial, and a real PostgreSQL 18.7 initdb launched by the service account while a separate Standard User attempts PROCESS_DUP_HANDLE on both the initdb parent and restricted re-exec child. This hosted test uses LocalService plus the unrestricted service SID because GitHub-hosted runners reject custom virtual-account logon; a supported Windows Server acceptance run under the actual dedicated virtual account is still required. It currently creates the cluster only; it does not configure and start the PostgreSQL server, create database roles/grants, or apply migrations. The existing initializer remains fail-closed and must not be wired to this candidate until those gates pass.
