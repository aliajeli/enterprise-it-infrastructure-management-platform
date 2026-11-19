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

### M1 — Identity, access control and persistence (implementation delivered; review/evidence gates open)

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

**M1 acceptance gates still outstanding:**
- The owner-approved ADMIN/OPERATOR/VIEWER action matrix is recorded in `DECISION_LOG.md` and its server-side policy primitives are implemented and CI-verified in PR #6.
- Branch lifecycle (edit/archive/restore) and ADMIN-issued temporary password reset are implemented on PR #6; no self-service recovery channel is configured.
- Clean target-Windows service identity/ACL/startup/API integration evidence; the five Windows services are not yet implemented.
- Production PostgreSQL encrypted backup/restore and key-recovery evidence; disposable CI backup/restore is not production evidence.
- PR #5 and PR #6 code review and merge remain owner-controlled. Passing CI is necessary but does not replace review.

### M2 — Branch and inventory management (initial slice in progress)

**Inventory UI slice implemented on Draft PR #8, stacked on Draft PR #7:** authenticated branch selector, branch-scoped asset listing/search/type filters, asset registration, switch-port metadata entry, and latest-observation display. A new `GET /api/v1/branches/accessible` endpoint returns only active branches the signed-in user may access. Desktop and mobile dashboard navigation now expose the inventory workspace. CI and review remain pending on PR #8's final head.

**Implemented on `phase3/m2-inventory-foundation` (CI passed; PR #7 Draft/unmerged):**
- PostgreSQL/Prisma schema and migration for branch-owned common assets, switch profiles, switch ports, timestamped port observations and discovery-run records.
- Branch-scoped inventory list/create/update API with bounded pagination, filtering, IP/MAC validation, optimistic concurrency and transactional audit events.
- Switch-port metadata list/create/update API for operator-maintained alias, description, configured VLANs and connected-device label.
- Server-side role and branch enforcement: OPERATOR can edit inventory and metadata only in assigned active branches; VIEWER is read-only; ADMIN is global. No live switch configuration is exposed.
- Integration tests cover OPERATOR create/edit, VIEWER read/denied write, cross-branch denial and optimistic version conflicts.
- GitHub Actions run [44531050529](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44531050529) passed on exact head `5d3aec16b760c1e5318297409a29fb7bb0135821`, including PostgreSQL 18 migration/integration, lint, typecheck, tests, production build and Windows API compile/runtime smoke.

**Credential Vault progress (2026-11-19):** AES-256-GCM envelope cryptographic core and unit tests are being added in PR #8. The production DPAPI provider, separately-held recovery/restore drill, persistent credential records, ADMIN-only API/RBAC and audit integration remain not implemented. Do not enter real equipment secrets or enable discovery yet.

**Remaining M2 work:**
- Branch links and richer typed asset profiles (servers, POS, printers, NVRs, cameras, routers and computers).
- Inventory UI with branch-aware filters, asset detail and port table/editor.
- Safe SNMP read-only discovery for supported Cisco/MikroTik devices; reconciliation and observation history without overwriting manual metadata.
- Import/export, bulk validation, deduplication and audit-friendly reconciliation.
- Real hardware validation before vendor/model/firmware compatibility claims.

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


## M2 continuation — guarded read-only network discovery (design gate)

The current inventory schema already has `DiscoveryRun`, `SwitchPort` and append-only `PortObservation` records. It does not yet have a durable Worker implementation, a credential vault, discovery endpoints or an SNMP transport. Do not begin device polling until those prerequisites and their tests are in place.

The next design slice is documented in [SNMP_DISCOVERY_DESIGN.md](SNMP_DISCOVERY_DESIGN.md). It is intentionally limited to SNMP reads against explicitly registered management IPs. Port-range scanning, subnet sweeps, NAT/port-forward changes, SNMP SET and automatic MikroTik firewall changes are prohibited. A target that times out or appears filtered is paused for the run; the application must not retry aggressively or attempt to unblock itself.

Implementation order:
1. Establish and test the PostgreSQL-backed Worker job lifecycle (lease, bounded retry, cancellation, idempotency and audit).
2. Implement server-side credential storage and retrieval with encryption, RBAC, redaction and key recovery tests. Never put community strings or SNMPv3 secrets in general asset/profile fields.
3. Add an explicit, branch-scoped discovery API and per-target policy/rate limits.
4. Implement SNMPv3 read-only polling for a single explicitly selected device; add opt-in SNMPv2c read-only compatibility only where required.
5. Add IF-MIB and bridge/VLAN table mapping, simulator tests, then controlled hardware tests for named Cisco and MikroTik models and firmware.
6. Enable scheduled discovery only after manual-run behavior and firewall-safe stop conditions pass acceptance.

No device compatibility or live discovery is claimed until target hardware tests pass.


### M2 continuation — PostgreSQL Worker queue foundation (implementation slice)

The separate `apps/worker` workspace now contains the first durable queue primitives over existing `DiscoveryRun` records: atomic `SKIP LOCKED` claim, worker-owned lease, heartbeat, expired-lease recovery, bounded exponential retry, cancellation acknowledgement and owner-bound completion. The Prisma schema and additive migration add lease/attempt/cancellation metadata and indexes.

**Safety gate:** the Worker currently registers no task handlers. Its supported-source allow-list is intentionally empty, so it cannot claim or execute discovery jobs. No SNMP/SSH/ISAPI/Agent transport, credential vault, enqueue/cancel API, Windows service registration or real-device access is implemented. Keep this as infrastructure foundation only. Before enabling any handler, add PostgreSQL concurrency/lease integration tests, API authorization and audit, encrypted credential handling, per-target network limits and simulator/hardware validation.


### Credential Vault continuation — key material hygiene and DPAPI design gate (2026-11-19)
- Exact-head CI passed on `4c2315d47b7d8e1e13e4221a838880ba6da14d3f` for both Push and PR validation, including Windows API runtime smoke and Linux/PostgreSQL platform validation.
- Credential envelope crypto now zeroes caller-owned KEK buffers returned by the provider as well as local copies. Added tests for successful encrypt/decrypt zeroization and invalid key-version failure.
- Added `WINDOWS_DPAPI_PROVIDER_DESIGN.md` defining the .NET helper protocol, DPAPI machine scope, service-SID entropy, ACL provisioning, keyring rotation and independent recovery/clean-host restore.
- Next implementation gate is the helper protocol and Windows DPAPI integration under a dedicated service identity. No DPAPI provider or keyring is currently implemented. Credential DB/API/RBAC/audit work remains blocked on verified key protection and recovery.


### Credential Vault continuation — DPAPI primitive (2026-11-19)
- Added the fixed-purpose .NET 10 Windows DPAPI helper and Node.js client using bounded binary stdin/stdout framing. DPAPI machine scope is fixed; optional entropy is derived within the helper from installation ID and current Windows SID.
- Windows CI now compiles the helper and runs the native round-trip and cross-installation binding test.
- This is not yet the production key provider. Installer/service identity provisioning, NTFS ACL creation/verification, persistent keyring and rotation, independently protected recovery export and clean-host restore remain mandatory gates. Credential records/API and discovery remain disabled.


### DPAPI primitive CI evidence — 2026-11-19
- Exact-head `5067518791b0899f410fee8b76495028e11bd590` passed Push run `44590138482` and PR run `44590153726`.
- Windows CI built the .NET 10 helper and passed native DPAPI Protect/Unprotect and installation-identity binding. Linux/PostgreSQL validation passed.
- Next milestone: installer/service identity + NTFS ACL provisioning/verification, persistent versioned keyring, atomic rotation and independently protected recovery/clean-host restore. Credential persistence/API remains blocked until those are implemented and tested.


### Credential Vault continuation — versioned keyring core (2026-11-19)
- Added a keyring core over the DPAPI protector boundary: initialize-once random 256-bit KEK, protected-blob persistence contract, read-back verification, versioned retrieval and serialized rotation.
- Rotation preserves every prior key version and has a bounded 64-entry capacity. No key retirement is implemented.
- Tests cover idempotent initialization, old-key retention, concurrent rotations, malformed/missing registry rejection and capacity handling.
- Remaining gates: concrete Windows storage adapter with ACL verification and atomic durable replacement; independent recovery export/custody and clean-host restore; reference-aware audited retirement; then Prisma Credential records/API/RBAC/audit.



### Credential Vault continuation — Windows storage adapter design gate (2026-11-19)
- Added `WINDOWS_KEYRING_STORAGE_DESIGN.md` as the binding implementation contract for the fixed ProgramData keyring location, dedicated service SID, exact owner/DACL policy, transaction-scoped cross-process lock, durable same-directory atomic replacement and binary helper session.
- Design explicitly rejects arbitrary paths, ACL auto-repair, unlocked fallback and use of LocalSystem/interactive administrator as an implicit service identity.
- Next step is helper-side protocol/path/ACL primitives and Windows acceptance tests. No production storage adapter or keyring registration is implemented; recovery, Credential DB/API/RBAC/audit, discovery and installer remain blocked.
