## 0.1.176 least-rights Vault retry fix — 2026-11-24

Windows run 45375850378 on 753e03da1463edbf185031ed8252f07a03a0f4f0: elevated admin fresh provision and verify succeeded, third (retry) attempt failed `credential-vault:win32-5`; Linux Node 26/PostgreSQL 18 passed. Candidate fix requests only FILE_ADD_SUBDIRECTORY on EnterpriseIT and FILE_ADD_FILE on Vault, not FILE_DELETE_CHILD. Verify exact-head CI, SYSTEM adversarial fixtures and full security/Windows Server acceptance. First-install DB bootstrap remains disabled and no installer has been built.

## 0.1.175 Vault smoke diagnostics — 2026-11-24

Windows run 45375347730 on 4103750bb9fc632c028b0cb7b04e2e5a355dbb45 passed Linux Node 26/PostgreSQL 18, compiled the Vault helper, but failed the elevated non-SYSTEM smoke with `path-validation-failed` during a provision attempt. Added safe fixed-component/native error code and attempt diagnostics; run exact-head Windows CI. The independent SYSTEM fixture tests did not run in this CI. No installer; PostgreSQL bootstrap remains disabled.

## 0.1.174 independent Vault fixture tests — 2026-11-24

Windows run 45374694960 on a32d906014495bc5ce88e2953fcd4fa94dfaac4b compiled helper and proceeded past fresh provisioning, but test inspection of keyring.lock failed with admin access denied, consistent with the protected ACL. Added separate elevated non-SYSTEM provision/verify/retry smoke and isolated SYSTEM-only scheduled-task fixture tests to inspect exact ACL/adversarial cases without opening ACLs; SYSTEM is not a runtime fallback. CI fixtures use explicitly protected parent ACL and cleanup. Exact-head Windows CI must validate this design and the candidate privilege scope; independent security review, real service SID, parent trust and rollback/race tests remain required. Linux Node 26/PostgreSQL 18 passed. Database bootstrap disabled, no installer built.

## 0.1.173 Vault privilege candidate — 2026-11-24

Windows CI run 45372992938 on 7c95f3d54ae79c87669ec0e367d1a0ffd646c450 passed the SID/orchestration regression and failed fresh Vault provisioning with error 1307; Linux Node 26/PostgreSQL 18 passed. Added candidate bounded backup/restore privilege scope for native fixed Vault/lock leaf operations in the dedicated provisioning process; restores prior privilege state and fails closed if unavailable. This is source only until exact-head Windows CI. Requires independent security review of privilege scope, trust chain, rollback and adversarial races, plus clean Windows Server acceptance. Database bootstrap remains disabled. No installer built.

## 0.1.172 service SID range check — 2026-11-24

Windows run 45372539798 on cfca62d516be1576748d5b8a5206fe99b8071746 reported an invalid synthetic service SID was accepted by the orchestration regression; Linux Node 26/PostgreSQL 18 passed. Added explicit ASCII/uint32 subauthority checks in orchestrator and Vault helper, and identify the invalid synthetic value in the CI test failure. These changes require exact-head Windows CI. Vault owner error 1307 still requires a bounded, reviewed privilege approach; first-install PostgreSQL bootstrap is disabled; no installer has been built.

## 0.1.171 CI diagnostic — 2026-11-24

Exact-head CI 45372111100 on 157c7ab103212ef65915b9b71dd1c4a2e322821e passed Linux/Node 26/PostgreSQL 18 but failed the Windows five-service orchestration policy test with the new SID/WhatIf cases. Since Actions logs cannot be downloaded, capture synthetic test exceptions as Actions annotations to identify the failure. Re-run exact-head CI; do not claim SID fix validated. Vault owner failure 1307, secure database bootstrap, and installer remain unresolved.

## 0.1.170 Vault SID and owner diagnosis — 2026-11-24

Exact-head run 45371445342 on 9d1aa056e9675bfe8434b3714323b6aec1d05796: Linux Node 26/PostgreSQL 18 job passed. Windows passed orchestration, bootstrap safety, staging, package tests and keyring compilation; fresh Vault provision failed at `open-or-create-vault:win32-1307` (invalid owner). The API service SID is not a valid assignable owner for the elevated process token without appropriate privilege handling. Next: design bounded privilege acquisition/reversion and handle access against exact owner/DACL contract, reject when privilege unavailable, test under elevated Windows token, ensure no mutations to unexpected stores and validate parent trust/rollback; no permissive fallback. Also fixed an independent orchestrator SID regex (was 15 instead of five subauthorities) with non-mutating WhatIf regression cases. Those changes need exact-head Windows CI. PostgreSQL bootstrap is disabled and no installer has been built.

## 0.1.169 Vault failure diagnosis — 2026-11-24

Run 45369417895 on e35067a00a27d6c2d1ac75f8f0c4839174ce1d5f: Linux Node 26/PostgreSQL 18 passed; Windows build and policy tests passed up to fresh Vault provisioning, which still failed with `provisioning-failed`. The added directory creation access did not fix it. Added bounded stage and numeric OS error reporting (never paths/SIDs/ACLs/secrets) to identify the failure on exact-head Windows CI. No installer; database bootstrap disabled pending secure implementation.

## 0.1.168 Vault handle access correction — 2026-11-24

Exact-head run 45368923642 on b7086eb06d03b4a20802754ca721f71324bc186c: Linux job passed; Windows passed orchestration, PostgreSQL safety, staging, offline packaging and keyring build but fresh Vault provisioning failed with generic `provisioning-failed`. Added missing FILE_ADD_SUBDIRECTORY access on ProgramData and created parent handles for provisioning only; this is a candidate fix, unverified until next exact-head CI. Remaining SID/owner/ACL/handle semantics, race and rollback need security review and Windows Server testing. No installer has been built; database bootstrap remains blocked.

## 0.1.167 CI diagnostics — 2026-11-24

Run 45368459750 for commit 6ccfac7d311692636baef64e055720eb07171ab6: Linux Node 26/PostgreSQL 18 job passed; Windows compiled the keyring helper and passed orchestration, bootstrap safety and package tests, but failed Credential Vault provisioning policy. Actions log host was unreachable from the sandbox. CI now emits that synthetic test's exception as an Actions error annotation for retrieval through GitHub API; exact-head CI is required to identify and fix the failure. No installer has been built, and first-install database setup is disabled pending secure implementation.

## 0.1.166 safety correction — 2026-11-24

No installer for user testing has been built. Previous bootstrap prototype was unsafe and is disabled, not complete. Windows CI for previous `372b472c082017e8297fd8b0b8e956c3a63f7456` completed (run 45367864039): Linux/Node 26/PostgreSQL 18 job passed; Windows job failed at orchestration policy; logs could not be retrieved because the Actions log host is inaccessible. Corrected an evident nonempty-directory fixture defect; exact-head result for this revision must be obtained. Local Node 22 typecheck/build/tests passed with `PRISMA_SCHEMA_ENGINE_BINARY=/bin/true` for Prisma client generation only; database/Windows integration tests are not thereby verified. Windows PowerShell/.NET are unavailable locally. Offline package/orchestration fixtures and a new database safety regression were added/updated but need Windows CI. Vault SID shape, NT create disposition and overbroad parent ACL mask corrected without Windows validation; remaining owner/ACL/handle and rollback behavior requires full security review and clean Windows Server tests.

## Current snapshot — Windows deployment continuation on Arena branch (0.1.166, 2026-11-24)

**Snapshot observed:** 2026-11-24 (UTC). This session works on `arena/821b29af-enterprise-it-infrastructure-m` (the current Arena branch). It incorporated `origin/phase3/windows-service-deployment` (PR #9, Draft/open/unmerged, head `ebf9522feb9067d8da80b5dcd2f4538f06f72e7b` at fetch time) and implemented Batch A/B/C foundation work. Evidence is source-level in this Linux sandbox unless stated otherwise.

| Item | Current verified state |
|---|---|
| Active branch | `arena/821b29af-enterprise-it-infrastructure-m` |
| Incorporated PR | PR #9 Draft/open/unmerged; PR #7/#8 also Draft/open/unmerged. No PR merged. |
| Root version | `0.1.166` |
| Credential Vault provisioner | Implemented in `apps/api/windows/keyring-storage-helper/VaultProvisioner.cs` with `--provision-vault`/`--verify-vault`, explicit SCM SID arg, elevation check, handle-relative creation with exact SDDL, parent trust baseline (ProgramData broad-write rejection; EnterpriseIT BA/SYSTEM protected DACL), idempotent correct-store validation, fail-closed unexpected object handling, post-create verification, and limited identity-based rollback. Orchestrator provisions after API SID resolution and runs verify-only before API start; payload preflight no longer requires leaf on fresh install but still rejects reparse/type anomalies. CI test script added. **Not compiled/run on Windows in this sandbox.** |
| PostgreSQL bootstrap/migration | **Disabled, fail-closed.** The 0.1.165 prototype exposed role passwords in `psql -c` arguments and could alter/adopt existing roles/database. Unsafe code removed; direct invocation and orchestration with bootstrap reject before service mutation, while `-WhatIf` remains non-mutating. Secure transport, ownership checks, privileges and migration execution require implementation and acceptance. |
| Offline payload/installer | Staging includes keyring helper; payload package required list includes keyring helper and bootstrap/migration/orchestrator scripts. Manifest/package/install scripts remain foundations; signed manifest/artifacts, deterministic full payload assembly proof, clean Windows VM install/upgrade/repair/rollback/uninstall remain pending. |
| Linux validation | Run in this session after code changes: pending at this snapshot line; see latest commit/test evidence below. |
| Windows validation | Not run in this sandbox. Exact-head Windows CI and clean supported Windows Server VM acceptance required. |
| Safety | No MikroTik/router/firewall/NAT/DST-NAT/port-mapping changes. No secrets in argv/logs/persistent env. No PR merges. |

---

## 2026-11-24 — Comprehensive implementation-agent handoff (0.1.164)

**Start here: `AGENT_HANDOFF.md`.** It is the self-contained takeover brief for the next implementation agent. It records the current branch/HEAD, exact CI evidence, architecture, service topology, owner constraints, security invariants, current code/design boundaries, Credential Vault and PostgreSQL blockers, offline installer/release gaps, acceptance checklist and recommended implementation batches.

This commit is a documentation and handoff change only. It does not implement the missing Vault provisioner, PostgreSQL bootstrap/migration integration, complete offline payload, integrated installer, clean Windows Server acceptance or signed release. PRs #5–#9 remain subject to explicit owner approval; do not merge. No MikroTik/router/firewall/NAT/DST-NAT/port-mapping changes.

## 2026-11-24 — Extend Credential Vault ProgramData path guard (0.1.163)

- Hardened orchestration preflight to include the ProgramData root in the reparse-point and filesystem-object-type checks, not only EnterpriseIT/CredentialVault/keyring.lock.
- Added a Windows junction regression fixture with a copied, otherwise valid ProgramData tree. The test requires rejection before any service provisioning.
- This is defense-in-depth path validation only. It does not replace retained-handle native owner/DACL checks or implement the elevated Credential Vault provisioner. No installer/release or Windows Server acceptance is claimed.
- Root package and lockfile versions synchronized at 0.1.163. PR #7/#8/#9 remain unmerged. No MikroTik, firewall, NAT, DST-NAT or port-mapping changes.

## 2026-11-24 — Define Credential Vault provisioning contract (0.1.162)

- Verified 0.1.161 exact-head CI run 45334177790 completed successfully: Windows API runtime smoke, Platform validation (Node.js 26/PostgreSQL 18), and npm lockfile refresh all succeeded.
- Reconfirmed PR #7/#8/#9 are Draft, open and unmerged.
- Added WINDOWS_CREDENTIAL_VAULT_PROVISIONING_DESIGN.md to make the next security-sensitive implementation bounded and testable. It specifies exact service-SID ownership and protected two-ACE DACL compatibility with the existing helper, elevated installer ordering, create-new/idempotent behavior, parent-chain trust validation, handle-based verification, and safe failure cleanup.
- This is a design artifact only. No production provisioner, parent ACL validation, runtime Node keyring registration, durable credential persistence, installer/release, or Windows Server acceptance is claimed.
- No firewall/router/MikroTik/NAT/DST-NAT/port-mapping changes. No PR merge.

## 2026-11-24 — Add Credential Vault junction rejection regression (0.1.161)

- Rechecked branch HEAD and confirmed the previous exact-head CI run 45197367123 succeeded on 0.1.160. PR #7, #8 and #9 remain Draft/open/unmerged.
- Added a Windows PowerShell policy-test fixture that creates a same-volume directory junction at the CredentialVault path and asserts orchestration preflight rejects it. The fixture is isolated under the test's temporary ProgramDataRoot and the ordinary directory is restored before later assertions.
- No production provisioning behavior was changed. The helper still requires the Vault directory and lock file to have the exact service-SID owner and protected two-entry DACL (service SID + LocalSystem), verified by handle. This commit does not create that store or claim owner/DACL acceptance.
- Exact-head CI is pending. Node Keyring adapter registration, durable credential persistence, parent-directory trust validation, crash-orphan cleanup and clean Windows Server acceptance remain open.
- No PR was merged. No firewall, router, MikroTik, NAT, DST-NAT or port-mapping changes.

## 2026-11-23 — Isolate Windows orchestration fixtures (0.1.160)

- Review immediately after 0.1.159 identified that the new test fixture referenced the runner's real `%ProgramData%`. Changed the orchestration test plan to accept an injectable ProgramDataRoot and moved all keyring fixture creation/removal under its temporary test directory.
- Production calls still default to the OS-known ProgramData root. This is test isolation only; the 0.1.159 presence/reparse guard remains unchanged.
- Version and lockfile metadata advanced to `0.1.160`. Exact-head Windows CI is required.

## 2026-11-23 — Restricted database suites pass; Credential Vault orchestration guard (0.1.159)

- Exact-head CI for parent `cfd360abff5b34e5731e2aef095729e45deb3be5`, run [45171097975](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/45171097975), completed successfully across all three jobs.
- PostgreSQL validation executed the runtime privilege probes and both restricted Prisma integration suites. API database identity tests: 2 passed; inventory integration: 1 passed; Worker queue integration: 8 passed. The workflow log explicitly reported that the runtime privilege matrix and restricted API/Worker suites passed against disposable PostgreSQL; no production role/grant was created.
- Windows smoke passed all five service-host provisioning/lifecycle policy groups. .NET tests passed: API 23, Web 17, Worker 10, Edge 11. Windows Node tests reported 48 passed and 4 skipped; skipped tests remain gated on a provisioned service identity/environment.
- Added an orchestration guard requiring the fixed CredentialVault directory and `keyring.lock` before service provisioning. It rejects reparse-point components and has a missing-lock regression test. This deliberately does not create or repair the store and does not claim exact ACL verification.
- Remaining Credential Vault gap: secure installer provisioning of directory/lock with exact service-SID owner and protected DACL, parent trust validation, crash-orphan cleanup, adversarial Windows Server tests, Node adapter registration and actual credential persistence. Helper remains fail-closed and unregistered.
- Root version and lockfile metadata advanced to `0.1.159`. Exact-head CI for this commit is still required.
- PR #7/#8/#9 remain unmerged. No MikroTik, firewall, NAT, DST-NAT, or port-mapping changes.

## 2026-11-23 — Separate Worker queue fixtures from runtime identity (0.1.158)

- Review of the current branch revealed that the Worker fixture split had not reached the live queue integration test. It still created/deleted branches and DiscoveryRun rows through the restricted Worker client, which would require permissions that the production Worker should not have.
- The Worker test now provisions and cleans test branches/queue rows using WORKER_TEST_FIXTURE_DATABASE_URL, while all queue state transitions and reads continue through the Worker runtime client. The fixture client is disconnected only when independently created.
- Worker grants remain SELECT/UPDATE on discovery_runs only; no INSERT/DELETE or branch-table grant is added. API audit fixture routing is fixed in 0.1.157. Exact-head CI must now confirm API suite success followed by Worker suite success.
- PR #7/#8/#9 remain unmerged. No MikroTik, firewall, NAT, DST-NAT, or port-mapping changes.

## 2026-11-23 — Correct API audit fixture routing (0.1.157)

- Exact-head CI for 0.1.156 passed the SQL privilege probes, the inventory integration suite (including append-only observation trigger assertion through the admin fixture), and 49 API tests, but one API integration assertion still queried audit_events using the restricted runtime db client.
- The two audit lookups and the append-only audit update assertion in database.integration.test.ts now use a dedicated verificationDb created from API_TEST_FIXTURE_DATABASE_URL. API route operations continue to use db under the restricted API login. The fixture client is disconnected only when the test created it.
- No SELECT grant on audit_events is added to the API runtime role. Exact-head CI must now prove the complete API and Worker integration suites.
- PR #7/#8/#9 remain unmerged. No MikroTik, firewall, NAT, DST-NAT, or port-mapping changes.

## 2026-11-23 — Finish API audit append-only integration wiring (0.1.156)

- 0.1.155 converted branch, inventory and user-route audit writes to INSERT-only SQL, but exact-head CI found remaining auth-route Prisma AuditEvent.create() calls. Temporary login returned HTTP 500 because those paths still emitted INSERT ... RETURNING. All five auth-route audit writes now use appendAuditEvent.
- The inventory integration test attempted to update port_observations through the restricted API runtime client and expected the append-only trigger message. PostgreSQL correctly denied the statement earlier due to the absence of UPDATE privilege, so the test was not reaching the trigger. The test now uses API_TEST_FIXTURE_DATABASE_URL only for this negative trigger assertion; normal app operations and observation inserts continue through the restricted API identity.
- No API SELECT grant on audit_events and no API UPDATE grant on port_observations was added. Exact-head CI must validate API and Worker integration tests.
- PR #7/#8/#9 remain unmerged. No MikroTik, firewall, NAT, DST-NAT, or port-mapping changes.

## 2026-11-23 — Keep audit writes compatible with INSERT-only API role (0.1.155)

- 0.1.154 resolved the missing @platform/database dist entrypoint and executed the restricted API suite. The suite then exposed two 500 responses on branch and inventory creation. PostgreSQL logs confirmed permission denied on audit_events while the API role had INSERT but no SELECT.
- Root cause: Prisma auditEvent.create() generates INSERT ... RETURNING, and PostgreSQL requires SELECT privilege on returned columns. Granting broad SELECT would weaken the intended append-only boundary.
- Added apps/api/src/security/audit-events.ts. It writes a parameterized INSERT without RETURNING, supplies UUIDs in the application, casts enum/inet/jsonb parameters explicitly, and asserts exactly one affected row. Updated branch, inventory and user routes to use it. Audit SELECT/update tamper assertions remain on the separate admin fixture connection.
- Exact-head CI for 0.1.155 must confirm API integration, Worker queue integration, and the remaining workflow. No API SELECT grant on audit_events was added. PR #7/#8/#9 remain unmerged; no MikroTik, firewall, NAT, DST-NAT, or port-mapping changes.

## 2026-11-23 — Build database workspace before restricted Prisma suites (0.1.154)

- Exact-head CI for 0.1.153 passed Windows API runtime smoke and SQL privilege probes, but the API integration suite failed during module loading: @platform/database exports dist/index.js, while the workflow had only run Prisma client generation and had not compiled the workspace package.
- The runtime privilege script now runs npm run build --workspace @platform/database before API/Worker integration tests. This emits the package entrypoint and generated Prisma client artifacts expected by workspace exports. No runtime grant is expanded.
- 0.1.154 exact-head CI must establish that both restricted integration suites run. If API passes and Worker fails, inspect its own output before changing grants.
- PR #7/#8/#9 remain unmerged. No MikroTik, firewall, NAT, DST-NAT, or port-mapping changes.

## 2026-11-23 — Restricted API/Worker Prisma integration suites (0.1.153)

- The runtime privilege script now runs the API and Worker integration suites while the disposable least-privilege login roles remain provisioned.
- API route operations execute through the API runtime login. `API_TEST_FIXTURE_DATABASE_URL` is used only for audit-event lookup and append-only trigger verification; it is not passed to the API application instance.
- Worker queue operations (claim, heartbeat, lease expiry, retry, cancellation and recovery) execute through the Worker runtime login. `WORKER_TEST_FIXTURE_DATABASE_URL` is used only to create and remove test branches and queue rows; Worker queue code continues to receive the restricted client.
- Fixture clients fall back to the existing test client when the dedicated fixture URL is absent. Separately created fixture clients are disconnected during teardown.
- Exact-head CI result is pending. If integration exposes a missing grant, inspect generated SQL/source and add only the minimum justified permission. Do not grant API audit SELECT/UPDATE or Worker queue INSERT/DELETE merely for fixture setup.
- This remains disposable CI evidence, not production role provisioning or Windows Server acceptance. PR #7/#8/#9 remain unmerged. No MikroTik, firewall, NAT, DST-NAT, or port-mapping changes.

## 2026-11-23 — Add runtime database privilege boundary CI experiment (0.1.152)

- Added `scripts/database/test-runtime-privilege-matrix.sh`, executed after baseline Prisma migrations in the PostgreSQL 18 validation job.
- The experiment creates temporary login roles, applies candidate table-level grants, then tests positive and negative SQL access using those actual logins. API is denied UPDATE/DELETE on append-only audit/observation tables, recovery_codes, migration metadata, schema DDL and administrative operations. Worker is limited to SELECT/UPDATE on discovery_runs and is denied unrelated tables, INSERT/DELETE, migration metadata and DDL.
- Roles are disposable CI-only identities and are dropped on exit. No production bootstrap, installer wiring, runtime connection configuration, or production grants were implemented.
- This is SQL-level privilege-boundary evidence only; it does not replace API Prisma integration tests under the restricted API identity, Worker queue integration tests under the restricted Worker identity, role-attribute/ownership audits, interrupted migration recovery, secure Windows credential transport, or Windows Server acceptance.
- PR #7/#8/#9 remain Draft/open/unmerged. No MikroTik, firewall, NAT, DST-NAT, or port-mapping changes.

## 2026-11-23 — Prisma migration-owner experiment passes exact-head CI (0.1.151)

- Push run 45148082967 completed successfully at parent commit `bc21475f04338c52c279c0b3366906209c52db43`; Platform validation confirmed `session_user=platform_migrator` and `current_user=platform_schema_owner`.
- The experiment ran Prisma Migrate deploy twice and verified the database, `_prisma_migrations`, relations/indexes/sequences/views, enum types and functions are owned by `platform_schema_owner`.
- PR-event run 45148094311 also completed successfully; PR #9 remains Draft/open/unmerged. PR #7 and #8 remain unmerged.
- This closes only the disposable PostgreSQL 18 / Prisma 7.10.1 ownership-mechanism experiment. It does not authorize production role bootstrap or migration credential transport. Runtime API/Worker privilege tests, interrupted migration retry, Windows Server virtual-account acceptance, Keyring provisioning, offline payload, and integrated installer remain open.
- No MikroTik, firewall, NAT, DST-NAT, or port-mapping changes were made.

## 2026-11-23 — CI PostgreSQL test credential wiring (0.1.150)

- Added the disposable PostgreSQL service password to the migration ownership experiment step environment.
- The 0.1.149 run completed baseline migrations but stopped at the experiment precondition because PGPASSWORD was unset; no Prisma ownership conclusion could be drawn.
- The test is rerun on this commit. No production database roles, grants, migration runner, secret transport, runtime or installer behavior changed. PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Migration identity assertion correction (0.1.149)

- Corrected the test query in `scripts/database/test-prisma-migration-ownership.sh` to use `chr(124)` as the separator between `session_user` and `current_user`.
- The previous query used double quotes around the delimiter, which PostgreSQL interprets as a quoted identifier. The corrected test must be validated by the next exact-head CI run.
- No production database behavior, roles, grants, migration runner, secret transport or installer flow changed. PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Prisma migration owner CI experiment (0.1.148)

- Added `scripts/database/test-prisma-migration-ownership.sh` and wired it into Platform validation.
- The test uses the exact pinned Prisma CLI 7.10.1 against disposable PostgreSQL 18, separates login and schema-owner identities, checks `session_user` versus `current_user`, runs migrations twice, and checks ownership of the database and generated objects.
- This is an experiment only. Exact-head CI result is pending; do not use the role-default mechanism in production until verified and separately reviewed for credential handling and Windows deployment.
- No production database roles/grants, migration runner integration, secret transport, runtime or installer behavior changed. PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Source-derived PostgreSQL privilege matrix (0.1.147)

- Reviewed API authentication, user, branch and inventory routes; API session resolution and one-time administrator bootstrap; Worker queue/recovery SQL; Prisma schema and the current migration set.
- Added `WINDOWS_POSTGRESQL_PRIVILEGE_MATRIX.md` with provisional table-level API grants, the Worker-only `discovery_runs` baseline, append-only table restrictions, sequence/DDL observations, and explicit source-change review requirements.
- Confirmed the current Worker has no discovery handlers and an empty source allow-list; it currently recovers expired leases on `discovery_runs` and does not need broad inventory/user privileges.
- Kept migration role/schema-owner implementation blocked pending a disposable PostgreSQL 18 test with the exact pinned Prisma Migrate engine proving `current_user`, `_prisma_migrations` ownership, DDL ownership, repeated deploy and interruption/retry semantics.
- Documentation/design only. No role/grant bootstrap, migration runner, credential transport, runtime or installer behavior changed. CI for this new commit is not yet known. PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — PostgreSQL first-install and migration contract (0.1.146)

- Reviewed the PostgreSQL cluster initializer, SCM provisioner, five-service orchestrator, API/Worker DPAPI database configuration, Prisma migration package and API readiness behavior.
- Confirmed the initializer creates `platform_admin` using a supplied SecureString and protects its temporary password workspace; the Orchestrator does not invoke the initializer and has no bootstrap-superuser input.
- Confirmed the Orchestrator requires an initialized PostgreSQL 18 cluster, accepts separate API/Worker connection URLs and stores them through service-specific DPAPI hosts, but does not create database roles or execute Prisma migrations.
- Added `WINDOWS_POSTGRESQL_BOOTSTRAP_DESIGN.md` defining identity separation, secret-transport constraints, fail-closed/idempotent lifecycle and acceptance tests.
- Design/documentation only. No role bootstrap, migration runner or installer integration was implemented. First-install PostgreSQL is not complete.
- PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Keyring parent ACL acceptance boundary (0.1.145)

- Exact-head hosted Push validation and PR validation for 603af65f33cbac61083c81e7ae6c7a72c7368e20 both completed successfully; Windows API runtime smoke passed. This does not replace a clean supported Windows Server acceptance run.
- Code review confirmed that the retained ProgramData -> EnterpriseIT -> CredentialVault chain currently verifies directory type, reparse status and volume identity, but does not inspect parent owner/DACL descriptors.
- Do not copy the strict two-ACE CredentialVault leaf policy onto ProgramData. Establish an OS-specific ProgramData trust baseline and an installer-owned EnterpriseIT/Vault/lock provisioning policy first. Existing provisioning scripts do not yet provision the keyring directory hierarchy and lock file.
- Parent ACL verification is deliberately not implemented until those baselines and installer behavior are defined. F-01/F-02 remain open; F-03 crash-orphan enumeration/failure injection, F-04 Windows baseline acceptance and F-05 provisioned-Service-SID/adversarial acceptance remain open.
- Node keyring adapter remains unregistered; credential persistence remains disabled. PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Keyring replace access mask correction (0.1.144)

- CredentialVault directory handle now requests FILE_ADD_FILE | FILE_DELETE_CHILD for relative temp creation and replacement of an existing registry file.
- Native replacement still requires supported Windows Server runtime acceptance; no production credential persistence enabled.
- PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Keyring temp cleanup gap correction (0.1.143)

- Temporary keyring content is now written and flushed through RandomAccess on the original SafeFileHandle.
- Every failure before successful rename retains the exact created file handle and attempts FileDispositionInformation before closing it, including setup and ACL/type failures that previously could leave a temp file.
- After rename, the source handle is closed before destination reopen/read-back to respect the no-share open mode.
- Crash-orphan enumeration/cleanup is still unimplemented. The design/review documents now distinguish in-process failure cleanup from crash recovery; F-03/F-04/F-05 remain open.
- PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Handle-relative keyring rename/delete (0.1.142)

- Keyring helper now performs lock/read/temp creation, atomic registry replacement and orphan cleanup using leaf handles relative to the retained Vault directory handle. Rename uses `NtSetInformationFile(FileRenameInformation)`; deletion uses handle-based `FileDispositionInformation`.
- The Vault handle is granted FILE_ADD_FILE for relative create/rename. The temporary file is opened with DELETE access. Its file ID is captured before rename and compared with the destination reopened relative to the Vault handle after closing the source handle.
- Lock acquisition retries sharing/lock violations (Win32 32/33) and still fails closed if the installer-provisioned lock file is absent.
- Exact-head CI is pending. F-05 provisioned-Service-SID/adversarial Windows acceptance, crash/restart testing, installer integration and production credential persistence remain outstanding. PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Handle missing keyring registry through native open semantics (0.1.141)

- Fixed the mismatch between `WindowsDirectoryHandleChain.OpenVaultFile` and its callers: NTSTATUS-to-Win32 translation raises `Win32Exception`; only native error 2 is now treated as the expected absent registry during read/existence checks.
- Other errors remain fail-closed. This does not complete handle-relative rename/delete: atomic replacement and orphan cleanup remain path-based; file identity is queried but not retained/compared across commit.
- Exact-head CI and dedicated-Service-SID/adversarial Windows acceptance remain required. Keyring client remains unregistered; PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Handle-relative keyring leaf opens (0.1.140)

- Lock-file acquisition, registry reads/existence checks and temporary-file creation now resolve the leaf name relative to the retained CredentialVault directory handle through NtCreateFile.
- The helper rejects directory/reparse-point leaf handles and verifies file-identity metadata on each open.
- Atomic replacement and orphan cleanup remain path-based; this increment does not close the full leaf-operation race or authorize production credential persistence.
- Exact-head Windows CI and dedicated-Service-SID/adversarial Windows acceptance remain required. PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-23 — Correct keyring directory-chain source documentation (0.1.139)

- Corrected the `WindowsDirectoryHandleChain` XML summary to match its current integration in the helper transaction lifecycle.
- Explicitly retained the limitation that leaf-file operations remain path-based and Windows adversarial acceptance is still blocking.
- No runtime behavior changed. No production keyring registration or credential persistence is enabled.

## 2026-11-23 — Restore full keyring hardening review (0.1.138)

- Restored the complete Windows keyring storage hardening review and documented the exact partial status of the parent-directory handle-chain mitigation.
- This documentation-only correction does not alter runtime behavior or close the remaining leaf-operation race conditions.

## 2026-11-23 — Retain trusted keyring directory chain for helper transaction (0.1.137)

- Connected `WindowsDirectoryHandleChain` to `keyring-storage-helper`: BEGIN resolves the OS-known local ProgramData path, opens the volume root and each fixed child relative to the preceding handle, validates directory attributes/reparse state and volume identity, and retains all handles through the helper session.
- The chain's directory handles are opened without FILE_SHARE_DELETE. The helper verifies the Vault owner/DACL through the retained Vault handle. Handles are disposed in Main's finally path on normal END, protocol failure, timeout or process exit.
- This is a partial mitigation for parent path traversal/rename substitution (review F-01/F-02), not closure of the full filesystem threat model. Lock, registry, temp file, replacement and cleanup leaf operations still use path-based APIs; F-03/F-04 remain open.
- Windows acceptance remains blocking: no positive run under installer-provisioned dedicated Service SID, no multi-process/adversarial namespace tests, no crash/power-loss drill. Do not register the keyring storage client, enable credential persistence or enter real equipment credentials.
- Next: move all leaf operations to retained-handle-relative opens/rename/delete, verify stable volume/file IDs and exact ACLs, then add Windows adversarial integration tests. No MikroTik/NAT/port-mapping changes; PR #7/#8/#9 remain unmerged.

## 2026-11-22 — Bind DPAPI adapter to credential envelope context (0.1.136)

- `WindowsDpapiProtector` now implements `LocalDataKeyProtector` from the isolated credential envelope v2 module.
- Protect and Unprotect require `CredentialEnvelopeV2Context`; the adapter compares `context.installationId` with its installer-configured Installation ID before payload validation or process launch.
- Mismatched/missing context fails closed. Tests inject a process launcher and assert that neither operation spawns the helper on mismatch.
- Existing fixed-purpose .NET helper remains machine-scope DPAPI, installation-ID + dedicated-service-SID entropy bound, and service-SID-only. No recovery private key enters the runtime path.
- This does not register the adapter in production composition or enable credential persistence. Database model/migration, keyring-backed provider, recovery utility, v1-to-v2 migration, installer public-key enrollment, dedicated service identity/ACL provisioning and clean-host recovery drill remain open.
- Exact-head CI is required. No PR merged; no MikroTik, NAT, firewall or port-mapping changes.

## 2026-11-22 — Authenticate both credential wrappers and fix RSA KeyObject typing (0.1.135)

- Fixed CI TypeScript failure by handling Node.js public KeyObject instances directly and rejecting private KeyObjects at the public-key provider boundary.
- Extended canonical AES-GCM AAD to bind the recovery key ID and SHA-256 digests of both the DPAPI and RSA-wrapped DEK blobs. Tampering with either wrapper or the recovery key ID is detected by the authenticated ciphertext.
- Added pre-decode base64 length bounds, exact 384-byte RSA-3072 wrapper validation and regression tests for wrapper/key-ID substitution.
- No production DPAPI adapter is connected yet. The test protector remains an identity fixture and is not secure for production. Recovery utility, persistence, v1-to-v2 migration, installer public-key enrollment and production credential use remain disabled.
- Exact-head CI is the acceptance gate. No PR merged; no MikroTik, NAT, firewall or port-mapping changes.

## 2026-11-22 — Add isolated dual-wrapper credential envelope core (0.1.134)

- Added a separate format-v2 crypto module; the existing format-v1 envelope and decrypt path remain unchanged.
- V2 uses a fresh 32-byte DEK per secret, AES-256-GCM, canonical context AAD, a local-protector interface for DPAPI and an independent RSA-3072 OAEP-SHA-256 recovery public-key wrapper.
- Normal service decryption accepts only the local protector and has no recovery private-key parameter. The RSA private key is used only in tests to verify the recovery wrapper.
- Added tests for local round trip, RSA recovery unwrap, fresh DEK/nonce, context/ciphertext tampering, weak RSA keys and local-protector failure.
- The local protector is currently an interface only; the test protector is an identity fixture and is not secure or suitable for production. No DPAPI helper integration, recovery utility, database persistence, v1-to-v2 migration, installer public-key enrollment, PostgreSQL administrator credential persistence or production credential use is implemented.
- Exact-head CI is the next acceptance gate. No PR merged; no MikroTik, NAT, firewall or port-mapping changes.

## 2026-11-22 — Approve public-key credential recovery architecture (v0.1.133)

- User approved removing USB/removable media from the recovery design.
- The recovery design now uses a random per-secret data-encryption key (DEK), AES-256-GCM for secret encryption, local DPAPI protection for normal service use, and an independent RSA-3072 public-key wrapper using OAEP-SHA-256 for disaster recovery. The private key is never deployed to the operational host or included in repository, installer, payload, database or backups.
- Recovery private-key custody is assigned to an organization-managed password manager protected by MFA, restricted access, audited emergency access and an independent encrypted backup. The password manager is a custody location, not a runtime dependency.
- The current CredentialKeyProvider / AES-GCM envelope is not yet integrated with this dual-wrapper recovery format. The existing DPAPI helper remains service-SID-bound and must not be reused for installer administrator credentials.
- This commit changes design documentation only. Recovery provider implementation, PostgreSQL administrator secret bootstrap, role/database provisioning, installer integration, key rotation/revocation tests and clean-host recovery drill remain outstanding. No production credential use is enabled.
- No PR merged; no MikroTik, NAT, firewall or port-mapping changes.

## 2026-11-22 — Isolate PostgreSQL bootstrap CI fixtures (v0.1.132)

- Review of v0.1.131 found its new test used the shared Program Files\EnterpriseIT\1.2.3 path and its cleanup deleted that entire install root. This could interfere with other Windows CI steps.
- v0.1.132 uses a unique numeric version directory for the fixture, fails on collision, and removes only paths it created. The test no longer touches the shared 1.2.3 tree.
- No production behavior is claimed as added. Bootstrap DPAPI recovery, state ledger, API/Worker roles, installer integration and clean Windows Server acceptance remain incomplete.
- No PR merged; no router/NAT/firewall/port mapping changes.

## 2026-11-22 — PostgreSQL bootstrap temporary-secret ACL hardening (v0.1.131)

- The prior bootstrap wrote a plaintext initdb password file and only applied its ACL after file creation. v0.1.131 creates a unique workspace, applies a protected DACL for SYSTEM and Administrators, verifies the resulting explicit identities, and only then creates the password file.
- The PostgreSQL data directory is likewise restricted to SYSTEM and Administrators before initdb writes cluster contents. The PostgreSQL service provisioner subsequently grants the dedicated PostgreSQL service SID its required data access.
- Added Windows CI guards for WhatIf non-mutation, existing-cluster rejection, non-empty directory preservation, and minimum password length.
- Remaining security and integration gates: administrator credential DPAPI protection/recovery, durable bootstrap state machine, API/Worker role and database provisioning, secret-free role provisioning, orchestration/installer integration, and clean Windows Server acceptance. The existing service-bound DPAPI helper is not reused for installer administrator credentials.
- No PR was merged; no router, NAT, firewall or port-mapping changes were made.

## 2026-11-22 — Validate Edge certificate before any service provisioning (v0.1.130)

- v0.1.129 exact-head Push CI run 45016701472 passed all three jobs: Windows API runtime smoke (including all 39 steps and five-service orchestration policy), Node.js 26/PostgreSQL 18 platform validation, and lockfile refresh. PR run 45016706686 passed Windows and platform jobs; lockfile refresh was correctly skipped.
- Review found Edge certificate, machine private-key provider/path, assigned bind IP and occupied HTTPS port were checked only when Edge provisioning ran last, after PostgreSQL/API/Worker/Web provisioning and ACL/config changes.
- v0.1.130 adds a shared read-only Edge preflight and invokes it before the first provisioner. It verifies certificate validity, private key, DNS name, Server Authentication EKU, trusted machine chain, supported RSA CNG/CSP key provider and key-file existence, plus listener address/port and Edge host payload. Edge provisioning repeats the same contract immediately before its own changes.
- Added fact-driven regression coverage for valid and invalid certificate/key/listener facts. This reduces late-failure partial provisioning; it does not implement full rollback of SCM registrations, ACLs, DPAPI configuration or pre-existing state.
- PR #9 remains Draft/open and unmerged; PR #7/#8 remain unmerged. No installer signing, Release, Repair/Uninstall, or clean Windows Server virtual-account acceptance is claimed. No MikroTik, NAT, firewall or port-mapping changes.

## 2026-11-22 — Preflight full service payload before provisioning (v0.1.129)

- Verified v0.1.128 exact-head CI run 45006781170: Platform validation and Windows API runtime smoke passed; lockfile bootstrap was correctly skipped.
- Review found that orchestration provisioned PostgreSQL, API, Worker and Web sequentially before Edge provisioning checked its host payload and certificate. A late missing Edge input could therefore leave earlier services/configuration partially provisioned.
- v0.1.129 adds a read-only preflight before the first provisioner. It checks all five service-host executables, Node.js, API/Worker/Web entry points, PostgreSQL binaries and initialized PostgreSQL cluster files; it also validates PostgreSQL 18, loopback-only listen address/port and explicit remote IPv4/IPv6 rejection.
- Added Windows regression tests for missing Edge host and unsafe PostgreSQL authentication policy. This reduces partial provisioning caused by missing/unsafe payload inputs; it is not a full transactional rollback of SCM registrations, ACLs, or DPAPI configuration.
- Exact-head CI is required. No signed installer, Release, Repair/Uninstall, or clean Windows Server virtual-account acceptance is claimed. PR #7/#8/#9 remain unmerged. No MikroTik, NAT, firewall or port-mapping changes.

## 2026-11-22 — Verify bounded Windows service startup rollback (v0.1.128)

- The v0.1.127 Windows API runtime smoke completed all 39 steps successfully, including Windows service-host builds/lifecycle checks, five-service orchestration policy, runtime staging, offline archive packaging, offline installer archive validation, DPAPI/keyring policy and API/Argon2 tests.
- Linux platform validation stopped at the root lockfile-version assertion: package.json was 0.1.127 while package-lock root metadata still reflected 0.1.126 in that run. The workflow's lockfile bootstrap created a follow-up branch commit (`f98f3663ed37e2a9cdf571d2774053fa154e0ede`) synchronizing the lockfile to 0.1.127. The PR workflow for that bot commit is action_required and needs repository-owner approval; it is not a passing run.
- v0.1.128 extracts startup rollback into a helper and tests reverse-order stopping of only services started by the current invocation, including continuation after a simulated stop failure. It deliberately does not unregister services or delete data/secrets.
- No signed installer, Release, repair/uninstall, transactional rollback of service provisioning, or clean Windows Server virtual-account acceptance is claimed. PR #7/#8/#9 remain unmerged. No MikroTik, NAT, firewall or port-mapping changes.

## 2026-11-22 — Repair duplicated offline installer source tail (v0.1.127)

- Exact-head v0.1.126 Push and PR runs both failed at the Windows offline-installer validation step. The PowerShell parser reported an unexpected closing parenthesis at line 110.
- Inspection of the committed file found the complete installer script followed by a duplicated fragment of the ZIP validator, beginning with an unmatched closing parenthesis and repeating the remainder of the script. Removed only that trailing duplicate; retained the intended validation logic, including reserved DOS device-name checks.
- Updated the test archive fixture package and manifest versions to 0.1.127. Exact-head Push and PR CI must pass before this installer validation gate is accepted.
- No installer signature, Release, clean Windows Server install, repair/uninstall or rollback acceptance is claimed. No MikroTik, NAT, firewall or port-mapping changes. PRs #7/#8/#9 remain unmerged.

## 2026-11-22 — Installer validation workflow syntax correction (v0.1.124)

- The 0.1.123 Push workflow failed before creating jobs. Inspection of the committed YAML showed the new test step contained literal backslash-n sequences rather than actual line breaks.
- Replaced the malformed single line with valid YAML lines. No installer behavior changed in this commit.
- Exact-head Push and PR CI must pass before accepting the installer work. The installer remains unsigned; no Windows Server install acceptance or Release is claimed.

## 2026-11-22 — Installer archive-validation binding and capacity hardening (v0.1.123)

- Corrected the installer script parameter contract: only archive path and trusted digest are required to load archive-validation functions; service credentials and Edge settings are validated at execution time before any host mutation. This prevents dot-sourcing the script in tests from prompting for installation-only inputs.
- The installer now verifies Program Files has enough free capacity for the complete expanded ZIP plus the configured free-space reserve, in addition to the baseline ProgramFiles/ProgramData preflight.
- Explicitly loads the .NET ZIP assembly before archive inspection. Exact-head CI is required; no installer signing, Release or clean Windows Server acceptance is claimed.

## 2026-11-22 — Guarded offline installer entry point (v0.1.122)

- Added `install-offline-payload.ps1`: it requires an out-of-band SHA-256 digest (the archive sidecar alone is not trusted), validates ZIP entry paths, rejects duplicate names and Unix symlink entries, verifies the extracted SHA-256 payload manifest and package version, and runs the read-only Windows host preflight before installation.
- Payload promotion uses a same-volume temporary directory beneath Program Files and refuses an existing version directory. It then calls the existing five-service orchestration with distinct SecureString API/Worker database URLs and explicit Edge bind/hostname/certificate inputs.
- If service orchestration fails after promotion, the versioned payload is deliberately retained for diagnosis; no automatic deletion of registered services or application data is attempted. No firewall, router, NAT or port mapping changes are performed.
- Added Windows CI tests for trusted-digest mismatch and ZIP path traversal. Exact-head CI is required. This is an unsigned PowerShell installer entry point, not a signed MSI/EXE, and no clean Windows Server acceptance or Release is claimed.

## 2026-11-22 — Offline payload source reparse-point preflight (v0.1.121)

- CI logs for v0.1.120 identified a deterministic race: Push validation checked commit 36a8306 while its parallel lockfile-bootstrap job later created 6147656. The validation checkout still contained package-lock root version 0.1.119 while package.json was 0.1.120. The later branch HEAD is 6147656, where both root lockfile versions are synchronized to 0.1.120.
- Windows runtime smoke on 36a8306 passed all recorded steps, including five-service orchestration policy, Node/Web/API/Worker staging, offline manifest and archive packaging, DPAPI/keyring helper checks, and Prisma/API tests. Linux platform validation stopped only at the stale root lockfile assertion before running subsequent checks.
- v0.1.121 advances package.json and package-lock root metadata together in the same commit and hardens the archive packager: source inventory now rejects reparse points before recursive copy, with a Windows directory-junction regression test.
- Exact-head Push/PR CI is pending. No installer, digital signature, Release or clean Windows Server acceptance is claimed. PR #7/#8/#9 remain unmerged; no MikroTik/NAT/port-mapping changes.

## 2026-11-22 — Offline archive fixture inventory assertion (v0.1.120)

- Review of the new archive fixture found that the expected inventory count treated the required Prisma migrations directory as a file. The manifest inventories files only, so the expected count must exclude that directory and include the root package.json.
- Updated the post-extraction test to assert the exact expected number of files. No production packager behavior changed.
- v0.1.120 awaits exact-head Push and PR CI; Installer, signature and Release remain outstanding.

## 2026-11-22 — Offline archive PowerShell condition fix (v0.1.119)

- Exact-head Windows CI on v0.1.118 failed in Test-OfflinePayloadPackage at Get-OfflinePayloadPackagePlan. The failure was a PowerShell parameter binding issue: Test-Path commands in if conditions joined with -or were not parenthesized, leading to duplicate LiteralPath parameter binding.
- Grouped the Test-Path calls explicitly in both preflight and final destination recheck. Removed an unused archive-prefix variable.
- Other Windows API/Worker/Edge Service Host tests and the offline manifest test completed successfully before the failing package test.
- v0.1.119 requires exact-head Push and PR CI. No Installer, digital signature, or Release is claimed. PRs #7/#8/#9 remain unmerged; no NAT/port mapping changes.

## 2026-11-22 — Same-volume Windows service-host promotion (v0.1.118)

- Review of the service-host staging implementation found that executable files were copied into a promotion directory under `[IO.Path]::GetTempPath()` and then moved into Program Files with `[IO.File]::Move`. On Windows systems where TEMP and Program Files are on different volumes, those moves fail because File.Move cannot perform a cross-volume rename.
- Promotion staging now resides under the versioned install root, guaranteeing that promotion and final destinations share a volume. Publish artifacts remain isolated in the system temp directory. The install-volume promotion directory is removed in finally, and rollback still removes only destinations promoted by the current invocation.
- Added a source-policy assertion for same-volume promotion. Exact-head CI is required; no claim of power-loss atomicity or completed installer is made.
- PR #9 remains open/unmerged; PR #7/#8 remain unmerged. No router, NAT or port-mapping changes.

## 2026-11-22 — Offline deployment archive packaging groundwork (v0.1.117)

- v0.1.116 is validated: exact-head Push run 44963745825 and PR run 44963750352 both passed. Push passed all three jobs; PR passed Platform validation and Windows API runtime smoke, with lockfile bootstrap skipped as expected.
- Added a packager that accepts an already staged deployment tree, checks for Node.js, API/Worker/Database, Web standalone, four Windows service hosts and PostgreSQL 18 binaries, then produces a ZIP with a verified SHA-256 inventory manifest and a separate archive checksum.
- The packager is deliberately non-overwriting and uses temporary output plus promotion. It does not sign the payload, create an installer, configure Windows services or perform installation.
- v0.1.117 is pending exact-head CI. PR #9 remains open/unmerged; PR #7/#8 remain unmerged. No MikroTik/NAT/port-mapping changes.

## 2026-11-22 — Relocatable API/Worker workspace promotion correction (v0.1.116)

- Exact-head v0.1.115 Push run 44962893785 and PR run 44962897297 both failed in the Windows API runtime smoke at `Test API and Worker production runtime staging`. All earlier Windows service-host builds, SCM lifecycle tests, service provisioning policy tests, five-service orchestration policy, Node runtime policy, Web staging policy, offline manifest policy, DPAPI/keyring helper builds and installer preflight passed. Linux/PostgreSQL validation also passed.
- The failing Node process reported `ERR_MODULE_NOT_FOUND: @platform/database` after the staged payload was promoted under Program Files. The integration test also hard-coded `EnterpriseIT\0.1.113`, so it was testing a stale versioned destination while root package metadata had advanced to 0.1.115.
- v0.1.116 replaces npm workspace links (which can still reference the temporary build root) with physical copies of API, Worker and Database packages under `node_modules\@platform` before promotion. The test now derives the install root from package.json and checks module resolution from both API and Worker directories.
- Exact-head Push and PR CI must pass before this runtime staging gate is accepted. No installer or GitHub Release exists; PR #9 remains open/unmerged, and PR #7/#8 remain unmerged. No MikroTik, NAT or port-mapping changes are part of this work.

## 2026-11-22 — Repair Windows validation workflow formatting (v0.1.110)

- Identified that v0.1.108 had inserted literal backslash-n characters into the Windows workflow step instead of actual YAML line breaks. This malformed the Node staging test step and prevented the intended Windows job definition from being valid.
- Replaced the escaped sequences with actual newlines, kept the Node runtime policy test as a distinct step, and added the offline payload manifest test as a separate step. Corrected the matching deployment decision record formatting as well.
- The v0.1.109 push still produced a completed run with zero jobs. This correction must trigger a fresh exact-head run; only that run can confirm YAML parsing and runner assignment.
- Root package/lock version advanced to 0.1.110. No installer or GitHub Release is created; PR #9 remains Draft/open/unmerged.

## 2026-11-22 — Add offline payload integrity manifest (v0.1.109)

- Added scripts/windows/new-offline-payload-manifest.ps1 with Create and Verify operations. It records schema/version, relative paths, byte lengths and SHA-256 hashes.
- Verification rejects missing/modified/unexpected files, unsafe paths, duplicate entries, unsupported schema/hash algorithm, version mismatch and filesystem reparse points. Creation refuses to overwrite an existing manifest.
- Added Windows PowerShell tests for valid inventory, tampering, unexpected files, version mismatch and path traversal.
- This is an integrity building block only; it does not assemble application payloads, sign artifacts, create an installer or publish a Release.
- The previous commit accidentally inserted literal backslash-n text into the Workflow step and deployment decision note. This commit repairs both as actual line breaks; exact-head CI must parse and execute the corrected workflow before validation can be claimed.
- Root package/lock version advanced to 0.1.109. PR #9 remains Draft/open/unmerged; no Releases exist.

## 2026-11-22 — Add Node.js runtime staging foundation (v0.1.108)

- Added `scripts/windows/stage-node-runtime.ps1` to stage the complete Node.js 26 runtime directory supplied by the build environment into the immutable versioned Program Files payload at `runtime\`. The script verifies the source and staged executable report the same exact Node version, rejects unsupported major versions and refuses to overwrite an existing destination.
- Added a Windows policy test and CI step using the Node runtime installed by setup-node. The script performs no network download and does not change firewall, NAT, MikroTik or router configuration.
- The script is a payload-staging foundation only. API/Worker production dependency staging, PostgreSQL payload integration, complete offline bundle assembly, installer/repair/uninstall/rollback and clean-VM virtual-account acceptance remain open.
- Exact-head CI is currently not executing: the last three jobs were completed with runner_id=0, empty runner names and zero steps; job log downloads return 404 because no runner logs were produced. This is an infrastructure-level Actions execution blocker, not a passing test result. Exact-head Windows validation is pending.
- Root package/lock version advanced to 0.1.108. No installer or GitHub Release is created. PR #9 remains Draft/open/unmerged; PR #7/#8 remain unmerged.

## 2026-11-22 — Correct Worker SCM smoke PID assertion (v0.1.107)

- Both exact-head CI runs for v0.1.106 passed Linux/PostgreSQL validation, including lint, typecheck, unit tests, production build and PostgreSQL backup/restore. Windows API, Web and Worker host builds and Worker lifecycle/provisioning policy tests also passed.
- The only failing step was the Worker SCM smoke's post-stop process assertion. Log evidence showed the service reached Stopped, then the script queried Win32_Process using `$children[0].ProcessId` from Get-Process. Get-Process returns System.Diagnostics.Process objects whose PID property is Id, not ProcessId. The cast therefore produced PID 0, and the CIM query matched the always-present System Idle process. This was a false-negative in the test, not evidence of an orphaned Worker child.
- Corrected the smoke to capture `.Id` and reject PID zero before checking the process after SCM stop. No production process lifecycle behavior was weakened or bypassed.
- Root package/lock version advanced to 0.1.107. Exact-head Windows CI must pass before marking the Worker SCM integration gate complete. No installer or Release is created.
- PR #9 remains Draft/open/unmerged. PR #7/#8 remain unmerged.

## 2026-11-22 — Fix Worker SCM dependency-injection activation (v0.1.106)

- Inspected the exact failing Windows Actions event log from run 44951401240. The service process did not fail because of Node DLL staging or child discovery: .NET Runtime event 1026 reported `InvalidOperationException: A suitable constructor for type 'EnterpriseIT.WorkerServiceHost.NodeWorkerProcessService' could not be located`.
- Root cause: `NodeWorkerProcessService` was registered through `AddHostedService<T>()`, but its only `ILogger<T>` constructor was `internal`. The default Microsoft DI activator requires a public constructor for this registration.
- Changed the constructor to public. The class remains internal, so this does not expand the application API surface; it makes the registered hosted service constructible by DI.
- The Windows SCM smoke exercises service start, enabled service SID, DPAPI configuration, child startup, loopback readiness, graceful stop and child reaping. Exact-head Push and PR CI must pass before this regression is considered fixed.
- Root package/lock version advanced to 0.1.106. No Release or installer is created: complete offline payload, repair/uninstall, clean-VM virtual-account, TLS certificate/private-key, PostgreSQL lifecycle and backup/restore acceptance gates remain open.
- PR #9 remains Draft/open/unmerged. PR #7/#8 remain unmerged.

## 2026-11-22 — Investigate Worker SCM startup regression (v0.1.105)

- Current branch head before this diagnostic commit: `f167b1a7755678c8bd46abeae705bd9dbb14c1c8` (v0.1.104).
- Linux platform validation passes. Windows runtime job fails only at `Verify Worker service host under Windows SCM`; Worker host build, 10 lifecycle tests, Worker provisioning policy tests, Edge/PostgreSQL policy tests and other Windows checks pass.
- Failure evidence: SCM service transitions to Stopped before the smoke finds a Node child. Prior smoke copied only node.exe; v0.1.105 stages adjacent Node runtime DLLs and emits bounded Application/System event-log diagnostics plus service configuration/SID state on failure.
- Do not claim the Worker SCM smoke is fixed until exact-head CI passes. Worker config uses LocalMachine DPAPI with service-SID-derived entropy and protected ProgramData ACL; clean-VM NT SERVICE virtual-account acceptance remains separate.
- Five service host/provisioning foundations (API, Web, Worker, Edge, PostgreSQL) and the orchestration script exist. Integrated offline app/runtime payload, installer, repair/uninstall, backup/restore/rollback, and clean-VM validation remain open. Installer path remains 3/9 (33%); no installer or Release exists.
- PR #9 remains Draft/open/unmerged. PR #7/#8 remain unmerged.

## 2026-11-21 — Worker SCM smoke uses Node 26 (v0.1.104)

- Replaced the synthetic .NET apphost masquerading as node.exe with the actual Node 26 executable provided by setup-node.
- The smoke entry point uses node:http bound only to 127.0.0.1:13002 and listens for the SHUTDOWN stdin command, then closes the server and exits.
- This tests the real Node child-process stdin/readiness contract used by the production Worker host. The test captures the exact child PID and verifies it exits after SCM stop.

## 2026-11-21 — Worker SCM child executable detection (v0.1.103)

- Worker SCM smoke's ParentProcessId-based filter did not match the hosted runner's service process metadata even though the Worker service reached Running.
- Replaced the filter with an exact executable-path comparison against the test's staged runtime\\node.exe and added non-secret process diagnostics for failures.
- The smoke captures the child's PID and checks that exact PID is gone after SCM stop.

## 2026-11-21 — Worker SCM smoke reap assertion (v0.1.102)

- Worker SCM smoke now captures the actual child process PID by comparing its ParentProcessId to the service host PID.
- After Stop-Service completes, the test queries that exact PID until it exits or the bounded timeout expires; it no longer equates service ProcessId=0 with proof that the child was reaped.

## 2026-11-21 — Worker SCM smoke child detection correction (v0.1.101)

- The hosted Worker service reached Running and passed its readiness gate, but the smoke test's CIM command-line substring filter failed to locate the child process.
- Replaced that brittle filter with a direct ParentProcessId comparison against Win32_Service.ProcessId, which identifies the service-host child regardless of command-line normalization.
- Exact-head CI must re-run the Worker SCM/DPAPI smoke and all downstream Edge/PostgreSQL/orchestration gates.

## 2026-11-21 — Worker SCM/DPAPI integration smoke (v0.1.100)

- Added Windows Worker SCM smoke using the hosted runner's supported LocalService identity with EnterpriseITWorker service SID enabled.
- Added a minimal TCP HTTP stub child that binds only to 127.0.0.1:13002, serves the readiness route and exits on the SHUTDOWN stdin command.
- The smoke provisions the Worker machine-DPAPI config through the one-shot host command, starts the Windows service, verifies HTTP readiness, stops it through SCM and confirms the child process is reaped.
- Hosted LocalService smoke is a lifecycle/DPAPI integration test only; it is not production virtual-account acceptance. Clean supported Windows Server validation under NT SERVICE\\EnterpriseITWorker remains open.

## 2026-11-21 — Self-contained Windows service host staging (v0.1.99)

- Added scripts/windows/stage-windows-service-hosts.ps1 to publish API, Web, Worker and Edge .NET hosts as self-contained win-x64 single-file executables directly under the versioned Program Files payload root expected by their service provisioners.
- The staging script validates the immutable versioned destination, refuses to overwrite any existing host executable, uses a unique temporary publish directory and cleans it in finally.
- This stages only the four .NET host executables. Node 26 runtime, API/Worker production dependencies and dist payloads, Next.js standalone tree and PostgreSQL 18.7-1 binaries remain separate payload staging tasks; no complete offline application bundle is claimed.
- Added Windows CI plan tests for host order, RID, self-contained and single-file policy.

## 2026-11-21 — API SCM smoke and rollback correction (v0.1.98)

- API SCM smoke now provisions the expected machine-DPAPI config envelope after creating the test service and enabling its service SID, grants only SYSTEM/Administrators/service SID access, and then starts the host. The test URL is synthetic and loopback-only.
- This resolves the prior SCM smoke failure where the host correctly refused to start without the newly required protected config file.
- Orchestration rollback now iterates safely when no service was started, avoiding invalid negative array indices.

## 2026-11-21 — Five-service orchestration foundation (v0.1.97)

- Added scripts/windows/orchestrate-windows-services.ps1. It provisions PostgreSQL, API, Worker, Web and Edge in dependency order, configures SCM dependency links, starts services and waits for real readiness endpoints.
- Startup dependencies: PostgreSQL -> API and Worker -> Web -> Edge. API/Worker use separate machine-DPAPI service-specific database configs; Web receives no database credentials.
- Health gates: pg_isready on 127.0.0.1:5432; API 127.0.0.1:13001/health/ready; Worker 127.0.0.1:13002/health/ready; Web 127.0.0.1:13000/health/ready; Edge HTTPS hostname/port /health/ready with normal Windows certificate validation.
- Rollback stops only services started by the failed orchestration invocation. It never deletes the PostgreSQL data directory, removes registered services, modifies Windows Firewall/NAT/MikroTik or creates port mappings.
- PostgreSQL and Edge services are set to Automatic start; all five SCM dependencies enforce boot ordering. Provisioning scripts still do not start services on their own.
- Added plan-only policy tests for exact service order, dependency count and no-firewall/no-router/no-port-mapping invariants.
- Exact-head CI and clean Windows Server acceptance remain required. Installer path is still 3/9 (33%); no installer or Release exists.

## 2026-11-21 — Edge and PostgreSQL CI policy corrections (v0.1.96)

- Added the missing Xunit import required by Edge configuration unit tests.
- Fixed the Windows CI staging-plan test to dot-source the PostgreSQL staging script with its required InstallRoot and CacheDirectory arguments; the test remains plan-only and does not download the large vendor archive.
- Exact-head CI must now verify Edge build/tests/provisioning, PostgreSQL staging/provisioning policy, API/Worker DPAPI tests and existing service gates.

## 2026-11-21 — API DPAPI source formatting correction (v0.1.95)

- Corrected escaped newline text in API service-host source so the SecurityIdentifier import and DPAPI DATABASE_URL injection are valid C# source.
- Corrected the API provisioning policy path assertion to use standard Windows path separators. Exact-head CI will validate build and tests.

## 2026-11-21 — Protect API database configuration (v0.1.94)

- API no longer depends on inherited machine DATABASE_URL. It loads ProgramData\\EnterpriseIT\\Api\\database.config.dpapi after validating the enabled EnterpriseITApi service SID.
- DPAPI LocalMachine encryption binds the file to the API service SID and a per-installation GUID; ProgramData ACL grants SYSTEM/Administrators full access and API service SID read/execute only.
- Provisioning accepts the URL as SecureString, passes it to a one-shot host command via redirected stdin, and validates PostgreSQL endpoint 127.0.0.1:5432. The secret is absent from command-line arguments and logs.
- Added API URL policy tests and provisioning WhatIf/config-path checks. Hosted CI and clean-VM DPAPI/virtual-account acceptance remain required.
- API, Web, Worker, Edge and PostgreSQL service foundations exist (5/5). Integrated service orchestration and clean-VM acceptance remain. Installer path 3/9 (33%), six milestones remaining; no installer or Release.

## 2026-11-21 — Edge and Worker CI compiler/policy corrections (v0.1.93)

- Fixed Edge service SID validation to handle nullable WindowsIdentity.User without warnings-as-errors.
- Fixed the Edge readiness ProblemDetails named argument to compile against the ASP.NET Core API.
- Fixed Worker DPAPI config path policy assertion to match the canonical Windows path separator.
- Exact-head Windows CI is required to confirm Edge build, Edge policy tests, Worker DPAPI tests, PostgreSQL policy tests and existing service gates.

## 2026-11-21 — Worker DPAPI provisioning hardening (v0.1.92)

- Corrected the Worker host to load DATABASE_URL exclusively from the machine-DPAPI protected ProgramData envelope; no inherited-environment fallback remains.
- Worker provisioning now requires a SecureString URL before any service/ACL changes, locks the ProgramData config directory to SYSTEM/Administrators/Worker service SID before writing the encrypted file, and verifies file creation.
- Added the missing xUnit import for Worker database URL validation tests. Exact-head Windows CI is required to validate these corrections; clean-VM DPAPI and virtual-account acceptance remain open.

## 2026-11-21 — Protect Worker database configuration (v0.1.91)

- Worker no longer reads DATABASE_URL from inherited machine/service environment. It loads a binary machine-DPAPI envelope from ProgramData\\EnterpriseIT\\Worker\\database.config.dpapi.
- DPAPI entropy binds ciphertext to the EnterpriseITWorker service SID and a random installation GUID. The config directory ACL grants SYSTEM/Administrators full access and Worker service SID read/execute only.
- Provisioning accepts the URL as SecureString and sends it to the host one-shot command through redirected stdin; the secret is not placed in command-line arguments or logs.
- The host validates its enabled service SID before decrypting; DATABASE_URL is passed only to the Worker child through the explicit environment allow-list. URL validation restricts PostgreSQL to 127.0.0.1:5432.
- Added URL validation tests and extended Worker provisioning WhatIf checks. Hosted CI and clean-VM virtual-account/DPAPI acceptance remain required.
- Five service foundations exist (5/5); integrated orchestration and clean-VM acceptance remain. Installer path 3/9 (33%), six milestones remaining; no installer or Release.

## 2026-11-21 — PostgreSQL Windows package and service foundation (v0.1.90)

- Pinned Windows x64 PostgreSQL to EDB archive postgresql-18.7-1-windows-x64-binaries.zip. Staging retrieves the vendor SHA-256 sidecar, hashes the archive before extraction, verifies postgres.exe reports 18.7 and preserves the complete pgsql runtime tree.
- Added cluster initialization requiring a SecureString superuser password. The password is written only to a temporary file with SYSTEM/Administrators ACL, passed to initdb by file path, and removed in a finally block.
- The initialized cluster uses SCRAM-SHA-256, listen_addresses 127.0.0.1, port 5432 and pg_hba rules that reject non-loopback IPv4/IPv6.
- Added native pg_ctl runservice registration as NT SERVICE\\EnterpriseITPostgreSQL, enabled service SID, bounded recovery, immutable Program Files read/execute ACL and isolated ProgramData data ACL. Provisioning never starts the service and never changes firewall/router configuration.
- Added CI policy checks for the exact EDB package version and PostgreSQL service plan/WhatIf. CI does not download the 389 MB-class database archive or claim clean-VM acceptance.
- Five service foundations now exist (API, Web, Worker, Edge, PostgreSQL). Protected Worker DATABASE_URL configuration, Edge TLS/key ACL acceptance, PostgreSQL native service start/stop/backup/restore on a clean Windows Server VM, and five-service orchestration remain open.
- Installer path remains 3/9 (33%), six milestones remain. No installer or Release exists. PR #9 remains Draft/unmerged; PR #7/#8 remain unmerged.

## 2026-11-21 — Windows Edge service foundation (v0.1.89)

- Added .NET 10 YARP Edge service with fixed API upstream 127.0.0.1:13001 and Web upstream 127.0.0.1:13000; only the configured non-loopback interface address and HTTPS port are exposed.
- TLS requires a current LocalMachine certificate with accessible private key, exact configured DNS name, Server Authentication EKU and trusted chain. The host validates its enabled NT SERVICE\\EnterpriseITEdge SID before startup.
- Incoming forwarded headers are replaced by YARP, the standard Forwarded header is disabled, Host is checked against the configured DNS name, and request/keepalive limits are bounded.
- Added Edge provisioning for NT SERVICE\\EnterpriseITEdge, unrestricted service SID, bounded SCM recovery, immutable Program Files ACL, protected ProgramData config and private-key read ACL. It never starts the service or changes Windows Firewall/router rules.
- Added Edge config tests and Windows CI build/provisioning tests. Actual certificate/key ACL and virtual-account acceptance on a clean Windows Server VM remain open.
- Five-service stage remains active: API, Web, Worker and Edge service slices exist; PostgreSQL packaging/SCM remains. Worker protected DB config and integrated orchestration remain open. Installer path 3/9 (33%), six milestones remaining; no installer or Release.
- PR #9 remains Draft/unmerged; PR #7 and PR #8 remain unmerged.

## 2026-11-21 — Worker service exact-head CI acceptance (v0.1.88)

- Verified commit `0562704e691e4898b319e38d11f413817dd6e884` in both exact-head GitHub Actions runs: Push `44933005081` and PR `44933009547`; both completed successfully.
- Linux platform validation passed dependency audit, lint, typecheck, unit tests, PostgreSQL backup/restore and production build.
- Windows runtime validation passed API and Web host tests, Worker host build, Worker lifecycle tests, Worker provisioning policy tests, Credential Vault helper checks, Windows preflight, Windows API typecheck/tests/build.
- Worker SCM host/provisioning implementation is CI-verified. Actual `NT SERVICE\\EnterpriseITWorker` acceptance on a clean supported Windows Server VM and protected per-service ProgramData database configuration/ACL remain release gates.
- Worker source allow-list remains empty; no discovery jobs are claimed and no device/network requests are emitted. The host fails closed if its required `DATABASE_URL` service configuration is absent.
- API, Web and Worker host/provisioning slices are implemented (3/5); Edge and PostgreSQL Windows packaging remain. Installer milestone 4 remains active; installer path remains 3/9 (33%), with 6 milestones remaining. No installer or Release exists.
- PR #9 remains Draft/open/unmerged; PR #8 and PR #7 remain Draft/open/unmerged.

## 2026-11-21 — Implement Windows Worker service foundation (v0.1.87)

- Added the dedicated .NET 10 `EnterpriseITWorker` host, fixed Node entry point, loopback readiness probe at 127.0.0.1:13002/health/ready, parent/child enabled service-SID checks and bounded process lifecycle.
- Added a host-owned stdin `SHUTDOWN` command to the Worker process. The Worker stops polling, wakes an in-flight poll delay, closes its health listener and disconnects Prisma before process exit.
- Added `NT SERVICE\\EnterpriseITWorker` provisioning policy with unrestricted service SID, bounded SCM recovery, immutable versioned Program Files ACLs, mismatched-existing-service refusal and side-effect-free `-WhatIf`; it never starts the service.
- Added Windows CI build and lifecycle/provisioning policy tests. Exact-head CI must be checked after commit.
- Worker alone receives `DATABASE_URL` through an explicit child-process environment allow-list. Secure per-service ProgramData configuration/ACL provisioning is not yet implemented and remains a release gate; Web does not receive this variable.
- Discovery handlers remain absent and the source allow-list remains empty. The Worker can recover expired leases but cannot claim discovery runs or send requests to equipment.
- API, Web and Worker host/provisioning slices are implemented (3/5); Edge and PostgreSQL Windows packaging remain. Clean-VM virtual-account acceptance remains open.
- Installer path remains 3/9 milestones (33%); milestone 4 is active, with 6 milestones remaining. No installer or Release exists. PR #9 remains Draft/unmerged; PR #8 and PR #7 remain unmerged.

## 2026-11-21 — Record successful Web service CI acceptance (v0.1.86)

- Verified the exact v0.1.85 implementation commit `a387f64b3f7f07ef40cabd1daf840db56fe13c67` in both GitHub Actions runs: Push `44925272158` and PR `44925278555`; both completed successfully.
- The Linux platform validation passed, including dependency audit, lint, typecheck, unit tests, PostgreSQL backup/restore and production build.
- The Windows runtime job passed: existing API host/SCM tests, Web host build, Web host lifecycle tests, Web provisioning policy tests, Credential Vault helper checks, Windows preflight, Windows API typecheck/tests/build.
- This confirms hosted CI compilation and policy tests only. Actual EnterpriseITWeb virtual-account acceptance on a clean Windows Server VM remains a release gate.
- Updated the deployment decision table to reflect the implemented Web host/provisioning slice. Worker SCM host, Edge and PostgreSQL Windows packaging remain unimplemented.

## 2026-11-21 — Harden Web launcher validation (v0.1.85)

- Replaced require-based imports in the standalone Web launcher with dynamic imports to comply with the strict repository lint policy.
- Shutdown now waits for active HTTP connections within a bounded window, forcibly closes remaining connections at the deadline, then closes the Next application.
- The previous v0.1.84 CI run exposed the lint violation; it is corrected here. CI for this commit must be checked independently.

## 2026-11-21 — Implement Windows Web service foundation (v0.1.84)

- Added a dedicated .NET 10 Windows SCM host under apps/web/windows/service-host. It supervises bundled Node 26 and the staged Next.js standalone launcher as EnterpriseITWeb.
- Parent and child tokens are checked for the enabled EnterpriseITWeb service SID. Fixed payload paths, sanitized environment allow-list, loopback readiness at 127.0.0.1:13000/health/ready, bounded startup/shutdown and child-process-tree reaping are implemented.
- Added apps/web/windows/service-entry.cjs: it prepares Next.js, binds only to 127.0.0.1:13000, handles stdin SHUTDOWN, drains connections and closes the Next application.
- Added /health/ready as a local dynamic Next route and removed the broad /health rewrite to API. Existing /api rewrites remain unchanged.
- Added scripts/windows/stage-web-standalone.ps1 and provision-web-service.ps1 with fixed versioned Program Files path validation, virtual account, unrestricted service SID, SCM recovery, immutable payload ACL, mismatched-service refusal and WhatIf. Provisioning never starts Web.
- Added Web host lifecycle and provisioning policy tests to Windows CI. CI result for this commit remains to be verified after push.
- Web receives no DATABASE_URL, database credentials or Credential Vault access. No firewall/NAT/MikroTik changes or port scans are performed.
- Clean-VM virtual-account acceptance, Edge/TLS/WSS, PostgreSQL Windows packaging and installer integration remain open. Installer progress remains 3/9 (33%); milestone 4 active. No installer or Release exists. PR #9 remains Draft/unmerged; PR #8 and #7 remain unmerged.

## 2026-11-21 — Add Worker loopback readiness (v0.1.83)

- Added the Worker health endpoint at the fixed contract address 127.0.0.1:13002/health/ready. It checks PostgreSQL on each request, returns 200 only when the dependency probe succeeds, and returns a sanitized 503 on unavailable/throwing probes.
- Added tests for loopback-only binding, healthy and unhealthy dependency responses, sanitized failures, route/method rejection and invalid port values.
- Fixed shutdown during the poll delay: the loop wakes immediately on SIGINT/SIGTERM, then closes the health listener and disconnects Prisma.
- Worker discovery handlers remain deliberately absent. Its source allow-list remains empty, so it cannot claim work; lease recovery remains the only queue maintenance operation.
- This does not yet make Worker an SCM service. A dedicated .NET Worker host, service-SID validation, bounded child lifecycle, installer provisioning and clean-VM SCM acceptance remain outstanding.
- Installer-path progress remains 3/9 milestones complete (33%); milestone 4 remains active. No installer or Release exists. PR #9 remains Draft/open/unmerged; PR #8 and PR #7 remain untouched and unmerged.

## 2026-11-21 — Define five-service Windows deployment contract (v0.1.82)

- Created `WINDOWS_SERVICE_DEPLOYMENT_DECISIONS.md` as the implementation contract for the five independent SCM services: Edge, Web, API, Worker and PostgreSQL.
- Selected .NET 10 + YARP for the Edge prototype direction and PostgreSQL 18 as the Windows packaging major-version baseline. Exact PostgreSQL patch/build, redistribution review and production Edge acceptance remain open gates.
- Fixed the internal listener contract: Web 127.0.0.1:13000, API 127.0.0.1:13001, Worker health 127.0.0.1:13002 and PostgreSQL 127.0.0.1:5432; only Edge may expose the configured LAN HTTPS listener.
- Defined distinct service identities, payload ACLs, startup order, readiness and clean-VM acceptance requirements. No service is allowed to change Windows Firewall, MikroTik, NAT or device network configuration.
- This is an architecture/implementation-contract commit, not implementation of all five services. API remains the only service with an implemented host/provisioning slice. Worker/Web hosts, Edge, PostgreSQL Windows packaging and end-to-end five-service validation remain open.
- Installer-path progress remains 3/9 milestones complete (33%); milestone 4 remains active. No installer or Release exists. PR #8 remains Draft/open/unmerged.

## 2026-11-21 — Begin installer-owned API service provisioning (v0.1.80)

- Added scripts/windows/provision-api-service.ps1 as the first installer-owned SCM provisioning slice for the completed API Host runtime.
- The plan accepts only a versioned Program Files\\EnterpriseIT\\<major.minor.patch> root and fixed host/Node/API payload paths. It refuses an existing service with an unexpected executable path or logon identity.
- Provisions NT SERVICE\\EnterpriseITApi, enables SERVICE_SID_TYPE_UNRESTRICTED, configures SCM recovery (60s, then 300s, then none; reset after 24h), and applies SYSTEM/Administrators full-control plus service-SID read/execute ACLs to the immutable version directory.
- It deliberately does not start the API: PostgreSQL and protected configuration must be ready first. It does not create/delete application data or change firewall, NAT, RouterOS or device network settings.
- Added Windows PowerShell policy tests and CI validation. Exact-head CI is required; clean Windows Server acceptance under the actual virtual service account remains a production gate.
- Installer-path progress remains 3/9 (33%); this is the first slice of milestone 4, not a completed milestone. PR #8 remains Draft/open/unmerged; no installer or Release exists.

## 2026-11-21 — API Windows Service Host runtime milestone complete (v0.1.79)

- Exact-head v0.1.78 Windows Push CI run 44906623563: completed/success.
- Exact-head v0.1.78 PR CI run 44906628820: completed/success.
- The Windows job passed:
  - .NET 10 API service-host build and all 17 lifecycle tests.
  - Real SCM smoke: temporary service creation, SERVICE_SID_TYPE_UNRESTRICTED, host and child service-SID token validation, loopback readiness, graceful shutdown, SCM Stopped state and child-process reaping.
  - Failed-readiness restart: host returned to Stopped and no child process remained.
  - DPAPI helper build and rejection of non-service identity.
  - Windows keyring helper build and fail-closed unprovisioned behavior.
  - Read-only installer preflight tests.
  - Windows API dependency install, Prisma compile, typecheck, API/Argon2id tests and API build.
- The hosted runner could not provision NT SERVICE virtual accounts (Win32 1057); therefore the SCM smoke uses LocalService as its temporary logon identity while still validating the exact EnterpriseITApi service SID in the parent and child tokens. This is CI-only and not a production fallback. Installer provisioning remains required to assign NT SERVICE\EnterpriseITApi and prove it on a clean supported Windows Server VM.
- The API Windows Service Host runtime milestone is complete. Installer-owned virtual account provisioning, immutable Program Files ACLs, protected ProgramData/configuration, SCM recovery actions, all five services, Credential Vault approval, offline packaging, installer, install/upgrade/repair/uninstall and backup/restore/rollback remain open.
- Installer-path progress: 3/9 milestones complete (33%); 6 remain. This is installer-path progress, not total product completion.
- PR #7 and PR #8 remain Draft/open/unmerged. Do not merge PR #8 without explicit user approval. No installer or Release exists.

## 2026-11-21 — Assert SCM state for failed startup (v0.1.78)

- The v0.1.77 Windows run got past CreateService, service-SID provisioning, parent/child token validation, readiness success, graceful service stop and child reaping.
- The second start deliberately disabled readiness. The host returned to Stopped, but Start-Service did not necessarily throw synchronously because SCM may accept the start request and surface the service's later startup failure asynchronously.
- Changed the harness to assert the final SCM Stopped state and zero remaining API child processes, independent of whether Start-Service itself throws. Extended the bounded observation window to 40 seconds.
- This is a harness assertion correction; service-host runtime is unchanged.

## 2026-11-21 — Literal service-account assertion (v0.1.77)

- The v0.1.76 Windows run reached CreateService SUCCESS and ChangeServiceConfig2 SUCCESS. It failed immediately afterward because the PowerShell -match operator treated the backslash in NT AUTHORITY\LocalService as a regex escape.
- Changed the account assertion to -notlike with a literal wildcard pattern. This is a test-harness-only fix; no host runtime changes.
- Next acceptance point: parent/child SID validation, readiness, graceful stop/reap and failed-readiness cleanup.

## 2026-11-21 — Correct LocalService account separator (v0.1.76)

- The v0.1.75 harness still failed at CreateService. Source inspection showed the PowerShell account literal contained a doubled backslash (NT AUTHORITY\\LocalService) rather than the canonical single separator (NT AUTHORITY\LocalService).
- Corrected the account literal. The test still uses LocalService only for hosted CI and asserts the EnterpriseITApi service SID; production provisioning remains the dedicated virtual account.

## 2026-11-21 — Canonical LocalService account name (v0.1.75)

- The v0.1.74 runner still returned Win32 1057 during CreateService because the short LocalService alias was not accepted as the service start account in this invocation.
- Updated the harness to use the canonical NT AUTHORITY\LocalService name. This is a CI-only low-privilege identity for exercising SCM, the enabled service SID, parent/child token validation and lifecycle; it is not the production service identity.
- Production provisioning remains NT SERVICE\EnterpriseITApi and must be validated on a supported clean Windows Server VM.

## 2026-11-21 — Hosted SCM smoke identity constraint (v0.1.74)

- The v0.1.73 Windows runner returned error 1057 directly from CreateService when assigning NT SERVICE\EnterpriseITApi. Earlier config-based attempts returned the same error. The test runner therefore cannot currently prove virtual-account logon provisioning.
- Updated the CI-only lifecycle harness to run as built-in LocalService (a low-privilege Windows service identity), while still enabling SERVICE_SID_TYPE_UNRESTRICTED, verifying the EnterpriseITApi service SID, and relying on the host's parent/child token validator. The harness resolves the service SID with sc.exe showsid and grants the temporary payload RX to that SID.
- This is not a production fallback. Permanent installer configuration remains NT SERVICE\EnterpriseITApi; acceptance of that logon identity and its inherited child SID must be tested on a clean supported Windows Server image.
- Exact-head Windows SCM CI still must pass service startup, readiness, graceful stop/reap and failed-readiness cleanup before the host runtime milestone can be marked complete.

## 2026-11-21 — Create service with virtual account directly (v0.1.73)

- The v0.1.72 Windows run showed SERVICE_SID_TYPE_UNRESTRICTED succeeded, but sc.exe config still returned 1057 for the virtual account even with explicit quotes. Microsoft documents virtual-account creation by passing obj= "NT SERVICE\ServiceName" to sc.exe create; a password is not supplied for a virtual account.
- Updated the smoke harness to set the virtual account during CreateService and removed the follow-up config/password call. It then enables the service SID type before ACL setup and startup.
- Runtime host unchanged. Exact-head Windows CI must prove this service account can start, the child inherits the SID, and shutdown/failure cleanup work.

## 2026-11-21 — Quote virtual service-account argument (v0.1.72)

- The v0.1.71 Windows runner successfully created the temporary service and configured its service SID (SC ChangeServiceConfig2 SUCCESS), then returned error 1057 on the virtual service-account assignment.
- Updated the sc.exe config arguments to include explicit quotes around NT SERVICE\EnterpriseITApi and the empty password token so the native SCM parser treats the account as one value.
- No runtime host code changed. Continue only after exact-head Windows SCM test proves the virtual account can start and the child inherits the enabled SID.

## 2026-11-21 — Service SID provisioning order (v0.1.71)

- The v0.1.70 Windows runner created the temporary SCM service successfully, but assigning the virtual service account before creating the service SID returned Win32 error 1057 (invalid account/password).
- The harness now configures the service SID type as UNRESTRICTED first, then assigns NT SERVICE\EnterpriseITApi as the service account. This tests the expected SCM/LSA provisioning order.
- The service had not been started in the failed attempt; the harness finally block removed the temporary service and payload. Do not claim the SCM smoke passed until this exact revision completes.

## 2026-11-21 — Virtual service-account SCM argument correction (v0.1.70)

- Follow-up static review found the sc.exe config call still passed obj= plus its account value and password= plus its empty value as single arguments. Split both pairs into separate native arguments, consistent with the documented sc.exe syntax.
- The v0.1.69 Windows workflow was still running when this correction was committed and will be superseded by v0.1.70. No SCM acceptance is claimed yet.
- Host runtime changes from v0.1.68 remain; PR #8 stays Draft/open/unmerged.

## 2026-11-21 — SCM harness argument correction (v0.1.69)

- The first real Windows runner attempt passed service-host compilation and all 17 lifecycle tests, then failed in the PowerShell harness at sc.exe create because sc.exe requires option tokens and values as separate arguments (for example binPath= followed by the executable path, and start= followed by demand).
- Updated the harness to pass those native arguments separately. The service was not created during the failed attempt; the harness cleaned its temporary payload.
- Runtime host code is unchanged from v0.1.68. Do not mark the Windows Service Host milestone complete until exact-head Windows SCM CI verifies the full service start/stop and failed-start cleanup flow.

## 2026-11-21 — API Windows Service Host SCM acceptance (v0.1.68)

- Added a real Windows SCM CI smoke harness using a temporary service named EnterpriseITApi and the matching virtual service account. It configures SERVICE_SID_TYPE_UNRESTRICTED, grants only temporary read/execute access to the isolated test payload, and exercises the published host rather than only unit-test delegates.
- A controlled child executable occupies the fixed runtime/node.exe path and exposes only the loopback readiness endpoint. CI verifies the host accepts the parent and child service SID, reports ready, stops gracefully through the SHUTDOWN pipe, and leaves no child process after SCM reaches Stopped.
- The harness then disables readiness and starts the service again. It verifies startup failure is bounded and no child process is orphaned. Temporary service and files are removed in finally; the script refuses to replace a pre-existing EnterpriseITApi service.
- Fixed a startup-abort defect: StartAsync timeout/cancellation previously called BackgroundService.StopAsync directly, which could cancel the readiness task without invoking the host's child-process cleanup. The new AbortStartupAsync kills/reaps first, then cancels the background task; it preserves startup and cleanup exceptions and does not dispose a child that is still alive.
- Scope is API Service Host runtime only. Installer-owned permanent service provisioning, immutable ACLs, ProgramData configuration, SCM recovery actions, supported Windows Server clean-VM matrix, four other services, Credential Vault storage approval, installer packaging and Release remain incomplete. Do not mark the entire installer path complete.
- PR #8 remains Draft/open/unmerged unless explicitly authorized by the user.

## 2026-11-21 — Testable bounded API child shutdown (v0.1.67)

- Extracted graceful shutdown orchestration from NodeApiProcessService.StopAsync into ApiChildShutdown, called by the production service host and parameterized with narrow process/pipe delegates for deterministic testing.
- The coordinator validates its timeout, handles an already-exited child, requests the fixed SHUTDOWN command, waits within a linked bounded deadline, and falls back to the existing process-tree terminate/reap policy after timeout, I/O failure, unavailable control channel or premature wait completion.
- Host cancellation triggers child cleanup before cancellation is rethrown. If cleanup also fails, both exceptions are preserved in an AggregateException.
- Added focused Windows-targeted tests for graceful success, broken pipe, graceful timeout, cancellation cleanup, invalid control state, premature wait completion and timeout validation.
- This does not provision or register SCM services, prove actual process-tree termination, or establish clean-VM service-SID/ACL acceptance. PR #8 remains Draft/open/unmerged; no installer or Release exists.

## 2026-11-21 — Verify child exit after reap wait (v0.1.66)

- The shared child terminate-and-reap policy now checks the process-exited postcondition after its wait operation completes. A premature wait completion is reported as InvalidOperationException and is not silently accepted as a successful reap.
- Added a regression test for the premature-wait case. Exact-head Push/PR CI required; clean-VM Windows SCM, process-tree and service-SID acceptance remain outstanding. PR #8 remains Draft/open/unmerged; no installer or Release exists.

## 2026-11-21 — Correct wait-cancellation policy test (v0.1.65)

- Corrected the cancellation test fixture: the termination helper owns its bounded reap token, so the test now injects an independent wait cancellation and verifies that exact exception propagates while the helper deadline remains unexpired.
- Runtime code is unchanged. The v0.1.64 test addition is retained with this fixture correction. Exact-head Push/PR CI required; PR #8 remains Draft/open/unmerged.

## 2026-11-21 — Expand API child-process termination policy tests (v0.1.64)

- Added tests for external cancellation propagation, unexpected kill-state failures and rejection of a non-positive reap deadline before process actions.
- Runtime code is unchanged. The tests distinguish caller cancellation from the helper's own reap timeout and ensure only the explicit already-exited race is suppressed.
- Exact-head Push and PR CI required. Real Windows SCM, service SID inheritance, ACL and process-tree acceptance remain outstanding. PR #8 remains Draft/open/unmerged; no installer or Release exists.

## 2026-11-21 — Correct API child reap test fixture (v0.1.63)

- Corrected the successful terminate-and-reap test so the fake process remains active after the kill callback and exits only during the wait callback. The test now asserts one kill, one wait and final exited state.
- Runtime code is unchanged from v0.1.62. This correction prevents a false-positive test that could previously return before exercising the reap wait.
- Exact-head Push and PR CI required. PR #8 remains Draft/open/unmerged; no installer or Release exists.

## 2026-11-21 — Add API child-process lifecycle policy tests (v0.1.62)

- Consolidated startup and stop cleanup onto the same bounded child-process terminate-and-reap policy. The policy handles already-exited processes and the race where the process exits while Kill is being requested; kill and reap failures remain surfaced.
- Added `apps/api/windows/service-host-tests` with controlled-delegate tests for already-exited, normal kill/reap, exit race, kill failure and reap timeout behavior.
- Added the Windows CI test step after the service-host build. These are policy unit tests, not proof of real SCM service operation, service SID inheritance or OS process-tree termination on a clean VM.
- Version and root package-lock versions updated to 0.1.62. PR #8 remains Draft/open/unmerged; no installer or Release exists.

## 2026-11-21 — Bound API child cleanup after startup failure (v0.1.61)

- The service-SID validation and API readiness failure paths no longer call unbounded WaitForExitAsync(CancellationToken.None) after killing the Node child.
- Both paths now use a shared terminate-and-reap helper with a five-second deadline, matching the existing shutdown reap budget. Process-exit races are handled, while kill/reap failures remain critical.
- If startup and cleanup both fail, both exceptions are preserved in an AggregateException. No service registration, SCM recovery action, ACL, firewall or network setting was changed.
- Exact-head Push and PR CI are required. PR #8 remains Draft/open/unmerged; no installer or Release exists.

## 2026-11-21 — Handle failed API shutdown command delivery (v0.1.60)

- NodeApiProcessService.StopAsync now treats a broken/closed stdin pipe or an invalid shutdown channel as a failed graceful-shutdown attempt, logs the condition and continues into the existing process-tree termination/reap path.
- This closes a path where an IOException during SHUTDOWN delivery could skip the explicit child termination attempt. Termination/reap failures remain surfaced as critical errors.
- Version and all root package-lock version entries updated to 0.1.60. Exact-head CI required. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-21 — Bound Windows API service startup and shutdown (v0.1.59)

- `NodeApiProcessService.StartAsync` now limits the synchronous readiness wait to 20 seconds. If readiness is not reached, it cancels the background service and awaits the normal child cleanup path; the 60-second background readiness loop no longer holds the SCM start phase open.
- Shutdown now applies a bounded five-second process-reap wait after termination is requested and a bounded five-second output-drain wait. Failed termination/reap is surfaced with critical logging rather than silently treated as success; stalled output pipes cannot block cleanup indefinitely.
- These bounds need validation under an actually installed Windows service and the target SCM configuration. No service provisioning, recovery policy, ACL changes, or installer was added.
- Exact-head Push and PR CI are required. PR #8 remains Draft/open/unmerged.

## 2026-11-21 — Harden API child cleanup on service stop (v0.1.58)

- Updated `NodeApiProcessService.StopAsync` so cancellation during the graceful `SHUTDOWN` handshake or wait does not skip child cleanup. The host now ensures the Node process tree is terminated and awaited before completing the stop path.
- Output drain tasks are awaited and the process handle is disposed after child exit. No arbitrary process is targeted: only the child process created and retained by this host instance.
- Exact-head Windows and platform CI are required. SCM recovery actions, actual service-state reporting, provisioned service identity and clean-VM integration acceptance remain outstanding. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-21 — Harden Windows service-token size query (v0.1.57)

- The TokenGroups sizing probe now requires the documented `ERROR_INSUFFICIENT_BUFFER` result and a bounded required size before allocating memory. Unexpected success, unexpected Win32 errors, undersized buffers and oversized buffers all fail closed.
- The existing exact enabled/non-deny-only service-SID validation remains unchanged. No privileges, ACLs, service configuration, firewall or network settings are modified.
- Exact-head Push and PR CI must pass. This does not replace real SCM identity inheritance tests on a clean Windows VM. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-21 — Verify API child process service SID (v0.1.56)

- Added a second identity gate immediately after Node process creation. The host opens the child process token using `OpenProcessToken` with `TOKEN_QUERY`, constructs a Windows identity from that token, and validates the exact expected `NT SERVICE\\EnterpriseITApi` SID as token user or enabled, non-deny-only group.
- The parent and child checks must return the same SID. Any child-token open/parse/identity mismatch kills the process tree, waits for exit, disposes the process handle and fails host startup before readiness probing.
- The child token is not logged. Token access is query-only; no privileges, ACLs, service configuration or firewall rules are changed.
- Exact-head Push and PR CI are required. This still does not replace clean-VM SCM tests under the provisioned virtual service account, including negative controls and explicit service-SID configuration.
- PR #8 remains Draft/open/unmerged. No installer/Release, device probing, port scanning, port mapping, NAT/DST-NAT, firewall changes or MikroTik automation.

## 2026-11-21 — Enforce API service SID before child startup (v0.1.55)

- Added `WindowsServiceIdentity.RequireEnabledServiceSid("EnterpriseITApi")` and invoke it before resolving or launching the Node runtime. The validator resolves the exact expected `NT SERVICE\\EnterpriseITApi` SID, inspects the current Windows access token's TokenGroups and accepts only an exact SID match that is enabled and not deny-only. It also accepts the exact SID as token user for a virtual service account.
- TokenGroups parsing validates bounded allocation, returned buffer length, group count and entry-table bounds. Any missing, disabled, deny-only, ambiguous or unresolvable identity aborts startup. The log contains only the expected SID after successful validation; no token contents are logged.
- This does not provision the service account, configure SCM service-SID type, prove the Node child inherits the enabled SID, or establish service ACLs. The installer must provision those settings and clean-VM Windows integration tests must verify the effective parent and child tokens.
- Exact-head CI is pending for this increment. PR #8 remains Draft/open/unmerged. No installer/Release, device probing, port scanning, port mapping, NAT/DST-NAT, firewall changes or MikroTik automation.

## 2026-11-20 — API host readiness gate and graceful-stop correction (v0.1.54)

- The .NET Windows API host now performs a bounded readiness gate against its own fixed loopback endpoint, `http://127.0.0.1:13001/health/ready`. It retries transient connection failures and non-200 responses for at most 60 seconds; the request itself is limited to two seconds and connection establishment to one second. If readiness is not reached, the child process tree is terminated and host startup fails rather than treating an unhealthy API as ready.
- The host's `StartAsync` now waits for the readiness task, so the hosted-service startup does not complete merely because Node was spawned. This does not yet prove SCM health reporting or a production recovery policy.
- Corrected a control-pipe parsing defect in `apps/api/src/server.ts`: it previously searched for the two-character sequence backslash+n while .NET `WriteLineAsync` sends an actual newline. The parser now detects the actual newline and can process the host's `SHUTDOWN` message.
- Exact-head Push and PR CI must pass before this increment is considered validated. Real Windows service identity, service SID/token validation, inherited child SID proof, immutable ACLs, log forwarding and clean-VM service lifecycle tests remain outstanding.
- No device probing, port scanning, port mapping, NAT/DST-NAT, firewall changes or MikroTik automation. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-20 — Service-host scaffold compile/metadata follow-up (v0.1.53)

- Added the missing namespace import to the Windows API service-host entry point and synchronized both root package-lock version fields to 0.1.53.
- Exact-head CI is required before calling the host scaffold validated. It remains an unregistered development artifact, not an installable Windows service.

## 2026-11-20 — Initial Windows API service-host scaffold (v0.1.52)

- Added `apps/api/windows/service-host` as a .NET 10 Windows Service Host for the API process. It resolves only fixed package-relative `runtime/node.exe` and `apps/api/dist/server.js` paths, uses `ProcessStartInfo.ArgumentList` without a shell, and clears inherited environment variables before adding a narrow OS-variable allowlist and non-secret API defaults.
- Added a private stdin `SHUTDOWN` control message to the Node API. The host requests graceful Fastify close and Prisma disconnect, waits up to 20 seconds, then terminates the child process tree if it does not exit.
- Added a Windows CI compile step for the host. This proves only compilation when CI passes; no service has been registered or started under a provisioned virtual service identity.
- Still blocking: service SID provisioning and token validation, positive child-token inheritance test, service recovery policy, health/readiness integration, TLS edge/Web/Worker/PostgreSQL service packaging, Credential Vault handle-relative path/ACL hardening and adversarial tests. The API host must not be installed as a production service yet.
- No firewall changes, port mapping, device probing, SNMP SET or MikroTik automation. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-20 — Installer preflight CI correction (v0.1.51)

- Fixed Windows CI test failure caused by naming a test-fixture parameter `$IsWindows`, which collides with PowerShell's automatic read-only platform variable. The parameter is now `WindowsPlatform`; the fixture output property remains `IsWindows`.
- The v0.1.50 Linux/PostgreSQL validation passed; both Windows-containing workflows failed only at the new preflight unit-test invocation due to this parameter binding collision. v0.1.51 reruns both full workflows on the exact new SHA.
- Installer remains unbuilt. Remaining gates: host support matrix, service host and five SCM services, keyring service identity/ACL hardening, offline payload, installer, upgrade/repair/uninstall/rollback tests.

## 2026-11-20 — Windows installer preflight baseline (v0.1.50)

- Added `scripts/windows/installer-preflight.ps1`, a read-only host check for Windows, x64 architecture, elevated execution and ready local fixed volumes for Program Files and ProgramData. The minimum free-space floor is configurable (default 10 GB) and is only a staging baseline, not a final capacity recommendation.
- Added pure fact-evaluation tests and wired them into the Windows CI job. Negative cases cover non-Windows, non-x64, non-elevated execution, insufficient free space, network volumes and unavailable volumes.
- The script does not create or modify files, ACLs, services, ports, firewall rules, PostgreSQL or application state. It does not claim that the host is supported or that the product is installable.
- Next installer gates: finalize supported Windows OS matrix and service identities/ports; implement and test the five independent Windows services; finish keyring path/ACL hardening and positive service-SID tests; then build and validate offline packaging, upgrade, repair, uninstall-retain-data and rollback.
- Root package and lockfile versions synchronized at 0.1.50. Exact-head Push/PR CI required. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-20 — Branch inventory CSV export (v0.1.49)

- Added an inventory CSV export action respecting the currently selected branch, search term and equipment-type filter. It fetches matching records in 100-row API pages and downloads a UTF-8 BOM CSV.
- Export is limited to 10,000 assets and checks the server-reported total on each page to avoid presenting a partial export as complete if inventory changes during pagination.
- CSV cells are quoted/escaped and values beginning with spreadsheet formula triggers are prefixed with an apostrophe. A unit test covers quoting, multiline fields and formula neutralization.
- Exact-head Push and PR CI required. PR #8 remains Draft/open/unmerged. No installer or Release.

## 2026-11-20 — Switch-port observation history UI (v0.1.48)

- Connected the existing read-only history endpoint to the inventory switch-port dialog. Each port exposes View history; the panel shows timestamp, source, admin/oper state, VLAN, speed, IP and MAC.
- Added 10-row pagination, total count, loading/empty/error handling and request-ID protection against stale responses after switching ports or closing the history panel.
- History reads remain branch-authorized and do not initiate SNMP/ICMP/HTTP polling or modify switch settings. Root package and lockfile metadata synchronized at 0.1.48.
- Exact-head Push and PR CI required. PR #8 remains Draft/open/unmerged. No installer or Release.

## 2026-11-20 — Switch-port observation history API (v0.1.47)

- Added GET /api/v1/inventory/assets/:assetId/switch-ports/:portId/observations. It verifies the port belongs to the requested non-deleted switch, enforces the existing branch-scoped switch.metadata.read permission, and returns read-only observations ordered newest-first with bounded limit/offset pagination.
- The response uses an explicit field selection and does not expose rawMetadata. Integration tests cover two observations, ordering, page totals, VIEWER read access and mismatched asset/port IDs.
- UI history viewer remains the next step. No live SNMP polling or device/network operation is introduced. PR #8 remains Draft/open/unmerged; no installer or Release.
- Root package and lockfile version metadata synchronized at 0.1.47; exact-head Push and PR CI required.

## 2026-11-20 — Switch-port request race protection (v0.1.46)

- Switch-port detail reads now use a monotonically increasing request ID. Responses from an earlier switch selection cannot overwrite the port list, error state or loading state for a newer selection.
- Opening a different switch clears the previous switch's port rows immediately; closing the dialog invalidates pending reads and clears transient selection state.
- Root package and both root lockfile version fields synchronized at 0.1.46. Exact-head Push/PR CI required. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-20 — Inventory pagination and request consistency (v0.1.45)

- Inventory UI now consumes the API pagination contract and exposes Previous/Next controls, current page, visible range and total matching result count.
- Branch/type/search changes reset to offset zero. Summary wording distinguishes all matching assets from switch assets on the current page.
- Added request sequencing to ignore stale asset-list responses when filters, branch or page change while a prior request is still in flight.
- Added PostgreSQL integration coverage confirming offset pagination preserves the total count. Root package and both lockfile version fields synchronized at 0.1.45.
- Exact-head Push/PR validation required. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-20 — Inventory search predicate hardening (v0.1.44)

- Corrected asset search construction: the primary-IP equality predicate is now added only when the query is a syntactically valid IPv4/IPv6 address. This avoids an undefined Prisma predicate being omitted from an OR expression and potentially widening text searches.
- Added disposable PostgreSQL integration assertions for a matching IP and a non-matching text term.
- Root package and both lockfile version fields synchronized at 0.1.44. Exact-head Push/PR validation required. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-20 — Bootstrap advisory-lock regression coverage (v0.1.43)

- Added a PostgreSQL integration test that executes the exact MATERIALIZED-CTE advisory-lock query used by `bootstrap-admin.ts` and asserts that Prisma can deserialize its integer result.
- Updated the local preview acceptance guide to version 0.1.43; the previous guide incorrectly advertised 0.1.38.
- This test validates the SQL/Prisma result contract when the disposable PostgreSQL integration database is enabled. It does not create an administrator or replace the manual Windows bootstrap test.
- Exact-head Push and PR CI are required. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-20 — Administrator bootstrap Prisma raw-query fix (v0.1.42)

- Fixed `bootstrap-admin.ts`: the transaction-scoped PostgreSQL advisory lock is now evaluated in a MATERIALIZED CTE while the outer query returns an integer column, avoiding Prisma's unsupported PostgreSQL `void` deserialization.
- The lock is preserved; bootstrap still serializes concurrent attempts and checks that no user exists before creating the initial administrator.
- Exact-head Linux/PostgreSQL and Windows CI must pass. PR #8 remains Draft/open/unmerged. No installer or Release.

## 2026-11-20 — VLAN clear schema correction (v0.1.41)

- Follow-up to the switch-port clear fix: explicit null is accepted only by the PATCH/update schema. The POST/create schema remains integer-only, matching CreatePortBody and preventing null from being sent to Prisma on create.
- Root package and lockfile synchronized at 0.1.41. Exact-head CI must validate the complete change set.
- PR #8 remains Draft/open/unmerged. No installer or Release.

## 2026-11-20 — Switch-port metadata clear semantics (v0.1.40)

- Fixed the switch-port PATCH route: a supplied empty text value now persists as SQL NULL for name, alias, description and connected-device label; omitted properties remain unchanged.
- Configured access VLAN now accepts explicit JSON null for clearing; tagged VLANs are cleared with an empty array. The web editor sends null when the access VLAN input is blank.
- Added integration assertions for all clear operations and updated the manual preview acceptance guide.
- This is metadata-only. It does not push VLAN configuration to a switch or perform discovery. Exact-head PostgreSQL and Windows CI must pass before considering the fix validated.
- Root package and lockfile synchronized at 0.1.40. PR #8 remains Draft/open/unmerged; no installer or Release.

## 2026-11-20 — Dashboard implementation status accuracy (v0.1.39)

- Dashboard no longer labels the API and PostgreSQL foundations as planned/scaffolded: API auth/user/branch/inventory routes are implemented, and PostgreSQL 18 is available for the documented local preview.
- Worker is accurately labeled as a queue/lease foundation without active job handlers; production TLS edge remains unconfigured.
- Dashboard empty-state notes now direct admins to branch administration and users to the inventory workspace instead of implying those modules do not exist.
- Added regression tests asserting these status labels and the preview version. Exact-head CI is required.
- Root package and lockfile versions synchronized at 0.1.39. PR #8 remains Draft/open/unmerged. No installer or GitHub Release created.

## 2026-11-20 — Local preview acceptance guide (v0.1.38)

- Added `PREVIEW_TEST_GUIDE.md` with reproducible manual checks for first-admin bootstrap, branch creation/edit, branch-scoped OPERATOR access, VIEWER read-only access, asset and switch-port metadata, optimistic concurrency and authorization boundaries.
- Updated README to accurately describe M2 UI/API implementation on Draft PR #8 rather than claiming the inventory UI is still future work.
- Explicitly documents that this is a local workflow test only: no fake monitoring data, no device discovery, no MikroTik/RouterOS changes, no real credentials, and no installer.
- Root package and lockfile versions are synchronized at 0.1.38. Exact-head CI is required before this commit is considered validated.
- PR #8 must remain Draft/open/unmerged. No installer or GitHub Release was created.

## 2026-11-20 — Preview startup reliability follow-up (v0.1.37)

- Updated the Windows preview procedure to use `docker compose up -d --wait db`, preventing migration/bootstrap steps from racing PostgreSQL initialization.
- Clarified the required equality of `POSTGRES_PASSWORD` and the password in `DATABASE_URL`, with a URL-safe password generation example.
- Root package and lockfile version metadata synchronized at 0.1.37. This is a documentation/configuration hardening follow-up; it does not create an installer or Release.
- CI on parent 0.1.36 commit `65e0b7ad7499a2f52963c1840c0c3e28ef885488` passed both Platform validation and Windows API runtime smoke. This new exact commit still requires its own CI result.
- PR #8 remains Draft/open/unmerged.

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


## 2026-11-21 — Harden API provisioning dry-run and ACL failure behavior (v0.1.81)

- `Invoke-ApiServiceProvisioning -WhatIf` now returns a dry-run plan before checking payload files or invoking SCM/SID/ACL tools; this avoids a false failure when a dry run skips service creation but later attempts `sc.exe showsid`.
- Removed `icacls /C` so recursive ACL errors are not intentionally ignored while reporting success.
- Added a test for the explicit dry-run result. Exact-head CI remains required; the provisioning script has not yet passed clean Windows Server acceptance under `NT SERVICE\EnterpriseITApi`.


## 2026-11-22 — Lockfile root-version consistency gate (v0.1.111)
- Corrected the root `packages[""]` version in `package-lock.json` from the stale `0.1.107` value to `0.1.111`, matching the root manifest and lockfile header.
- Added a Windows-independent Node.js validation step in the platform workflow checking npm lockfile v3, root version parity, and package name/version parity for the API, Worker and Database workspaces.
- No third-party dependency versions, workspace versions, dependency ranges, service configuration or network settings were changed.
- Runtime packaging was inspected but not claimed complete: the current Node staging script only stages an immutable Node.js runtime and does not package API/Worker workspace outputs or production dependencies. No installer or GitHub Release is available from this change.


## 2026-11-22 — Web standalone staging hardening (v0.1.112)
- Replaced direct overlay-copy behavior with a no-overwrite staging transaction: preflight, sibling temporary directory, payload completeness checks, and same-volume directory promotion.
- Added `-WhatIf`/ShouldProcess support and a Windows policy test covering dry-run, runtime/static/public content, and rejection of an existing destination.
- CI execution for this exact commit is required before treating the new staging policy as validated. This does not complete API/Worker runtime bundling, installer, rollback, or real Windows Server acceptance.


## 2026-11-22 — API/Worker production runtime staging (v0.1.113)
- Added `stage-node-application-runtime.ps1` to assemble API, Worker and Database compiled outputs, selected workspace production dependencies, and Prisma schema/migrations.
- Requires the versioned Node.js 26 runtime to be staged first, refuses existing destinations, verifies production module resolution before promotion, and removes promoted directories if a later promotion fails.
- Added a Windows integration test that builds/stages the runtime and resolves Database, Fastify and Argon2 modules from the staged production tree. Exact-head CI is required before acceptance.
- Worker discovery handlers remain unregistered; packaging does not enable discovery. Installer, PostgreSQL provisioning, credential provisioning, Edge TLS acceptance, repair/uninstall and clean-VM acceptance remain open.


## 2026-11-22 — Relocatable workspace runtime correction (v0.1.114)
- Exact-head CI for v0.1.113 exposed a post-promotion `ERR_MODULE_NOT_FOUND` for `@platform/database`. The failure occurred after the temporary staging root was removed; npm's workspace link did not remain valid in the installed layout.
- Replaced the three selected workspace links under `node_modules/@platform` with physical copies before final module resolution and promotion. Extended the integration test to resolve dependencies from the staged API and Worker directories after promotion.
- This is a targeted correction to the runtime layout. It remains unaccepted until the exact-head Windows CI passes; no Installer or Release is claimed.


## 2026-11-22 — Transactional service-host payload staging (v0.1.115)
- Hardened `stage-windows-service-hosts.ps1`: all four self-contained .NET service hosts are published and copied into a temporary promotion area before the versioned installation directory is modified.
- The script preflights all final destinations, promotes only after all four outputs exist, and removes outputs promoted by the current invocation if promotion fails. Existing immutable destinations are never overwritten.
- Expanded plan tests. CI acceptance on the exact commit is still required; this does not create an installer or establish clean-VM installation acceptance.

## 2026-11-22 — Offline installer ZIP path hardening (v0.1.125)
- Reviewed the current installer path: archive digest verification, ZIP entry preflight, extraction to a unique staging directory, manifest verification, immutable version-directory promotion, then service orchestration.
- Hardened ZIP entry checks against Windows-specific extraction hazards: NTFS alternate data streams, reserved DOS device names, invalid/control characters, trailing dots/spaces, and DOS reparse-point attributes. Existing traversal, duplicate, absolute-path, symlink and 100 GB expansion checks remain.
- Added regression tests for ADS syntax, CON device names, and trailing-dot/space paths. Exact-head CI must pass before this is accepted.
- Root package.json and package-lock.json versions are synchronized at 0.1.125. This remains an unsigned script-based installer entry point; clean Windows Server install, repair/uninstall/rollback and signed release are still outstanding.

## 2026-11-22 — Installer ZIP validator parser correction (v0.1.126)
- Windows CI for v0.1.125 exposed a PowerShell ParserError in the ZIP path validation block before installer tests could execute.
- Replaced the complete malformed block with syntactically complete checks for Windows-invalid segments, reserved DOS names, duplicate entries, Unix symlinks and DOS reparse-point attributes.
- Version metadata synchronized at 0.1.126. Installer validation remains unaccepted until exact-head Windows CI succeeds.
