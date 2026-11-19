# Enterprise IT Infrastructure Management Platform

## Project status

**Current phase:** Phase 3 — Implementation (owner-authorized 2026-11-19).

The project is being implemented in reviewable milestones. The first milestone establishes the application workspace and initial web interface. The platform is not yet production-ready; authentication, API, database, Windows services, Agent, integrations, installer and release automation remain future milestones.

## Application baseline

- **Web:** Next.js App Router, React, strict TypeScript and Tailwind CSS.
- **Runtime:** Node.js 26 Active LTS.
- **Database target:** PostgreSQL 18 (dedicated Windows service).
- **ORM target:** Prisma ORM 7 GA; Prisma ORM 8 remains a release candidate and is not selected for production.
- **Windows Agent target:** C# / .NET 10 LTS.
- **Deployment target:** self-contained Windows installation with five independent Windows services.

## Development

The web application lives in `apps/web`.

After installing the supported Node.js runtime and dependencies:

```sh
npm ci
npm run lint
npm run typecheck
npm run build
npm run dev
```

The development server binds to `127.0.0.1`. The initial dashboard is an implementation-status shell; it does not display fabricated device or monitoring data.

**Reproducibility status:** `package-lock.json` is committed. Use Node.js 26/npm 11 and `npm ci` for clean, deterministic installs. GitHub Actions validates dependency installation, dependency-tree integrity, lint, typecheck and production build; the committed-lockfile `npm ci` run is still pending.

## Documentation index

### Design and specifications

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
