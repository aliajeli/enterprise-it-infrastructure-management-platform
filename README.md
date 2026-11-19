# Enterprise IT Infrastructure Management Platform

## Project status

**Current phase:** Phase 3 — Implementation (owner-authorized 2026-11-19).

The project is being implemented in reviewable milestones. **M0 is complete.** The M1 identity/authentication/persistence foundation is implemented and under review in [PR #4](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/4). M1 remains in progress: user management, password change/recovery and final operational permissions are not yet implemented. The platform is not production-ready; Windows services, Agent, monitoring, integrations, installer, updater and release automation remain future milestones.

## Application baseline

- **Web:** Next.js App Router, React, strict TypeScript and Tailwind CSS.
- **Runtime:** Node.js 26 Active LTS.
- **Database target:** PostgreSQL 18 (dedicated Windows service).
- **ORM target:** Prisma ORM 7.10.1 with the PostgreSQL driver adapter; Prisma ORM 8 remains a release candidate and is not selected for production.
- **Windows Agent target:** C# / .NET 10 LTS.
- **Deployment target:** self-contained Windows installation with five independent Windows services.

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
- [Deployment workflows](DEPLOYMENT_WORKFLOWS.md)
- [Security policy](SECURITY_POLICY.md)
- [Desktop Bridge PoC specification](DESKTOP_BRIDGE_POC.md)
- [Testing strategy](TESTING_STRATEGY.md)
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
- M2 inventory management and subsequent Windows Agent, monitoring, integrations, installer and release milestones are not yet implemented.
