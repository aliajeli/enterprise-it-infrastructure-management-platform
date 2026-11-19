# Phase 3 — Implementation plan

**Status:** Active — owner authorization received 2026-11-19.  
**Baseline:** `main` at `60b0e515896c6db1e3d3469f834866e76d0198ca`.  
**Execution rule:** implementation proceeds through reviewable milestones and pull requests. Owner-approved architecture decisions in `DECISION_LOG.md` are binding.

## Delivery principles

- Build an installable, self-contained Windows product; do not require end-user developer runtimes.
- Preserve the five independently supervised Windows services: TLS Edge, Next.js Web, API/WebSocket, Background Worker, and dedicated PostgreSQL.
- Treat readiness separately from process liveness. Do not report a service healthy merely because its process is running.
- Use strict TypeScript for the Node.js platform and C# .NET 10 LTS for the Windows Agent.
- Keep all authorization, secrets, database access and operational policy on trusted server components. The browser is not a trust boundary.
- Use PostgreSQL-backed durable jobs with leases, bounded retries, idempotency and reconciliation for uncertain side effects.
- No arbitrary command execution through Agent or Desktop Bridge. No credentials in URLs, process arguments, logs or browser payloads.
- Never claim real-device compatibility from mocks. Hardware-dependent features remain unverified until tested against the named models and actual firmware.
- Keep the owner-supplied original prompt in the protected region of `GUIDELINE.md` byte-identical.
- Work on feature branches and submit pull requests to `main`. Do not alter repository settings, branch protections, hooks, webhooks, permissions or workflow configuration without separate authorization.

## Milestones

### M0 — Repository and application foundation (completed 2026-11-19)

- Establish a maintainable monorepo and strict frontend baseline.
- Create the first real Next.js application shell with responsive navigation and truthful empty states.
- Pin a supported runtime/framework baseline and record package-lock generation/verification as a required gate.
- Establish build, typecheck, lint, unit and dependency-security validation before enabling any release workflow.
- Keep the first smoke tests focused on honest dashboard empty states and accessible navigation; add domain-specific tests alongside each later module.
- Use the Next.js 16 ESLint flat-config integration; do not rely on the removed `next lint` command.
- Reconcile the operational handover with the post-PR #2 repository state.

**Exit criteria: PASS.** Committed npm v3 lockfile; clean Node.js 26.13.1/npm 11.20.0 runner; `npm ci`; `npm audit --audit-level=high` (0 vulnerabilities); dependency-tree verification; ESLint; TypeScript; two Vitest smoke tests; production build; and honest dashboard empty states. Evidence: GitHub Actions run [44491419345](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44491419345).

### M1 — Identity, access control and persistence (in progress)

- Add the dedicated Fastify API workspace and Prisma 7.10.1 PostgreSQL adapter package.
- Establish users, sessions, recovery codes, branches, branch-scoped access grants and append-only audit events.
- Implement Argon2id password hashing, opaque HttpOnly sessions, strict Origin validation, login throttling, generic authentication failures and server-side authorization primitives.
- Keep the exact operational permission matrix owner-pending; no branch/device mutation endpoints are enabled until that matrix is approved.
- Add database migration validation against disposable PostgreSQL 18 in CI. Production backup/restore and Windows service identity remain later acceptance requirements.

### M2 — Branch and inventory management

- Implement branches, branch links, common device identity and typed device records.
- Add switch inventory and manually maintained switch-port/VLAN/IP/device bindings.
- Implement validated CRUD, search, filtering, pagination, optimistic concurrency and audit history.

### M3 — Windows Agent lifecycle

- Implement C# .NET 10 LTS Agent identity, one-time enrollment, authenticated outbound connection, heartbeat, task allowlist and safe upgrade lifecycle.
- Implement deployment preflight and staged SMB/ADMIN$/Remote SCM workflow with explicit GIG/OKCS credential separation and no WinRM dependency.
- Validate on isolated Windows VMs before any production deployment.

### M4 — Monitoring and durable operations

- Implement PostgreSQL-backed worker scheduling, leases, retries, cancellation and reconciliation.
- Add router reachability probes with honest status semantics, history and bounded concurrency.
- Add service/agent health and alert lifecycle.

### M5 — Network and CCTV integrations

- Implement switch read-only discovery where supported, while preserving manual port metadata.
- Implement Hikvision ISAPI discovery/synchronization and distinguish channel configuration from runtime state.
- Validate DS-7732NI-K4 and DS-7732NXI-K4 against actual firmware before compatibility claims.

### M6 — Remote access and Desktop Bridge

- Implement audited SSH session management with host-key verification.
- Execute the separately scoped, isolated Desktop Bridge PoC only after its explicit task approval; no automatic credential handoff without client-specific evidence.
- Evaluate RDP/VNC/Winbox/TeamViewer behavior against installed client versions.

### M7 — Software and Store Commerce deployment

- Implement package intake, source/destination SHA-256 validation, date-only package destination and exact-path persistence.
- Implement stepwise deployment audit, bounded retry, explicit operator approval and Store Commerce safety controls.

### M8 — Installer, updates and release operations

- Package the five Windows services and all runtime dependencies into a genuine offline installer.
- Implement the authenticated central Update Proxy and a publisher-signing/trust strategy.
- Implement the approved per-commit version/build/test/installer/release flow, with the one-time bootstrap exception ending only after independent clean Windows validation.
- Verify install, upgrade, repair, rollback, backup/restore and data-retaining uninstall on clean Windows VMs.

## Current scope and explicit limitations

The initial implementation commit establishes only the web workspace shell. It does not implement authentication, API, database, Windows services, Agent, monitoring, device integrations, installer, updater or release automation. No production data or credentials are present. A generated dependency lockfile and successful clean-runner build are required before this foundation can be considered reproducible or releasable.

## Open owner-confirmation items

- Cross-channel reuse/promotion of the same Git commit SHA remains marked **PROPOSED — OWNER CONFIRMATION REQUIRED** in `VERSIONING_POLICY.md`; do not implement a conflicting release policy until resolved.
- Branch protection for `main` and future `beta` remains an owner-controlled repository setting and is not changed by this implementation.
- Desktop Bridge PoC execution remains a separately authorized task under `DESKTOP_BRIDGE_POC.md`.
