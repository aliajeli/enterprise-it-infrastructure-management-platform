## 2026-11-20 — Local preview path (v0.1.36)

- Added `compose.yaml` with PostgreSQL 18, persistent named storage, health check and loopback-only host binding. The application services still run locally through Node.js/npm; this is not a full containerized deployment.
- Added a Windows PowerShell quick-preview guide to README: copy root environment template, start DB, install Node workspaces, validate/generate Prisma, apply migrations, build, interactively bootstrap the first administrator, then run API and web in separate terminals.
- Root `package.json` and the two root metadata entries in `package-lock.json` are synchronized at 0.1.36.
- No seed/demo device data is fabricated. No SNMP/SSH discovery, port scan, NAT/port mapping, RouterOS change, or automatic unblock is introduced. The preview database is loopback-only and its default password is explicitly local-only.
- Current PR #8 head before this change was `cd343c55f869db234c5cb9123c16fd09cc9933b3`; its PR workflow ended `action_required` with zero check runs. Previous successful CI on `6f5b0d7` does not validate that newer head. CI for this preview commit must be checked independently.
- PR #8 remains Draft/open/unmerged. No installer or Release is created by this milestone.

## 2026-11-20 — Correct native interop overload ambiguity (v0.1.35)
- Exact Windows CI on commit 64b82dcc3c4d96c9b697a615cea04a91218c8750 failed while compiling WindowsDirectoryHandleChain.cs with CS0121: overloaded GetFileInformationByHandleEx P/Invoke declarations made both out-var calls ambiguous.
- Renamed the managed declarations to GetFileAttributeTagInfo and GetFileIdentityInfo while retaining EntryPoint=GetFileInformationByHandleEx. This addresses the compile-time ambiguity; exact-head CI must still prove the correction.
- The directory-chain primitive remains isolated and unused by Program.cs. No ACL/TOCTOU acceptance is claimed; Node client remains unregistered.
- PR #8 remains Draft/unmerged. No installer or Release.

## 2026-11-20 — Handle-relative Windows directory-chain groundwork (v0.1.34)
- Added an isolated .NET primitive that opens the standard local volume root and each fixed child directory (ProgramData, EnterpriseIT, CredentialVault) relative to a retained parent handle using NtCreateFile.
- The primitive checks directory/reparse attributes and same-volume identity, captures file IDs, denies delete sharing on retained directory handles, and disposes the chain in reverse order.
- This is compile-time groundwork only. It is not called by Program.cs; current lock/read/write/replace/cleanup paths remain path-based. No ACL policy or adversarial Windows acceptance tests exist yet.
- Next: add provisioned-Windows tests for path substitution, reparse points, file IDs, ACL tampering and multi-process locking; then migrate every storage operation to retained directory handles. Do not register the Node client or store real credentials before those gates pass.
- Push CI on exact head must be checked before treating this change as validated. PR #8 remains Draft/unmerged; no installer or Release.

## 2026-11-20 — Windows keyring storage hardening review (v0.1.33)
- Revalidated branch head `f428f63a7a30fdd67b5da9bd42cce94d4debd019`; PR #8 remains open, Draft and unmerged.
- Reviewed the current .NET keyring helper and storage contract. The helper checks the final vault directory and individual file handles, but it does not yet pin and validate the complete ProgramData → EnterpriseIT → CredentialVault path chain for the lifetime of a transaction. Directory opens currently permit delete sharing; temp cleanup and replacement remain path-based. These leave unresolved rename/path-substitution and TOCTOU questions.
- Added `WINDOWS_KEYRING_STORAGE_HARDENING_REVIEW.md` with concrete remediation and Windows integration gates. This is an assessment/design checkpoint, not a runtime security fix.
- The PR workflow for `f428f63a7a30fdd67b5da9bd42cce94d4debd019` ended as `action_required` with zero jobs/check runs; exact-head CI is therefore unverified. Prior `d947b5b` Push and PR runs passed, but that SHA is not the current branch head.
- Keep the Node storage client unregistered, Worker discovery handlers empty, and real credential entry disabled until path/ACL/lock/atomic-write integration tests pass under a provisioned dedicated service SID. No installer or Release.


# Project handover
## Current verified snapshot — patched dependency and service SID hardening CI passed (2026-11-20)

**Branch:** `phase3/m2-inventory-ui`  
**Verified code commit:** `720ca7caa1813a6c81647578601ddf47b70c6261`  
**Current branch head:** `a1214f0e5b60fce3167a27363404eda3aa393572` (lockfile metadata refresh only)  
**PR:** [#8](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/8) — Draft/open/unmerged.

### Exact-head CI evidence

- Push workflow [44673439072](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44673439072) completed successfully on code SHA `720ca7caa1813a6c81647578601ddf47b70c6261`; all jobs passed: Platform validation, Windows API runtime smoke, and lockfile refresh.
- Platform validation passed: install dependencies, exact Effect lockfile guard, Prisma validate/generate/migrate, dependency tree, npm audit, lint, typecheck, unit tests, PostgreSQL backup/restore and production build.
- Windows smoke passed: DPAPI helper build and non-service identity rejection; keyring helper build and unprovisioned fail-closed check; Windows dependency install; Prisma package build; API/test typecheck; API and Argon2id tests; API service build.
- The lockfile workflow then pushed `a1214f0e5b60fce3167a27363404eda3aa393572`, changing only root package-lock metadata. Verified package and lock versions are both `0.1.31`; `node_modules/effect` is `3.22.1` with its npm registry integrity value.

### Security work completed in 0.1.31

- Keyring helper now accepts a service SID from the token user or only from an enabled, non-deny-only TokenGroups entry. Disabled and deny-only group SIDs are ignored; ambiguous active service SIDs fail closed.
- Added `WINDOWS_SERVICE_HOST_PROVISIONING_DESIGN.md` defining a dedicated virtual API service identity, .NET SCM host proposal, immutable executable ACLs, separate mutable ProgramData layout, process supervision, installer lifecycle and acceptance tests.

### Remaining Credential Vault blockers

- Current helper validates the final CredentialVault directory handle only; a complete trusted handle-bound chain from ProgramData through every parent is not implemented. Reparse-point, junction, mount-point and TOCTOU handling remains a production blocker.
- Dedicated service provisioning, positive DPAPI/keyring integration tests under the real service identity, cross-process crash/recovery tests, independent recovery drill, installer/upgrade/uninstall/rollback are not complete.
- Storage client remains unregistered; no production credential persistence. Do not store real equipment credentials.

### Network discovery safety

- No subnet sweeps, port scans, port-range probing, NAT/DST-NAT/port-forward changes, SNMP SET, firewall edits or automatic MikroTik unblocking.
- Discovery remains read-only and target-scoped. SNMP UDP/161 only after administrator confirmation. On timeout/possible filtering, stop that target run; do not try alternate ports/protocols. Timeout is not proof of a router block.

### Release gates

- PR #8 remains Draft/unmerged. No installer or GitHub Release is authorized or claimed.
- Release requires real clean-Windows install, service identity/ACL provisioning, upgrade, uninstall, rollback, database migration/restore and independent recovery drills.

---

---

---

---

---

# Project handover
## Current observed snapshot — dependency audit remediation pending CI (2026-11-20)

**Branch:** `phase3/m2-inventory-ui`  
**Previous head:** `8ea9de882014b76e157bc9fd1bea1016568e34c4`  
**PR:** [#8](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/8) — Draft/open/unmerged.

### Latest CI result on 0.1.26

- Windows API runtime smoke passed on exact SHA `8ea9de882014b76e157bc9fd1bea1016568e34c4` in both Push run [44668937423](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44668937423) and PR run [44668945827](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44668945827).
- Platform validation failed at `npm audit --audit-level=high` before lint, typecheck, tests, backup/restore smoke or production build.
- Audit identified `effect@3.20.0` through `prisma@7.10.1 -> @prisma/config@7.10.1`, affected by GHSA-7589-6fvf-x4pw / CVE-2026-121707. The advisory's patched version is `effect@3.22.1`.

### 0.1.27 remediation in progress

- Root `package.json` adds npm override `effect: ^3.22.1`; this avoids the suggested `npm audit fix --force` path, which proposed a Prisma downgrade and is not accepted.
- The push workflow's lockfile-bootstrap job must regenerate `package-lock.json`; until that exact generated lock is committed and CI reruns, the remediation is not verified.
- Do not mark platform validation successful until audit, lint, typecheck, tests, PostgreSQL backup/restore and production build all pass on the same exact head.

### Credential Vault status and security gates

- AES-256-GCM envelope crypto core, DPAPI helper, keyring core, bounded helper protocol, Node helper-session client and .NET storage helper groundwork exist.
- The Windows helper remains unprovisioned and the Node storage adapter remains unregistered. No production credential persistence is enabled.
- Before registration, harden every path component from ProgramData to the vault directory against reparse points/TOCTOU; verify token SID attributes (enabled, not deny-only); validate exact owner/DACL from handles; and prove process-safe lock, durable atomic replacement, crash recovery and tampered-ACL rejection on real Windows.
- Installer/service provisioning and a dedicated service identity are not implemented. Recovery key custody and clean-host restore remain design-only.

### Network discovery safety

- No subnet sweeps, port scans, port-range probing, NAT/DST-NAT/port-forward changes, SNMP SET, firewall edits or automatic MikroTik unblocking.
- Discovery must remain read-only and target-scoped. Use SNMP UDP/161 only after an administrator confirms the management path; stop the target run on timeout/possible filtering rather than trying alternate ports or protocols. A timeout is not proof of a router block.

### Release gates

- PR #8 remains Draft/unmerged. No installer or GitHub Release is authorized or claimed.
- Release requires real clean-Windows install, service identity/ACL provisioning, upgrade, uninstall, rollback, database migration/restore, and independent recovery drills.

---




## Current verified snapshot — Worker queue foundation CI passed (2026-11-19)

**Authoritative branch:** `phase3/m2-inventory-ui`  
**Verified head before this handover refresh:** `d2e15169d2d7cd12c7590e5ebe0aeef9b635a437`  
**PR:** [#8](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/8) — Draft, open, unmerged; stacked on Draft PR #7.

| Area | Verified state |
|---|---|
| M2 inventory UI/API | Branch-scoped inventory, asset and switch-port metadata editing, optimistic concurrency and audit events are implemented in this branch. |
| Worker queue | PostgreSQL-backed atomic claim, owner-bound leases/heartbeat, expired-lease recovery, bounded retries and cancellation/finalization primitives are implemented. |
| Queue safety | No task handlers are registered; the supported-source allow-list is empty. Worker does not claim or execute discovery jobs and does not contact network devices. |
| Worker tests | PostgreSQL integration coverage includes concurrent claims, lease ownership/expiry, recovery, retry exhaustion and cancellation/failure races; test isolation was corrected in commit `4ca9fd7`. |
| Exact-head CI | Push workflow run [44576967674](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44576967674) passed on exact head `d2e15169d2d7cd12c7590e5ebe0aeef9b635a437`; all three jobs passed: Node.js 26/PostgreSQL 18 platform validation, Windows API runtime smoke, and npm lockfile bootstrap. |
| Not implemented | Credential vault, discovery enqueue/cancel API, SNMP/SSH/ISAPI handlers, live device polling, Windows services/Agent, monitoring integrations, installer, updater and release automation. |
| Release/production | No installer, GitHub Release, production deployment or real-device compatibility is claimed. |

### Next implementation gates

1. Resolve and implement recoverable server-side credential encryption consistent with the owner-approved DPAPI-wrapped AES-key direction. Machine-bound key recovery and rotation must be designed and tested before storing production secrets.
2. Add explicit branch-scoped discovery create/cancel endpoints, RBAC, target registration validation, idempotency and audit. Do not enqueue executable discovery until the credential and target policy gates pass.
3. Add SNMPv3 read-only transport for one explicitly registered target, simulator tests and conservative rate/circuit-breaker behavior. No port scans, subnet sweeps, NAT changes, SNMP SET or automatic MikroTik firewall changes.
4. Validate supported Cisco/MikroTik models and firmware on actual hardware before compatibility claims.
5. Keep PR #8 Draft/unmerged and do not publish an installer or Release until the independent clean-Windows install/readiness gates in `VERSIONING_POLICY.md` pass.

---

# Project handover

## Historical snapshot — CI-verified M2 inventory UI before Worker queue validation (2026-11-19)

**Snapshot observed:** branch `phase3/m2-inventory-ui`, PR [#8](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/8), head `e324d6a47fc232421488c330528bc1784fac9f94`. PR #8 remains Draft/open/unmerged and is stacked on Draft PR #7.

| Item | Verified state |
|---|---|
| M2 inventory UI and editing | Branch selector, branch-scoped inventory list/search, asset create/edit, switch-port metadata create/edit, latest observation display |
| Exact-head validation | PR run [44570604144](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44570604144) and push run [44570589162](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44570589162) both passed on `e324d6a47fc232421488c330528bc1784fac9f94` |
| PostgreSQL/API tests | Inventory integration suite executed; API Vitest reported 15 tests passed across 5 files |
| Windows API | Runtime smoke, Prisma generation/compile, API/test typecheck and API build passed |
| Platform checks | Prisma schema/migrations, dependency tree, npm audit, ESLint, TypeScript, unit tests, PostgreSQL backup/restore smoke and production build passed |
| MikroTik safety | SNMP discovery design prohibits port scans/mapping, NAT/port-forward changes, SNMP SET and automatic RouterOS firewall/address-list changes |
| Not implemented | Worker, credential vault, SNMP/SSH discovery transport, live switch configuration, monitoring, NVR integration, Windows Agent/services, installer, updater and release automation |
| Release/production | No installer, tag, GitHub Release or production deployment claimed |

### Immediate next actions

1. Keep PR #8 Draft/unmerged; CI passing does not replace code review or resolve the stacked dependency chain #5 → #6 → #7 → #8.
2. Implement and test the durable PostgreSQL-backed Worker lifecycle before any device polling.
3. Implement the encrypted credential vault and explicit branch-scoped discovery API before storing or using SNMP credentials.
4. Implement a single-target, read-only SNMP prototype using the safety requirements in `SNMP_DISCOVERY_DESIGN.md`; test with a simulator before named Cisco/MikroTik hardware.
5. Keep the one-time installer bootstrap exception in `VERSIONING_POLICY.md`: do not fabricate an installer or Release. Per-commit version ledger and release automation are not implemented.

---


## Historical snapshot — M2 inventory UI before CI repair (2026-11-19)

**Snapshot observed:** 2026-11-19, branch `phase3/m2-inventory-ui`, PR [#8](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/8), based on PR #7 head `e015919110a77cc13db0678113a88eae95166063`. PR #8 is Draft/open/unmerged. CI must be checked against its final head before treating this slice as validated.

| Item | Verified state |
|---|---|
| Authoritative repository | `aliajeli/enterprise-it-infrastructure-management-platform` — Private |
| M0 | Complete and merged |
| M1 identity foundation | Merged — PR #4 |
| M1 user/branch administration | PR #5 Draft/open/unmerged |
| M1 lifecycle and approved role policy | PR #6 Draft/open/unmerged |
| M2 inventory and switch-port API | PR #7 Draft/open/unmerged; CI passed on its exact head `e015919110a77cc13db0678113a88eae95166063` |
| M2 inventory UI | PR #8 Draft/open/unmerged; branch selector, inventory list/search, asset registration, switch-port metadata and observation display added |
| M2 inventory editing | Asset and switch-port metadata edit forms use optimistic version PATCH. API integration assertions cover valid asset IP/MAC updates, invalid IP/MAC rejection, successful port metadata update, duplicate/out-of-range VLAN rejection, and stale port-version conflict. Test changes committed in `f980fa1473f82ab65baa7dc40225ebf26fc978e6`; execution still needs verification |
| Accessible branch API | Added in PR #8; ADMIN sees active branches globally, OPERATOR/VIEWER see only active granted branches |
| Not implemented | SNMP/SSH discovery, live switch configuration, Windows services, Worker, Windows Agent, monitoring, NVR integration, Desktop Bridge, Store Commerce deployment, installer, updater and release automation |
| Release/production | No installer, release, tag or production deployment claimed |

### Immediate next actions

1. Verify the CI run for the exact current PR #8 head after the workflow-trigger change (`7f071f51c13431624994110a275c2832995a86a3`). The workflow now triggers on pushes to `phase3/**` and pull requests targeting `main` or `phase3/**`. The available commit-workflow query only returns pull-request-triggered runs, so it cannot by itself confirm the push run; inspect the Actions run directly before declaring validation complete.
2. API integration assertions now cover asset IP/MAC validation, successful asset and port updates, duplicate/out-of-range VLAN rejection, and stale port-version conflict. They are committed but not yet demonstrated as executed; verify the PostgreSQL integration test job.
3. Review the stacked PR chain #5 → #6 → #7 → #8; passing CI does not replace code review. Keep all dependent PRs Draft/unmerged until owner review and dependency order are resolved.
4. Continue M2 with asset detail presentation, switch-port metadata history and safe read-only discovery as a separate tested slice.
5. Keep installer/release work within the documented one-time bootstrap exception: assign immutable per-commit version identities in the future release ledger, but do not fabricate an installer before clean Windows installation and readiness gates are genuinely met.

---

## Historical snapshot — M2 inventory foundation (2026-11-19)

## Historical snapshot — M2 inventory foundation (2026-11-19)

**Snapshot observed:** 2026-11-19, development branch `phase3/m2-inventory-foundation` at CI-verified head `5d3aec16b760c1e5318297409a29fb7bb0135821`, based on CI-verified M1 review head `ebc349cffd35c50a91f3c18c219821acf0d53391`. PR #7 is Draft/open/unmerged. This is a development handover, not a production-readiness assertion.

| Item | Verified state |
|---|---|
| Authoritative repository | `aliajeli/enterprise-it-infrastructure-management-platform` — Private |
| Default branch | `main` at `b7dc102bc7293817d10022176ac7fe5627d015ca` at last verified baseline |
| M0 | Complete and merged — PR #3 |
| M1 identity foundation | Merged — PR #4 |
| M1 user/branch administration | Implemented on PR #5 branch; PR #5 remains Draft/open/unmerged |
| M1 completion work | [PR #6](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/6), Draft/open/unmerged, based on PR #5; branch lifecycle, admin temporary password reset and approved role policy added |
| M2 inventory foundation | [PR #7](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/7), Draft/open/unmerged, branch `phase3/m2-inventory-foundation`; schema, migration, scoped CRUD and switch-port metadata APIs; latest CI run 44531799575 passed on head `60e9f694e9b0cf8960452ac63dfba8ee84431ca0` |
| Branch lifecycle | Edit with optimistic version; soft archive; restore; audit events; archive revokes grants and restore does not reinstate them |
| Password recovery | ADMIN-issued one-time temporary password for active non-admin users; no-store response, forced change, session revocation, auth epoch increment and audit |
| M1 CI | [Run 44527895017](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44527895017) **passed** on exact final PR #6 head `ebc349cffd35c50a91f3c18c219821acf0d53391`, including Node.js 26/PostgreSQL 18, migrations, audit, lint, typecheck, tests, backup/restore smoke, production build and Windows API runtime smoke |
| M1 / platform acceptance gates | Role/action matrix approved and helper tested; clean target-Windows service identity/ACL/startup/API integration; production PostgreSQL encrypted backup/restore and key recovery; final review of PRs #5/#6 |
| M2 CI | [Run 44531799575](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44531799575) **passed** on exact PR #7 head `60e9f694e9b0cf8960452ac63dfba8ee84431ca0`; all Linux/PostgreSQL and Windows API validation jobs passed, including immutable port-observation tests |
| Not implemented | SNMP/SSH discovery workers, inventory UI, Windows services, Background Worker, Windows Agent, monitoring, switch/NVR integrations, Desktop Bridge PoC, Store Commerce deployment, installer, updater and release automation |
| Security boundaries | User/branch management routes remain ADMIN-only. Owner-approved role policy is centralized in `PlatformAction`; OPERATOR is branch-scoped inventory/metadata editor plus safe discovery/sync; VIEWER is branch-scoped read-only; ADMIN is global. No operational device endpoints exist yet; no ADMIN creation/promotion via API |
| Repository administration | No repository settings, branch protections, permissions, hooks, webhooks or workflow administration settings changed |
| Desktop Bridge | PoC not executed; separate authorization remains required |
| Release/production | No installer, tag, release or production deployment claimed |

### M1 completion implementation details

- Branch edits require the current version and return conflict on stale writes.
- Archiving is transactional: mark inactive/deleted, revoke active branch grants, and append audit event.
- Restore makes the branch active but intentionally leaves old grants revoked; an administrator must reassign access.
- Password reset is deliberately admin-mediated because no verified email/SMS recovery channel exists. Self-service recovery is not exposed.
- PostgreSQL integration tests passed for these paths on run 44516741144. The custom-format PostgreSQL backup/restore smoke test also passed on that run. The explicit PostgreSQL host was added to `pg_restore` after the initial backup-smoke failure; the corrected backup/restore smoke passed on run 44517063564.

### Owner-approved role/action matrix — 2026-11-19

The owner approved ADMIN global administration and platform capabilities; OPERATOR branch-scoped inventory and switch-port/VLAN metadata read/write plus non-destructive discovery/sync; and VIEWER branch-scoped read-only inventory/metadata. OPERATOR is denied live device configuration, remote sessions, stored credentials, deployments and Store Commerce force-close. Force-close requires separate explicit per-operation approval and warning even for ADMIN. The server-side `PlatformAction` policy and branch-scope helper are implemented and CI-tested; future operational routes, WebSocket events and job handlers must enforce them. No operational device endpoint is claimed implemented.

### M2 inventory foundation — implementation boundary

The M2 branch adds common assets, switch profiles, manually maintained switch-port metadata, timestamped port observations and discovery-run persistence. API routes are branch-scoped and enforce the approved role matrix. CI run 44531050529 passed. This slice does not perform SNMP/SSH discovery, switch configuration, subnet scanning, Agent execution or monitoring. Discovery must preserve manual metadata and append provenance-stamped observations; partial/failed discovery must not delete assets or ports.

### Next actions

1. Keep PR #5 and PR #6 Draft/open/unmerged pending owner code review; no merge is performed here.
2. Collect clean target-Windows service identity/ACL/startup/API integration evidence when the five-service implementation is available.
3. Collect production PostgreSQL encrypted backup/restore and key-recovery evidence; CI disposable restore is not production evidence.
4. After M1 acceptance, begin M2 inventory and switch-port management, applying the approved role policy at every server-side entry point.

---

## Historical snapshot — M0 foundation (2026-11-19)



**Snapshot observed:** 2026-11-19T08:54:00Z (UTC). This section supersedes the earlier Phase 2 snapshot below; historical evidence and decisions remain preserved.

| Item | Current verified state |
|---|---|
| Authoritative repository | `aliajeli/enterprise-it-infrastructure-management-platform` — Private |
| Default branch | `main` at `60b0e515896c6db1e3d3469f834866e76d0198ca` |
| Current phase | **Phase 3 — Implementation**, explicitly authorized by the owner on 2026-11-19 |
| Active development branch | `phase3/platform-foundation` |
| Current implementation commit | `65ae3036437923288b27914b06be84cf3cddeaaa` |
| Active pull request | [PR #3 — initial platform web foundation](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/3), open, draft, base `main`; not merged |
| First milestone | M0 — repository and application foundation, **completed 2026-11-19** |
| Implemented scope | Initial Next.js App Router workspace, strict TypeScript configuration, Tailwind CSS integration, responsive infrastructure overview shell with truthful empty states, Phase 3 plan, refreshed landing page/changelog, ESLint 9 flat configuration using the official Next.js 16 Core Web Vitals and TypeScript presets, root/workspace lint scripts, and `.nvmrc` Node 26 selector, native keyboard-accessible mobile navigation, a GitHub Actions validation workflow for Node.js 26, and a Vitest 5.1.1 dashboard smoke-test baseline and a high-severity npm dependency audit gate |
| Not implemented | Authentication, API, database schema/migrations, Windows services, worker, Agent, monitoring, NVR/switch integrations, Desktop Bridge, installer, updater and release automation |
| Dependency reproducibility | `package-lock.json` is committed (lockfileVersion 3), refreshed to include Vitest 5.1.1 using Node.js 26.13.1/npm 11.20.0. A clean `npm ci` validation against this refreshed lockfile passed |
| Validation | GitHub Actions run [44491419345](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44491419345) passed all current gates on branch head `bd4eaf84`: `npm ci`, dependency-tree verification, `npm audit --audit-level=high` (0 vulnerabilities), ESLint, TypeScript, Vitest (1 file / 2 tests) and production build. The separate lockfile bootstrap job completed successfully. M0 acceptance criteria are met. PR remains draft and must not be merged/released until the committed-lockfile run passes |
| Execution environment limitation | Available execution environment reports Node.js 22.16.0/npm 10.9.2, below the selected Node.js 26 baseline; outbound DNS/network access is unavailable. GitHub-hosted runners successfully provision Node.js 26.13.1/npm 11.20.0. This limitation concerns the current assistant execution container, not the owner's workstation |
| Architectural constraints | All six owner-approved decisions in `DECISION_LOG.md` remain binding. Five independent Windows services remain required |
| Repository administration | No repository settings, branch protection, hooks, webhooks or permissions changed. Added a project-level CI validation workflow; no release workflow or production deployment workflow was added |
| Desktop Bridge | PoC not executed; it remains a separately authorized isolated task |

### Next actions

1. Merge the reviewed M0 foundation PR after confirming its current head and green CI status.
2. Begin M1 identity, access control and persistence on a new feature branch, starting with a threat-reviewed authentication/session design and Prisma schema/migration plan.
3. Keep production readiness and Windows installer claims blocked until the relevant M1–M8 acceptance criteria are independently validated.

---

## Historical snapshot — primary repository (2026-11-19, post-merge R1)

**Snapshot observed:** 2026-11-19T08:27:09Z (UTC). This is a dated record, not continuously current status. Before acting, verify live PR/main state from GitHub with `gh pr view 2 --json state,headRefOid,baseRefName,url` and `git ls-remote origin refs/heads/main`. The authoritative repository/default branch is the primary private repository's `main`; a temporary Arena session branch is only a PR source, not a replacement authoritative development branch.

This section is the operative handover snapshot for the primary private repository. The "Current package" paragraph and sections A–G below it were written **before** the transfer and describe the local `FINAL_UPLOAD` draft and the temporary public mirror; they are retained unchanged as history. Where they state that the package has not been transferred to the primary repository, [TRANSFER_STATUS.md](TRANSFER_STATUS.md) and this section supersede them: the transfer was completed and is recorded in commit `f60676205bcf9ff7f5608f0e3b3074a76bdb3776`.

| Item | Value (verified 2026-11-19 unless noted) |
|---|---|
| Repository | `aliajeli/enterprise-it-infrastructure-management-platform` — primary, private (GitHub API metadata `private: true`) |
| Sole authoritative repository | This primary private repository — owner-approved decision of 2026-11-19, recorded in [DECISION_LOG.md](DECISION_LOG.md). The temporary public documentation mirror https://github.com/aliajeli/testing was **permanently deleted by the owner** (owner-confirmed; independently checked read-only: HTTP 404 anonymously and with the owner token, and absent from the owner's authenticated repository list, which does include private repositories). Deletion does **not** recall content already cloned, downloaded, crawled, indexed or cached while the mirror was public, and no GitHub Support cache purge or offline archival copy is claimed or verified. Historical references to the mirror elsewhere in this file are retained verbatim as history |
| Default branch / latest commit on `main` | `main` / `eb8b704f945ca4c5199d97a6a8c4bd286068cfbb` — PR #1 squash merge (2026-11-19T07:58:59Z); independently verified via GitHub commit/PR metadata and `git ls-remote origin refs/heads/main` |
| PR #1 | **MERGED**, squash commit `eb8b704f945ca4c5199d97a6a8c4bd286068cfbb`, merged at `2026-11-19T07:58:59Z`; [PR #1](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/1). The review report's open/unmerged wording is historical |
| Historical transfer history | 22 commits at pre-merge review time (not the current post-merge count): root `c509d99` (README baseline, 06:37:26Z), 19 per-file transfer commits (06:37:51Z–06:38:36Z), `b6bd6d8` (README landing page — the commit referenced by TRANSFER_STATUS.md, 06:38:54Z), `f606762` (TRANSFER_STATUS.md, 06:39:03Z). Review clones may be shallow; unshallow before history verification |
| Current development phase | Phase 2 — Architecture, Design, Documentation and Technical Validation Planning. Phase 3 not authorized and not started |
| Current owner-review item | [PR #2](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/2) — **OPEN, unmerged** at the snapshot observation; documentation-only R1 reconciliation against `main`. Do not merge it |
| PR #2 head observed at snapshot preparation | `2561d5052bce7875cbe27b2579a6ab6fedd1561c` — input to these review corrections, not a claim that it remains the live head. The commit containing this updated snapshot necessarily follows that SHA; obtain its exact SHA from live PR metadata/Git history rather than attempting a self-referential commit hash |
| Current application version | Not applicable — no application and no version metadata exist yet (bootstrap period per [DECISION_LOG.md](DECISION_LOG.md) decision 3). Version assignment for documentation-only commits is an open owner question (see [PHASE2_REVIEW_2026-11-19.md](PHASE2_REVIEW_2026-11-19.md) §8) |
| Latest stable / beta release, tags | None — zero releases, zero tags (verified via GitHub API) |
| Latest installer build | None — no installer, build system or application source exists |
| GitHub Actions / release pipeline status | Not configured — zero workflows (verified via GitHub API). None were created or modified during the review |
| Branch protection (`main`, future `beta`) | Historical review observation: protection settings unreadable (HTTP 403); `beta` absent at that review. Not reverified by R1; no protection enabled or settings changed. Q-07 remains an owner decision |
| Database migration status | None — no schema, migrations or database exist |
| Required environment / services / run-and-test commands | Not applicable — documentation-only repository |
| Documentation baseline and integrity | **22 tracked root files**, verified in the remote tree at `eb8b704` and the R1 working tree (historical transfer baseline: 21 at `f606762`). PR #1 delivered the GUIDELINE.md archival repair. R1 refreshes [FINAL_FILE_MANIFEST.md](FINAL_FILE_MANIFEST.md) (20 content entries) and [SHA256SUMS.txt](SHA256SUMS.txt) (21 entries including the manifest, excluding itself); verify with `sha256sum -c SHA256SUMS.txt` |
| Last completed task | PR #1 successfully squash-merged; post-merge remote verification completed. Its Phase 2 review findings remain recorded as historical evidence in [PHASE2_REVIEW_2026-11-19.md](PHASE2_REVIEW_2026-11-19.md) |
| In-progress task | Owner review of PR #2, including the archival measurement-scope clarification and dated HANDOVER snapshot corrections. Update this existing PR only, rerun integrity checks and stop for owner review; do not open a replacement PR |
| Known documentation discrepancies | Historical pre-transfer wording in this file, [FINAL_HANDOVER_REPORT.md](FINAL_HANDOVER_REPORT.md) and [DOCUMENTATION_REVIEW_REPORT.md](DOCUMENTATION_REVIEW_REPORT.md) describes the temporary mirror and the untransferred local package; retained as history, superseded by this snapshot and TRANSFER_STATUS.md. Full list in the review report §4 |
| Exact next action | Verify live PR #2/main status from GitHub, then owner-review the existing PR #2 and its latest correction commit; do not merge it during this task. Remaining review-report §8 questions still require owner decisions, including Q-02 (archival byte-preservation mechanism; Appendix B not implemented) and Q-07 (branch protection; not enabled). Q-03 is resolved. Stop and wait; no Phase 3 authorization is implied and no Desktop Bridge PoC may run |

## GUIDELINE archival measurement clarification — 2026-11-19 (PR #2 review)

The previous audit wording “lines 6–1544 = 39,181 bytes” conflated the **embedded source prompt** with the **complete protected region**. It is not a valid measurement of those complete lines. The PR description's 39,295-byte protected-region count and 39,181-byte source-prompt count measure different scopes, not different archived versions. Historical review reports remain unchanged; this clarification defines the scopes explicitly.

Compared exact Git objects (no text-mode decoding or newline conversion):
- Baseline commit `eb8b704f945ca4c5199d97a6a8c4bd286068cfbb`, GUIDELINE blob `5cf1fe00f420226716fab36a6f26828d005fb547`.
- PR #2 head observed before these corrections: commit `2561d5052bce7875cbe27b2579a6ab6fedd1561c`, GUIDELINE blob `2dc1d0c82503df0ff26a68b41f4644a76ba87b5d`. This follow-up does not modify GUIDELINE.md at all, so the corrected PR head retains this same blob.

**Exact boundaries (zero-based, half-open byte offsets in both blobs):**
- Complete protected region: `[626, 39921)`, physical lines 6–1544 inclusive. Starts with `<!-- BEGIN ORIGINAL MASTER PROMPT; SOURCE BYTES FOLLOW -->` plus LF (59 bytes); ends with `<!-- END ORIGINAL MASTER PROMPT; SOURCE BYTES END -->` plus LF (54 bytes).
- Embedded original prompt: `[685, 39866)`, excluding both markers and the one LF separator at `[39866, 39867)` immediately before the closing marker. This source has 1,536 CRLF pairs and no terminal newline. No `strip`/`rstrip` or line-ending normalization is applied.
- Maintained wrapper outside the protected region: concatenate prefix `[0, 626)` and suffix `[39921, EOF)` in that order, with no inserted separator. This is the measured outside region; historical wrapper passages are not thereby authorized for rewriting.

| Scope | Baseline bytes | PR-head bytes | Baseline SHA-256 | PR-head SHA-256 |
|---|---:|---:|---|---|
| Complete protected region | 39295 | 39295 | `70c4863fb97824a35e22a084e78d7916646d0038fe8c681d1c10f142020f8932` | `70c4863fb97824a35e22a084e78d7916646d0038fe8c681d1c10f142020f8932` |
| Embedded original prompt | 39181 | 39181 | `38634f573b0391402a1b58ad927d133fa0ad2ca6551c8ea66180daddd3e24b16` | `38634f573b0391402a1b58ad927d133fa0ad2ca6551c8ea66180daddd3e24b16` |
| Maintained wrapper outside protected region | 15939 | 16674 | `0d69334d899b483dd1d34b7ec686badc101c90343ec6335a812dfdb67384dab5` | `9614fb40ee0df15618e0b01b6f6009ab18e45102bb4e9a188f3e15d1e20ef4c6` |

The protected-region difference from the source size is exactly **114 bytes = 59 + 1 + 54**. Wrapper size increased by 735 bytes in R1's maintained repository-location correction; none of those bytes are inside the protected region. Both protected scopes are byte-identical, not merely hash-equal.

Reproduce against the baseline, original PR head and live locally fetched PR head (replace `HEAD` with the fetched head SHA if necessary):

```sh
python3 - <<'PYCODE'
import hashlib, subprocess
begin = b'<!-- BEGIN ORIGINAL MASTER PROMPT; SOURCE BYTES FOLLOW -->\n'
end = b'<!-- END ORIGINAL MASTER PROMPT; SOURCE BYTES END -->\n'
versions = []
for ref in ('eb8b704f945ca4c5199d97a6a8c4bd286068cfbb',
            '2561d5052bce7875cbe27b2579a6ab6fedd1561c', 'HEAD'):
    d = subprocess.check_output(['git', 'show', ref + ':GUIDELINE.md'])
    assert d.count(begin) == d.count(end) == 1
    a, e = d.index(begin), d.index(end)
    z = e + len(end)
    assert d[e-1:e] == b'\n' and d[e-2:e] != b'\r\n'
    parts = (d[a:z], d[a+len(begin):e-1], d[:a] + d[z:])
    assert parts[0] == b''.join(d.splitlines(keepends=True)[5:1544])
    assert (a, z) == (626, 39921)
    assert tuple(map(len, parts[:2])) == (39295, 39181)
    versions.append(parts)
    for scope, data in zip(('protected', 'source', 'outside-wrapper'), parts):
        print(ref, scope, len(data), hashlib.sha256(data).hexdigest())
assert all(v[:2] == versions[0][:2] for v in versions)
assert versions[1] == versions[2]  # follow-up leaves entire GUIDELINE blob unchanged
PYCODE
```

*Historical — pre-transfer; superseded by the snapshot above.*

**Current package:** `FINAL_UPLOAD` is a local root-level owner-review draft based on local branch `phase2/final-documentation-corrections`, commit `4dea17d1bdc02e2b5e00aaefc0d759094011b915`, with further uncommitted package-only reconciliation. No GitHub operations occurred during this local finalization. It has not been verified or transferred to the private primary repository. See [FINAL_HANDOVER_REPORT.md](FINAL_HANDOVER_REPORT.md).

## A. Current repository state
- **Public documentation mirror:** https://github.com/aliajeli/testing — intentionally public, for review; not the private application repository.
- **Branch:** `main`, as observed on the public mirror at review start.
- **Published temporary-mirror snapshots:** initial package `94fdb5a35d6ed6774954a06c8fa0f0d9d7220e92`; subsequent corrections `a19fce5c5e2c632ada3ff3748a11a541d0853a30`, committer timestamp `2026-11-19T09:46:29+03:30`. The latter was verified as `main` at review start.
- **Publication scope:** The documentation package has been published to the temporary mirror at the commit above. That publication is not publication to the main project repository. The owner reports that the main repository has not yet received the documentation; its current private contents were not independently verified. The corrections in `a19fce5c5e2c632ada3ff3748a11a541d0853a30` are published to the temporary mirror. Further independent-review corrections are on local branch `phase2/final-documentation-corrections`; remote publication remains unverified. A commit cannot embed its own final hash without changing that hash; obtain this review branch’s exact local commit using `git rev-parse HEAD`, and verify its remote ref separately after any authorized push. No unverified branch SHA is asserted here.
- **Last verified mirror synchronization:** `a19fce5c5e2c632ada3ff3748a11a541d0853a30` on `main`. A prior review used the session-provided date 2026-11-18, while host and remote commit timestamps showed 2026-11-19; that discrepancy has not been reconciled.
- **Current prepared file inventory:** `README.md`, `AGENT_SPECIFICATION.md`, `API_DOCUMENTATION.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `DATABASE_DESIGN.md`, `DECISION_LOG.md`, `DEPLOYMENT_WORKFLOWS.md`, `DESKTOP_BRIDGE_POC.md`, `DOCUMENTATION_REVIEW_REPORT.md`, `GUIDELINE.md`, `HANDOVER.md`, `NETWORK_REQUIREMENTS.md`, `RELEASE_PROCESS.md`, `SECURITY_POLICY.md`, `TESTING_STRATEGY.md`, `VERSIONING_POLICY.md`. These documents are in the published mirror under `prepared/`; `MANIFEST.md` and `SHA256SUMS.txt` are at mirror root. The corrections in `a19fce5` are published; the subsequent independent review changes are local until independently verified on a remote branch.
- **Actual application repository:** separate, private; current authenticated contents, branch, releases and permissions **Not verified** in this review. The mirror's public visibility is intentional.

## B. Current project phase
Phase 2 — Architecture, Design, Documentation and Technical Validation Planning. No Phase 3 authorization has been given. Do not implement the application, production Agent or Bridge, create production migrations or releases, build installers, execute the Bridge PoC, or configure production release workflows during this task.

## C. Approved architectural decisions
[DECISION_LOG.md](DECISION_LOG.md) records six owner-approved decisions: five separate services; date-only package destination with identifier metadata; one-time installer bootstrap exception; central private-release Update Proxy; bounded, separately authorized Bridge PoC; and three-tier testing. These decisions are authoritative; technical implementation and compatibility remain unverified.

## D. Completed documentation work
- [README.md](README.md): review-mirror purpose and index.
- [GUIDELINE.md](GUIDELINE.md): original owner-supplied requirements archive and development history. This local package restores the archived original bytes from the supplied source and compares them byte-for-byte; the earlier published mirror copy was LF-normalized and not byte-identical. Neither was independently compared against the conversation.
- [ARCHITECTURE.md](ARCHITECTURE.md), [DATABASE_DESIGN.md](DATABASE_DESIGN.md), [DECISION_LOG.md](DECISION_LOG.md): topology, logical data model, decisions.
- [SECURITY_POLICY.md](SECURITY_POLICY.md), [NETWORK_REQUIREMENTS.md](NETWORK_REQUIREMENTS.md): proposed trust boundaries and network requirements.
- [AGENT_SPECIFICATION.md](AGENT_SPECIFICATION.md), [DEPLOYMENT_WORKFLOWS.md](DEPLOYMENT_WORKFLOWS.md), [DESKTOP_BRIDGE_POC.md](DESKTOP_BRIDGE_POC.md): Agent, installation and separately authorized PoC designs.
- [API_DOCUMENTATION.md](API_DOCUMENTATION.md): proposed, unimplemented API.
- [VERSIONING_POLICY.md](VERSIONING_POLICY.md), [RELEASE_PROCESS.md](RELEASE_PROCESS.md), [TESTING_STRATEGY.md](TESTING_STRATEGY.md): proposed delivery and test gates.
- [CHANGELOG.md](CHANGELOG.md) and [DOCUMENTATION_REVIEW_REPORT.md](DOCUMENTATION_REVIEW_REPORT.md): history and current review findings.

## E. Unverified assumptions
Windows edition/architecture, service accounts, service readiness/restart behavior, edge mTLS/identity forwarding, service-to-service authentication, firewall/network access, and certificate provisioning are untested. PostgreSQL bundled installation, backup/restore, DPAPI key recovery, migrations, major upgrade and rollback are untested. GIG/OKCS explicit-credential deployment without trust using SMB/ADMIN$/SCM, Agent enrollment/rotation/revocation and Session Helper delivery are untested. Bridge browser integration, isolation, replay resistance, app launch and credential handoff are untested; PoC not executed. Hikvision model/firmware and ISAPI behavior, camera reconciliation, MikroTik/Winbox, TeamViewer LAN, SSH/RDP/VNC, ICMP monitoring and real Store Commerce deployment are untested. GitHub per-commit dispatch/allocator/concurrency, installer/upgrade, private Update Proxy, signing, release and update behavior are untested. Features remain unimplemented unless independently verified otherwise.

## F. Outstanding tasks
| Status | Task |
|---|---|
| Completed | Original ZIP prompt and this local package prompt match the owner-supplied file; earlier published mirror copies have CRLF-to-LF differences. |
| Designed | Five-service topology, date-only package path, Agent/Bridge/proxy boundaries, database model and release/testing policy. |
| Pending validation | Windows, database, security, integration, installer, CI and hardware checks listed above. |
| Pending validation | Owner review of public-mirror security findings and archival CRLF differences; GitHub publication of the separate local review branch remains unverified. |
| Not started | Application implementation, production migrations, installer, production release workflow and Bridge PoC. |

## G. Exact next action
Provide this local package for owner review and wait for explicit feedback and authorization. Do not publish, merge, transfer to the main repository or start Phase 3.

## Historical context
An earlier application-repository inspection reported an empty clone before the repository became private. A later persisted workspace lost some Git metadata. Those historical facts do not describe this public mirror, which has the verified `main` commit and documentation listed above. The six decisions were approved on 2026-11-18. Documentation-only source archival and design reviews did not implement or validate the application.


## Follow-up snapshot — Worker queue foundation (2026-11-19)

- Added commit-level Worker queue foundation in `apps/worker`, backed by additive `DiscoveryRun` lease fields and migration `20261119150000_discovery_worker_leases`.
- Queue operations use atomic `FOR UPDATE SKIP LOCKED`, owner-bound leases, heartbeat, expiry recovery, bounded retry, cancellation acknowledgement and guarded completion.
- Worker source allow-list is empty by design; no discovery run is claimed and no network traffic can be generated by this milestone.
- Unit tests cover retry delay and max-attempt policy. PostgreSQL race/lease integration tests are still outstanding.
- No SNMP handler, credential vault, API enqueue/cancel route, Windows service registration, installer or release is implemented.
- Previous exact-head CI for `f73cab6c97ab199c415e77f356e80e1682cac7a3` passed; CI for this new commit is required and pending.


## 2026-11-19 — Worker queue follow-up (current session)
- Verified GitHub Actions run [44572613928](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44572613928) on head `356c5b5ab2e49fbbf29ae7d6b26a5ccf06d3d302`: all three jobs passed, including Windows API runtime smoke, Prisma schema/migration validation on PostgreSQL 18, lint, typecheck, unit tests, backup/restore smoke and production build.
- Fixed Worker lease recovery ordering so cancellation takes precedence over retry exhaustion. Added live-lease-expiry predicates to completion and cancellation acknowledgement so stale workers cannot finalize expired runs.
- Added PostgreSQL integration tests for single-claim concurrency, lease owner enforcement, stale-worker rejection, expired-lease recovery/reclaim, retry requeue/exhaustion, cancellation precedence and transaction rollback. Tests are restricted to the disposable `platform_test` database.
- Commits after the last validated CI head: `5c2cb8f`, `3600961`, `1691302`. Their validation is pending; do not describe these fixes/tests as CI-passing until a run for the exact current head succeeds.
- PR #8 remains Draft and unmerged. Worker has no discovery handlers and its source allow-list remains empty. No network polling, credential vault, enqueue API, Windows Worker service, installer or Release is available yet.
- Next action: wait for the current head's CI, inspect logs on failure, then add any missing queue race tests and reconcile this handover with the exact result. Do not merge or publish an installer/release without owner approval and required platform gates.


## 2026-11-19 — PostgreSQL integration test failure analysis
- CI run [44576334911](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44576334911) on `3ee4a787` completed with failure in Worker unit/integration tests. Windows API runtime smoke and lockfile bootstrap passed; Platform validation reached Unit tests and failed 4 of 11 Worker integration tests.
- Root cause in the tests: the queue claim API is global (no branch filter), but cases shared queued rows in one branch. Later tests sometimes claimed an earlier test's row instead of the row they had just created. This produced misleading LEASE_LOST / cancellation failures and a lease-pair check violation when the test mutated an unclaimed row.
- Corrected test isolation with per-test cleanup and explicit assertions that each claim returns the intended run. Lease recovery count assertion now allows additional eligible rows, while still verifying the target run's recovered state.
- Follow-up commit: `4ca9fd786eb1820db99e0a7745079908c418ccad`. CI run [44576830667](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44576830667) is currently in progress; exact-head results are not yet known.
- Do not claim the PostgreSQL queue tests pass until run 44576830667 (or a later exact-head run) succeeds. Worker remains fail-closed with no discovery handlers enabled.


## 2026-11-19 — Credential Vault validation correction
- Exact-head CI for crypto-core commit `25021e1b2b428f2f8287484105a36d7d2bd9d381` failed on both Linux platform validation and Windows API runtime smoke. Both failures came from the same malformed control-character validation expression in `apps/api/src/security/credential-vault-crypto.ts`; six envelope tests rejected the valid `credential-1` context before exercising encryption.
- Corrected context validation to reject ASCII control characters by code point, and added a regression test for valid identifiers and control-character rejection.
- Bumped root package version to `0.1.1` and synchronized the npm lockfile root metadata. This is source/version metadata only; no installer or Release was produced.
- The correction requires fresh exact-head Linux/PostgreSQL and Windows CI before DPAPI implementation proceeds. Credential Vault remains unconnected to the API and must not be used for real equipment secrets.


## 2026-11-19 — Credential Vault regression fixture follow-up
- Windows CI on `e9084406dd300ba2c0412316fc799f68bb3dcba3` passed the six pre-existing envelope tests (20 tests passed overall) but exposed an error in the newly added control-character test fixture: it supplied a literal backslash-u sequence instead of an actual U+0001 character.
- Updated the fixture to use `String.fromCharCode(1)`, ensuring the test exercises the intended control-character guard. Bumped root package/lockfile version to `0.1.2`.
- This follow-up is pending exact-head Linux/PostgreSQL and Windows CI. No production key provider or Credential API is enabled.


## 2026-11-19 — Credential key-buffer hygiene and DPAPI design
- CI for exact head `4c2315d47b7d8e1e13e4221a838880ba6da14d3f` passed both Push and PR workflows, including Windows API runtime smoke and Linux/Node.js 26/PostgreSQL 18 platform validation.
- Hardened `CredentialKeyProvider` ownership semantics. The crypto core now zeroes provider-returned KEK buffers and local copies on encrypt/decrypt, including invalid key-version failure. Added regression tests.
- Added `WINDOWS_DPAPI_PROVIDER_DESIGN.md` with a bounded .NET helper/stdin-stdout binary protocol, fixed machine-scope DPAPI, service SID-derived entropy, installer-owned ACL requirements, atomic keyring/rotation and independent recovery custody/clean-host restore requirements.
- This is not yet a DPAPI implementation. No production key provider, persistent credential model/API, independent recovery export, installer ACL provisioning or clean-machine restore drill exists. Keep Credential Vault disconnected and do not enter real equipment secrets.
- Root package version and lockfile metadata are now `0.1.3`; this is source metadata only. No installer or Release was created.


## 2026-11-19 — Windows DPAPI helper primitive
- Added `apps/api/windows/dpapi-helper/CredentialVault.DpapiHelper.csproj` and a fixed-purpose .NET 10 Windows helper. It performs only DPAPI machine-scope Protect/Unprotect for exactly 32-byte KEKs, derives optional entropy from a domain separator + installation ID + current Windows SID, and communicates through a bounded length-prefixed binary stdin/stdout protocol.
- Added `apps/api/src/security/windows-dpapi-protector.ts`: absolute helper path, no shell/arguments/environment key, bounded frames, five-second timeout, generic errors and best-effort buffer zeroization.
- Windows CI now builds the helper and runs DPAPI round-trip / installation-binding integration tests. Non-Windows test runs verify fail-closed behavior and skip the native integration test.
- This is a DPAPI primitive only, not a production key provider. No installer-created service identity or ACL verification, persistent key registry, atomic rotation, independent recovery export or clean-host restore drill exists. No Credential DB/API or real-device credential use is enabled.
- Root version metadata is `0.1.4`; no installer/Release was created.


## 2026-11-19 — DPAPI helper native-memory correction
- Corrected allocator pairing in the .NET helper: HGlobal input/entropy buffers are freed with `FreeHGlobal`; DPAPI-owned output is released with `LocalFree` after zeroization.
- Request frame, copied key, entropy and output buffers are now zeroed in an outer finally path, including malformed requests.
- Updated the cross-installation integration test for the helper's generic nonzero-exit failure.
- Normalized root package/lock JSON file endings and bumped root version metadata to `0.1.5`.
- Fresh Windows helper build/runtime and Linux validation are required. No production keyring or recovery is enabled.


## 2026-11-19 — DPAPI helper test path portability
- Adjusted the non-native helper path fixture to use the current host's absolute path. This allows the Node.js constructor/fail-closed tests to run on Linux while retaining the Windows native helper integration test.
- Bumped root version and lockfile metadata to `0.1.6`. Fresh CI required.


## 2026-11-19 — DPAPI response framing correction
- Windows native integration exposed a response parser assumption: it incorrectly required the DPAPI-protected blob to be 32 bytes. Protected DPAPI blobs are variable length; only the unprotected KEK must be exactly 32 bytes.
- Node helper now accepts a bounded variable-length Protect result and continues to require exactly 32 bytes after Unprotect. Bumped root version/lock metadata to `0.1.7`.
- Fresh Linux/PostgreSQL and Windows helper/runtime CI is required before proceeding.


## 2026-11-19 — DPAPI Unprotect request bounds
- Windows integration showed that the Node client incorrectly required the input to Unprotect to be exactly 32 bytes. DPAPI ciphertext is variable length; only the original KEK and decrypted output are 32 bytes.
- Node framing and .NET helper now allow bounded protected blobs for Unprotect, while Protect still accepts exactly 32-byte KEKs and Unprotect output remains exactly 32 bytes.
- Bumped root version/lock metadata to `0.1.8`. Fresh Windows and Linux CI required.


## 2026-11-19 — DPAPI payload test expectation
- The Linux CI run on `6392e0cff79257a7a03e78b450d0c2663cabfaf4` exposed only a stale assertion message in the invalid-length unit test after the request validator was generalized for variable-length protected blobs. Updated the expectation and bumped root/lock metadata to `0.1.9`.
- The native Windows integration test has not yet passed; the next exact-head Windows run must verify Protect/Unprotect end-to-end.


## 2026-11-19 — DPAPI primitive validation completed
- Exact HEAD `5067518791b0899f410fee8b76495028e11bd590` passed both CI workflows:
  - Push: [44590138482](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44590138482) — all three jobs successful.
  - PR: [44590153726](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44590153726) — Linux platform validation and Windows API runtime smoke successful; bootstrap job skipped as expected for PR.
- Windows CI compiled the .NET 10 DPAPI helper and passed the native Protect/Unprotect integration test, including installation-identity binding. Linux CI passed the non-Windows fail-closed tests and full platform suite.
- The Node client and helper implement bounded binary framing, machine-scope DPAPI, installation ID + current SID entropy, generic failure behavior and buffer cleanup. The helper is a primitive, not a production provider.
- Remaining hard gates: installer-managed service identity and NTFS ACL provisioning/verification; persistent protected key registry; atomic key rotation and reference-aware retirement; independent recovery export/custody; clean-machine recovery drill. No Credential model/API, production key registration, discovery handler, installer or Release is available.
- Root version metadata is `0.1.10`.



## 2026-11-19 — Windows keyring storage design gate
- Exact-head CI passed on keyring-core commit `2b9b30d99018161970aba4f8e3aa9e33b904d1b3`: Push run [44595293338](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44595293338) and PR run [44595309352](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44595309352). Both Linux/PostgreSQL platform validation and Windows API runtime smoke completed successfully.
- GitHub Actions then created lockfile metadata commit `7d5927d907e961afd60eb48c09834268b9b01e2d` as the expected bootstrap follow-up; branch head was verified before this documentation change.
- Added `WINDOWS_KEYRING_STORAGE_DESIGN.md` defining fixed ProgramData storage, dedicated service SID, exact ACL verification, transaction-scoped process lock, durable atomic replacement, binary helper session and Windows acceptance gates.
- Design only; no production storage adapter or real credential storage. Worker handlers remain disabled. No installer or Release.
- Root package and lockfile metadata advanced to `0.1.12`.



## 2026-11-19 — package-lock dependency consistency correction
- Both Push and PR validation on `8e877a8a4640987491a6a3584cec561b37059de4` failed at `npm ls --all`. The precise invalid entry was `node_modules/@prisma/streams-local`: lock metadata incorrectly said `0.1.12` while the resolved package tarball was `0.1.11` and `@prisma/dev` required `0.1.11`.
- Windows API runtime smoke passed on that SHA, including DPAPI helper build and API build/tests.
- Corrected only the third-party lock entry back to `0.1.11`; root package/lock metadata advances to `0.1.13`. Exact-head Linux/PostgreSQL and Windows CI must pass before implementation continues.


## 2026-11-19 — Windows keyring protocol contract milestone
- Exact-head CI for `12a44a5e83e2771ab176bca9564d6a05fa359618` passed both Push run [44597262204](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44597262204) and PR run [44597276046](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44597276046). Linux/Node.js 26/PostgreSQL 18 platform validation and Windows API runtime smoke passed; the Push lockfile bootstrap also passed.
- Added the version-1 bounded binary frame codec and unit tests for the Windows keyring helper session. Frozen opcodes and frame semantics in `WINDOWS_KEYRING_STORAGE_DESIGN.md`.
- This milestone does not implement the .NET storage operations, service SID/DACL validation, cross-process lock, durable atomic replace or Node storage adapter. No keyring is persisted in production and no real equipment credentials may be entered.
- Root package and lockfile metadata advanced to `0.1.14`; no installer or Release was created.


## 2026-11-19 — Windows keyring helper-session transport
- Exact-head CI for `1343b1dd6e9a0a10f37beb7866e6a2f84c74384b` passed both Push run [44599777807](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44599777807) and PR run [44599791110](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44599791110), including Linux/PostgreSQL validation, Windows DPAPI helper build/API tests, and lockfile bootstrap on Push.
- Added an unregistered Node helper-session transport client and fake-process tests. It holds a single helper session for a storage callback and validates protocol state.
- The .NET helper does not yet implement the storage opcodes. Service SID/NTFS ACL verification, cross-process lock, durable atomic replace, installer provisioning and production registration remain unimplemented. Keep Credential Vault test-only; no real equipment credentials, installer or Release.
- Root version metadata advanced to `0.1.15`.


## 2026-11-19 — helper-session lifecycle correction
- Follow-up review of `89c0dc8dc96f5700c1227f3009326b9b6e8690f7` found that successful transaction completion needed to send the explicit END opcode, and helper startup failures must release the local queue. Corrected both and added an END assertion.
- This is still only an unregistered transport client; the .NET helper storage operations, ACL, cross-process lock, atomic write and installer provisioning remain absent.
- Root version metadata advanced to `0.1.16`.


## 2026-11-19 — Windows keyring helper path portability correction
- Exact-head CI on `505a2b2b487d7a4e85e26b4d0396def84399c59b` failed only in Linux Platform validation's API Unit tests: two tests constructed the Windows helper client with a Windows drive path, while the implementation used host-native `node:path.isAbsolute`. Windows API runtime smoke passed; lint and typecheck passed on Linux.
- Corrected validation to use `node:path.win32.isAbsolute`, because this executable path is always a Windows path regardless of where the unit test runs. Added explicit regression coverage for absolute and relative Windows paths.
- Root package/lockfile version metadata advanced to `0.1.17`. Fresh exact-head Push and PR CI are required; do not treat the fix as validated until both complete.
- The Node transport remains deliberately unregistered. The .NET helper still lacks keyring storage operations, strict service-SID/DACL validation, cross-process locking and durable atomic replacement. No installer, Release or real credential storage is enabled.


## 2026-11-19 — Windows keyring storage helper groundwork (v0.1.18)
- CI on parent `f4829cbf35bb5a3ebb4ec07143c787abd12e6b4d` completed successfully for both Push and PR workflows, including Linux/PostgreSQL validation and Windows API runtime smoke.
- Added separate .NET 10 project `apps/api/windows/keyring-storage-helper`; it implements the v1 session protocol, fixed ProgramData registry path, installer-provisioned lock-file requirement, service-SID-only runtime identity, exact protected owner/DACL validation, handle-based reparse checks, bounded JSON read/write, same-directory temporary file, flush-to-disk, write-through replacement and read-back verification.
- The helper deliberately fails closed if the installer has not provisioned the dedicated service SID, directory, exact ACLs and lock file. It does not create or repair them.
- Windows CI now compiles the new helper. Dedicated service-account integration tests, ACL tamper tests, two-process lock tests, crash/interrupted-write tests, and clean-VM provisioning are still outstanding. Compile success alone is not acceptance.
- The Node client remains unregistered; no API composition wiring, real credential persistence, Worker discovery, installer or Release.


## 2026-11-19 — Helper compile correction (v0.1.19)
- Windows CI on `5637432dcaf4253d7e12eb214b20932e6f3574ec` compiled the existing DPAPI helper but failed compiling the new keyring storage helper at the CreateFileW P/Invoke declaration (CS1001).
- Moved `EntryPoint="CreateFileW"` into the `DllImport` attribute. This is a compile-only correction; the new helper remains unregistered and has not passed dedicated Windows identity/ACL/process integration tests.


## 2026-11-19 — Windows helper nullable compile correction (v0.1.20)
- The first P/Invoke syntax correction on `c0ede7b69d464750d0d17bc0e2d07cb563057c83` passed the previous syntax location but exposed two nullable-analysis errors: the compiler could not infer the transaction guard's non-null guarantee for `heldLock`, and `RawSecurityDescriptor.Owner` is nullable.
- Added an explicit null-forgiving dereference only after `RequireLock()`, and an explicit null-owner rejection before SID equality. No storage behavior was broadened.


## 2026-11-19 — Service SID token resolution and fail-closed smoke (v0.1.21)
- Updated service SID resolution to consider both the token User SID and token Groups, then require exactly one unique S-1-5-80 service SID. This supports dedicated virtual service accounts while still rejecting ordinary interactive identities and ambiguous tokens.
- Added a Windows CI process smoke test for the actual built helper: on an unprovisioned runner, BEGIN must return exactly the stable one-byte generic ERROR frame, a non-zero exit code and no stderr diagnostics.
- This is a fail-closed protocol smoke test only. It does not validate installer provisioning, the real dedicated service SID ACLs, concurrent processes, crash recovery or power-loss durability.


## 2026-11-20 — DPAPI service identity binding (v0.1.22)
- Security review found the DPAPI helper derived entropy from `WindowsIdentity.GetCurrent().User` without requiring the dedicated service SID. This could bind the key to an unintended account identity and did not enforce the intended service-only execution contract.
- DPAPI helper now resolves exactly one unique `S-1-5-80-...` service SID from token user/groups and uses that SID in DPAPI entropy. No fallback to LocalSystem or interactive users.
- DPAPI helper rejects trailing bytes after its one bounded request.
- Windows CI launches the actual helper under the unprovisioned hosted-runner identity and requires the generic failure frame, non-zero exit and no stderr.
- Still outstanding: actual execution under an installer-provisioned service SID, DPAPI protect/unprotect round-trip in that identity, ACL tamper and process integration tests. No adapter registration, no credential persistence, no Installer/Release.


## 2026-11-20 — DPAPI test contract correction (v0.1.23)
- Windows CI correctly rejected the helper under the hosted runner's non-service identity after v0.1.22. The existing Vitest integration test still expected an interactive-user DPAPI round-trip, so that test failed by design.
- Updated tests to assert rejection for a non-service process token in CI. Positive protect/unprotect round-trip is now explicitly gated behind `RUN_PROVISIONED_DPAPI_INTEGRATION=1` and must only run inside the future installer-provisioned dedicated service identity test environment.
- This is a test expectation correction, not a weakening of service identity enforcement.


## 2026-11-20 — Independent recovery design (v0.1.24)
- Added `CREDENTIAL_VAULT_RECOVERY_DESIGN.md`: independent offline RSA-3072 OAEP-SHA256 wrapping for every retained KEK, separate RSA-PSS-SHA256 manifest signing, canonical bounded manifest, HSM/hardware-backed private-key custody, two-person export/restore approval, clean-host restore preserving installation ID, and explicit acceptance gates.
- This is a design decision proposal only. No recovery keys or recovery workflow have been implemented. DPAPI remains machine-bound; no production use until the clean-host restore drill succeeds.


## 2026-11-20 — Windows helper process shutdown verification (v0.1.25)
- Fixed a lifecycle gap in the unregistered Node storage transport: after END_OK it now closes stdin and waits for the helper's close event with exit code 0.
- Non-zero exit or shutdown timeout fails the enclosing storage transaction; cleanup still kills the helper and releases the in-process transaction queue.
- Tests cover successful shutdown, stdin closure and non-zero process exit after END_OK.
- This does not enable storage. Installer provisioning, positive dedicated-Service-SID integration, path-component hardening and real multi-process/ACL/crash tests remain outstanding.


## 2026-11-20 — Shutdown test fixture correction (v0.1.26)
- Corrected a duplicate constructor declaration in the FakeHelper test fixture introduced with the process-exit lifecycle tests. The runtime transport changes from v0.1.25 are unchanged.
