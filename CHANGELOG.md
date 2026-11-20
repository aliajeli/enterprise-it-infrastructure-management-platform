## 0.1.41 — Correct nullable VLAN update schema

- Corrected the API schema placement for explicit null VLAN clearing: create-port continues to accept only a numeric VLAN, while update-port accepts either a valid VLAN ID or null.
- This keeps the create contract aligned with its TypeScript type and enables the new update-only clear operation.
- Root package and lockfile versions synchronized at 0.1.41. Exact-head CI remains required.

## 0.1.40 — Allow clearing switch-port metadata

- Fixed switch-port PATCH handling so blank text fields clear persisted metadata instead of being treated as omitted updates.
- Allowed an explicit null for configured access VLAN so operators can remove a previously set VLAN value; an empty tagged-VLAN list continues to clear tagged VLANs.
- Updated the inventory editor to send an explicit null when the access VLAN field is cleared.
- Added PostgreSQL integration coverage for clearing alias, description, connected-device label, access VLAN and tagged VLANs.
- Expanded the local preview checklist to exercise clearing port metadata. Root package and lockfile versions synchronized at 0.1.40.

## 0.1.39 — Correct dashboard implementation status (2026-11-20)

- Updated dashboard component states to distinguish implemented API/authentication/inventory capabilities from the worker foundation and unconfigured production TLS edge.
- Replaced stale static notes claiming inventory was not connected or no branches existed with actionable links/context for existing management workflows.
- Added dashboard regression assertions for the implementation status labels and preview version.
- Synchronized root package and lockfile version metadata at 0.1.39. This is a UI/status accuracy improvement; it does not add monitoring, production services or an installer.

## 0.1.38 — Add a repeatable local preview acceptance guide (2026-11-20)

- Added a manual Windows preview checklist for administrator bootstrap, branch administration, branch-scoped OPERATOR/VIEWER access, asset and switch-port metadata, optimistic concurrency and authorization checks.
- Updated README project status to reflect the implemented branch-aware inventory UI and the current Draft PR #8.
- Documented explicit preview boundaries: no fabricated monitoring data, device discovery, port scanning/mapping, MikroTik configuration changes, production credentials or installer claim.
- Synchronized root package and lockfile version metadata at 0.1.38. This is documentation and QA enablement only; it is not an installable release.

## 0.1.37 — Harden local preview startup instructions (2026-11-20)

- Wait for PostgreSQL health before continuing with migrations using Docker Compose `--wait`.
- Clarify that `POSTGRES_PASSWORD` and the password component of `DATABASE_URL` must match; recommend URL-safe generated values.
- Added an environment-template reminder and synchronized root package/lockfile version metadata.

## 0.1.36 — Add local preview database workflow (2026-11-20)

- Added a PostgreSQL 18 Docker Compose service with a persistent named volume, health check and loopback-only published port.
- Added a Windows PowerShell local-preview path for dependency installation, Prisma validation/generation/migrations, administrator bootstrap and separate API/web development processes.
- Added explicit local-only credential, data-reset and network-discovery safety warnings. No installer, sample device data, discovery transport or GitHub Release is included.
- Synchronized root package and npm lockfile version metadata to 0.1.36.

## 0.1.35 — Disambiguate Windows file-information interop calls (2026-11-20)

- Corrected the Windows helper build failure in the new directory-chain primitive: the two GetFileInformationByHandleEx declarations now have distinct managed names while both retain the documented Win32 entry point.
- Exact CI for 0.1.34 exposed compiler error CS0121 at both file-attribute and file-ID lookups; this is a compile correction, not a security acceptance result.
- Root application version advanced to 0.1.35. No installer or Release created.

## 0.1.34 — Add isolated handle-relative Windows directory-chain primitive (2026-11-20)

- Added WindowsDirectoryHandleChain, an isolated .NET helper primitive that opens the standard local ProgramData → EnterpriseIT → CredentialVault chain using retained directory handles and parent-relative NtCreateFile opens.
- The primitive rejects non-directory/reparse components, rejects volume changes, records file identities, and denies delete sharing while the chain is held.
- Added WINDOWS_KEYRING_HANDLE_RELATIVE_FILESYSTEM.md documenting native API contracts and remaining acceptance gates.
- Deliberately not wired into storage operations: existing lock/read/write/replace/cleanup remain path-based. ACL policy, adversarial Windows tests and transaction-relative file operations are still required. The Node client remains unregistered.
- Root application version advanced to 0.1.34. No installer or Release created.

## 0.1.33 — Record Windows keyring storage security review gate (2026-11-20)

- Added `WINDOWS_KEYRING_STORAGE_HARDENING_REVIEW.md` with a source-level review of the current helper and explicit blockers for parent-path trust, rename/delete races, path-based atomic replacement/cleanup, and missing provisioned-Windows integration coverage.
- The review distinguishes implemented controls from unverified assumptions and defines a handle-relative implementation direction plus mandatory Windows acceptance tests.
- No runtime helper behavior or adapter registration changed. Credential storage remains test-only; do not enter real equipment credentials. Worker discovery remains disabled.
- Root application version advanced to `0.1.33`. No installer or Release created.

## 0.1.32 — Record service SID hardening CI verification (2026-11-20)

- Recorded successful exact-code validation for the TokenGroups service SID hardening and Windows service provisioning design milestone.
- CI run [44673439072](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44673439072) passed all three jobs on code SHA `720ca7caa1813a6c81647578601ddf47b70c6261`; the follow-up lockfile-only commit `a1214f0e5b60fce3167a27363404eda3aa393572` keeps root and lock versions aligned at `0.1.31` and Effect at `3.22.1`.
- Full parent-path/reparse-point hardening and positive service-identity integration remain mandatory before registering storage. This release note does not claim production readiness.
- Root application version advanced to `0.1.32`. No installer or Release created.

## 0.1.31 — Harden service SID token validation and define Windows service provisioning (2026-11-20)

- Keyring storage helper now accepts a service SID from the token user or only from an enabled, non-deny-only TokenGroups entry; disabled and deny-only service SID groups are ignored, and ambiguous active service SIDs fail closed.
- Added `WINDOWS_SERVICE_HOST_PROVISIONING_DESIGN.md` covering the dedicated virtual API service identity, .NET SCM host, immutable binary ACLs, separate mutable ProgramData layout, complete path-component/TOCTOU validation, lifecycle, and real Windows acceptance tests.
- The helper still validates only the final vault directory handle today; full ProgramData parent-chain validation, service provisioning, and positive integration under a real service identity remain blockers. No production keyring registration is enabled.
- Root application version advanced to `0.1.31`. No installer or Release created.

## 0.1.30 — Verify patched Effect lockfile resolution in CI (2026-11-20)

- The corrected bootstrap workflow successfully generated and pushed a lockfile resolving `node_modules/effect` to `3.22.1` (lockfile commit `2db7510a5725c2f777ca396d53565692b7fe2dba`).
- Added an explicit CI guard that fails unless the checked-in lockfile resolves exactly `effect@3.22.1`, preventing a future stale-lock regression from reaching dependency audit.
- Full dependency audit, lint, typecheck, tests, PostgreSQL backup/restore and production build still require successful runs on the new exact head.
- Root application version advanced to `0.1.30`. No installer, Release, or production credential-vault registration is created.

## 0.1.29 — Fix lockfile refresh workflow quoting (2026-11-20)

- Corrected the shell quoting in the lockfile refresh commit step; the preceding `npm update effect --package-lock-only` command completed, but the commit step failed during shell parsing before staging or pushing the generated lockfile.
- The workflow now reads the root package version into a shell variable and uses it in the generated lockfile commit message.
- Exact lockfile contents and the security audit remain pending a successful bootstrap push and CI rerun.
- Root application version advanced to `0.1.29`. No installer, Release, or production credential-vault registration is created.

## 0.1.28 — Refresh transitive dependency lockfile for Effect security fix (2026-11-20)

- Pin the transitive `effect` package to exactly `3.22.1`, the first release fixing GHSA-7589-6fvf-x4pw / CVE-2026-121707.
- Corrected the lockfile bootstrap workflow to run `npm update effect --package-lock-only`; a plain `npm install --package-lock-only` only synchronized root metadata and left the vulnerable transitive version locked.
- Workflow-generated lockfile refresh and exact-head dependency audit are still pending; this change is not yet security-verified.
- Root application version advanced to `0.1.28`. No installer, Release, or production credential-vault registration is created.

## 0.1.27 — Remediate transitive Effect ReDoS advisory (2026-11-20)

- Added a root npm override pinning the transitive `effect` package to the patched `^3.22.1` line, addressing GHSA-7589-6fvf-x4pw / CVE-2026-121707 reported through Prisma's `@prisma/config` dependency.
- The override is a compatible patch-line update; no Prisma major-version downgrade or forced dependency-tree rewrite was applied.
- The lockfile bootstrap workflow is expected to regenerate the exact npm lock metadata on push. The dependency audit and full platform validation remain unverified until the follow-up run completes.
- Root application version advanced to `0.1.27`. No installer, Release, or production credential-vault registration is created.

## 0.1.26 — Correct helper shutdown test fixture (2026-11-20)

- Corrected the fake helper constructor used by the new process-exit tests so its configured exit code is initialized in a single constructor.
- No runtime behavior changed from 0.1.25.

## 0.1.25 — Verify Windows keyring helper process termination (2026-11-20)

- The Node transport now closes helper stdin after the acknowledged END frame and waits for the child process to exit with code 0.
- A non-zero exit or shutdown timeout now fails the storage transaction instead of being silently swallowed.
- Added fake-process tests for stdin closure, successful exit and non-zero exit after END acknowledgement.
- The storage adapter remains unregistered; no installer provisioning or production credential persistence is enabled.

## 0.1.24 — Define independent Credential Vault recovery (2026-11-20)

- Added a recovery architecture for offline RSA-OAEP KEK wrapping, separately signed canonical manifests, HSM-backed private-key custody, and clean-host DPAPI re-protection.
- Defined export/restore authorization, version retention, rotation, audit, backup pairing and acceptance tests.
- Design only: no recovery private key, export API, restore utility or production credential persistence was added.

## 0.1.23 — Align DPAPI tests with service-only execution (2026-11-20)

- Replaced the outdated Windows CI expectation of interactive-user DPAPI round-trip with an explicit fail-closed test for tokens without the dedicated service SID.
- Kept positive DPAPI protect/unprotect coverage gated behind an explicitly provisioned service-identity integration environment; it remains skipped until that environment exists.
- No production wiring or credential persistence enabled.

## 0.1.22 — Bind DPAPI helper to the dedicated service SID (2026-11-20)

- DPAPI entropy now uses the unique dedicated service SID from the process token, considering the token user and groups and rejecting missing or ambiguous service identities.
- The helper rejects trailing bytes after its single request frame.
- Windows CI now runs the built DPAPI helper as the unprovisioned hosted-runner identity and verifies the exact generic failure frame, non-zero exit and empty stderr.
- No DPAPI key is provisioned and no production storage is enabled.

## 0.1.21 — Verify fail-closed helper startup (2026-11-19)

- Hardened service SID resolution to recognize a dedicated service SID represented as either the process user SID or an enabled token group, deduplicating the same SID.
- Added a Windows CI process-level smoke test that sends BEGIN to the actual built helper on an unprovisioned runner and requires a generic binary ERROR response, non-zero exit and empty stderr.
- The test does not provision storage or enable credential persistence.

## 0.1.20 — Resolve nullable analysis in Windows helper (2026-11-19)

- Made the transaction-held lock dereference explicit after the fail-closed transaction guard.
- Explicitly reject a missing owner SID before exact owner comparison.
- No runtime permissions or storage semantics changed.

## 0.1.19 — Fix Windows keyring helper P/Invoke declaration (2026-11-19)

- Corrected the CreateFileW P/Invoke EntryPoint placement found by the first Windows helper compile.
- No storage semantics or registration behavior changed; helper remains unregistered and production-gated.

## 0.1.18 — Windows keyring storage helper implementation groundwork (2026-11-19)

- Added a separate .NET 10 Windows keyring storage helper implementing the frozen v1 binary session protocol and fixed-path read/atomic-write operations.
- Added fail-closed service-SID, protected DACL, exact ACE, and reparse-point checks through opened handles.
- Added bounded JSON payload validation, exclusive cross-process lock-file ownership, durable same-directory replacement, and post-write verification.
- Extended Windows CI to compile the new helper and added protocol malformed-frame regression tests.
- This does not provision the service identity/storage ACLs, register the Node adapter, enable credential persistence, or qualify production use.

## Unreleased — Windows helper path validation portability (2026-11-19)

- Corrected helper executable path validation to use Windows path semantics explicitly, independent of the host running the unit tests.
- Added regression coverage proving that an absolute Windows drive path is accepted on Linux-hosted tests while relative Windows paths are rejected.
- Root package and lockfile metadata advanced to `0.1.17`; this fixes the test portability defect only. The helper remains unregistered and no installer or Release is created.

## Unreleased — keyring helper-session lifecycle correction (2026-11-19)

- Corrected transaction completion so END is sent after a successful callback, while callback/helper failures abort the session. Helper startup failures now release the in-process transaction queue.
- Added an assertion that the helper receives END on successful completion.
- Root package version metadata advanced to `0.1.16`; no installer or Release is created.

## Unreleased — Windows keyring helper-session transport (2026-11-19)

- Added an unregistered Windows-only Node transport client for the v1 helper protocol. It retains one child process across a complete storage transaction, serializes local transactions, rejects nested/out-of-transaction operations and fails closed on protocol errors.
- Added transport tests using a fake helper process. The .NET helper does not yet implement these storage operations; ACL verification, cross-process locking, durable atomic replacement, installer provisioning and production registration remain blocked.
- Root package version metadata advanced to `0.1.15`; no installer or Release is created.

## Unreleased — Windows keyring protocol contract (2026-11-19)

- Added a bounded version-1 binary frame codec for the future Windows keyring helper session, with explicit transaction/read/atomic-write/end request and response opcodes.
- Added unit coverage for UTF-8 payloads, exact frame lengths, truncated/trailing data, unknown versions/opcodes and payload bounds. The existing Linux and Windows CI workflows execute these API tests.
- Froze the wire contract in `WINDOWS_KEYRING_STORAGE_DESIGN.md`. This is protocol groundwork only: no filesystem helper operation, ACL validation, process lock, atomic write, storage adapter or production registration exists yet.
- Root package version metadata advanced to `0.1.14`; no installer or Release is created.

## Unreleased — DPAPI primitive validation milestone (2026-11-19)

- Exact-head Push and PR validation both passed for `5067518791b0899f410fee8b76495028e11bd590`: Linux/Node.js 26/PostgreSQL 18 and Windows API runtime smoke, including .NET 10 DPAPI helper compilation and native Protect/Unprotect integration.
- DPAPI protocol accepts a 32-byte KEK for Protect, bounded variable-length protected blobs for Unprotect, and enforces a 32-byte decrypted KEK. Installation ID + current Windows SID are bound as optional entropy.
- Root package version advanced to `0.1.10`; no installer or Release is created.

## Unreleased — DPAPI payload validation test correction (2026-11-19)

- Updated the invalid-length test to assert the revised generic DPAPI payload-length error after allowing variable-size protected blobs.
- Bumped root package version to `0.1.9` and synchronized lockfile metadata.

## Unreleased — DPAPI Unprotect payload bounds (2026-11-19)

- Corrected request validation so Protect accepts exactly a 32-byte KEK, while Unprotect accepts a bounded variable-length DPAPI blob and still requires the helper's decrypted output to be exactly 32 bytes.
- Windows integration exposed the prior assumption that both input operations carry a 32-byte payload; this correction is pending fresh exact-head CI.
- Bumped root package version to `0.1.8` and synchronized lockfile metadata.

## Unreleased — DPAPI protected-blob framing correction (2026-11-19)

- Fixed Node.js DPAPI response validation: DPAPI Protect returns a variable-length protected blob, while Unprotect must return exactly 32 bytes. The protocol parser now enforces bounded variable output for Protect and exact key length for Unprotect.
- Windows CI exposed the mismatch in the first native round-trip test; this correction is pending fresh exact-head validation.
- Bumped root package version to `0.1.7` and synchronized lockfile metadata.

## Unreleased — DPAPI test path portability (2026-11-19)

- Fixed the helper-path fixture in the platform-independent Node.js test to use a host-native absolute path, so the constructor test can execute on both Linux and Windows.
- Bumped root package version to `0.1.6` and synchronized lockfile metadata.

## Unreleased — DPAPI helper memory and allocator correction (2026-11-19)

- Corrected native allocation cleanup in the DPAPI helper: unmanaged input/entropy buffers use `FreeHGlobal`, while DPAPI-owned output uses `LocalFree` after zeroization.
- Expanded cleanup so request frame, copied KEK, derived entropy and output buffers are zeroed on malformed requests and exception paths as well as successful operations.
- Updated the installation-binding integration test to assert the helper's generic nonzero-exit failure.
- Corrected trailing literal escape characters in root package/lock JSON files and bumped root package version to `0.1.5`.

## Unreleased — Windows DPAPI helper protocol (2026-11-19)

- Added a fixed-purpose .NET 10 Windows helper for DPAPI machine-scope Protect/Unprotect of 32-byte KEKs. It uses a bounded length-prefixed binary stdin/stdout protocol; no shell, arguments, environment secrets or temporary plaintext files.
- Added a Node.js client with absolute helper-path validation, bounded response framing, timeout, fail-closed error handling and buffer cleanup.
- DPAPI optional entropy is derived inside the helper from a domain separator, installation ID and the current Windows service SID. The helper fixes machine scope and disallows UI prompts.
- Added Windows CI compilation and DPAPI round-trip / installation-binding integration coverage.
- This helper is only the DPAPI primitive. It does not provision service identities or ACLs, persist a keyring, implement rotation/recovery, or enable credential storage/API. Production use remains blocked pending those gates.
- Bumped root package version to `0.1.4`; synchronized npm lockfile metadata. No installer or Release is created.

## Unreleased — Credential Vault regression-fixture correction (2026-11-19)

- Corrected the new control-character regression test to construct an actual U+0001 character with `String.fromCharCode(1)`; the previous fixture contained the six printable characters `\\u0001` and therefore did not exercise the intended rejection path.
- CI for `e9084406dd300ba2c0412316fc799f68bb3dcba3` confirmed the original six encryption tests now pass on Windows, but this added regression test failed because its fixture was escaped incorrectly. Linux/PostgreSQL validation was still running when this follow-up was prepared.
- Bumped the root package version to `0.1.2` and synchronized the npm lockfile. Fresh exact-head CI is required.

## Unreleased — Credential Vault context-validation correction (2026-11-19)

- Fixed the control-character validation in the credential encryption context. The previous escaped character-class expression rejected valid identifiers such as `credential-1` on both Linux and Windows.
- Added regression coverage for ordinary identifiers and rejection of ASCII control characters.
- Exact-head CI for the preceding crypto-core commit `25021e1b2b428f2f8287484105a36d7d2bd9d381` failed in both platform-validation and Windows runtime-smoke jobs; six crypto tests failed at context validation. This correction is pending fresh CI and is not yet verified.
- Bumped the application package version from `0.1.0` to `0.1.1`; no installer or GitHub Release is created until required validation and release gates pass.

## Unreleased — Credential Vault cryptographic core (2026-11-19)

- Added an AES-256-GCM envelope-encryption primitive with a fresh random 256-bit data key per credential, independent 96-bit nonces for data/key wrapping, 128-bit authentication tags and AAD bound to credential, branch, asset and credential kind.
- Added a versioned key-provider contract; production key material must be supplied by a future Windows DPAPI-backed provider. No plaintext/environment/file key fallback is provided.
- Added tests for round-trip, per-record randomization, context substitution, ciphertext/tag/wrapped-key tampering, key rotation and missing-key failure.
- **Security boundary:** no DPAPI provider, recovery export/restore drill, database model, API, RBAC, audit integration or production key provider is implemented. The module is not wired into the API and must not store real equipment secrets yet.
- Prior exact-head CI passed on `4b67a718ce1210a7dc8a634b811bbdf5c8af0814` (runs [44579435913](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44579435913) and [44579448547](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44579448547)); validation for this new commit is pending.

## Unreleased — PostgreSQL Worker queue CI validation (2026-11-19)

- Corrected queue integration test isolation so each test clears only its own branch-scoped discovery runs and asserts the exact run ID returned by claim.
- Recorded the prior CI failure (4 integration-test failures caused by globally shared queue fixtures) and its test-isolation correction; no queue semantics were changed to mask test interference.
- Verified exact head `d2e15169d2d7cd12c7590e5ebe0aeef9b635a437` with GitHub Actions run [44576967674](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44576967674): all three jobs passed — Node.js 26/PostgreSQL 18 platform validation, Windows API runtime smoke, and npm lockfile bootstrap.
- Worker remains fail-closed with an empty source-handler allow-list. No discovery job is claimed, no network device is contacted, and no credential vault or discovery API is implemented.
- PR #8 remains Draft/open/unmerged. No installer, tag, GitHub Release or production deployment was created.

## Unreleased — inventory CI repair and guarded SNMP discovery design

- Fixed React Hooks ESLint failures by deferring inventory data-loading calls from effects to a microtask.
- Verified PR-triggered run [44570604144](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44570604144) and push run [44570589162](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44570589162), both successful on exact head `e324d6a47fc232421488c330528bc1784fac9f94`.
- PostgreSQL-backed API integration tests executed, including the inventory integration suite; the API Vitest run reported 15 passing tests across 5 files. Windows API runtime smoke, lint, typecheck, security audit, backup/restore smoke and production build passed.
- Added a read-only SNMP discovery design with explicit MikroTik safety controls: no port scanning/mapping, no NAT/port forwarding, no SNMP SET, no automatic firewall/address-list changes, and conservative per-target rate limits/circuit breaking.
- Discovery remains design-only until the durable Worker, credential vault and scoped API are implemented and tested. No device was contacted and no router configuration was changed.

## Unreleased — Phase 3 pull-request CI trigger

- Expanded `.github/workflows/validation.yml` so pull requests targeting `phase3/**` branches receive the same validation workflow as pull requests targeting `main`. Push validation for `phase3/**` remains enabled.
- The available workflow-run inspection endpoint only reports PR-triggered runs; an empty result does not prove that a push-triggered run did not execute. Verify the Actions run for the exact commit before treating checks as passed.

## Unreleased — M2 edit validation coverage

- Extended PostgreSQL-backed inventory API integration coverage for successful asset IP/MAC updates, invalid IP/MAC rejection, successful switch-port metadata updates, duplicate and out-of-range VLAN rejection, and stale switch-port version conflicts.
- Tests are committed but not yet verified as executed; the current GitHub commit status and PR workflow-run queries return no checks for the latest code head.

## Unreleased — M2 inventory editing

- Added asset editing for asset code, name, management IP, MAC, hostname, status, vendor, model, physical location and description. Updates use the existing branch-scoped API, optimistic version checks and audit events.
- Added switch-port metadata editing for interface name, alias, description, access/tagged VLANs and connected-device label. Updates use optimistic version checks and do not configure the physical switch.
- Follow-up commits: `6fb36a9334555bed3bad08af6dc99c730dafaa80` and `e1afdf8b1e064d8d246a55ff861bb71d1af2b8f9`.
- Validation is pending: no commit status checks or PR-triggered workflow runs are currently returned for the latest head. Do not treat this UI slice as CI-verified until checks pass on the exact head.

## Unreleased — M2 inventory workspace

- Added a responsive, authenticated inventory page with active-branch selection, equipment search/type filters, asset registration and switch-port metadata entry.
- Added `GET /api/v1/branches/accessible`: ADMIN receives active branches globally; OPERATOR/VIEWER receive only active branches with a current grant. The existing ADMIN-only branch administration endpoint remains unchanged.
- Added integration assertions for branch-scoped branch discovery and exposed the inventory page from desktop/mobile navigation.
- The UI distinguishes operator-maintained port metadata from timestamped observations and does not imply live switch configuration or discovery.
- Implementation is in Draft PR [#8](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/8), stacked on Draft PR #7; CI must pass on the final head before review.

## Unreleased — M2 inventory foundation

- Added PostgreSQL/Prisma models and migration for branch-owned assets, switch profiles, switch ports, port observations and discovery-run records.
- Added branch-scoped inventory list/create/update APIs with bounded pagination, branch/kind/search filters, IP/MAC validation, optimistic concurrency and transactional audit events.
- Added switch-port metadata list/create/update APIs for operator-maintained aliases, descriptions, configured VLANs and connected-device labels.
- Enforced the owner-approved role policy at each M2 API entry point: OPERATOR write access only within active assigned branches; VIEWER read-only; ADMIN global.
- Added PostgreSQL integration coverage for role restrictions, cross-branch denial, asset editing and stale-version conflicts.
- GitHub Actions run [44531050529](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44531050529) passed on initial M2 head. Follow-up run [44531799575](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44531799575) passed on `60e9f694e9b0cf8960452ac63dfba8ee84431ca0`, including append-only observation enforcement and active-branch scope tests.
- No SNMP/SSH discovery, live switch configuration, subnet scanning, monitoring or hardware compatibility is claimed. PR #7 remains Draft and unmerged pending review.

## Unreleased — M1 lifecycle completion
- Added ADMIN-only branch editing with optimistic version checks, soft archive and restore.
- Archiving a branch now revokes all active user-branch grants in the same transaction; restoring the branch does not silently reinstate revoked grants.
- Added administrator-issued one-time temporary password reset for active non-admin accounts, with Argon2id hashing, forced password change, auth-epoch increment, session revocation, rate limiting, audit event and no-store response.
- Added administrator UI controls for branch edit/archive/restore and user password reset; temporary credentials are shown once and can be cleared from the screen.
- Expanded PostgreSQL integration coverage for branch version conflicts/lifecycle, grant revocation on archive, non-restoration of grants and password reset/session invalidation.
- Updated M1 design, API contract, testing strategy and project status documentation.
- Owner confirmation of the OPERATOR/VIEWER operational action matrix, target-Windows service identity/integration tests, and production PostgreSQL backup/restore evidence remain acceptance gates. No production readiness is claimed.

# Changelog

## 2026-11-19 — primary-repository review, archival repair and status refresh
- Performed a comprehensive Phase 2 architecture and documentation consistency review of the transferred primary-repository baseline (22-commit history, `main` at `f606762`); findings, evidence and owner questions recorded in `PHASE2_REVIEW_2026-11-19.md`.
- Repaired `GUIDELINE.md`: restored the 1536 original CRLF line-ending bytes of the archived master prompt that were normalized to LF during the repository transfer. The embedded prompt again matches the recorded source SHA-256 (`38634f57…`) and the file again matches its package-manifest SHA-256 (`2a14f841…`, 55234 bytes). No prompt content or wrapper text changed.
- Completed the `README.md` documentation index (changelog, Desktop Bridge PoC specification, historical review and handover reports, manifest, checksums, current review report).
- Added a current primary-repository snapshot section to `HANDOVER.md` and labeled the pre-transfer "Current package" wording as historical; no historical text removed.
- Recomputed `FINAL_FILE_MANIFEST.md` and `SHA256SUMS.txt` against the post-repair tree as directed by `TRANSFER_STATUS.md`; both now also cover `TRANSFER_STATUS.md` and the new review report. Pre-repair values remain in commit `f606762`.
- Verified: repository private; zero releases, tags and workflows; all relative Markdown links resolve; `sha256sum -c SHA256SUMS.txt` passes for every listed file; limited secret-pattern scan found no credential-like values.
- No application implementation, migrations, installers, releases, workflow changes, repository settings changes or PoC execution. Phase 3 remains not started.

### Corrections and additions — same day, owner-authorized
- Corrected the per-file transfer commit count (20 → 19) and the `f606762` UTC timestamp (07:09:03Z → 06:39:03Z) in `PHASE2_REVIEW_2026-11-19.md` and the `HANDOVER.md` snapshot.
- Restored the historical `**Current package:**` label in `HANDOVER.md` byte-for-byte (owner-selected option B); the historical/superseded qualifier now sits on a separate preceding line, so all pre-transfer text is retained 100% verbatim.
- Extended the review report with Appendix A (public-mirror exposure assessment: two post-review mirror commits, aggregated package tree, published Git bundle of private review-branch history; zero credential-pattern matches across 413 scanned records; containment recommendations) and Appendix B (recommended `GUIDELINE.md` byte-preservation strategy: `.gitattributes` `-text` plus archival-region SHA-256 validation — proposal documented, not implemented), with new evidence E-15…E-20.
- Recomputed `FINAL_FILE_MANIFEST.md` and `SHA256SUMS.txt` a second time after these corrections; `sha256sum -c` passes for all 21 entries.
- Documentation only: no settings, visibility, hook, workflow or Git-history changes; the pull request remains open and unmerged; Phase 3 remains not started.

### Owner decision recorded — same day, owner-authorized documentation update
- Recorded the owner-approved decision of 2026-11-19 in `DECISION_LOG.md`: the temporary public documentation mirror `aliajeli/testing` has been **permanently deleted by the owner**, and the primary private repository `aliajeli/enterprise-it-infrastructure-management-platform` is the **sole authoritative project repository**. The change is purely additive — the six owner-approved architectural decisions of 2026-11-18 are unchanged.
- Explicitly recorded in the decision entry: deletion does **not** recall content already cloned, downloaded, crawled, indexed or cached while the mirror was public; no GitHub Support cache purge is claimed or verified; no offline archival copy is claimed to have been created (**Not verified**). The decision entry also lists the point-in-time statements in other documents that it supersedes.
- `PHASE2_REVIEW_2026-11-19.md`: Q-03 closed as **RESOLVED by owner decision**; F-09 and S-1 updated; §7 deferred list and §9 P1 list annotated; Appendix A extended with "Current state" and "Outcome of the owner decision" subsections and temporal framing that separates the verified historical public exposure (retained as history) from the post-deletion state; new evidence E-21 (read-only deletion verification).
- `HANDOVER.md`: snapshot rows updated for consistency (new "Sole authoritative repository" row; next-action question list). All historical pre-transfer text remains byte-for-byte verbatim.
- `FINAL_FILE_MANIFEST.md` and `SHA256SUMS.txt` recomputed a third time, after all other changes; `sha256sum -c` passes for all 21 entries.
- Documentation only: no settings, visibility, branch protection, webhook, workflow, hook or Git-history changes; no branches created or deleted; the pull request remains open and unmerged; `main` unchanged; Phase 3 remains not started.

## Unreleased — 2026-11-18
- Drafted architecture, security, database, deployment, testing and release design documentation.
- Recorded repository visibility evidence and outstanding validation gaps.
- No application features, migrations, installer, releases or tests implemented.
- Expanded the proposed Windows service topology, bridge security, Agent identity/deployment, monitoring, CCTV, installation, data relationships, and per-commit release design after architecture review. No compatibility tests performed.
- Recorded owner-approved service, package-path, bootstrap, update-proxy, bridge-PoC and tiered-testing decisions; updated related design and planned API documentation. No implementation or compatibility validation.
- Archived the owner-supplied master prompt verbatim and verified the embedded bytes against the source file.
- Prepared a public documentation-mirror review snapshot; the initial package and subsequent corrections were published in earlier mirror commits. The local independent-review branch was not verified on GitHub.
- Prepared a local root-level owner-review package; reconciled handover, release-policy proposal wording, archival line endings and checksums. No GitHub operation or Phase 3 work performed during this milestone.

## 2026-11-19 — successful PR #1 squash merge and post-merge reconciliation (R1)
- **Independently verified:** GitHub PR metadata reports [PR #1](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/1) **MERGED** at `2026-11-19T07:58:59Z`; its merge commit is `eb8b704f945ca4c5199d97a6a8c4bd286068cfbb`. GitHub commit metadata shows one parent (`f60676205bcf9ff7f5608f0e3b3074a76bdb3776`) and the squashed review changes. Remote `main` resolves to that SHA. Earlier entries describing PR #1 as open/unmerged are preserved as historical records.
- **Independently verified:** authenticated repository metadata reports private visibility; the remote main tree is untruncated and contains 22 root files. There are zero releases, tags and workflows at reconciliation time.
- **Owner-reported versus independently observed:** the owner confirmed deletion of `aliajeli/testing` on 2026-11-19. The prior independent unavailability checks (404 anonymously/authenticated and absence from the authenticated repository list) remain recorded as review evidence E-21; R1 does not claim to have witnessed the deletion. Deletion does not prove prior copies, clones, downloads or caches were recalled. Token revocation remains owner-reported, not independently reverified.
- Reconciled current SECURITY_POLICY.md repository/exposure wording, the GUIDELINE.md maintained repository-location wrapper, DECISION_LOG.md custody/supersession status and HANDOVER.md operational snapshot; appended a dated supersession note to TRANSFER_STATUS.md. Historical review reports, earlier changelog entries and pre-transfer handover records remain unchanged.
- Preserved GUIDELINE.md immutable lines 6–1544 byte-for-byte and the source archive invariant (39181 bytes; SHA-256 `38634f573b0391402a1b58ad927d133fa0ad2ca6551c8ea66180daddd3e24b16`). All six owner-approved architectural decisions and their detailed elaborations remain unchanged. Recomputed FINAL_FILE_MANIFEST.md, then SHA256SUMS.txt last; integrity results accompany the R1 PR.
- Documentation only: no application code, migrations, installers, workflows, settings, permissions, hooks, webhooks, branch protection or remote-branch deletion. No `.gitattributes` or Appendix B implementation (Q-02 undecided); Q-07 remains an owner decision. Phase 2 remains active; Phase 3 was not started and the Desktop Bridge PoC was not executed. Submit R1 for owner review; do not merge it.

### PR #2 review corrections — 2026-11-19
- Clarified archival measurement scopes in HANDOVER.md using exact baseline/PR-head Git blobs and a reproducible byte-comparison procedure: complete protected lines 6–1544 are 39,295 bytes; the embedded original prompt alone is 39,181 bytes. The earlier audit's assignment of 39,181 bytes to the complete line range was a scope-labeling error. The 114-byte difference consists of two marker lines and one separator LF, not altered source bytes. GUIDELINE.md is unchanged by this follow-up.
- Replaced HANDOVER.md's temporary session-branch entry with PR #2 as the dated owner-review item, recorded the head SHA observed when preparing the snapshot, and required live GitHub PR/main verification before action. A snapshot cannot embed its own future commit SHA; the updated head is reported in PR #2 and Git history. Historical sections and all six architectural decisions remain unchanged.
- Recomputed the manifest and then checksums last; repeated archival, decision-preservation, historical-record, checksum and relative-link checks. Documentation only; Phase 3 not started, Desktop Bridge PoC not executed, Q-02 not implemented, and PR #2 not merged.

## 2026-11-19 — Phase 3 authorized; initial platform foundation
- Owner explicitly authorized Phase 3 implementation.
- Added the initial Next.js App Router web workspace using strict TypeScript and Tailwind CSS.
- Added a responsive infrastructure overview shell with truthful empty states; no simulated inventory, monitoring or service health.
- Added the Phase 3 milestone plan, refreshed the repository landing page and changelog, and added a current Phase 3 operational snapshot to HANDOVER.md.
- Selected Node.js 26 Active LTS, Next.js 16.4.6, PostgreSQL 18 and Prisma ORM 7 GA as the initial compatibility baseline; exact dependency installation and clean-runner verification remain pending.
- No API, database migration, Windows service, Agent, Desktop Bridge, installer, release workflow or production integration is claimed as implemented.
- No repository settings, branch protection, hooks, webhooks or permissions were changed.

## 2026-11-19 — M0 quality-gate scaffolding
- Added an explicit ESLint CLI gate using the official Next.js 16 Core Web Vitals and TypeScript flat configurations.
- Added root and web-workspace lint scripts and documented the local validation sequence.
- Added a Node.js 26 runtime selector file.
- Dependency installation, lockfile generation and execution of lint/typecheck/build remain pending a network-enabled Node.js 26 runner.
- Added a native, keyboard-accessible mobile navigation disclosure menu and made the active Overview item a real navigation link.

## 2026-11-19 — M0 validation and dependency lockfile bootstrap
- Added a Node.js 26 GitHub Actions validation workflow covering dependency installation, dependency-tree verification, ESLint, TypeScript and production build.
- Added a safe lockfile bootstrap job: dependency lifecycle scripts are disabled while generating the lockfile, and the workflow commits only the lockfile to the active feature branch.
- Committed the generated npm v3 lockfile using Node.js 26.13.1/npm 11.20.0.
- The first lint run found two internal anchor elements; both were replaced with Next.js Link components.
- GitHub Actions run 44490452757 passed dependency installation, dependency-tree verification, lint, typecheck and production build for the application source. That run preceded the lockfile commit; a fresh npm ci run against the committed lockfile is still required.

## 2026-11-19 — M0 unit and dependency-security gates
- Added Vitest 5.1.1 and server-rendered dashboard smoke tests covering truthful empty states and navigation semantics.
- Added a high-severity threshold npm dependency audit to the GitHub Actions validation workflow.
- Optimized lockfile bootstrap to skip registry resolution once the lockfile is already tracked.
- The committed-lockfile CI run passed npm ci, dependency-tree verification, ESLint, TypeScript and production build; the expanded test and audit gates are now being validated.
- Refreshed and committed the npm lockfile after adding Vitest 5.1.1; the first npm ci attempt correctly detected the stale lockfile and failed closed. A new clean-runner validation is required against the refreshed lockfile.

## 2026-11-19 — M0 completed
- Completed M0 on Node.js 26.13.1/npm 11.20.0 with a committed npm v3 lockfile and a clean `npm ci` install.
- GitHub Actions run 44491419345 passed dependency-tree verification, `npm audit --audit-level=high` (0 vulnerabilities), ESLint, TypeScript, Vitest (2 tests) and production build.
- M0 acceptance criteria are met. M1 identity, access control and persistence is the next milestone; no production integration is claimed.

## 2026-11-19 — M1 Prisma security patch update
- Dependency audit found high-severity advisories in Prisma 7.9.1 transitive dependencies (deepmerge-ts and mysql2).
- Updated the pinned Prisma 7 packages to 7.10.1, a patch release that updates dependencies with security advisories. Prisma 8 remains a release candidate and is not adopted.
- Prisma 7.10.1 migration/schema validation and the refreshed lockfile must pass the complete CI gate before the M1 branch is considered validated.
- Bound API proxy trust to loopback peers so rate limiting and audit IP attribution can use the reverse proxy's forwarded client IP. Documented that the edge proxy must overwrite X-Forwarded-For.
- Added a disposable-PostgreSQL integration test for branch-grant partial uniqueness and append-only audit enforcement, plus a Windows runner smoke gate for the native Argon2id binding and API build.
- Added an interactive, one-time administrator bootstrap CLI protected by a PostgreSQL advisory lock; it refuses to create an account if any user already exists and never accepts passwords in command-line arguments.
- Added server-side branch-scope and administrator capability primitives. Operational permission mutations remain disabled pending owner approval of the exact role/action matrix.
- Added a browser sign-in form, session-gated dashboard shell and logout control. The UI uses same-origin API routes and HttpOnly cookies; no session token is stored in browser storage.

## 2026-11-19 — M1 identity foundation validated; PR #4 opened
- Completed the first M1 implementation slice: dedicated Fastify API and Prisma 7.10.1 database packages, PostgreSQL identity/session/branch-grant/audit migration, Argon2id authentication, opaque HttpOnly sessions, login/logout, origin/rate-limit controls, one-time administrator bootstrap, branch-scope primitives and browser sign-in/session/logout flow.
- Added live PostgreSQL integration coverage for migration compatibility, active branch-grant partial uniqueness and append-only audit enforcement.
- Added a Windows runner smoke gate for Prisma generation/build, API typecheck, native Argon2id execution, tests and API build.
- Validation run 44495513578 passed: npm audit reported zero vulnerabilities; 10 API and 2 web tests passed on Linux; 9 API tests passed on Windows with the database-only integration test skipped there; Linux production build and Windows API build passed.
- Opened [PR #4](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/4) for owner review. It is not merged. M1 remains in progress; user management, password change/recovery, branch CRUD and the owner-confirmed operational role/action matrix remain outstanding.

## 2026-11-19 — M1 user and branch administration implementation

- Added admin-only user provisioning and listing, cryptographically random temporary credentials, no-store credential delivery and forced password change at first login.
- Added branch creation/listing and transactional replacement of per-user branch grants.
- Added OPERATOR/VIEWER role changes and account disable/enable with session revocation and auth-epoch invalidation.
- Added self-modification protections, owner-controlled administrator-account restrictions and audit events for administrative actions.
- Added PostgreSQL integration coverage for provisioning, login, password change, branch-scope replacement, role/status changes, session revocation and append-only audit enforcement.
- Fixed Prisma relation-connect semantics for branch/grantor provisioning and corrected Node response-header typing in the integration test.
- GitHub Actions run 44504888903 passed all three validation jobs, including Linux/PostgreSQL 18 and Windows native Argon2id runtime validation.
- Opened [PR #5](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/5) as Draft for review. It is not merged. M1 remains in progress pending code review, the owner-confirmed operational role/action matrix, complete branch lifecycle, password recovery and production/Windows service validation.


## 2026-11-19 — Owner-approved operational role/action matrix
- Recorded the owner's ADMIN/OPERATOR/VIEWER permissions: ADMIN global administration; OPERATOR branch-scoped inventory and switch-port/VLAN metadata editing plus non-destructive discovery/sync; VIEWER branch-scoped read-only inventory/metadata.
- Explicitly denied OPERATOR remote sessions, stored credential use, live device configuration, deployments and Store Commerce force-close. Force-close requires separate explicit approval and warning even for ADMIN.
- Added a closed server-side `PlatformAction` policy and branch-action authorization helper requiring both capability and active branch grant.
- Expanded unit tests to cover allowed and denied actions for all roles and branch-scope enforcement. Operational endpoints remain unimplemented and must enforce the policy when introduced.


## Unreleased — PostgreSQL Worker queue foundation

- Added an additive migration and Prisma fields for discovery-run leases, heartbeats, attempts, retry scheduling and cancellation requests.
- Added a separate `@platform/worker` workspace with atomic PostgreSQL `SKIP LOCKED` claiming, lease recovery, heartbeat, owner-bound completion/failure, cancellation acknowledgement and bounded exponential retry.
- Added Worker unit tests for retry policy and attempt limits.
- The Worker deliberately registers no discovery handlers and uses an empty source allow-list; it cannot claim queued runs. No SNMP/SSH/ISAPI/Agent requests, credential storage, enqueue API or Windows service deployment are included.
- Runtime/CI validation is pending for commit-specific head.


## Unreleased — Worker lease correctness and PostgreSQL integration tests
- Corrected expired-lease recovery so cancellation is processed before retry exhaustion; a cancellation-requested run cannot be incorrectly marked FAILED by the exhausted-attempt update.
- Enforced live-lease expiry for completion and cancellation acknowledgement, preventing a stale worker from finalizing a run after its lease has expired.
- Added disposable-PostgreSQL integration tests for concurrent claims, lease ownership, stale-worker rejection, lease recovery/reclaim, retry exhaustion, cancellation precedence and transaction rollback.
- The preceding Worker foundation CI run (commit `356c5b5`, run `44572613928`) passed all three jobs. Validation of these follow-up fixes and integration tests is pending on their exact commit head.
- Discovery handlers remain disabled; no SNMP/SSH/ISAPI/Agent network activity, installer or release is enabled by this change.


## Unreleased — Worker integration test isolation
- PostgreSQL CI exposed test interference caused by globally-scoped queue claiming across test cases. Integration tests now clean up their branch's runs before each case and assert that the intended run was actually claimed.
- Lease recovery assertions validate the target run rather than assuming no other eligible expired lease exists in the disposable database.
- The first integration run failed (4/11 Worker integration tests); follow-up CI on commit `4ca9fd7` is pending. No passing claim is made until the exact head completes successfully.

## Unreleased — Credential keyring core
- Added a versioned keyring core behind explicit DPAPI-protector and storage contracts.
- Added initialize-once behavior, protected 256-bit KEKs, read-back verification, versioned key retrieval and serialized rotation.
- Rotation preserves every prior key version and fails closed at a bounded 64-version capacity; no automatic key retirement is provided.
- Added tests for initialization idempotency, old-key retention, concurrent rotation, malformed registry rejection and capacity handling.
- No concrete filesystem adapter, ACL verification/provisioning, independent recovery or clean-host restore drill exists yet. This is not a production key store; do not enter real equipment secrets.
- Root version metadata advanced to 0.1.11. No installer or Release is produced under the approved bootstrap exception.


## Unreleased — Windows keyring storage adapter design gate
- Recorded a fixed-path, service-SID-bound Windows storage contract for the versioned Credential Vault keyring.
- Specified exact owner/DACL validation, transaction-scoped cross-process locking, same-directory durable atomic replacement, bounded binary helper sessions and Windows multi-process/security acceptance tests.
- This is a design milestone only: no filesystem adapter, ACL provisioning, storage helper operation, production keyring registration, recovery export or installer is implemented by this change.
- Root version metadata advanced to 0.1.12; no Release or installer is produced.


## Unreleased — dependency lock consistency correction
- Exact-head CI for `0.1.12` failed at `npm ls --all`: the root version bump had inadvertently changed the locked `node_modules/@prisma/streams-local` package version to `0.1.12` while its resolved tarball and `@prisma/dev` dependency remained at `0.1.11`.
- Restored the third-party package lock entry to `0.1.11`; only the root package and root lock metadata use `0.1.13`.
- Windows API runtime smoke passed on the failed commit; Linux dependency-tree verification is rerun on this correction. No application dependency versions were intentionally changed.
