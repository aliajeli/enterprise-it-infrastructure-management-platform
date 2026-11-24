# Agent Handoff — Enterprise IT Infrastructure Management Platform

**Purpose:** authoritative, self-contained handoff for an implementation agent taking over this repository. Read this file before changing code. It consolidates the decisions, implementation status, known gaps, acceptance gates and owner constraints accumulated through 2026-11-24.

**Snapshot:** 2026-11-24  
**Active branch (original handoff):** `phase3/windows-service-deployment` (PR #9, Draft/unmerged). **Current Arena working branch:** `arena/821b29af-enterprise-it-infrastructure-m` incorporates that state and continues implementation.  
**HEAD at handoff authoring:** `ebf9522feb9067d8da80b5dcd2f4538f06f72e7b` (PR #9 base incorporated); 0.1.165 continuation on `arena/821b29af-enterprise-it-infrastructure-m` (see git log for exact commit)  
**Root package version:** `0.1.213`
**Project state:** Phase 3 implementation; Windows deployment foundation exists, but Phase 4 / production installer is NOT complete.  
**This handoff is not an authorization to merge PRs or declare a release.**

**0.1.181 testing update:** Disposable hosted Windows real-PostgreSQL initdb pipe and six self-contained executable publish jobs have been added; verify exact-head CI. PostgreSQL initialization/bootstrap/migration remain disabled and no installer exists.

**0.1.180 PostgreSQL safety correction:** The prior cluster initializer wrote a plaintext temporary password file and has been disabled before mutation. Experimental same-user/PID-checked named-pipe transport is synthetic-test-only and not approved, integrated or accepted with real initdb. Database bootstrap and migrations remain disabled. No installer.

**0.1.173 Vault candidate:** Privileges are temporarily enabled only around native opens/creation of the fixed Vault and lock leaf in the dedicated provisioner, with restoration and fail-closed behavior. This security-sensitive source change requires exact-head Windows CI, independent security review, and clean Windows Server adversarial tests. No ACL/owner fallback is allowed.

**0.1.170 Vault finding:** Hosted Windows run 45371445342 failed fresh Vault creation with `open-or-create-vault:win32-1307` (invalid owner). Correct service-SID ownership requires a narrowly scoped reviewed privilege solution; do not loosen ACLs or assign an alternate owner. Orchestrator SID validation fixed; exact-head CI and Windows Server acceptance remain pending.

**0.1.166 safety correction:** PostgreSQL bootstrap and migration are disabled; the earlier prototype put role passwords into `psql -c` arguments and could alter existing roles or silently adopt a database. Never re-enable it without approved secret transport, ownership verification and tests. Orchestration rejects bootstrap before mutation. No test installer has been built. Exact-head Windows CI and clean Windows Server acceptance remain outstanding.

**0.1.165 continuation note:** Credential Vault provisioner mode, orchestrator wiring, bootstrap/migration scripts, and payload/staging updates were added on the Arena branch. Windows compilation/CI/VM acceptance was not executed in this Linux sandbox. Re-validate all claims against exact-head CI and supported Windows Server evidence.

---

## 1. Mandatory owner instructions — do not violate

1. **Never change MikroTik or network edge configuration.** No RouterOS commands, firewall policy changes, address-list edits, automatic unblock, NAT, DST-NAT, port forwarding/mapping or router configuration. Do not attempt to "fix connectivity" by changing the user's network.
2. **Do not merge PR #7, #8 or #9.** They must remain open and Draft until the owner explicitly authorizes a specific merge. Do not merge #5/#6 either without explicit authorization. Do not change PR base branches or close/recreate PRs as a workaround.
3. **Do not claim work is complete without evidence.** Distinguish source implementation, hosted CI, clean Windows Server acceptance, packaging, signed release and production readiness. A successful GitHub Actions run does not prove clean-VM/production acceptance.
4. **After every commit, bump the root version** and synchronize `package.json`, `package-lock.json`, `CHANGELOG.md` and `HANDOVER.md`. Keep workspace package versions consistent where the repository's versioning policy requires it. Use the repo's npm lockfile workflow/validation.
5. Do not weaken security gates to make tests pass. No fail-open fallback to LocalSystem, interactive administrator, broad ACLs, plaintext credentials or permissive network listeners.
6. Do not enable real credential persistence, discovery handlers, SNMP polling or device scanning until their explicit security and acceptance gates are satisfied.
7. Preserve immutable/versioned deployment payloads. Do not overwrite an existing install version or silently adopt unknown services, PostgreSQL clusters, certificates, ACLs or data directories.
8. Never pass secrets in process arguments, logs, transcripts, persistent environment variables, generated manifests or temporary plaintext files. Never commit secrets, private recovery keys or production connection strings.
9. Keep changes incremental, tested and reviewable. Inspect the exact current HEAD before every commit; update refs non-forcibly with the expected parent SHA. Never force-push.
10. The owner intends to have this project completed by an agent, then return for independent review and bug-fixing. Prioritize implementation and testable deliverables over repeated planning-only documents. Do not ask the owner to do local work unless a target Windows Server or physical environment is genuinely required.

---

## 2. Product objective and scope

Build a centralized enterprise IT infrastructure management platform for multiple retail/branch locations, operated from a central management computer. It is intended to manage branch inventory and, in later milestones, discover/monitor infrastructure assets.

Current application foundation:
- Web: Next.js App Router, React, strict TypeScript, Tailwind.
- Runtime: Node.js 26.x; npm 11.x.
- Database: PostgreSQL 18.
- ORM: Prisma 7.10.1 with PostgreSQL driver adapter.
- Windows service hosts/helpers: C# / .NET 10 LTS.
- Root workspaces: `apps/*`, `packages/*`.
- Root commands: `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`, plus database validation/generation/migration commands.

Do not fabricate inventory, topology, health or monitoring measurements. No SNMP discovery/polling is currently authorized/implemented as a production feature. No subnet sweeps, TCP/UDP port scans, NAT discovery, firewall edits or router automation.

### Milestone history (high-level)
- M0: complete.
- M1 identity/authentication/persistence foundation: merged in PR #4.
- M1 user/branch administration and role policy: code is in Draft PRs #5 and #6; verify their current state before assuming merged.
- M2 inventory API/schema and initial branch-aware UI: code is in Draft PRs #7 and #8; they must not be merged without owner approval.
- Windows five-service deployment foundation: ongoing on `phase3/windows-service-deployment`, associated with Draft PR #9; do not merge.
- Device discovery, monitoring transports, hardware validation, complete offline packaging and production installer/release remain unfinished.

Project is **not production-ready**.

---

## 3. Repository and branch state at handoff

Repository: https://github.com/aliajeli/enterprise-it-infrastructure-management-platform  
Original PR9 branch: `phase3/windows-service-deployment` (Draft/unmerged, head `ebf9522feb9067d8da80b5dcd2f4538f06f72e7b` at incorporation).  
Current Arena working branch: `arena/821b29af-enterprise-it-infrastructure-m`  
Current version: `0.1.213`

Latest completed validation before 0.1.213:
- Run [45442729264](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/45442729264) on `7dfcc446f59bbcfd784d61803da896bdaf87bbb6` (0.1.210) failed overall: synthetic same-user stdin interception, real initdb named-pipe PID mismatch and same-user PROCESS_DUP_HANDLE access to real initdb re-exec. No credential was sent in the latter probe.
- Windows installer/archive and preflight fixture tests, Windows runtime, Web, disposable fast and assembled/extracted PostgreSQL migration experiments, Linux validation and self-contained publish passed. These are fixtures, not secure production credential transport or supported Windows Server acceptance.
- 0.1.211 changed Vault handle retention/rollback; 0.1.212 Windows CI passed the isolated fault tests. 0.1.213 adds pre-identity failure checks; exact-head Windows CI and independent security review are required. See HANDOVER.md for current detail.

Current open PR constraints:
- PR #7: Draft/open/unmerged — do not merge.
- PR #8: Draft/open/unmerged — do not merge.
- PR #9: Draft/open/unmerged — do not merge.
- Check current state live before making assumptions; never merge without explicit owner approval.

Latest change 0.1.163:
- Orchestration preflight now checks the OS ProgramData root as well as EnterpriseIT, CredentialVault and keyring.lock for reparse points and expected file-system object type.
- A Windows regression fixture creates a junction at ProgramData and expects preflight rejection.
- This is path-shape defense in depth only. It does not implement native owner/DACL verification or the elevated Credential Vault provisioner.

---

## 4. Five-service Windows deployment target

Five separate SCM services are required. Do not collapse them into one service/process.

| Service | SCM name | Listener / role | Identity / key constraint |
|---|---|---|---|
| PostgreSQL | `EnterpriseITPostgreSQL` | PostgreSQL 18, loopback `127.0.0.1:5432` only | Dedicated low-privilege service identity; do not assume LocalSystem |
| API | `EnterpriseITApi` | Loopback `127.0.0.1:13001` | Dedicated virtual service account and enabled service SID |
| Worker | `EnterpriseITWorker` | Health only on `127.0.0.1:13002`; no LAN listener | Separate dedicated service account/SID; no keyring access |
| Web | `EnterpriseITWeb` | Next.js standalone, loopback `127.0.0.1:13000` | Separate dedicated service account/SID; no DB credentials |
| Edge | `EnterpriseITEdge` | LAN HTTPS/WSS listener (default 443); proxies only to loopback backends | Separate dedicated service account/SID; private-key ACL restricted |

Implementation foundations already present in source:
- PostgreSQL 18.7-1 staging with SHA-256 sidecar verification, SCRAM-oriented initialization/configuration, loopback binding and SCM provisioning foundation.
- API .NET 10 self-contained service host, Node runtime launcher, service SID validation, machine-DPAPI database configuration and ProgramData ACL foundation.
- Worker .NET 10 self-contained host, readiness endpoint, graceful shutdown, service SID checks and machine-DPAPI DB configuration. Worker handlers are disabled and source allow-list is empty.
- Web .NET 10 SCM host, Node 26 runtime and Next standalone staging/provisioning foundation.
- Edge .NET 10/YARP TLS reverse-proxy foundation, certificate/DNS/EKU/chain checks and private-key ACL work.
- PowerShell orchestration script installs/provisions services in dependency order, checks readiness and rolls back only services started by the failed invocation.
- Hosted Windows smoke coverage exists for service-host and policy behavior. Some SCM smoke paths use LocalService and are not equivalent to production virtual-account acceptance.

These are foundations, not proof of a complete production installer.

### Required network binding rules
- PostgreSQL, API, Worker health and Web must bind loopback only.
- Only Edge may listen on the explicitly configured LAN HTTPS interface/port.
- Edge upstreams must be loopback-only.
- Do not automatically add Windows Firewall rules unless an explicitly approved installer design calls for it; current safety boundary forbids router/MikroTik/NAT modifications.
- Fail on port conflicts; do not silently choose another port.

---

## 5. Current implementation status and key gaps

### 5.1 Credential Vault — primary implementation blocker

Current source:
- `apps/api/src/security/credential-vault-crypto.ts`
- `apps/api/src/security/credential-vault-envelope-v2.ts`
- `apps/api/src/security/windows-dpapi-protector.ts`
- `apps/api/windows/keyring-storage-helper/Program.cs`
- `apps/api/windows/keyring-storage-helper/WindowsDirectoryHandleChain.cs`
- `scripts/windows/provision-api-service.ps1`
- `scripts/windows/orchestrate-windows-services.ps1`
- `WINDOWS_CREDENTIAL_VAULT_PROVISIONING_DESIGN.md`
- `WINDOWS_KEYRING_STORAGE_DESIGN.md`
- `WINDOWS_KEYRING_HANDLE_RELATIVE_FILESYSTEM.md`
- `WINDOWS_KEYRING_STORAGE_HARDENING_REVIEW.md`
- `WINDOWS_DPAPI_PROVIDER_DESIGN.md`
- `CREDENTIAL_VAULT_RECOVERY_DESIGN.md`
- `WINDOWS_CREDENTIAL_RECOVERY_DESIGN.md`

Crypto foundations:
- Existing v1 envelope uses AES-256-GCM and a `CredentialKeyProvider` interface; maintain v1 read compatibility.
- v2 envelope uses a fresh random 32-byte DEK per secret; AES-256-GCM with 12-byte nonce and 16-byte tag.
- v2 binds installation/credential/branch/asset/kind/key/recovery metadata via authenticated context/AAD.
- The same DEK has two independent wrappers:
  1. local machine-scope DPAPI wrapper bound to installation ID and dedicated API service identity;
  2. RSA-3072 OAEP-SHA256 recovery wrapper.
- Recovery private key is external to the production host and must be held in an organization-managed password manager or approved HSM/offline custody with MFA, least privilege, audit and independent encrypted backup. Password manager is not a runtime dependency.
- Private recovery key must never be stored in repo, database, installer, offline payload, routine DB backup, logs, env or process arguments.
- Recovery must be tested on a clean replacement host with different machine identity/service SID.
- USB/removable media is explicitly not required.

DPAPI adapter:
- `WindowsDpapiProtector implements LocalDataKeyProtector` and validates installation ID before invoking helper.
- The helper uses machine-scope DPAPI and service identity binding.
- Adapter is not registered in the API composition root; no production persistence path uses it yet.

Keyring helper:
- Runtime helper accepts a bounded stdin/stdout protocol and fails closed if required store is absent/unsafe.
- It derives the actual API service SID from the running service token. Installer provisioning must instead receive/verify the API SID from SCM; an elevated installer token is not the API service token.
- It expects `%ProgramData%\\EnterpriseIT\\CredentialVault` and a pre-existing `keyring.lock`.
- It verifies Vault/lock owner is exactly API service SID; DACL is protected and contains exactly two explicit allow ACEs (API service SID and LocalSystem), each FullControl. It rejects reparse points.
- SDDL target: `O:<API_SERVICE_SID>D:P(A;;FA;;;<API_SERVICE_SID>)(A;;FA;;;SY)`.
- Retained-handle chain opens ProgramData -> EnterpriseIT -> CredentialVault, checks directory type/reparse status/volume identity. Parent owner/DACL trust policy is not fully implemented.
- Lock, registry reads and temp creation are relative to retained Vault directory handle.
- Registry replacement uses `NtSetInformationFile(FileRenameInformation)` relative to retained directory handle; temp cleanup uses handle-based disposition.
- File identity, ACL, type, length and bytes are verified after replacement.
- Abrupt process termination/power loss can leave orphan temp files; there is no robust handle-relative directory enumeration/crash-orphan cleanup yet.
- Native rename/disposition/sharing behavior has not been accepted on all supported Windows Server baselines.
- No positive/adversarial integration suite under the actual installer-provisioned service SID has been completed.

Provisioning gap (must solve, do not bypass):
- `provision-api-service.ps1` provisions the API SCM service and resolves its service SID using SCM; it provisions API-specific ProgramData config but does not create the CredentialVault directory or keyring.lock.
- Orchestrator preflight currently requires Vault and keyring.lock to exist and rejects reparse paths. It does not create them.
- Thus a clean installation cannot satisfy the keyring preflight unless the store is provisioned by a missing step.
- **Do not simply remove the preflight requirement** or weaken runtime ACL verification. Implement an elevated native provisioner and integrate it in the correct order.

Required Provisioner behavior:
1. Verify elevated installer context.
2. Resolve API service SID from SCM (`sc.exe showsid EnterpriseITApi`) and validate canonical `S-1-5-80-...`; never use current elevated process token as the service SID.
3. Establish trusted ProgramData and EnterpriseIT parent chain with OS-appropriate owner/DACL policy, volume continuity and no reparse points.
4. Create Vault directory relative to retained EnterpriseIT parent handle using native handle-relative APIs and explicit security descriptor at creation time.
5. Create `keyring.lock` relative to retained Vault handle with CREATE_NEW and same exact owner/protected DACL.
6. Existing correct store: validate by handle and return idempotent success without replacing identity/content.
7. Existing wrong owner/DACL/type/reparse/volume/collision: fail closed; do not repair, take ownership, delete or replace.
8. Verify post-create owner/DACL/type/volume/reparse by handle.
9. Roll back only objects created by this exact invocation, retaining handles and comparing exact file identity; if safety is uncertain, leave object and fail.
10. No secrets in args/env/logs.
11. Provide `--verify-only` (or equivalent) for validation immediately before API start.
12. Integrate after API service SID provisioning and before API start; do not run during `-WhatIf`.
13. Failure must prevent API startup.

Tests required:
- Fresh create; idempotent rerun; wrong owner; unprotected/inherited/extra ACE/wrong mask; reparse at each component; wrong object type; volume mismatch; collision immutability; concurrent installer race; rollback exact created objects only; cleanup uncertainty; non-elevated rejection; SCM SID mismatch; orchestrator ordering; WhatIf no mutation; API startup blocked on failure.
- Windows hosted CI is useful, but clean supported Windows Server VM acceptance is still required.

### 5.2 Credential envelope v2 test expectations
Existing tests cover local round-trip, independent RSA recovery unwrap, fresh DEK/nonce, context/ciphertext tampering, wrapper/key-id substitution, reject weak RSA-2048 and fail-closed local protector errors. Preserve these tests and add fuzz/bounds/rotation/recovery lifecycle coverage where appropriate. Recovery private key is test-only in automated tests.

### 5.3 PostgreSQL first-install / migration blocker

Relevant files:
- `WINDOWS_POSTGRESQL_BOOTSTRAP_DESIGN.md`
- `WINDOWS_POSTGRESQL_PRIVILEGE_MATRIX.md`
- `scripts/windows/*postgres*`
- `scripts/database/test-prisma-migration-ownership.sh`
- `scripts/database/test-runtime-privilege-matrix.sh`

Current state:
- PostgreSQL 18.7-1 staging and service provisioning foundations exist.
- Cluster initializer mutation is disabled: the previous SecureString flow wrote a prohibited temporary plaintext file. The experimental named-pipe transport is not yet approved or integrated.
- Orchestrator expects a pre-initialized cluster and separate API/Worker DB URLs; it stores them using service-specific DPAPI config.
- No integrated role/database bootstrap or migration runner exists.
- API readiness checks DB connectivity and presence of `public.users`; it does not run migrations or prove all grants.
- One-time `platform_admin`, schema owner, migration login, API runtime login and Worker runtime login must remain separate.
- Disposable PostgreSQL 18 / Prisma 7.10.1 CI experiment passed: migration login vs current schema-owner identity and object ownership; repeated migrate deploy succeeded. This closes only the mechanism experiment, not production secret transport or Windows install.
- Runtime privilege matrix CI creates disposable API/Worker logins and tests allowed/denied SQL. Restricted API/Worker Prisma integration suites have also been wired into CI in recent changes. Re-check latest exact-head logs and source before asserting their current status.
- Candidate API grants are limited to source-used tables; audit_events and port_observations are append-only (INSERT only for API; no UPDATE/DELETE). Worker currently only needs SELECT/UPDATE on discovery_runs. Worker handler allow-list is empty; no discovery handlers enabled.
- Do not grant superuser, schema DDL, broad table CRUD or privileges simply to make tests pass.

Must implement:
1. Approve and implement secure one-time bootstrap credential transport (never argv/env/log/plaintext temp).
2. Idempotent PostgreSQL role/database bootstrap with exact role attributes and grants.
3. Explicit migration runner using the tested Prisma ownership mechanism; verify `session_user` vs `current_user`, migration table and all objects' owner.
4. Migration failure prevents dependent services from starting; preserve cluster and evidence, never destructive auto-reset.
5. Separate API and Worker DPAPI runtime configs; no platform_admin/migration secret in service configs.
6. Test clean install, repeat, interruption/retry, drift, backup/restore, upgrade/rollback and role boundary.
7. Verify PostgreSQL service account/data ACL on supported Windows Server.

### 5.4 Offline payload / installer / release gaps

Existing foundations:
- Offline payload manifest builder/verifier with SHA-256 inventory and rejection of traversal/reparse/missing/modified/unexpected files/version mismatch.
- Node.js 26 runtime staging script stages a complete supplied runtime directory into immutable versioned payload.
- .NET service hosts and provisioning scripts for five services.
- Orchestrator performs preflight, provisioning, readiness and limited rollback.
- Some policy tests are hosted in Windows CI.

Still missing or unaccepted:
- Complete deterministic offline payload assembler including all Node runtime, app artifacts, .NET self-contained hosts, PostgreSQL binaries, native helpers, dependencies, license notices and required configuration templates.
- Signed manifest and signed release artifacts with documented signing key custody.
- Integrated installer with preflight, install, upgrade, repair, rollback and uninstall behavior.
- Database first-install/bootstrap/migrations.
- Credential Vault provisioning.
- Certificate enrollment/import/renewal lifecycle and clean-VM private-key ACL acceptance.
- Clean supported Windows Server VM test for all five actual service identities, service start/stop/reboot dependency order, DPAPI, ports, ACLs and data persistence.
- Dependency/license inventory, backup/restore and upgrade/rollback.
- Release packaging and actual installer acceptance.
- No production-ready claim until all mandatory gates pass.

---

## 6. Windows orchestration contract

Current orchestrator sequence (verify actual source before changing):
1. Validate payload/preflight.
2. Validate DNS/Edge inputs.
3. Provision PostgreSQL service.
4. Provision API service and obtain its service SID.
5. Provision Worker.
6. Provision Web.
7. Provision Edge.
8. Configure SCM dependencies.
9. Start PostgreSQL and wait readiness.
10. Start API and wait readiness.
11. Start Worker, Web and Edge with health checks.

Credential Vault integration must alter the order:
- Initial preflight must validate immutable runtime payload/PostgreSQL artifacts and safe parent conditions, but must not demand a leaf Vault/lock that does not yet exist on a fresh install.
- Provision API SCM identity; obtain and validate API service SID.
- Run elevated Vault provisioner (create or validate Vault + lock).
- Verify-only immediately before API start.
- If Vault provision fails, do not start API.
- Ensure `-WhatIf` has no filesystem/ACL/SCM/database/network/credential mutations and does not invoke the helper.
- Preserve rollback behavior: stop only services started by this invocation. Do not remove existing services/data or blindly delete a Vault after a later-stage failure.

Do not treat path-based PowerShell `Test-Path`, `Get-Item`, `New-Item` or `icacls` as sufficient for the native Vault security boundary. They may be used for non-sensitive staging where appropriate, not as substitutes for handle-based security verification.

---

## 7. Existing design documents — read before implementation

The repository contains substantial source-derived design and review material. At minimum read:
- `WINDOWS_SERVICE_DEPLOYMENT_DECISIONS.md`
- `WINDOWS_CREDENTIAL_VAULT_PROVISIONING_DESIGN.md`
- `WINDOWS_KEYRING_STORAGE_DESIGN.md`
- `WINDOWS_KEYRING_HANDLE_RELATIVE_FILESYSTEM.md`
- `WINDOWS_KEYRING_STORAGE_HARDENING_REVIEW.md`
- `WINDOWS_DPAPI_PROVIDER_DESIGN.md`
- `CREDENTIAL_VAULT_RECOVERY_DESIGN.md`
- `WINDOWS_CREDENTIAL_RECOVERY_DESIGN.md`
- `WINDOWS_POSTGRESQL_BOOTSTRAP_DESIGN.md`
- `WINDOWS_POSTGRESQL_PRIVILEGE_MATRIX.md`
- `WINDOWS_SERVICE_HOST_PROVISIONING_DESIGN.md`
- `PREVIEW_TEST_GUIDE.md`
- `README.md`

If a design doc conflicts with source, inspect the code and tests and update the doc in the same change. Mark proposals as proposals; do not quietly convert them into implementation claims.

---

## 8. Suggested execution plan for the takeover agent

Work in implementation batches. Avoid spending the entire assignment producing more design-only files.

### Batch A — stabilize and implement Vault provisioning
- Inspect current HEAD and all helper/provisioning/orchestration/test files.
- Design and implement a native elevated Provision mode in the .NET helper (or a separate small native helper) with explicit SCM SID input and verify-only mode.
- Establish and validate parent trust policy; avoid assuming the Vault leaf ACL is appropriate for ProgramData/EnterpriseIT parents.
- Implement handle-relative CREATE_NEW directory and lock creation with security descriptor supplied at creation.
- Implement exact owner/DACL validation shared with runtime verifier.
- Add safe identity-based rollback and comprehensive Windows integration tests.
- Integrate into Orchestrator in correct order, preserving WhatIf and fail-closed behavior.
- Run Windows CI; then record target Windows Server acceptance as pending until performed.

### Batch B — PostgreSQL lifecycle
- Implement secure bootstrap secret channel.
- Implement idempotent roles/database/grants with separate identities.
- Implement migration runner using proven Prisma ownership pattern.
- Add integration tests for actual API/Worker runtime logins and migration failure/retry.
- Integrate database readiness/migrations before dependent services start.

### Batch C — complete offline payload and installer
- Deterministically stage all runtime/application/native artifacts.
- Verify hashes, versions, signatures, license notices and immutable layout.
- Implement install/upgrade/repair/rollback/uninstall with safe state detection.
- Add signed manifest and release artifacts; do not embed private signing key in repository.
- Verify clean install and upgrade on clean Windows Server VM.

### Batch D — production acceptance and handoff
- Run full test matrix and exact-head CI.
- Run clean supported Windows Server VM acceptance for all five services, identities, ACLs, DPAPI, Vault, PostgreSQL, TLS/WSS, reboot, upgrade, backup/restore and uninstall.
- Produce release notes, operator runbook, troubleshooting guide and explicit known limitations.
- Only then propose completion. Ask owner before merging PRs or publishing production release.

---

## 9. Acceptance gates checklist

A milestone may be called complete only when applicable gates are evidenced.

- [ ] Exact-head CI passes on final commit (all relevant jobs and logs inspected).
- [ ] Credential Vault elevated provisioner creates fresh store and validates existing correct store.
- [ ] Wrong owner/DACL/reparse/type/volume/collision cases fail closed without mutation.
- [ ] Parent ProgramData/EnterpriseIT trust policy is implemented and validated on target OS.
- [ ] Vault helper positive transaction runs under actual provisioned API service SID.
- [ ] Cross-process lock, race, interruption, orphan cleanup and atomic replace tests pass.
- [ ] Node keyring adapter is registered only after native acceptance; credential persistence remains disabled until then.
- [ ] Recovery private-key custody, restore drill and rotation/revocation procedure are implemented and tested.
- [ ] PostgreSQL cluster initialization, role bootstrap, least-privilege grants and migration runner are integrated.
- [ ] API and Worker integration tests pass using actual restricted runtime identities.
- [ ] Database backup/restore and upgrade/rollback tested.
- [ ] All five services install/start/stop/reboot/upgrade under their actual dedicated identities on clean supported Windows Server.
- [ ] Edge TLS/WSS, certificate private-key ACL, hostname/SNI/chain and renewal tested.
- [ ] Complete offline payload manifest and signatures verified.
- [ ] Integrated installer install/repair/upgrade/rollback/uninstall tested.
- [ ] Dependency and license inventory complete.
- [ ] Signed release artifacts generated and verified.
- [ ] No unauthorized PR merge, router/firewall/NAT/MikroTik change or secret exposure.

---

## 10. Handoff rules and expected agent reporting

For each implementation batch, report:
- Exact commit SHA and version.
- Files changed and behavior implemented.
- Tests actually executed and their exact result.
- CI run URL and exact HEAD SHA.
- Any test skipped and why.
- Remaining blockers, explicitly separating code gaps from external Windows Server acceptance.
- PR status; do not merge without authorization.

Never write "done", "complete", "production-ready", "installer ready" or "release ready" when only a design, policy test, hosted compile or partial smoke test exists.

**Owner's next workflow:** the implementation agent should complete the outstanding work and leave PRs unmerged. The owner will then perform a separate review and bug-fixing pass with ChatGPT.