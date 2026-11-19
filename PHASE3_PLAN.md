# Phase 3 — Implementation plan

**Status:** Active — owner authorization received 2026-11-19.  
**Current main baseline:** `b7dc102bc7293817d10022176ac7fe5627d015ca` (2026-11-19).  
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

### M1 — Identity, access control and persistence (in progress; implementation slices delivered)

**Merged in PR #4 (2026-11-19):**
- Fastify API and Prisma 7.10.1 database workspaces; PostgreSQL migration for users, sessions, recovery codes, branches, branch grants and append-only audit events.
- Argon2id authentication, opaque hashed sessions, login/logout, database-backed login lockout, strict Origin checks, rate limits and one-time interactive first-administrator bootstrap.
- Initial browser sign-in, session-gated dashboard and logout flow; server-side branch-scope primitives.
- PR #4 is merged. Its original CI run 44495513578 passed the identity foundation gates.

**Implemented in PR #5 (Draft; CI passed, awaiting review):**
- Admin-only user provisioning and listing; no public administrator self-registration.
- Cryptographically random temporary credentials, no-store response and forced password change at first login.
- Branch creation/listing and per-user branch-grant replacement.
- Role changes between OPERATOR and VIEWER; account disable/enable; session revocation and auth-epoch invalidation.
- Self-disable/self-role/self-branch-scope protections; administrator account mutation is restricted to an owner-controlled procedure.
- Audit events for administrative operations and PostgreSQL integration coverage for user lifecycle, password rotation, branch grants, session revocation and append-only audit enforcement.
- CI run [44504888903](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44504888903) passed all three jobs: Linux/Node.js 26/PostgreSQL 18 platform validation, Windows API/native Argon2id runtime smoke and lockfile bootstrap.

**M1 acceptance criteria still outstanding:**
- Owner confirmation of the precise OPERATOR/VIEWER action matrix before any operational inventory/device/network mutation is enabled.
- Complete branch lifecycle (update, archive/restore and safe reassignment behavior).
- Password recovery workflow and operational recovery policy.
- Production backup/restore evidence, Windows service identity/integration validation and pre-production operational hardening.
- PR #5 code review and merge. Passing CI is necessary but does not replace review or owner decisions.

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

The repository now contains the merged M0 web foundation and M1 identity/authentication/persistence foundation. M1 user and branch administration is implemented on PR #5 but remains under review and is not merged. No Windows services, Agent, monitoring, switch/NVR integrations, Desktop Bridge, Store Commerce deployment, installer, updater or release automation are claimed as implemented. No production deployment or hardware compatibility is claimed.

## Open owner-confirmation items

- Cross-channel reuse/promotion of the same Git commit SHA remains marked **PROPOSED — OWNER CONFIRMATION REQUIRED** in `VERSIONING_POLICY.md`; do not implement a conflicting release policy until resolved.
- Branch protection for `main` and future `beta` remains an owner-controlled repository setting and is not changed by this implementation.
- Desktop Bridge PoC execution remains a separately authorized task under `DESKTOP_BRIDGE_POC.md`.
