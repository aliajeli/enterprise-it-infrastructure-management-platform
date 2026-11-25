# Enterprise IT Infrastructure Management Platform

## Project status

**Current phase:** Phase 3 — Implementation (owner-authorized 2026-11-19).

The project is being implemented in reviewable milestones. **M0 is complete.** The M1 identity/authentication/persistence foundation is merged in [PR #4](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/4). User/branch administration and role policy are implemented in Draft PRs [#5](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/5) and [#6](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/6), both unmerged. M2 inventory API/schema and the first branch-aware inventory UI are implemented in Draft PRs [#7](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/7) and [#8](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/8), both unmerged. The local preview path is documented below and in [PREVIEW_TEST_GUIDE.md](PREVIEW_TEST_GUIDE.md). M1 still requires clean Windows service integration and production encrypted backup/restore evidence. Device discovery, monitoring transports, hardware validation and production packaging remain future work. The platform is not production-ready.

## Windows deployment: current state (0.1.223)

**There is no production-ready or installable release yet.** This branch contains a development-only offline payload assembly and verification workflow, not a finished installer. Installer mutation, PostgreSQL initialization/bootstrap/migrations and service orchestration fail closed pending the security and ownership gates below. Offline archive inspection (`-WhatIf`) does not establish installability or authenticate a publisher; a trusted independent digest is required. Packaged ZIPs are not signed releases.

- The Vault provisioner and helper have candidate source and hosted Windows fixture coverage, but need independent security review, a real service-SID transaction and supported Windows Server acceptance. Real credential persistence remains disabled.
- Synthetic PostgreSQL stdin experiments work functionally but same-user handle interception is reproducible. The real initdb named-pipe client has an unexpected PID and is rejected before any password is sent. A separate non-admin test account did not protect the process from the elevated runner. **None is approved for production secrets.**
- Cluster identity/ownership, role bootstrap/grants and production migration are unresolved; existing services, clusters, ACLs and data must never be silently adopted. Disposable migration tests are not production acceptance.
- [CI 45480884339](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/45480884339) for `f640873f3e178dad4064156b592b81f0c8ccb74a` (0.1.222) completed with overall failure: Windows archive/manifest/Vault, fast and full disposable migration/assembly, Linux and other functional tests passed; four security probes failed. Hosted CI is not clean Windows Server acceptance.

Current handoff and evidence: [AGENT_HANDOFF.md](AGENT_HANDOFF.md), [HANDOVER.md](HANDOVER.md), [testing strategy](TESTING_STRATEGY.md), [PostgreSQL bootstrap contract](WINDOWS_POSTGRESQL_BOOTSTRAP_DESIGN.md), [Vault provisioning contract](WINDOWS_CREDENTIAL_VAULT_PROVISIONING_DESIGN.md) and [installer preflight](INSTALLER_PREFLIGHT.md). Historical specifications and reports remain point-in-time records, not current readiness claims. PRs #5–#9 remain Draft/open; the owner retains the merge and release decision. No network edge, MikroTik, NAT or firewall changes are authorized.

## Application baseline

- **Web:** Next.js App Router, React, strict TypeScript and Tailwind CSS.
- **Runtime:** Node.js 26 Active LTS.
- **Database target:** PostgreSQL 18 (dedicated Windows service).
- **ORM target:** Prisma ORM 7.10.1 with the PostgreSQL driver adapter; Prisma ORM 8 remains a release candidate and is not selected for production.
- **Windows Agent target:** C# / .NET 10 LTS.
- **Deployment target:** self-contained Windows installation with five independent Windows services.

## Quick local preview (Windows)

This preview runs PostgreSQL 18 in Docker and the API/web applications directly on Windows. It is intended for local UI and workflow evaluation, not production deployment. Docker Desktop with Linux containers, Node.js 26 and npm 11 are required.

From the repository root, in PowerShell:

```powershell
Copy-Item .env.example .env
docker compose up -d --wait db
docker compose ps
node --version
npm --version
npm ci
npm run db:validate
npm run db:generate
npm run db:migrate:deploy
npm run build
npm run bootstrap-admin
```

Use Node.js 26.x and npm 11.x. The bootstrap command interactively creates the first administrator; there is no default account or password.

Open two separate PowerShell terminals in the repository root:

Terminal 1 — API:

```powershell
npm run dev:api
```

Terminal 2 — web application:

```powershell
npm run dev
```

Then open **http://127.0.0.1:3000**. Sign in with the administrator credentials created by the bootstrap command. The web server proxies API requests to the local API service on port 13001.

The Compose database port is bound to loopback only. If you change `POSTGRES_PASSWORD` in `.env`, change the password in `DATABASE_URL` to exactly the same value as well; otherwise Prisma/API connections will fail. Prefer a URL-safe password (for example, generate one with `node -e "console.log(require('node:crypto').randomBytes(24).toString('base64url'))"`) so it does not need URL encoding. The example password is for an isolated local preview only; never reuse it outside this environment. No sample device/monitoring data is fabricated, and this preview does not perform SNMP discovery, port scanning, NAT/port mapping or MikroTik changes. Do not enter production equipment credentials.

To stop PostgreSQL while preserving the database:

```powershell
docker compose down
```

**Destructive reset:** `docker compose down -v` deletes the local PostgreSQL volume and all preview data.

## First local administrator

Copy the repository-root `.env.example` to `.env` and set a local PostgreSQL connection string. Start PostgreSQL, then run:

```sh
npm ci
npm run db:validate
npm run db:migrate:deploy
npm run build
npm run bootstrap-admin
```

The bootstrap command requires an interactive terminal, masks password entry, and creates an administrator only when the users table is empty. It has no default username or password and never accepts a password as a command-line argument.

For local development, run the API and web app in separate terminals:

```sh
npm run dev:api
npm run dev
```

## Development

The web application lives in `apps/web`, the API service in `apps/api`, and the Prisma database package in `packages/database`. See [M1 authentication and persistence design](M1_AUTHENTICATION_DESIGN.md) for the security model. In local development, the Next.js server proxies same-origin `/api` requests to the loopback API service.

After installing the supported Node.js runtime and dependencies:

```sh
npm ci
npm run lint
npm run typecheck
npm test
npm run build
npm run dev
```

The development server binds to `127.0.0.1`. The initial dashboard is an implementation-status shell; it does not display fabricated device or monitoring data.

**Reproducibility status:** `package-lock.json` is committed. Use Node.js 26/npm 11 and `npm ci` for clean, deterministic installs. GitHub Actions validates Prisma schema/migrations against PostgreSQL 18, dependency integrity, security audit, lint, typecheck, tests and production build.

## Documentation index

### Design and specifications

- [M1 authentication and persistence design](M1_AUTHENTICATION_DESIGN.md)

- [Phase 3 implementation plan](PHASE3_PLAN.md)
- [Architecture](ARCHITECTURE.md)
- [Database design](DATABASE_DESIGN.md)
- [API contract](API_DOCUMENTATION.md)
- [Windows Agent specification](AGENT_SPECIFICATION.md)
- [Network requirements](NETWORK_REQUIREMENTS.md)
- [SNMP read-only discovery design and MikroTik safety controls](SNMP_DISCOVERY_DESIGN.md)
- [Deployment workflows](DEPLOYMENT_WORKFLOWS.md)
- [Security policy](SECURITY_POLICY.md)
- [Desktop Bridge PoC specification](DESKTOP_BRIDGE_POC.md)
- [Testing strategy](TESTING_STRATEGY.md)
- [Local preview and manual acceptance checklist](PREVIEW_TEST_GUIDE.md)
- [Windows installer host preflight](INSTALLER_PREFLIGHT.md)
- [Windows Credential Vault provisioning](WINDOWS_CREDENTIAL_VAULT_PROVISIONING_DESIGN.md)
- [Windows DPAPI provider contract](WINDOWS_DPAPI_PROVIDER_DESIGN.md)
- [Windows keyring storage contract](WINDOWS_KEYRING_STORAGE_DESIGN.md)
- [Windows keyring filesystem and security review](WINDOWS_KEYRING_STORAGE_HARDENING_REVIEW.md)
- [Windows PostgreSQL bootstrap and migration contract](WINDOWS_POSTGRESQL_BOOTSTRAP_DESIGN.md)
- [PostgreSQL runtime privilege matrix](WINDOWS_POSTGRESQL_PRIVILEGE_MATRIX.md)
- [Release process](RELEASE_PROCESS.md)
- [Versioning policy](VERSIONING_POLICY.md)
- [Decision log](DECISION_LOG.md)

### Project record and status

- [Project guideline and history](GUIDELINE.md)
- [Handover](HANDOVER.md)
- [Transfer status](TRANSFER_STATUS.md)
- [Changelog](CHANGELOG.md)
- [Phase 2 primary-repository review — 2026-11-19](PHASE2_REVIEW_2026-11-19.md)
- [Documentation review report (historical, pre-transfer)](DOCUMENTATION_REVIEW_REPORT.md)
- [Final handover report (historical, pre-transfer)](FINAL_HANDOVER_REPORT.md)

### Package integrity

- [File manifest](FINAL_FILE_MANIFEST.md)
- [Checksums](SHA256SUMS.txt)

The Phase 2 checksum manifest predates the Phase 3 source tree and does not cover the new source files. Recompute it when the documentation baseline is formally retired; do not use it as an integrity gate for the current application tree.

All behavior described as planned or not implemented remains unverified until implemented and independently validated.

## Current implementation status

- M0 web application foundation: complete and merged.
- M1 identity/authentication/persistence: merged.
- M1 user and branch administration: implemented in [PR #5](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/5), CI-verified and awaiting review; not yet merged.
- M2 branch-aware inventory UI, asset CRUD, switch-port metadata and API/schema: implemented on Draft PR #8; CI status must be checked against the latest exact branch head, and manual Windows preview acceptance is still required. No real discovery or switch configuration.
- Windows Agent, monitoring, SNMP/SSH integrations, installer, updater and release milestones remain future work. No installer or GitHub Release exists yet.
