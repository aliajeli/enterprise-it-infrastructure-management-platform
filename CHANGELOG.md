# Changelog

## 0.1.246 — 2026-11-25

- Extended the hosted SCM fixture to capture bounded Application/.NET Runtime and Service Control Manager events when the bootstrap service stops before pipe readiness, not only when pipe connection times out. The 0.1.245 run stopped before reaching the pipe-connect diagnostic.
- No production behavior changed. The next exact-head run must identify and correct the service startup failure before the service-SID pipe boundary can be accepted.

## 0.1.245 — 2026-11-25

- Fixed hosted SCM startup: the bootstrap BackgroundService constructor was internal, so the default Microsoft DI activator could not resolve it and the service exited with an unhandled InvalidOperationException before creating its pipe. The constructor is now public for DI activation.
- The exact-head Windows SCM integration test exposed the issue through bounded Application/.NET Runtime and Service Control Manager event diagnostics. Re-run the SCM/Standard User pipe test before claiming the service starts successfully.

## 0.1.244 — 2026-11-25

- Removed explicit Named Pipe owner assignment to the service SID. A service SID is an authorization group and is not guaranteed to be owner-enabled in the process token; forcing it as the kernel object owner can prevent pipe creation. The kernel-selected owner now follows the service process's primary identity, while the protected DACL continues to grant only the dedicated service SID, SYSTEM and Administrators.
- Added bounded SCM and Windows Event Log diagnostics when the hosted service pipe does not become available. No credential is sent before the pipe positive control succeeds.
- Exact-head Windows CI must verify service startup and pipe creation. The production virtual-account owner behavior and full initdb/credential acceptance remain open.

## 0.1.243 — 2026-11-25

- Corrected the hosted-Windows SCM fixture to use LocalService plus the unrestricted service SID. The existing API SCM smoke documents that hosted runners reject custom `NT SERVICE\...` logon-account assignment with SCM error 1057; the bootstrap service still requires and verifies its own enabled service SID, which is the SID used by its pipe DACL.
- The fixture now verifies SCM reports LocalService and the service SID is unrestricted. This does not validate production virtual-account logon; that remains an explicit supported-Windows-Server acceptance gate.

## 0.1.242 — 2026-11-25

- Added hosted-Windows SCM integration for the dedicated PostgreSQL bootstrap service: virtual-account registration, unrestricted service SID, startup verification, authorized-admin pipe positive control and same-session Standard User pipe denial. Only a malformed frame is sent; no credential or initdb is used.
- Reclassified superseded caller-owned pipe/handle experiments as non-gating legacy diagnostics. Their failures remain visible in Actions but no longer block the dedicated-service validation path.
- This is not end-to-end credential acceptance. Real service-owned initdb isolation, PostgreSQL 18.7 initialization, secret-leakage checks, timeout/crash cleanup, data ACL/ownership and supported Windows Server acceptance remain open. Production initializer remains fail-closed.

## 0.1.241 — 2026-11-25

- Removed the explicit System.IO.Pipes.AccessControl package reference after Windows CI confirmed the API is already included by the .NET 10 target and treats redundant references as NU1510 errors. This is a build correction only.

## 0.1.240 — 2026-11-25

- Fixed Windows bootstrap service compilation: imported the service namespace in the top-level host, guarded nullable Windows token user SIDs, and set the pipe owner to the dedicated service SID rather than requiring the service to assign ownership to SYSTEM.
- Sanitized all inherited PostgreSQL environment variables before launching initdb and added a post-initdb SCRAM policy check. CI on 0.1.234 identified the namespace and nullable-analysis errors.

## 0.1.239 — 2026-11-25

- Restored the supported System.IO.Pipes.AccessControl 5.0.0 package for PipeSecurity/NamedPipeServerStreamAcl APIs (the package does not publish a 10.0.0 release). Improved the self-contained publisher's failure diagnostics so the exact dotnet publish output is preserved for the failed host.
- This is a build correction only; service startup and real credential transport still require dedicated CI acceptance.

## 0.1.238 — 2026-11-25

- Removed the unavailable System.IO.Pipes.AccessControl 10.0.0 package reference; the Windows target uses the framework-provided API surface. Corrected service-host staging rollback to use .NET Array.Reverse rather than an unsupported Select-Object parameter.
- Windows CI for 0.1.234 identified both issues. The corrected exact-head build and publish must pass before acceptance.

## 0.1.237 — 2026-11-25

- Consolidated bootstrap service provisioning into one ShouldProcess approval before SCM and ACL mutation. This prevents a declined individual ACL prompt from being reported as a successful provisioning operation.

## 0.1.236 — 2026-11-25

- Fixed the bootstrap provisioning script's conditional structure and corrected the changelog heading. No runtime gate was enabled.

## 0.1.235 — 2026-11-25

- Tightened bootstrap service provisioning confirmation handling and documented that exact-head Windows CI and standard-user process-isolation tests remain required.

## 0.1.234 — 2026-11-25

- Added a dedicated Windows PostgreSQL Bootstrap Service candidate under the virtual service identity `NT SERVICE\EnterpriseITPostgreSQLBootstrap`.
- Added a SYSTEM/Administrators-only named-pipe request endpoint, Windows-token authorization, bounded binary credential framing, and service-owned PostgreSQL 18.7 initdb execution through redirected stdin. Credential bytes are excluded from argv, environment, files, logs, and process output.
- Added service provisioning and a SecureString-based local client script; included the new executable in immutable Windows service-host staging and CI build/publish validation.
- This is an implementation candidate, not an approved production path. Exact-head Windows CI, same-user Standard User handle-denial integration, real initdb service-account integration, service ACL/SCM lifecycle, cluster ownership/grants, role provisioning, migrations, and supported Windows Server acceptance remain mandatory. The existing initializer stays fail-closed.

# Changelog

## 0.1.233 — 2026-11-25

- Corrected the isolated-account CI probe to honor the selected threat model: elevated Local Administrators are trusted, so their access is an expected positive control rather than a failure. Non-administrator access remains denied; this does not implement or approve the production bootstrap service.

## 0.1.232 — 2026-11-25

- Enabled push validation for `arena/**` development branches so security and Windows integration changes receive CI feedback before review. This does not approve credential transport or enable PostgreSQL initialization.

## 0.1.231 — 2026-11-24

- Recorded the hosted synthetic process-object boundary experiment and the continuing PostgreSQL credential transport blockers.

## 0.1.230 — 2026-11-24

- Corrected the Windows DLL binding for process security descriptor inspection in the synthetic process-boundary diagnostic.

## 0.1.229 — 2026-11-24

- Corrected privilege restoration in the synthetic Windows process-object boundary diagnostic; exact-head CI required.

## 0.1.228 — 2026-11-24

- Added bounded child-fixture diagnostics to investigate the synthetic process-object positive-control failure.

## 0.1.227 — 2026-11-24

- Added bounded, synthetic-only diagnostic annotations for the process-object experiment.

## 0.1.226 — 2026-11-24

- Added a no-secret, hosted-Windows-only process object DACL and debug-privilege diagnostic. It does not enable or establish an approved PostgreSQL credential transport.

## 0.1.225 — 2026-11-24

- Recorded completed 0.1.224 hosted CI and updated deployment/test status; no production security gate was opened.

## 0.1.224 — 2026-11-24

- Reduced exposure in the synthetic initdb pipe by delaying credential materialization until after the exact-PID guard, avoiding immutable managed plaintext strings and promptly clearing temporary buffers. This does not solve same-user handle interception or enable production use.

## 0.1.223 — 2026-11-24

- Reconciled README, handoff and active deployment/security/testing documentation with the completed 0.1.222 validation and outstanding production gates.

## 0.1.222 — 2026-11-24

- Made manifest file creation no-overwrite at the file open and hardened ZIP inspection against file/ancestor conflicts and superscript Windows device names. Added regression fixtures.

## 0.1.221 — 2026-11-24

- Prevented deletion by pathname of a published offline archive when checksum publication fails. Added collision regressions; incomplete archives are retained for inspection, not treated as completed packages.

## 0.1.220 — 2026-11-24

- Added fixed-category, fail-closed diagnostics for experimental pipe client PID mismatch; matching parent/image remains explicitly insufficient for credential delivery. No production initializer or installer gate was opened.

## 0.1.219 — 2026-11-24

- Extended the disposable failed-migration experiment to check preservation of deliberately committed partial effects through blocked retry and explicit synthetic reconciliation. Production migration remains disabled.

## 0.1.218 — 2026-11-24

- Added disposable Windows Prisma failed-migration, blocked-retry, explicit resolution and data/ownership preservation checks using a scratch migration tree. Production migration and installer remain disabled.

## 0.1.217 — 2026-11-24

- Shortened the no-secret isolated-account fixture command to fit the Windows credentialed process command-line constraint; exact-head CI required.

## 0.1.216 — 2026-11-24

- Added sanitized, fixed-category diagnostics for the disposable isolated-account process probe after its positive control failed; no deployment or credential gate was opened.

## 0.1.215 — 2026-11-24

- Added a disposable Windows CI experiment for process access across a temporary non-admin local test account, with a same-account positive control and identity-checked cleanup. This is not PostgreSQL credential transport or production security approval.

## 0.1.214 — 2026-11-24

- Added independent concurrent Vault provisioner fixture coverage and verified retry preserves existing data and exact ACLs. This nondeterministic test is not exhaustive race or Windows Server security acceptance.

## 0.1.213 — 2026-11-24

- Added test-only Vault faults before identity capture and regressions requiring unproven objects to remain untouched after failed provisioning. Production test hooks remain compiled out.

## 0.1.212 — 2026-11-24

- Isolated the test-only Vault fault build in a copied source directory to avoid duplicate generated assembly attributes and production build contamination. Exact-head Windows CI required.

## 0.1.211 — 2026-11-24

- Retained created Vault object handles and identity state before post-open validation, allowing identity-checked rollback on later failures. Added separate test-only fault build and fresh/existing-store rollback checks; no Vault or installer security gate was opened.

## 0.1.210 — 2026-11-24

- Added shared fail-closed PostgreSQL deployment input validation for loopback endpoint, identifier safety and distinct roles, with negative tests. Offline package validation now requires the validator and disabled initializer. No database mutation gate was opened.

## 0.1.209 — 2026-11-24

- Added a no-credential hosted Windows diagnostic probing same-user PROCESS_DUP_HANDLE access to a real PostgreSQL initdb restricted re-exec child. It cannot prove either actual interception or production security and does not enable installation.

## 0.1.208 — 2026-11-24

- Hardened disposable Linux and Windows database privilege tests to require PostgreSQL SQLSTATE 42501 for denied operations rather than accepting arbitrary failures, and added DDL/ownership checks. Corrected stale PostgreSQL bootstrap documentation; production mutation remains disabled.

## 0.1.207 — 2026-11-24

- Bound offline installer ZIP metadata reads and entry processing, with regression tests; installation remains disabled and these limits do not prevent allocations while ZipArchive first parses its central directory.

## 0.1.206 — 2026-11-24

- Made installer preflight distinguish host baseline from actual installation readiness, which remains false while security and acceptance gates are open. It now rejects non-Server and ARM64/unknown architectures; no Windows Server version is claimed as accepted.

## 0.1.205 — 2026-11-24

- Expanded the disposable Windows PostgreSQL migration experiment with separate synthetic API and Worker roles and positive/negative SQL privilege checks. This does not implement production role provisioning or enable installer/database mutation.

## 0.1.204 — 2026-11-24

- Removed potential task-result leakage into the experimental stdin return stream and strengthened strict-mode result-count checks in synthetic and disposable migration tests. No production credential or migration gate was opened.

## 0.1.203 — 2026-11-24

- Added independent fast disposable migration CI and narrowed synthetic initializer failure stages without emitting credentials or raw child diagnostics. Production database/installer gates remain disabled.

## 0.1.202 — 2026-11-24

- Added fixed, non-secret initdb substage diagnostics to the disposable packaged migration experiment after Windows CI failed before migration. Production initialization and migration remain disabled.

## 0.1.201 — 2026-11-24

- Added a disposable Windows CI experiment that uses the extracted archive Prisma tool and PostgreSQL to deploy migrations twice under a distinct synthetic login/effective schema owner, then verifies migration count and object ownership. Production bootstrap, migration and installer remain disabled.

## 0.1.200 — 2026-11-24

- Added isolated, pinned Prisma migration tooling staging and required it in the offline payload. The staging and extraction tests validate CLI version, Windows schema engine and schema without executing migrations. Production migration, bootstrap and installation remain disabled.

## 0.1.199 — 2026-11-24

- Added a disposable Windows CI experiment assembling real Node, API/Worker, Next.js, service hosts, PostgreSQL and deployment scripts into an archive, checking extraction and manifest while confirming installation remains disabled. No release or installable artifact is produced.

## 0.1.198 — 2026-11-24

- Fixed staging and package validation for the actual monorepo Next.js standalone layout, retaining flat layout support and rejecting ambiguity. The Web service now loads its built standalone configuration so API rewrites and disabled powered-by headers are preserved. Added synthetic and real-build Windows tests.
- A same-user synthetic child-handle attack succeeded in CI; inherited stdin remains experimental and production initialization and installation remain disabled.

## 0.1.197 — 2026-11-24

- Added an isolated Windows adversarial diagnostic for same-user duplication of a synthetic child stdin handle. Interception fails the probe; the model does not establish the behavior of PostgreSQL restricted children. Production database and installer gates remain closed.

## 0.1.196 — 2026-11-24

- Closed a no-bootstrap orchestration path that could act on an unverified PostgreSQL cluster; offline installation now stops before staging while initialization and ownership gates remain unresolved. Read-only WhatIf and archive inspection remain available. Added fail-closed regressions.

## 0.1.195 — 2026-11-24

- Bounded disposable PostgreSQL authentication-test output handling and avoid waiting indefinitely for EOF from inherited pg_ctl descendant handles. Production gates remain disabled.

## 0.1.194 — 2026-11-24

- Extended disposable real-PostgreSQL stdin experiment to check successful and rejected SCRAM logins on loopback and added a synthetic restricted-re-exec-error regression. These tests do not establish safe production handle custody or Windows Server acceptance.

## 0.1.193 — 2026-11-24

- Updated disposable stdin experiment to exercise PostgreSQL simple_prompt stdin fallback with process-local `OSTYPE=msys`. Production gates remain closed; this does not bypass or prove restricted-token re-execution.

## 0.1.192 — 2026-11-24

- Added isolated, synthetic-only PostgreSQL initdb anonymous-stdin experiment using `--pwprompt`, with inherited re-exec environment sanitized, output suppressed and timeout tests. It is not connected to production and does not establish security against same-user handle attacks.

## 0.1.191 — 2026-11-24

- Split pipe client verification into fixed query-failure and PID-mismatch categories, and made the synthetic wrong-client test require the PID-mismatch guard. No credential is sent on either failure.

## 0.1.190 — 2026-11-24

- Removed unsupported extra READ_CONTROL bit from experimental CreateNamedPipe open mode after hosted Windows reported error 87. The explicit protected user-SID ACL and subsequent handle inspection and exact-client-PID check remain mandatory.

## 0.1.189 — 2026-11-24

- Narrowed experimental pipe creation diagnostics to a fixed whitelist of exception categories and selected OS error codes, without exposing exception messages, pipe names or secret values.

## 0.1.188 — 2026-11-24

- Added fixed, non-secret pipe creation substage diagnostics after CI 45391948797 failed at pipe creation before starting a child. Exact ACL and PID checks remain mandatory; production PostgreSQL initialization remains disabled.

## 0.1.187 — 2026-11-24

- Investigated Windows PostgreSQL pipe-open permission failure: .NET CurrentUserOnly derives the pipe ACL from the token owner, which can be the Administrators group that PostgreSQL deliberately disables in its restricted token. The experimental pipe now uses an explicit protected single-ACE ACL for the token user SID and verifies it by handle. The exact-client-PID check remains in force; no production fallback or PostgreSQL privilege bypass has been added. Synthetic and real Windows CI required; production initialization/bootstrap/migration remain disabled.
- This is not a complete installer or clean Windows Server acceptance.

## 0.1.186 — 2026-11-24

- Hardened the offline installer foundation against archive substitution: SHA-256 validation, ZIP entry inspection, manifest reading and extraction now all use a single retained read-only file handle rather than reopening a path after validation. Added Windows tests for denied writes/renames and handle-based verification independent of the original path. Exact-head CI and independent security review required; this is not a completed installer.
- Hosted real Windows PostgreSQL experiment run 45388522058 on 0.1.185 failed with permission denied opening the named pipe before any secret was sent. The restricted-token/pipe-client issue remains open; production initialization/bootstrap/migration remain disabled. No Windows Server VM acceptance or installer artifact.

## 0.1.185 — 2026-11-24

- Hosted run 45387588398 on 0.1.184 passed reproducible offline archive fixture tests, six actual self-contained Windows executable publications, existing Windows validation and Linux Node 26/PostgreSQL 18; real Windows initdb failed opening the protected named pipe before any secret was sent. Added fixed error-type subcategories without logging child output or secrets. Exact-head CI required.
- PostgreSQL restricted-token execution and same-user pipe client authentication remain unresolved; no production initialization/bootstrap/migration, signed installer or clean Windows Server acceptance is claimed.

## 0.1.184 — 2026-11-24

- Made offline ZIP generation reproducible for identical input files on the same .NET toolchain by using ordinal path ordering, normalized ZIP timestamps/attributes and a manifest without wall-clock build time. Added repeated-build and changed-content digest regressions. Empty directories are omitted. Exact-head Windows CI required; this is not yet a full assembler or signed installer.
- Hosted real Windows PostgreSQL experiment run 45386888172 on 0.1.183 failed opening the named-pipe password path before any secret was sent. The PostgreSQL process re-executes with a restricted token; do not bypass it or weaken client authentication. Production initialization/bootstrap/migration remain disabled pending secure solution and acceptance.

## 0.1.183 — 2026-11-24

- Hosted Windows real initdb run 45386231171 for 0.1.182 exited before connecting to the experimental pipe. Added fixed, whitelisted early-failure categories; child output, paths and secrets remain suppressed. PostgreSQL source review also shows Windows initdb re-executes itself with a restricted token, so the synthetic direct-child PID assumption needs careful redesign rather than relaxed authentication. Production initialization/bootstrap/migration remain disabled. Exact-head CI required.
- Hosted six-executable publication and Linux validation passed; this does not create an installer or prove Windows Server acceptance.

## 0.1.182 — 2026-11-24

- Hosted run 45385493840 on 0.1.181 passed Windows self-contained publication of all six hosts/helpers, Windows existing policy/runtime tests and Linux Node 26/PostgreSQL 18 validation; the independent real Windows PostgreSQL initdb pipe experiment failed with a generic error. Added bounded operation-stage/exit-code diagnostics without child output, paths or secrets to identify the failure on exact-head CI. No production initialization or bootstrap is enabled.
- The successful host publication is not an assembled/signed installer, a five-service installation, or Windows Server acceptance. No installer has been built.

## 0.1.181 — 2026-11-24

- Added an isolated Windows CI experiment that downloads and SHA-256-verifies the pinned PostgreSQL 18.7 binary archive and exercises real `initdb` with a synthetic password over the experimental pipe; no service is started and production initialization remains disabled. Exact-head result and actual Windows Server security/installation acceptance remain pending.
- Added the DPAPI helper to the self-contained host publication plan and offline payload prerequisites; packaging now rejects missing service-provisioning and installer scripts independently. Added a hosted Windows job to actually publish the six executables and verify overwrite protection. No discovery, credential persistence or service identity fallback is enabled.
- This is an incremental test/build foundation, not a complete offline package, signed installer, PostgreSQL bootstrap, or clean-VM acceptance. Hosted CI run 45382731557 on 0.1.180 passed Linux and Windows synthetic tests.

## 0.1.180 — 2026-11-24

- Security correction: the prior PostgreSQL cluster initializer created a temporary plaintext password file even with a restricted ACL, violating the owner prohibition. Disabled initialization before any filesystem/SCM/database mutation; retained read-only WhatIf and added a regression for this gate. Existing bootstrap and migration remain disabled.
- Added an isolated experimental current-user named-pipe credential transport and synthetic fake-initdb tests for process arguments, suppressed child output, invalid password, timeout, and rejecting another same-user connecting process by PID. The candidate is deliberately not integrated with initialization or deployment. Real PostgreSQL on Windows, logging/custody review, unauthorized-user access, failure/crash behavior and supported Windows Server acceptance are still required. No installer.
- Exact-head hosted CI run 45378870531 for 0.1.179 passed Linux Node 26/PostgreSQL 18 and full Windows validation; it is not clean-VM acceptance. Exact-head CI for this revision is pending.

## 0.1.179 — 2026-11-24

- Hosted CI run 45377990138 on 0.1.178 passed Linux Node 26/PostgreSQL 18 and full Windows validation including the new ancestor-junction rejection. This does not establish clean Windows Server/security acceptance.
- Improved Vault failure handling: post-create verification failures invoke identity-checked rollback, and a newly created Vault retains DELETE access so rollback uses its original exclusive handle instead of reopening it. Rollback remains best effort and leaves objects when identity cannot be proven. Exact-head Windows CI and fault-injection/race tests are required. Database bootstrap remains disabled; no installer has been produced.

## 0.1.178 — 2026-11-24

- Windows CI run 45376861959 on 0.1.177 passed Linux Node 26/PostgreSQL 18 and the full Windows hosted validation, including elevated-admin Vault provision/verify/retry and independent protected ACL fixtures. This is not Windows Server acceptance or a release.
- Hardened the Vault provisioner to open and retain each ProgramData ancestor relative to its parent, rejecting reparse points and volume transitions; leaf privilege handling is no longer selected merely by an ancestor name. Production orchestration no longer passes mutable ProgramData environment data as a helper override. Added an intermediate junction fixture. Exact-head Windows CI and independent security review remain necessary. No installer; PostgreSQL bootstrap remains disabled.

## 0.1.177 — 2026-11-24

- Windows run 45376364739 on 0.1.176 passed elevated non-SYSTEM Vault fresh provision, verification and retry; independent SYSTEM ACL fixture reported an owner mismatch. Compare owner using the ACL API directly as a SecurityIdentifier instead of converting its displayed account name; if still failing, report only a bounded owner category. The owner mismatch remains unverified until exact-head CI, and no owner/ACL policy was changed. Linux Node 26/PostgreSQL 18 passed. No installer.

## 0.1.176 — 2026-11-24

- Windows run 45375850378 showed the elevated admin could provision and verify a Vault but repeat provisioning failed opening the protected Vault with Win32 access denied. Reduced parent-handle access to the exact child-creation right needed at each level; removed unnecessary FILE_DELETE_CHILD and unrelated add-subdirectory rights on the Vault. ACL/owner checks remain unchanged. Exact-head Windows CI and independent security/Windows Server acceptance remain required. Linux Node 26/PostgreSQL 18 passed. No installer.

## 0.1.175 — 2026-11-24

- Windows run 45375347730 compiled the Vault helper but the independent elevated-admin provision/verify/retry smoke failed with a generic path error. Added safe fixed-component/numeric Windows error diagnostics and attempt numbering; no ACL, owner or security checks were relaxed. Linux Node 26/PostgreSQL 18 passed. Exact-head CI and Windows Server/security acceptance remain pending; no installer exists.

## 0.1.174 — 2026-11-24

- Windows run 45374694960 on 0.1.173 compiled the Vault helper and moved past fresh provisioning, but the prior test attempted to read the protected lock file as the interactive admin and got access denied. Added an explicit elevated non-SYSTEM provision/verify/retry smoke test and isolated LocalSystem-only CI fixtures for independent exact ACL and adversarial inspection; SYSTEM is an ACL principal only for fixture tests and is not a production runtime fallback. Added deterministic test parent ACL and SID translation. Exact-head Windows CI remains necessary.
- Privilege scope, parent trust, race/rollback, service-identity operation and clean Windows Server acceptance still require independent review/testing; bootstrap is disabled and no installer exists. Linux Node 26/PostgreSQL 18 passed that run.

## 0.1.173 — 2026-11-24

- Candidate fix for Windows Vault owner error 1307: the dedicated elevated provisioning process temporarily enables backup and restore privileges only around native opens/CREATE_NEW for fixed Vault and lock leaves, then restores their prior state. Both privileges must be assigned; no alternate owner or broader ACL fallback. Existing object verification remains mandatory. Requires exact-head Windows compilation/CI and independent security, race and Windows Server acceptance; not a release claim.
- Exact-head Windows run 45372992938 on 0.1.172 passed the orchestration SID regression, then failed fresh Vault provisioning with error 1307; Linux/Node 26/PostgreSQL 18 passed. Secure PostgreSQL first-install bootstrap and test installer remain incomplete.

## 0.1.172 — 2026-11-24

- Windows run 45372539798 found a synthetic invalid service SID was accepted by the orchestration regression. Explicitly require five ASCII decimal 32-bit unsigned SID components in the orchestrator and Vault helper; test now identifies which synthetic SID was accepted if this still fails. Exact-head Windows CI remains required.
- Linux Node 26/PostgreSQL 18 passed in that run. Vault owner assignment (error 1307), security review, PostgreSQL bootstrap and installer remain open.

## 0.1.171 — 2026-11-24

- Run 45372111100 (0.1.170) passed Linux/Node 26/PostgreSQL 18 but failed the Windows five-service orchestration policy test after new SID/WhatIf cases were added. Emit the synthetic test failure as an Actions annotation to diagnose it when log download is unavailable. No Windows acceptance or installer is claimed. Vault owner error 1307 and secure bootstrap remain unresolved.

## 0.1.170 — 2026-11-24

- Fixed the orchestrator to accept the actual five-subauthority Windows service SID shape and reject malformed or out-of-range SIDs before helper launch. Added provision/verify `-WhatIf` regression cases for valid and invalid SIDs; Windows CI must confirm them.
- Run 45371445342 identified the remaining Vault fresh-creation failure as Windows error 1307 (`ERROR_INVALID_OWNER`) at creation: the elevated token cannot assign the requested service SID as owner without appropriate privilege handling. Do not weaken the two-ACE ACL or replace the service SID owner; narrowly scoped privilege handling needs implementation, security review, and adversarial Windows testing. PostgreSQL bootstrap remains disabled; no test installer exists.

## 0.1.169 — 2026-11-24

- Add fixed-stage and numeric OS error diagnostics for unexpected Vault provisioning failures without exposing paths, SIDs, ACLs or secrets. Windows run 45369417895 on 0.1.168 still failed fresh provisioning; the previous access change was not sufficient. Windows exact-head CI and clean Windows Server acceptance remain required. PostgreSQL bootstrap stays disabled; no installer has been produced.

## 0.1.168 — 2026-11-24

- The Windows Vault test in run 45368923642 failed on fresh provisioning with generic `provisioning-failed`. Corrected a candidate cause: provisioning parent directory handles lacked `FILE_ADD_SUBDIRECTORY`; verify-only does not request it. This change is not a demonstrated fix until Windows CI and adversarial acceptance pass.
- Linux Node 26/PostgreSQL 18 validation passed in that run; Windows safety, staging, packaging and helper compilation passed before the Vault failure. Database bootstrap remains disabled and no installer is available.

## 0.1.167 — 2026-11-24

- Windows CI run 45368459750 for 0.1.166 passed orchestration, PostgreSQL safety, staging, offline archive tests and keyring helper compilation, but failed the Credential Vault provisioning policy test. The CI log download host is inaccessible in this sandbox. Emit the test exception as a GitHub Actions error annotation so its non-secret test failure is available via the GitHub API; no production behavior or security policy is changed.
- Linux Node 26/PostgreSQL 18 job passed in that run. Vault provisioning, first-install database lifecycle, installer and clean Windows Server acceptance remain incomplete.

## 0.1.166 — 2026-11-24

- Security correction: the 0.1.165 PostgreSQL bootstrap prototype embedded role passwords in SQL passed to `psql -c` (process arguments) and could reset existing roles or adopt an unknown database. The earlier claim of no argv secrets was incorrect. Removed the unsafe executable prototype and made bootstrap and migration fail closed; `-WhatIf` remains non-mutating. Orchestration rejects requested bootstrap before changing services. Secure transport, ownership verification and end-to-end database setup remain unimplemented.
- Added a Windows regression for the fail-closed behavior and updated the offline-package and orchestration test fixtures. Corrected the service SID shape, native `FILE_CREATE` disposition and overbroad ProgramData write-mask check in the unverified Vault prototype. These changes and fixtures do not produce a real installer or prove Vault provisioning works.
- Local Node 22: typecheck, build and unit test command passed using a dummy Prisma schema-engine path solely for client generation; DB/Windows integration tests were skipped or not run. This does not validate Prisma migrations or supported Node 26/Windows deployment. Exact-head hosted CI and clean Windows Server acceptance remain required.

## 0.1.165 — 2026-11-24

### Credential Vault provisioner (Batch A foundation)
- Added `VaultProvisioner` mode to `apps/api/windows/keyring-storage-helper` (`--provision-vault` / `--verify-vault`) with explicit `--service-sid` input and optional `--program-data-root` for controlled test use. The provisioner validates elevation, canonical `S-1-5-80-*` service SID format, ProgramData/EnterpriseIT/CredentialVault path safety (reparse/type/volume checks), and exact owner/protected DACL policy for Vault leaf objects (`O:<API_SID>D:P(A;;FA;;;<API_SID>)(A;;FA;;;SY)`).
- Provisioner creates EnterpriseIT and CredentialVault directories and `keyring.lock` with handle-relative native creation and explicit SDDL at creation time; it is idempotent for an already-correct store and fails closed on unexpected owner/DACL/type/reparse/volume/collision. It performs post-create handle-based verification and rolls back only objects created by the exact invocation when identity can be proven.
- Parent trust policy: ProgramData is treated as OS-managed and rejected on broad write ACEs for Everyone/Anonymous/Authenticated Users/Users; EnterpriseIT requires protected DACL with Administrators/SYSTEM FullControl OICI ACEs only. This is a conservative baseline and requires supported Windows Server acceptance.
- Wired orchestrator: payload preflight no longer demands a pre-existing Vault leaf on fresh install; it still rejects reparse/type path anomalies. After API SCM provisioning returns a validated service SID, orchestrator invokes the elevated Vault provisioner; it performs verify-only immediately before API start. Provisioning/verify failures block API startup. `-WhatIf` does not invoke the helper or mutate.
- Added `scripts/windows/test-credential-vault-provisioning.ps1` covering fresh create, idempotent rerun, missing-store verify-only failure, invalid SID rejection, wrong-ACL fail-closed/no-mutation, Vault junction rejection, lock-directory collision rejection, invalid args, and orchestrator WhatIf/policy checks. Added CI step in Windows validation.
- Staging/orchestration now include `CredentialVault.KeyringStorageHelper.exe`; staging test and orchestration tests updated.

### PostgreSQL bootstrap and migration (Batch B foundation)
- Added `scripts/windows/bootstrap-postgresql-database.ps1`: idempotent role/database bootstrap using SecureString passwords and process-scoped PGPASSWORD for child psql processes (no argv/persistent env). Creates/validates schema owner (NOLOGIN), migration role (LOGIN NOINHERIT, NOCREATEDB/NOCREATEROLE/NOSUPERUSER, SET ROLE to owner), API runtime role, Worker runtime role, database ownership, schema grants, and existing-object runtime grants aligned with the runtime privilege matrix.
- Added `scripts/windows/invoke-postgresql-migrations.ps1`: runs `prisma migrate deploy` using the migration identity with process-scoped DATABASE_URL, then reapplies runtime grants. Migration failure throws and prevents dependent service startup by caller contract.
- Orchestrator accepts optional bootstrap parameters and, when provided, runs bootstrap and migration after PostgreSQL readiness and before Vault verify-only/API start. Migration/bootstrap failure prevents API/Worker/Web/Edge startup.

### Offline payload / installer (Batch C foundation)
- Added `CredentialVault.KeyringStorageHelper.exe`, bootstrap and migration scripts to offline payload required component list. Updated staging to publish the keyring helper.

### Validation / evidence
- This Linux sandbox cannot compile/run Windows .NET or PowerShell Windows-specific tests. No Windows CI run was executed from this session for this commit. Changes must be validated by exact-head Windows CI and clean supported Windows Server VM acceptance before any completion claim.
- Linux Node/TS lint/typecheck/test/build should be run before push; record results in commit/PR evidence.

## 0.1.164 — Comprehensive implementation-agent handoff

- Added `AGENT_HANDOFF.md`, a self-contained takeover brief consolidating product scope, repository/branch snapshot, owner constraints, five-service topology, security decisions, Credential Vault/DPAPI/recovery state, PostgreSQL role/migration gaps, offline payload/installer gaps, CI evidence, acceptance gates and an execution sequence.
- Explicitly distinguishes implemented source, hosted CI evidence, design-only work and uncompleted Windows Server/production acceptance. It instructs the next agent not to merge PRs #5–#9 without owner authorization and forbids MikroTik/router/firewall/NAT/DST-NAT/port-mapping changes.
- Updated HANDOVER.md with a prominent pointer to the agent brief. No application runtime behavior changed. Root package and lockfile versions synchronized at 0.1.164.
- This documentation handoff does not complete the installer, Credential Vault provisioner, PostgreSQL first-install lifecycle, offline payload or production acceptance.
## 0.1.163 — Extend Credential Vault path preflight to ProgramData

- Extended the Windows orchestration preflight to inspect the OS ProgramData root itself, in addition to EnterpriseIT, CredentialVault and keyring.lock. Every component must have the expected directory/file type and must not be a reparse point.
- Added a Windows regression fixture that places a valid-looking ProgramData tree behind a directory junction and proves the preflight rejects it before service provisioning.
- This remains a path-shape guard, not native owner/DACL verification or an elevated Vault provisioner. The keyring helper remains fail-closed; Credential Vault provisioning and clean Windows Server acceptance remain open.

## 0.1.162 — Specify fail-closed Credential Vault provisioning contract

- Added a dedicated Windows provisioning design that records the exact runtime-helper owner/DACL contract, required service-creation ordering, native create-new semantics, retained-handle validation, parent trust checks, rollback limits, and acceptance tests.
- The design explicitly records that elevated Vault provisioning and parent-chain security validation are not implemented. Existing preflight remains a presence/reparse guard; no installer readiness or credential persistence claim is made.

## 0.1.161 — Exercise Credential Vault junction rejection in orchestration preflight

- Extended the Windows orchestration policy test with a real same-volume directory-junction fixture at the CredentialVault boundary.
- The test proves a reparse-point Vault directory is rejected before orchestration can provision or start services; the fixture is removed and the ordinary temporary directory is restored before subsequent checks.
- This is regression coverage for the existing fail-closed guard only. It does not provision the Vault, validate owner/DACL, or enable credential persistence. Exact-head Windows CI is required.

## 0.1.160 — Isolate Credential Vault preflight fixtures from host ProgramData

- Corrected the 0.1.159 orchestration regression test so its ProgramData root is injected from a temporary fixture directory instead of writing under the Windows runner's real `%ProgramData%`.
- The orchestration functions now accept an optional ProgramDataRoot on their test plan; production invocation continues to use the OS ProgramData location.
- No production behavior or security boundary is relaxed. Exact-head CI must validate the correction.

## 0.1.159 — Gate Windows service orchestration on pre-provisioned Credential Vault infrastructure

- The five-service orchestration preflight now requires the fixed `%ProgramData%\\EnterpriseIT\\CredentialVault\\keyring.lock` file and CredentialVault directory to exist before any service provisioning begins.
- The preflight rejects reparse-point components in the EnterpriseIT/Vault/lock path and has a regression test proving a missing lock file blocks orchestration.
- This is a fail-closed readiness gate only. It does not create the directory or lock file, validate the exact owner/DACL through retained handles, or complete installer provisioning. The keyring helper remains authoritative for handle-based owner/DACL validation and will still reject an incorrectly provisioned store.
- Exact-head Windows and platform CI must pass. No keyring adapter registration, credential persistence, Installer/Release, or production acceptance is claimed.

## 0.1.158 — Isolate Worker queue fixtures from restricted runtime identity

- Worker queue integration now creates/deletes branch and DiscoveryRun fixtures through WORKER_TEST_FIXTURE_DATABASE_URL. Actual claim, lease, heartbeat, recovery, completion, cancellation and retry code continues to use the restricted Worker runtime Prisma client.
- This keeps the Worker runtime role at SELECT/UPDATE on discovery_runs and removes its previous test-only need for branch access or queue INSERT/DELETE.
- Exact-head CI must execute both API and Worker suites end-to-end under their restricted logins.

## 0.1.157 — Route API audit verification through the admin fixture

- Corrected the API identity integration test so audit-event lookup and append-only mutation assertions use the dedicated API_TEST_FIXTURE_DATABASE_URL connection, not the restricted API runtime Prisma client.
- API setup, authenticated routes and ordinary persistence remain on the restricted API login. This preserves INSERT-only audit permissions while keeping read/tamper verification separate.
- Exact-head CI must verify both API and Worker integration suites; no runtime grant is broadened.

## 0.1.156 — Complete restricted audit and observation integration coverage

- Routed authentication audit writes through the INSERT-only append helper, including login, password-change and logout/lockout event paths. This closes remaining Prisma create() calls that require SELECT on audit_events.
- Inventory integration now uses the separate administrator fixture connection only to attempt a prohibited port-observation update and verify the append-only trigger. API runtime remains SELECT/INSERT only on port_observations; no UPDATE grant is added.
- Exact-head CI must now verify the full API integration suite and then the Worker queue suite under their respective restricted identities.

## 0.1.155 — Preserve INSERT-only audit access for API runtime

- Replaced Prisma AuditEvent create() calls in API branch, inventory and user routes with a parameterized INSERT-only audit writer. Prisma create() emits INSERT ... RETURNING and PostgreSQL requires SELECT on returned columns; restricted CI proved this caused API mutations to fail with permission denied on audit_events.
- The new writer inserts an application-generated UUID and typed values without RETURNING, preserving append-only triggers and the intended API INSERT-only privilege. Audit read/tamper assertions continue through the separate administrator fixture connection.
- This is based on exact-head PostgreSQL 18 integration evidence; rerun CI must verify API and Worker restricted suites end-to-end. No SELECT grant is added to the API role.

## 0.1.154 — Build database workspace before restricted integration tests

- Fixed the restricted-runtime CI sequence: Prisma client generation alone does not emit the @platform/database workspace entrypoint declared by its exports (dist/index.js). The privilege test script now builds the database workspace before invoking API and Worker integration suites.
- This addresses the package-resolution failure observed in exact-head CI for 0.1.153; it does not change runtime grants or database behavior. The rerun must confirm both restricted suites actually execute.

## 0.1.153 — Run API and Worker Prisma suites with restricted runtime identities

- API database integration tests use the API runtime login for route, session, branch and user operations; a separate disposable administrator fixture connection is reserved for audit-event verification and append-only trigger assertions.
- Worker queue integration tests use the restricted Worker login for claim, lease, heartbeat, retry, cancellation and recovery operations. A separate disposable fixture connection creates and removes fixture branches and queue rows.
- The runtime privilege CI script executes both workspace integration suites before dropping its disposable roles. It does not broaden API or Worker grants or change production role provisioning.
- Exact-head CI is required to establish the integration result. This does not establish production credential transport, Windows Server virtual-account acceptance, or installer readiness.

## 0.1.152 — Add PostgreSQL API/Worker runtime privilege integration checks

- Added a disposable PostgreSQL 18 CI test that creates temporary API and Worker login roles and applies the source-derived candidate privilege matrix.
- Verifies API positive table access, append-only audit/observation restrictions, denied recovery-code and migration-metadata access, and denied DDL/TRUNCATE/database creation.
- Verifies Worker access is limited to SELECT/UPDATE on discovery_runs and rejects access to unrelated application tables, INSERT/DELETE, migration metadata and administrative DDL.
- Test roles are disposable, removed on exit, and are not production provisioning. API Prisma route/integration tests under the restricted login, interrupted migration retry, secure Windows credential transport, and Windows Server acceptance remain open.

## 0.1.151 — Record successful Prisma migration-owner CI proof

- Recorded the exact-head PostgreSQL 18 / Prisma 7.10.1 CI result: the migration login remained `session_user=platform_migrator`, the effective role was `current_user=platform_schema_owner`, database and migration-created object ownership matched the schema owner, and a second `prisma migrate deploy` succeeded.
- The Push validation run (45148082967) and PR validation run (45148094311) completed successfully for the migration ownership experiment and the other executed validation jobs.
- This is a disposable CI proof of the role-default mechanism only. It does not implement production role provisioning, secure migration-secret transport, API/Worker least-privilege grants, interruption recovery, or clean Windows Server acceptance.

## 0.1.150 — Provide disposable PostgreSQL admin credential to CI experiment

- Fixed the CI test-step environment so the migration ownership experiment receives the disposable PostgreSQL service administrator password required for role/database setup.
- The previous run stopped before the identity/ownership assertions because PGPASSWORD was not exposed to the script. This change addresses only test harness configuration; Prisma ownership semantics remain unverified pending rerun.

## 0.1.149 — Correct migration identity assertion in CI harness

- Corrected the SQL delimiter expression in the disposable Prisma migration ownership experiment so PostgreSQL concatenates the login and effective role identities without treating the delimiter as an identifier.
- The exact-head PostgreSQL 18 / Prisma 7.10.1 experiment remains pending CI execution; no production role bootstrap or installer behavior is claimed.

## 0.1.148 — Add Prisma migration ownership integration experiment

- Added a disposable PostgreSQL 18 CI experiment for the repository-pinned Prisma 7.10.1 migration engine.
- The experiment separates the migration login from a NOLOGIN schema owner, checks session_user/current_user, applies migrations twice, and asserts ownership of the database and created objects.
- The result is pending exact-head CI; no production role bootstrap, secret transport, runtime grants, migration runner integration, or installer behavior is claimed.

## 0.1.147 — Inventory PostgreSQL runtime privileges and migration ownership gate

- Derived a provisional API privilege matrix from current route/security Prisma operations and raw SQL, including explicit append-only restrictions for audit events and port observations.
- Confirmed the current Worker source only performs lease recovery/claim operations on `discovery_runs`; discovery handlers remain disabled and the source allow-list is empty. Documented the narrow current Worker privilege candidate.
- Recorded the unresolved Prisma Migrate object-ownership/current_user contract and required exact-engine PostgreSQL 18 experiments before implementing role bootstrap or grant SQL.
- Documentation/design only. No database roles, grants, migration runner, secret transport, runtime behavior or installer flow changed. No PR merge, Installer/Release, or MikroTik/NAT/port-mapping changes.

## 0.1.146 — Specify PostgreSQL first-install and migration contract

- Added a verified implementation inventory and security contract for first-install PostgreSQL bootstrap, role separation, least-privilege runtime grants, migration execution, secret transport, retry semantics and Windows Server acceptance.
- Recorded the integration gap: cluster initialization, application role/database creation and Prisma migration execution are not connected to the five-service orchestrator; API/Worker DPAPI configuration currently accepts externally supplied database URLs.
- Documentation/design only. No runtime behavior, database schema, role grants, credential transport or installer flow changed.
- Existing-cluster protection, secret lifecycle, role isolation, migration interruption/retry, clean-VM acceptance and installer integration remain open. No PR merge, Installer/Release, or MikroTik/NAT/port-mapping changes.

## 0.1.145 — Record keyring parent ACL acceptance boundary

- Revalidated exact-head Push validation and PR validation for commit 603af65f33cbac61083c81e7ae6c7a72c7368e20; both workflows completed successfully, including the Windows API runtime smoke job. This is hosted CI evidence, not supported Windows Server acceptance.
- Reviewed the retained directory-chain implementation against the installer/provisioning scripts. ProgramData, EnterpriseIT and CredentialVault are opened and checked for directory type, reparse status and volume identity, but parent owner/DACL policy is not verified.
- Recorded that ProgramData requires an OS-managed trust baseline distinct from the strict CredentialVault leaf policy, and EnterpriseIT/CredentialVault plus keyring.lock need explicit installer provisioning before parent ACL verification can be safely implemented.
- Crash-orphan enumeration, failure injection, adversarial namespace tests, positive provisioned-Service-SID acceptance and Windows Server runtime acceptance remain open. Node keyring adapter remains unregistered; production credential persistence remains disabled.
- No PR merge, Installer/Release, or MikroTik/NAT/port-mapping changes.

## 0.1.144 — Request directory delete-child access for keyring replacement

- Added FILE_DELETE_CHILD to the retained CredentialVault directory handle access mask alongside FILE_ADD_FILE, so handle-relative FileRenameInformation replacement has the required destination-directory access.
- Documented the access-mask requirement. Runtime replacement on supported Windows Server versions remains an acceptance gate.
- F-01 through F-05 remain open as documented; Node adapter remains unregistered.
- No Installer/Release, PR merge, or MikroTik/NAT/port-mapping changes.

## 0.1.143 — Close pre-rename keyring temp cleanup gap

- Replaced the owning FileStream in the keyring temp-write path with RandomAccess on the exact SafeFileHandle, so cleanup retains the file handle through failure handling.
- Pre-rename failures after temp creation now attempt handle-based FileDispositionInformation, including ACL/type validation and setup failures before any write.
- Successful rename closes the source handle before destination read-back, then validates file identity, ACL, type, length and bytes.
- Corrected documentation: crash-orphan temp enumeration/cleanup is not implemented; F-03/F-04/F-05 remain open pending Windows Server and adversarial acceptance.
- No credential persistence activation, PR merge, Installer/Release, or MikroTik/NAT/port-mapping change.

## 0.1.142 — Perform keyring replacement and cleanup relative to the Vault handle

- Replaced path-based `MoveFileEx`, post-commit path reopen, `File.Exists` and `File.Delete` operations with `NtSetInformationFile` handle-relative rename and disposition operations rooted at the retained CredentialVault directory handle.
- Opened the Vault directory handle with FILE_ADD_FILE for relative temp creation and rename. Temporary files are opened with DELETE access; the helper captures file identity before rename, closes the source handle, reopens the committed registry relative to the Vault handle, and requires the destination identity to match before read-back verification.
- Corrected lock contention handling to retry native sharing/lock violation codes while keeping missing pre-provisioned lock files fail-closed. Missing registry remains a first-run absence only for Win32 error 2.
- This removes known path-based leaf mutation calls but does not constitute Windows security acceptance. Provisioned-Service-SID, adversarial namespace, crash/restart and target Windows Server tests remain mandatory; Node storage adapter remains unregistered.

## 0.1.141 — Handle missing keyring registry through native open semantics

- Corrected the first-run/missing-registry path: `OpenVaultFile` reports NTSTATUS failures as `Win32Exception`, not an invalid handle. The helper now maps only Win32 file-not-found (error 2) to an absent registry for reads and existence checks.
- All other open errors remain fail-closed; ACL and reparse validation still run on every successfully opened leaf.
- Atomic replacement and orphan cleanup remain path-based acceptance blockers. No production credential persistence, PR merge, or MikroTik/NAT/port-mapping change.

## 0.1.140 — Open keyring leaf files relative to the retained Vault handle

- Changed lock-file acquisition, registry reads, existing-registry checks and temporary-file creation to open fixed leaf names relative to the retained CredentialVault directory handle using NtCreateFile with a root directory handle.
- The relative-open helper rejects directory and reparse-point leaves and verifies that the opened file exposes stable file identity metadata before returning its handle.
- Atomic replacement and orphan cleanup still use path-based operations and remain explicit acceptance blockers; this is a partial leaf-operation hardening increment, not closure of F-03/F-04.
- Exact-head Windows CI and provisioned-Service-SID/adversarial namespace acceptance are required. No production credential persistence enabled; no PR merged; no MikroTik/NAT/port-mapping changes.

## 0.1.139 — Correct keyring directory-chain implementation contract

- Corrected the XML summary on `WindowsDirectoryHandleChain`: the chain is now retained by the keyring helper for the full transaction, rather than being described as not wired into storage.
- The comment explicitly preserves the remaining limitation: lock, registry, temporary-file, replacement and cleanup leaf operations are still path-based pending Windows acceptance.
- No runtime behavior or security boundary changed in this documentation-only correction.

## 0.1.138 — Restore and clarify keyring hardening review

- Restored the full Windows keyring hardening review and added an explicit implementation-status update for the partial parent-directory handle-chain mitigation in 0.1.137.
- No runtime behavior changed in this documentation correction.

## 0.1.137 — Pin the Windows keyring storage parent directory chain

- Wired the existing handle-relative ProgramData -> EnterpriseIT -> CredentialVault chain into the keyring helper transaction lifecycle.
- The helper now opens and retains the verified directory handles from BEGIN through process termination; the chain opens each child relative to its parent, rejects reparse points and volume changes, and denies delete sharing on the retained directory handles.
- Vault owner/DACL and reparse checks now run against the retained Vault handle rather than reopening the root directory by path. This reduces parent-directory rename/substitution risk during a helper session.
- Leaf lock/registry/temp-file operations remain path-based. Temporary-file cleanup still has a path-based check/delete race, atomic replacement is not handle-relative, and positive provisioned-Service-SID/adversarial Windows acceptance tests remain absent. The storage adapter stays unregistered and production credential persistence remains blocked.
- Exact-head Windows and platform CI required. No PR merged; no MikroTik, NAT, firewall or port-mapping changes.

## 0.1.136 — Connect Windows DPAPI protector to credential envelope v2

- Made `WindowsDpapiProtector` implement the v2 `LocalDataKeyProtector` contract, including the full credential context on Protect and Unprotect.
- Enforced exact Installation ID equality before any helper process can be spawned; a mismatched or missing context fails closed.
- Added an injectable process launcher boundary for deterministic tests and regression coverage proving both Protect and Unprotect reject mismatched installations without invoking the helper.
- Preserved the helper's dedicated-service-SID and machine-scope DPAPI enforcement. This is adapter integration only: no production composition registration, persistent credential storage, recovery utility, v1-to-v2 migration, or installer enrollment is enabled.
- Exact-head Linux and Windows CI are required. No PR merged; no MikroTik, NAT, firewall or port-mapping changes.

## 0.1.135 — Fix recovery-key metadata authentication and public-key typing

- Corrected Node.js KeyObject handling so RSA public-key objects are accepted without passing KeyObject through the incompatible createPublicKey overload; private KeyObjects are rejected.
- Bound the recovery key ID and SHA-256 digests of both DPAPI and RSA wrappers into AES-256-GCM AAD. Wrapper substitution or key-ID tampering now fails authentication on the normal service path.
- Added strict encoded-size bounds before base64 decoding and exact RSA-3072 wrapper length validation.
- Expanded regression tests for wrapper and recovery key ID substitution. This remains a crypto-core increment; no production DPAPI adapter, recovery utility, migration or production credential use is enabled.

## 0.1.134 — Add versioned dual-wrapper credential envelope core

- Added an isolated format-v2 AES-256-GCM envelope with a fresh per-secret DEK, local DPAPI-protector contract and independent RSA-3072 OAEP-SHA-256 recovery public-key wrapper.
- Added strict RSA key-size, key identifier, context, base64, ciphertext and DPAPI-blob bounds validation. Normal service decryption uses only the local protector and has no recovery private-key input.
- Added tests for local and independent RSA unwrap round trips, fresh key/nonce generation, context and ciphertext tampering, weak recovery keys and fail-closed local-protector errors. Format-v1 code remains unchanged.
- Crypto-core increment only: no production DPAPI adapter, recovery utility, persistence migration, v1-to-v2 migration, installer enrollment or production credential use is enabled.

## 0.1.133 — Define independent Windows credential recovery envelope

- Replaced the removable-media recovery proposal with the approved public-key recovery model: local service use remains DPAPI-protected, while recovery uses an independent RSA-3072 OAEP-SHA-256 key pair and AES-256-GCM authenticated encryption.
- Specified credential and installation context binding, key custody in an organization-managed password manager with MFA and independent encrypted backup, rotation/revocation, audit requirements and clean-host recovery acceptance gates.
- This is a design-only change. No recovery cryptographic provider, installer flow, PostgreSQL administrator credential persistence, or production recovery operation is implemented or enabled by this commit.

## 0.1.132 — Isolate PostgreSQL bootstrap guard fixtures

- Corrected the Windows bootstrap guard test to use a unique, test-owned versioned Program Files directory instead of the shared EnterpriseIT\1.2.3 path.
- The test now refuses an unexpected path collision and only removes directories it created, preventing it from overwriting or deleting PostgreSQL/runtime fixtures used by other Windows CI steps.
- No production bootstrap behavior changed. DPAPI administrator credential recovery, durable state transitions, role/database provisioning and installer/orchestrator integration remain open gates.

## 0.1.131 — PostgreSQL bootstrap workspace ACL hardening

- The PostgreSQL bootstrap now establishes and verifies a protected SYSTEM/Administrators DACL on the empty data directory before initdb writes cluster files.
- The temporary initdb password file is now created only inside a unique workspace whose protected DACL is applied and checked before the file exists; cleanup removes the workspace.
- Added Windows guard tests for read-only WhatIf, refusal to overwrite an existing cluster, preservation of non-empty data directories, and weak-password rejection.
- This closes the temporary-file ACL race but does not implement DPAPI-backed administrator credential recovery, a bootstrap state ledger, API/Worker role creation, or orchestration/installer integration. No clean-install acceptance is claimed.

## 0.1.130 — Preflight Edge certificate and listener before provisioning

- Added a read-only Edge preflight that verifies the host executable, assigned LAN address, unoccupied HTTPS port, machine certificate validity/private key, DNS name, Server Authentication EKU, trusted certificate chain, supported RSA key provider and private-key file.
- The five-service orchestrator now runs this preflight before PostgreSQL/API/Worker/Web provisioning, preventing a late Edge certificate or listener failure from leaving earlier services partially provisioned.
- Edge provisioning reuses the same validation contract immediately before applying service, ACL and configuration changes; added fact-driven Windows regression coverage for invalid certificate/key/listener states.
- Root package and lockfile versions advanced together. Hosted Windows CI is required; this is not full transactional rollback or clean Windows Server acceptance.

## 0.1.129 — Preflight complete service payload before provisioning

- Added a read-only orchestration preflight that verifies all five service hosts, Node.js, API/Worker/Web entry points, PostgreSQL binaries and initialized cluster files before any Windows service registration or ACL changes.
- The preflight also enforces PostgreSQL 18, loopback-only listener configuration and explicit IPv4/IPv6 remote rejection before provisioning begins.
- Added Windows regression coverage for a missing Edge host and an unsafe PostgreSQL authentication policy. Existing provisioning remains non-destructive; no service registrations or application data are removed by this preflight.
- Root package and lockfile versions advanced together. Exact-head Push and PR CI are required before accepting the change.

## 0.1.128 — Test rollback scope for Windows service orchestration

- Extracted the orchestration failure cleanup into a dedicated helper that stops only services started by the current invocation, in reverse startup order.
- Added a Windows policy regression test with a simulated stop failure to prove rollback continues, does not target pre-existing/unstarted services, and never removes service registrations or application data.
- Advanced root package and lockfile versions together. Exact-head CI is required; service provisioning and clean Windows Server acceptance remain separate gates.

## 0.1.127 — Remove duplicated installer validator tail

- Fixed the Windows installer PowerShell parser failure by removing a duplicated trailing fragment that had been appended after the installer entry point. The ZIP validation block itself remains intact, including reserved DOS device-name checks.
- Updated the offline installer test fixture package and manifest versions to 0.1.127.
- Exact-head Windows CI is required to validate parsing and all archive-validation cases. This does not create a signed installer or establish clean Windows Server installation acceptance.

## 0.1.124 — Correct installer validation workflow YAML

- Corrected the offline-installer test step in the Windows validation workflow. The previous commit inserted escaped newline characters literally, causing GitHub Actions to reject the workflow before jobs could start.
- This is a workflow-only correction; installer acceptance remains pending exact-head Push and PR CI.

## 0.1.123 — Harden installer parameter binding and capacity gate

- Made installation-only credentials and Edge settings optional at script binding time so the archive-validation functions can be dot-sourced and tested without interactive prompts; actual installation still rejects missing values before host changes.
- Added a Program Files capacity check for the full expanded archive plus the configured free-space reserve and explicitly loads the ZIP assembly used by the installer.
- Exact-head Windows CI remains required. No signed MSI/EXE or clean-server acceptance is claimed.

## 0.1.122 — Verified offline payload installation entry point

- Added a guarded Windows installer entry point that requires an independently supplied SHA-256 digest, validates ZIP entry paths and rejects duplicate names and symbolic-link entries before extraction.
- The installer verifies the extracted payload manifest and version, runs the read-only host preflight, promotes the payload into an immutable versioned Program Files directory, then invokes the existing five-service orchestration with separate SecureString database URLs and explicit Edge TLS settings.
- Added Windows tests for trusted-digest mismatch and ZIP path traversal rejection. CI is the acceptance gate; this is an unsigned PowerShell installer entry point, not a signed MSI/EXE or production release.

## 0.1.121 — Reject reparse points before offline payload copy

- Hardened offline archive preflight to inventory the source tree and reject junctions/symbolic links before recursive Copy-Item begins. This prevents packaging from following a reparse point outside the staged payload during the copy phase.
- Added a Windows junction regression test that verifies a source tree containing an external directory junction is rejected before archive creation.
- Root package.json and package-lock.json metadata are advanced together to 0.1.121, avoiding the prior parallel lockfile-bootstrap race where validation saw a stale root lock version.
- Exact-head Push and PR CI are required. This remains an integrity-checked archive, not a signed installer or Release.

## 0.1.120 — Correct offline archive fixture inventory expectation

- The archive integration fixture includes an empty Prisma migrations directory, which is intentionally not a file in the SHA-256 inventory. Corrected the post-extraction assertion to count required files plus the root package manifest, excluding that directory.
- The assertion now requires an exact file count instead of an imprecise lower bound. Exact-head Windows CI remains the acceptance gate.

## 0.1.119 — Correct PowerShell archive path preflight conditions

- Windows CI exposed PowerShell parameter binding in the offline archive packager: multiple Test-Path calls combined without grouping caused a duplicate LiteralPath binding.
- Grouped each Test-Path invocation explicitly and removed an unused archive-prefix variable. No packaging behavior or output format changed.
- Exact-head Push and PR Windows CI are required to validate the correction.

## 0.1.118 — Keep service-host promotion on the install volume

- Corrected Windows service-host staging so the promotion directory is created beneath the versioned Program Files install root, while publish output remains in the temporary build directory. This ensures final `File.Move` operations are same-volume even when the system temp directory is on another drive.
- Added a policy assertion that prevents reverting promotion staging to the system temp volume.
- Exact-head Windows CI is required; this does not claim a full transactional filesystem guarantee across power loss, nor create an installer or Release.

## 0.1.117 — Assemble immutable offline deployment archives

- Added a packaging step for a previously staged deployment tree. It requires the versioned Node.js runtime, API/Worker/Database outputs, Web standalone runtime, four Windows service hosts and pinned PostgreSQL binaries before packaging.
- The packager copies the staged tree into a temporary sibling directory, creates and verifies the SHA-256 payload manifest, creates a ZIP archive, and writes a separate SHA-256 checksum sidecar. Existing output files are never overwritten.
- Added Windows policy tests for dry-run behavior, required-component validation, archive checksum verification, post-extraction manifest verification and overwrite rejection.
- This produces an integrity-checked offline payload archive only. It does not create an installer, digitally sign the archive/manifest, provision services, or prove clean-machine installation. Exact-head Push and PR CI are required.

## 0.1.116 — Make production workspace packages relocatable

- Replaced npm's temporary-root workspace links with physical copies under the staged `node_modules/@platform` namespace before promotion. This prevents package resolution from depending on the disposable staging directory after promotion.
- Updated the Windows integration test to derive its immutable Program Files destination from the root package version instead of the stale hard-coded 0.1.113 path.
- Expanded the post-promotion smoke to resolve the database package from both API and Worker working directories and assert all three physical workspace package manifests exist.
- Exact-head Windows CI is required; this change is not accepted until both Push and PR validation pass. No installer or Release is created.

## 0.1.110 — Repair Windows validation workflow formatting

- Corrected the Windows validation workflow step introduced in v0.1.108: escaped backslash-n text was stored literally in the YAML instead of actual line breaks. The Node runtime policy test is now a normal standalone step, and the offline payload manifest integrity test follows it.
- Repaired the same literal escaped-newline formatting in the deployment decision record. This corrects workflow syntax; it does not establish that GitHub runners are available or that tests have passed.
- Root package and lockfile versions advanced to 0.1.110. No installer or Release is produced.

## 0.1.109 — Add offline payload integrity manifest

- Added a SHA-256 inventory manifest for versioned offline payloads, recording relative paths, byte sizes and hashes. Verification rejects modified, missing, unexpected and path-traversal entries.
- Reparse points are rejected so inventory cannot follow junctions or symbolic links outside the staged tree. Existing manifests cannot be overwritten.
- Added Windows PowerShell policy tests for valid inventory, tampering, unexpected files, version mismatch and unsafe paths.
- This is integrity metadata, not a complete offline installer or signed release. Exact-head CI must run before acceptance.

## 0.1.108 — Add immutable Node.js runtime staging

- Added an offline staging script for the exact Node.js 26 runtime supplied by the build environment. It validates the source executable/version, requires a versioned Program Files install root, copies the complete runtime directory (including adjacent runtime files), and verifies the staged executable reports the same exact version.
- The staging operation refuses to overwrite an existing immutable runtime directory and removes only its newly created incomplete destination if staging fails. It does not download packages, change firewall/router settings, or create an installer.
- Added Windows policy coverage for the Node 26 requirement and versioned destination, and wired it into Windows CI. Exact-head CI remains blocked until GitHub assigns hosted runners; this change is not yet validated on Windows.
- No installer or GitHub Release is produced.

## 0.1.107 — Fix Worker SCM smoke PID verification

- Corrected the Windows Worker SCM smoke to read the child PID from the Get-Process object's `Id` property. The prior `ProcessId` lookup resolved to zero, causing the post-stop check to query System Idle (PID 0) and report a false orphan.
- Added an explicit zero-PID guard. Production Worker service code and shutdown semantics are unchanged.
- Exact-head CI is required to verify the corrected SCM smoke. No installer or GitHub Release is produced.

## 0.1.106 — Fix Worker Windows SCM host activation

- Fixed the Worker hosted-service constructor visibility required by the default .NET dependency-injection activator. The previous internal constructor caused the Windows SCM process to terminate before starting its Node child.
- Root cause was confirmed from the hosted Windows Application/.NET Runtime event logs; this is a code fix, not a test-only workaround.
- Exact-head Windows SCM integration and full CI validation are pending. No installer or GitHub Release is produced.

## 0.1.105 — Diagnose Worker SCM startup failures

- Extended the Worker SCM smoke to stage Node adjacent runtime DLL dependencies alongside node.exe.
- On SCM startup failure, the smoke now emits bounded service configuration, service SID state and recent Application/System event diagnostics so the actual host failure is visible in CI.
- This is diagnostic hardening; it does not claim the Worker SCM integration passes. Exact-head Windows CI must confirm the cause and verify the fix.

## 0.1.104 — Use the actual Node runtime in Worker SCM smoke

- Replaced the .NET stub copied as node.exe with the Node 26 executable from the Windows CI toolchain.
- The smoke Worker now serves its loopback readiness endpoint using node:http and handles the host's SHUTDOWN stdin command, exercising the real Node process contract.

## 0.1.103 — Correct Worker SCM child executable detection

- Updated the Worker SCM smoke to locate the child by its exact staged node.exe image path instead of relying on CIM parent PID metadata.
- Added sanitized process diagnostics when the expected child is not found; the test still captures the PID and verifies it exits after graceful stop.

## 0.1.102 — Verify Worker child PID is actually reaped

- Strengthened the Worker SCM smoke to capture the child PID after readiness and verify that exact process no longer exists after SCM stop.
- Avoids treating a stopped service with an orphaned child as a successful reap.

## 0.1.101 — Fix Worker SCM smoke child-process detection

- Changed the Worker SCM smoke to identify the child by its parent service-host PID rather than matching a potentially normalized command-line path.
- The test still proves the child is running after readiness and has exited after graceful SCM stop.

## 0.1.100 — Add Worker Windows SCM and DPAPI integration smoke

- Added a Windows SCM smoke test for Worker using a LocalService runner identity with enabled EnterpriseITWorker service SID.
- The smoke provisions the machine-DPAPI database config, starts the Worker host, verifies loopback readiness, sends SCM stop and confirms graceful child shutdown/reap.
- The test explicitly does not claim hosted-runner acceptance of the production NT SERVICE virtual account.

## 0.1.99 — Add self-contained Windows service host staging

- Added a versioned Program Files staging script that publishes API, Web, Worker and Edge .NET hosts as self-contained win-x64 single-file executables.
- Staging refuses to overwrite immutable service-host executables and removes temporary publish output.
- Added a plan-only policy test and Windows CI coverage. Node runtime, application payloads, Web standalone tree and PostgreSQL binaries remain separate staged inputs.

## 0.1.98 — Extend API SCM smoke for protected DB config

- Updated the Windows SCM smoke test to create a service-SID ACLed ProgramData directory and provision the API's machine-DPAPI database config through the one-shot stdin command before service startup.
- The SCM smoke now validates the new fail-closed API startup contract rather than relying on inherited DATABASE_URL.
- Fixed orchestration rollback iteration for the zero-started-services case.

## 0.1.97 — Add five-service dependency orchestration

- Added a five-service provisioning/start orchestrator with dependency order PostgreSQL -> API/Worker -> Web -> Edge.
- Added SCM dependency graph for automatic startup on reboot and explicit readiness waits for pg_isready, API, Worker, Web and HTTPS Edge.
- On startup failure, the orchestrator stops only services started during that invocation; it never removes services/data or modifies firewall, NAT, router or port mapping.
- PostgreSQL and Edge service start modes are now automatic; provisioning still never starts services.
- Added plan-only orchestration tests and Windows CI coverage.

## 0.1.96 — Fix Edge test imports and PostgreSQL staging CI invocation

- Added the missing xUnit namespace import to Edge configuration tests.
- Fixed the PostgreSQL staging-plan CI step to dot-source the script with its mandatory parameters supplied, without downloading the external database archive.

## 0.1.95 — Correct API DPAPI source formatting

- Replaced literal escaped newline sequences in API service host imports and child environment configuration with valid source line breaks.
- Corrected the API ProgramData config path policy assertion to use canonical Windows separators.

## 0.1.94 — Protect API database configuration with DPAPI

- Removed any dependency on inherited machine DATABASE_URL for the API child process.
- Added machine-scope DPAPI encryption bound to the EnterpriseITApi service SID and per-installation GUID; the encrypted envelope is stored under ProgramData with a service-SID-only read ACL.
- Added a one-shot API host provisioning command that accepts the URL only through redirected stdin, validates PostgreSQL loopback 127.0.0.1:5432 and does not place the secret in command-line arguments or logs.
- Added API database URL validation tests and extended API provisioning policy. Clean-VM DPAPI/virtual-account acceptance remains pending.

## 0.1.93 — Fix Edge host compiler errors and Worker policy path

- Fixed nullable Windows token user handling in Edge service SID validation.
- Corrected the ASP.NET Core ProblemDetails named argument in the Edge readiness endpoint.
- Corrected the Worker ProgramData DPAPI config path assertion in its PowerShell policy test.

## 0.1.92 — Harden Worker DPAPI provisioning and fail-closed behavior

- Corrected Worker host configuration loading so it decrypts the protected ProgramData envelope rather than reading DATABASE_URL from the parent environment.
- Restricted the Worker config directory before writing the DPAPI envelope and fail before SCM/ACL changes if no SecureString database URL is supplied.
- Added explicit xUnit import to Worker DPAPI URL policy tests. This commit repairs source substitutions before relying on CI.

## 0.1.91 — Protect Worker database configuration with DPAPI

- Removed Worker database configuration from the inherited machine environment.
- Added machine-scope DPAPI encryption bound to the EnterpriseITWorker service SID and a per-installation GUID; the encrypted envelope is stored under ProgramData with a service-SID-only read ACL.
- Added a one-shot host provisioning command that accepts the URL only through redirected stdin, validates PostgreSQL loopback 127.0.0.1:5432 and does not place the secret in command-line arguments or logs.
- Worker decrypts configuration only after validating its enabled service SID, then passes DATABASE_URL through its explicit child environment allow-list.
- Added database URL policy tests and extended Worker provisioning policy. Clean-VM DPAPI/virtual-account acceptance remains pending.

## 0.1.90 — Add pinned PostgreSQL Windows packaging and service lifecycle

- Added PostgreSQL 18.7-1 EDB Windows x64 binary staging with vendor SHA-256 sidecar verification and immutable versioned payload checks.
- Added explicit SCRAM cluster initialization using a short-lived ACL-restricted password file; listener binds only to 127.0.0.1:5432 and pg_hba rejects non-loopback IPv4/IPv6.
- Added native EnterpriseITPostgreSQL SCM registration under its dedicated virtual account, service SID, bounded recovery and separate immutable binary/data ACLs. Provisioning does not start the service.
- Added Windows CI checks for package pinning and PostgreSQL service provisioning policy. Large EDB binary download and real cluster/service lifecycle remain deployment acceptance tests.

## 0.1.89 — Implement Windows TLS Edge service foundation

- Added a dedicated .NET 10 YARP reverse-proxy service with API and Web loopback upstreams, explicit LAN bind address, TLS 1.2/1.3 and readiness checks.
- Added machine-store certificate validation for private key, exact DNS hostname, Server Authentication EKU and trusted certificate chain.
- Replaced client-supplied X-Forwarded headers, disabled RFC Forwarded passthrough, validated HTTP Host and applied bounded Kestrel request limits.
- Added Edge virtual-account provisioning, service SID and recovery policy, protected ProgramData listener config, certificate private-key ACL and immutable Program Files payload ACL.
- Added Edge configuration and provisioning policy tests to Windows CI. Clean-VM virtual-account and certificate acceptance remain open.

## 0.1.88 — Record Worker service hosted CI acceptance

- Recorded successful exact-head validation for Worker service foundation commit 0562704e691e4898b319e38d11f413817dd6e884.
- Push run 44933005081 and PR run 44933009547 both completed successfully across Linux platform validation and Windows runtime validation.
- Windows CI passed Worker host compilation, Worker lifecycle tests and Worker provisioning policy tests, in addition to the existing API/Web/Credential Vault/installer-preflight gates.
- Hosted CI success does not prove clean-VM acceptance of the NT SERVICE virtual account or protected per-service database configuration; both remain release gates.

## 0.1.87 — Implement the Windows Worker service foundation

- Added a dedicated .NET 10 SCM host for `EnterpriseITWorker`, fixed Node 26/Worker entry point, loopback-only readiness at 127.0.0.1:13002 and parent/child enabled service-SID validation.
- Added bounded startup/readiness/shutdown, graceful stdin `SHUTDOWN` control, process-tree termination/reaping and lifecycle policy tests.
- Added guarded versioned Program Files provisioning for `NT SERVICE\\EnterpriseITWorker`, unrestricted service SID, bounded SCM recovery, immutable payload ACL, mismatch refusal and side-effect-free WhatIf. Provisioning does not start the service.
- Added Windows CI build, lifecycle and provisioning-policy gates.
- Worker discovery source allow-list remains empty; no discovery jobs are claimed or device requests sent. Protected per-service database configuration and clean-VM virtual-account acceptance remain release gates.

## 0.1.86 — Record Web service hosted CI acceptance

- Updated the Windows service deployment decision table to mark Web host, launcher, standalone staging and provisioning policy as implemented while retaining clean-VM virtual-account acceptance as an open release gate.
- Recorded successful Push and PR validation runs for the v0.1.85 Web service implementation commit. Hosted CI success is not represented as clean-VM production acceptance.

## 0.1.85 — Fix Web launcher lint compatibility

- Replaced CommonJS require calls in the Web standalone launcher with runtime dynamic imports so the repository ESLint policy passes without weakening lint rules.
- Made graceful drain close active connections after the bounded drain window, then close the Next.js application.

## 0.1.84 — Implement the Windows Web service foundation

- Added a dedicated .NET 10 Windows SCM host for Next.js, using the independent EnterpriseITWeb virtual account and validating the enabled service SID in parent and child tokens.
- Added a fixed Node launcher bound only to 127.0.0.1:13000, a local /health/ready route and bounded graceful shutdown through the host-owned stdin SHUTDOWN channel.
- Added staging for Next.js standalone runtime, static assets, public assets and service launcher. Web receives no database credentials or Credential Vault access.
- Added guarded Web service provisioning with explicit WhatIf, immutable Program Files ACL and bounded SCM recovery; provisioning does not start the service.
- Added Windows host lifecycle and provisioning policy checks to CI. Removed the Web-to-API /health rewrite; /api rewrites remain unchanged.
- Clean-VM virtual-account acceptance, Edge/TLS/WSS, installer integration and production packaging remain release gates.

## 0.1.83 — Add loopback Worker readiness endpoint

- Added the Worker readiness listener on fixed loopback address 127.0.0.1:13002/health/ready. It returns 200 only while the database probe succeeds and fails closed with 503 without leaking dependency errors.
- Added automated tests for healthy/unavailable dependency states, thrown probes, route/method rejection, loopback binding and invalid port configuration.
- Corrected Worker shutdown so an in-flight poll delay is released immediately instead of leaving the event loop waiting for the full poll interval.
- Discovery handlers remain intentionally unregistered and the supported-source allow-list remains empty; no discovery run can be claimed or reported as processed.
- This is a Worker process-readiness slice, not the Windows SCM host/provisioner. Worker service identity, parent/child SID enforcement, bounded process lifecycle, provisioning and clean-VM SCM acceptance remain open.

## 0.1.82 — Define the five-service Windows deployment contract

- Added a concrete five-service deployment contract covering Edge, Next.js, API, Worker and PostgreSQL, including service names, fixed entry points, loopback listeners, identity boundaries and startup order.
- Selected .NET 10 + YARP as the Edge prototype direction and PostgreSQL 18 as the packaging major-version baseline; exact PostgreSQL patch/build and production Edge acceptance remain explicit gates.
- Documented that the API provisioning work is only the first service slice. Worker/Web hosts, Edge, PostgreSQL packaging, clean-VM virtual-account acceptance and end-to-end SCM validation remain outstanding.
- No installer, firewall/NAT change, device scan or release was created by this architecture commit.

## 0.1.81 — Make API service provisioning dry-run safe

- The API provisioning function now returns an explicit dry-run plan immediately under -WhatIf, before payload checks or any SCM/SID/ACL command. This prevents a dry run from attempting to query a service SID that has not been created.
- Removed icacls /C so ACL application failures are not deliberately suppressed while the script reports success.
- Added a policy test asserting -WhatIf returns a dry-run result and never reports the service started.

## 0.1.80 — Add guarded API service provisioning

- Added installer-owned provisioning for the API Windows service. It accepts only a versioned Program Files\\EnterpriseIT\\<version> payload and validates the fixed host, Node runtime and API entry-point layout.
- Configures NT SERVICE\\EnterpriseITApi, SERVICE_SID_TYPE_UNRESTRICTED, bounded SCM recovery (60 seconds, then 300 seconds, then no automatic restart; reset after 24 hours), and immutable version-directory ACLs.
- Existing services with unexpected executable path or logon identity are rejected. The script deliberately does not start the API before PostgreSQL and protected configuration are ready.
- Added PowerShell policy tests and Windows CI validation. This is the first API provisioning slice, not the complete five-service installer; clean Windows Server virtual-account acceptance remains required.

## 0.1.79 — Close API Windows Service Host runtime milestone

- Recorded successful exact-head Windows CI acceptance for v0.1.78: Push run 44906623563 and PR run 44906628820 both completed successfully.
- The Windows job passed the real SCM smoke (temporary service start, enabled EnterpriseITApi service SID, parent/child token validation, loopback readiness, graceful stop/reap, and failed-readiness startup cleanup), all 17 service-host lifecycle unit tests, DPAPI helper checks, keyring helper fail-closed checks, installer preflight tests, Windows API typecheck/tests and API build.
- Marked the API Windows Service Host runtime milestone complete. The hosted SCM smoke uses LocalService because the hosted runner returned Win32 1057 for NT SERVICE virtual-account assignment; production provisioning must still configure NT SERVICE\EnterpriseITApi and validate it on a clean supported Windows Server VM.
- This documentation/version closure does not create an installer or Release and does not complete the five-service installation, protected ProgramData/immutable ACL provisioning, SCM recovery policy, Credential Vault approval or install/upgrade/repair/uninstall acceptance.

## 0.1.78 — Assert failed-start state instead of PowerShell exception shape

- The Windows SCM smoke now successfully creates the service under LocalService, enables the EnterpriseITApi service SID, passes host/child identity validation, starts readiness, and completes graceful stop/reap.
- The failed-readiness restart reached the expected stopped state but Start-Service did not always throw synchronously; Windows can accept the start request and report the subsequent host startup failure asynchronously. Updated the harness to assert the authoritative SCM Stopped state and absence of the child process rather than requiring a particular PowerShell exception behavior.
- No host runtime code changed. Exact-head Windows CI must now verify the entire smoke flow.

## 0.1.77 — Avoid regex parsing of Windows service account name

- The hosted Windows runner now creates the service and enables SERVICE_SID_TYPE_UNRESTRICTED successfully. The smoke script then failed because PowerShell interpreted the backslash in the NT AUTHORITY\LocalService account string as a regular-expression escape.
- Replaced regex matching with a literal wildcard comparison. No host runtime changes; the next run proceeds to token validation and service lifecycle assertions.

## 0.1.76 — Correct LocalService account separator in SCM harness

- Fixed the temporary SCM account string to use the single Windows account separator in NT AUTHORITY\LocalService. The prior attempt passed a doubled separator and SCM returned 1057 during service creation.
- No host runtime behavior changed. Exact-head Windows SCM acceptance remains pending.

## 0.1.75 — Use canonical LocalService account name in SCM smoke

- Corrected the CI-only SCM test service logon name from the short alias LocalService to the canonical NT AUTHORITY\LocalService account name. The prior Windows runner returned error 1057 during CreateService before the service SID or host lifecycle could be tested.
- Production identity remains NT SERVICE\EnterpriseITApi; LocalService is only a hosted-runner lifecycle test principal and does not change installer policy.

## 0.1.74 — Run SCM lifecycle smoke under LocalService on hosted runners

- The hosted Windows runner returned Win32 1057 when asked to provision NT SERVICE\EnterpriseITApi, both through sc.exe config and CreateService, despite successfully creating the service SID type. Updated the CI-only SCM smoke to use built-in LocalService as its logon principal while still enabling SERVICE_SID_TYPE_UNRESTRICTED and validating the exact EnterpriseITApi service SID in both parent and child process tokens.
- The harness grants the temporary payload read/execute access by the resolved service SID, not by account-name lookup. It asserts the smoke service's configured identity is LocalService.
- This is explicitly a CI runner limitation, not a production fallback. The installer must still configure NT SERVICE\EnterpriseITApi and that exact virtual-account configuration must be accepted on a supported clean Windows Server VM.

## 0.1.73 — Create API service directly with its virtual account

- Changed the Windows SCM harness to create EnterpriseITApi with obj= "NT SERVICE\EnterpriseITApi" in the initial sc.exe create call and omit password= entirely. Windows virtual accounts do not use an administrator-supplied password; the preceding config attempts returned 1057 even after enabling the service SID.
- The harness then sets SERVICE_SID_TYPE_UNRESTRICTED, grants the temporary identity read/execute access, and proceeds with start/stop and failed-readiness checks.
- No service-host runtime code changed. Exact-head SCM acceptance is still pending.

## 0.1.72 — Quote Windows virtual service-account name for SCM

- Corrected the SCM smoke harness to explicitly quote the virtual account name and empty password value when passing them to sc.exe config. The v0.1.71 run confirmed service SID provisioning succeeds, but SCM still returned error 1057 while parsing the account string containing a space.
- No host runtime changes. Exact-head Windows SCM acceptance remains pending.

## 0.1.71 — Provision service SID before virtual account assignment

- Reordered the Windows SCM smoke harness to configure SERVICE_SID_TYPE_UNRESTRICTED before assigning NT SERVICE\EnterpriseITApi as the service logon identity. The previous attempt created the service but SCM/LSA returned error 1057 while resolving the virtual account before its service SID had been provisioned.
- The current attempt will verify whether this ordering resolves the account on the hosted Windows runner. No service-host runtime code changed; exact-head SCM acceptance remains pending.

## 0.1.70 — Correct virtual service-account SCM argument tokenization

- Corrected the remaining sc.exe config invocation so obj= and password= option names are passed separately from their values, matching the native Service Controller command-line contract.
- The 0.1.69 harness correction split create arguments; static review found the config call still grouped its option/value pairs. The current Windows CI run will be superseded by this exact-head attempt.
- No host runtime code changed. SCM integration acceptance remains pending until the Windows runner completes the temporary service start, child-token, readiness, stop and failed-start checks.

## 0.1.69 — Correct Windows SCM smoke command-line tokenization

- Corrected the PowerShell SCM smoke harness to pass sc.exe option names and values as separate native arguments. The first hosted Windows execution had already confirmed host compilation and all 17 lifecycle unit tests, but stopped at sc.exe create with an invalid start= argument before the service was created.
- No runtime behavior changed from 0.1.68. The exact-head Windows SCM smoke must pass before the API Service Host runtime milestone is marked complete.

## 0.1.68 — Complete API Windows Service Host runtime acceptance

- Added a real Windows SCM smoke test to Windows CI. It temporarily provisions the API service under NT SERVICE\EnterpriseITApi, enables the service SID, launches the published host and a controlled child process, and verifies parent/child service-token validation, readiness, graceful stop and child reaping.
- The same SCM test forces readiness startup failure and verifies the service fails cleanly without leaving an orphaned child process.
- Fixed startup timeout/cancellation cleanup: the host now terminates and reaps the child before cancelling the background readiness loop, preserves the original startup failure alongside cleanup failures, and only disposes an exited child.
- Added a controlled Windows smoke child and an isolated PowerShell harness. The harness refuses to overwrite an existing service and removes its temporary service and payload.
- This completes the API Service Host runtime acceptance scope only after exact-head Windows CI passes. Permanent service provisioning, immutable ACLs, ProgramData configuration, SCM recovery policy, clean Windows Server matrix testing, remaining four services, Credential Vault approval, installer and Release remain separate gates.

## 0.1.67 — Testable bounded API child shutdown orchestration

- Extracted the API host's graceful-stop and forced-reap decision path into a deterministic internal coordinator used by the production StopAsync implementation.
- Added Windows-targeted tests for already-exited children, successful graceful shutdown, broken stdin/control pipe, graceful timeout, host cancellation with cleanup, unexpected control-channel state, premature wait completion and invalid timeout configuration.
- Host cancellation remains observable after the child cleanup attempt; if cleanup also fails, both failures are retained. No SCM configuration or process identity behavior is changed.
- Real Windows SCM, service-SID inheritance, ACL and process-tree acceptance tests remain required. No installer or Release is produced.

## 0.1.66 — Verify child exit after reap wait

- Hardened the shared terminate-and-reap policy to verify the child process is actually exited after the wait delegate completes. A wait implementation that returns prematurely now fails closed instead of being treated as successful cleanup.
- Added a regression test for a completed wait that does not establish process exit. Existing cancellation, timeout, kill-race and failure tests remain in place.
- This is a runtime lifecycle hardening change; real Windows process-tree and SCM integration tests remain required.

## 0.1.65 — Correct wait-cancellation policy test

- Corrected the cancellation test to inject an OperationCanceledException from the wait operation while the helper's own reap deadline remains unexpired. This accurately verifies that an independent wait cancellation is propagated rather than translated into a reap TimeoutException.
- No runtime behavior changed; the remaining v0.1.64 policy tests are retained.

## 0.1.64 — Expand API child-process termination policy tests

- Added deterministic coverage that external cancellation during the reap wait remains an OperationCanceledException and is not misreported as the helper's own timeout.
- Added coverage proving unexpected InvalidOperationException failures from process-tree termination are propagated; only the verified already-exited race is treated as benign.
- Added validation coverage proving a non-positive reap deadline is rejected before any process action.
- Runtime service-host behavior is unchanged. These tests strengthen the policy contract but do not replace real Windows SCM/process-tree acceptance testing.

## 0.1.63 — Verify the API child reap wait path

- Corrected the successful-termination unit fixture so the fake child remains running after the kill request and transitions to exited only when the reap wait delegate runs. The test now proves that the wait path is actually invoked, rather than returning early as already exited.
- This is a test-assertion correction; runtime termination behavior is unchanged.

## 0.1.62 — Test bounded Windows API child-process cleanup

- Extracted the API child terminate-and-reap policy into a small internal component shared by startup-failure and normal shutdown paths. Both paths now use the same bounded wait and process-exit race handling.
- Added a Windows-targeted .NET test project covering already-exited children, successful termination/reap, exit races during termination, kill failures, and reap timeouts. The Windows CI job runs these tests after building the service host.
- These tests validate the deterministic lifecycle policy with controlled process delegates; they do not replace a clean-VM test of a real SCM service, service SID inheritance, or OS process-tree termination.

## 0.1.61 — Bound API child startup-failure cleanup

- Replaced unbounded process waits in the API host's service-SID validation and readiness-failure paths with a shared bounded terminate-and-reap routine.
- Startup cleanup now uses the same five-second process-reap budget as normal shutdown, treats a process-exit race as benign, and reports kill/reap failures as critical errors.
- If both startup and cleanup fail, both exceptions are retained in an AggregateException rather than silently losing the original failure.
- This does not prove Windows SCM recovery behavior or clean-VM service lifecycle acceptance; no service registration, identity provisioning, ACL, firewall, or network changes are made.

## 0.1.60 — Fall back to process termination when shutdown IPC fails

- Hardened Windows API service shutdown when the child process stdin pipe is broken, closed or otherwise unavailable. I/O and invalid-operation failures while sending the graceful shutdown command are logged and fall through to the existing bounded process-tree termination/reap path instead of skipping termination.
- This does not claim that Windows can always terminate a protected or unresponsive process; failure to terminate/reap remains a critical shutdown error.

## 0.1.59 — Bound Windows API service startup and shutdown

- Bound the synchronous Windows service startup readiness wait to 20 seconds. If the API is not ready within that startup budget, the host cancels its background startup and waits for the child-process cleanup path instead of keeping SCM startup pending for the full 60-second readiness window.
- Added a bounded post-termination process-reap wait and bounded redirected-output drain. A child that cannot be terminated/reaped is logged as a critical shutdown failure; output-drain delay can no longer hold service shutdown indefinitely.
- The 20-second budget is a conservative startup bound, not proof of SCM timing behavior on every Windows host. Real service installation, configured SCM recovery, and clean-VM acceptance remain required.

## 0.1.58 — Ensure API child process is reaped during service stop

- Hardened Windows API host shutdown so cancellation of the host stop token no longer bypasses the child-process cleanup path. The host requests graceful API shutdown, then terminates and waits for the child process tree if the graceful window expires or is cancelled.
- The host continues to drain redirected output streams and dispose the process handle after the child has exited. This is lifecycle hardening, not proof of SCM recovery configuration or clean-VM service acceptance.

## 0.1.57 — Validate Windows token size-query failure

- Hardened service-SID token inspection: the initial `GetTokenInformation(TokenGroups)` sizing call must fail specifically with `ERROR_INSUFFICIENT_BUFFER` and report a bounded required buffer size. Unexpected success or any other Win32 error now fails closed instead of allowing an untrusted/invalid size result to proceed.
- This is defensive validation of the existing parent/child identity gate. It does not provision the service account, configure SCM, prove clean-VM service-token behavior or create an installer.

## 0.1.56 — Verify API child process service SID

- After launching the fixed Node API executable, the Windows host opens the child process token with query-only access and independently verifies the exact enabled, non-deny-only `NT SERVICE\\EnterpriseITApi` SID before accepting the child or starting readiness checks.
- A missing, disabled, deny-only, ambiguous or mismatched child SID causes immediate process-tree termination and host startup failure. The child token is never logged or exported.
- This is runtime token validation, not proof of installer provisioning or clean-VM SCM behavior. Real Windows tests must still verify parent/child token inheritance, service configuration and lifecycle.

## 0.1.55 — Enforce API Windows service SID at startup

- Added a Windows token validator for the API host. Before launching Node, it resolves the exact `NT SERVICE\\EnterpriseITApi` SID and requires that SID to be the process token user or an enabled, non-deny-only token group.
- Token group parsing is bounded and validates the returned buffer and group table before inspecting SID attributes. Missing, disabled, deny-only, ambiguous or unresolvable service identity fails closed; the host does not start the API child.
- This is an enforcement gate, not service provisioning. The installer still must create/configure the service account and explicit service SID. Real SCM-token and child-token inheritance tests on a clean Windows VM remain mandatory.

## 0.1.54 — Gate Windows API service startup on readiness

- The Windows API host now waits for the fixed loopback `/health/ready` endpoint before completing hosted-service startup. The probe is bounded to 60 seconds, retries transient connection/503 responses, and terminates the child process if readiness is not reached.
- Corrected the Node host-control parser to recognize the actual newline written by the Windows host, so the `SHUTDOWN` command can trigger Fastify close and Prisma disconnect.
- This remains a service-host development increment, not service registration or installer approval. The host still lacks provisioned service-SID identity, child-token proof, immutable ACL enforcement and clean-VM lifecycle acceptance.

## 0.1.53 — Correct Windows API host build metadata

- Added the service-host namespace import required by the top-level host bootstrap and synchronized both root version fields in package-lock.json with package.json.
- This is a compile/metadata correction only; Windows service registration, identity provisioning and production readiness remain unimplemented.

## 0.1.52 — Add initial Windows API service host

- Added a .NET 10 Windows Service Host project for the API process. It launches only the fixed, installer-layout Node runtime and API entry point, without a shell or caller-supplied arguments.
- Added a private standard-input shutdown command so the host can request Fastify/Prisma graceful shutdown before bounded process-tree termination. The child environment is restricted to required OS variables and non-secret API defaults; database configuration remains in the protected application configuration file.
- Added the host project to Windows CI compilation. This is an implementation scaffold only: it does not provision the virtual service account/service SID, install/register the service, prove child-token inheritance, provide TLS edge/Web/Worker/PostgreSQL services, or approve Credential Vault storage.
- Root package and lockfile versions synchronized at 0.1.52. PR #8 remains Draft/open/unmerged; no installer or Release.

## 0.1.51 — Fix Windows installer preflight test parameter collision

- Renamed the test fixture parameter that collided with PowerShell's automatic read-only `$IsWindows` variable; the fixture still supplies the `IsWindows` fact consumed by the evaluator.
- No runtime preflight behavior or host state changes. Version and lockfile synchronized.

## 0.1.50 — Windows installer host preflight baseline

- Added a read-only PowerShell preflight for Windows x64, elevated execution, and ready local fixed Program Files/ProgramData volumes with a configurable free-space floor.
- Separated environment collection from pure evaluation and added Windows CI assertions for non-Windows, non-x64, non-elevated, insufficient-space, network-volume and unavailable-volume rejection.
- This is an installer prerequisite check only: it does not create directories, change ACLs, register services, inspect or modify ports/firewall rules, initialize PostgreSQL, or install the application. OS support matrix, five-service registration and installer packaging remain open gates.
- Root package and lockfile versions synchronized at 0.1.50.

## 0.1.49 — Branch inventory CSV export

- Added a CSV export action that follows the active branch, search text and equipment-type filters and retrieves all matching records in bounded 100-row pages.
- Export is capped at 10,000 assets, checks the result total between pages to detect concurrent inventory changes, and reports actionable errors instead of silently producing a partial file.
- CSV fields are quoted/escaped, UTF-8 BOM is included for spreadsheet compatibility, and formula-like cell values are prefixed to mitigate spreadsheet formula injection. Root package and lockfile versions synchronized at 0.1.49.

## 0.1.48 — Switch-port observation history UI

- Connected the inventory switch-port dialog to the branch-authorized, read-only observation-history API. Each port now has a View history action with observed time, source, administrative/operational state, VLAN, speed, IP and MAC fields.
- Added bounded 10-row pagination, total count, loading/empty/error states and request sequencing so late history responses cannot overwrite a newer port selection or a closed dialog.
- The history view performs no polling and sends no switch configuration. Root package and lockfile versions synchronized at 0.1.48; no installer or Release.

## 0.1.47 — Paginated switch-port observation history API

- Added a branch-authorized, read-only endpoint for a switch port's append-only observation history, with bounded pagination (1–100 rows), deterministic newest-first ordering and a total count.
- The response deliberately excludes raw discovery metadata and exposes only operational fields needed by the inventory UI.
- Added PostgreSQL integration coverage for newest-first ordering, pagination totals, VIEWER read access, and rejection of a port ID that does not belong to the requested switch.
- Root package and lockfile versions synchronized at 0.1.47. No discovery runner, device probing, switch configuration, installer or Release is enabled.

## 0.1.46 — Prevent stale switch-port responses

- Added request sequencing to switch-port detail loading. When operators open another switch or close the dialog while a request is in flight, late responses are ignored instead of replacing the currently selected switch's ports or changing its loading/error state.
- Clear the previous port list immediately when switching devices, and invalidate pending reads when the dialog closes.
- Root package and lockfile version metadata synchronized at 0.1.46. This is a UI consistency fix; it does not add live discovery, device configuration, an installer or a Release.

## 0.1.45 — Add inventory pagination and accurate totals

- Added offset-based pagination controls to the inventory workspace using the API's existing `limit`, `offset` and `page.total` contract.
- The summary now displays the total number of matching assets rather than only the currently loaded first 100; the switch count is explicitly scoped to the visible page.
- Branch, type and search changes reset pagination to the first page. Concurrent asset-list requests are sequenced so a slower stale response cannot overwrite newer filters or page results.
- Added PostgreSQL integration coverage for offset and total semantics. Root package and both lockfile version fields synchronized at 0.1.45. Exact-head CI is required; no installer or Release.

## 0.1.44 — Fix inventory search IP filter semantics

- Fixed inventory asset search so the IP-address predicate is included only when the search term is a valid IP address. Non-IP searches no longer pass an `equals: undefined` condition to Prisma, which could be omitted and broaden the OR query unexpectedly.
- Added PostgreSQL integration coverage for exact IP search and a non-matching text search returning zero rows.
- Synchronized both root package and lockfile version metadata at 0.1.44. Exact-head CI is required; no installer or Release.

## 0.1.43 — Add PostgreSQL regression coverage for bootstrap advisory lock

- Added a PostgreSQL integration assertion that executes the exact transaction-scoped advisory-lock query used by administrator bootstrap and verifies Prisma receives a supported integer result rather than PostgreSQL `void`.
- Updated the preview guide to the current version. This is regression coverage and documentation synchronization; it does not create an installer or Release.
- Root package and lockfile versions synchronized at 0.1.43. Exact-head CI is required.

## 0.1.42 — Fix administrator bootstrap advisory-lock query

- Fixed the bootstrap transaction's PostgreSQL advisory-lock query to materialize the void-returning lock call internally and return a supported integer result to Prisma. The transaction-scoped lock and concurrent-bootstrap protection remain intact.
- Root package and lockfile versions synchronized at 0.1.42. Exact-head CI is required; no installer or Release is created.

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

## 0.1.111 — Lockfile root-version consistency gate
- Corrected the npm lockfile root package metadata to match the root package version; no third-party dependency versions or workspace dependency ranges were changed.
- Added a CI assertion for lockfile v3, root version parity, and API/Worker/Database workspace name and version parity.
- Runtime packaging remains a separate acceptance item; this change does not create an installer or release.


## 0.1.112 — Immutable Web standalone staging
- Hardened Next.js standalone staging to reject an existing destination rather than silently overlaying a previous payload.
- Added a read-only `-WhatIf` plan, `ShouldProcess` confirmation, isolated sibling staging directory, post-copy completeness checks and same-volume atomic promotion.
- Added Windows PowerShell coverage for dry-run behavior, required runtime/static/public files and overwrite rejection; wired it into Windows CI.
- This packages only the Web standalone output. API/Worker production dependency bundling, installer, rollback and clean Windows Server acceptance remain outstanding.


## 0.1.113 — API and Worker production runtime staging
- Added immutable staging for compiled API, Worker and shared Database workspaces with Prisma schema and migrations.
- Installs selected workspace production dependencies using the already-staged Node.js/npm runtime, then verifies Database, Fastify and Argon2 module resolution before promotion.
- Refuses existing destinations and rolls back directories already promoted if a later promotion fails.
- Added Windows integration coverage and CI build/staging gate for API and Worker.
- This is runtime payload staging, not a complete installer; PostgreSQL provisioning, credentials, Windows service identities, Edge certificates, repair/uninstall and clean-VM acceptance remain outstanding.


## 0.1.114 — Relocatable workspace runtime links
- Fixed production payload promotion: npm workspace links may resolve to the temporary staging directory and become invalid after promotion.
- Replaced API, Worker and Database workspace links under node_modules/@platform with physical copies before module-resolution checks and promotion.
- Extended Windows integration smoke tests to resolve Database dependencies from both API and Worker application directories after promotion.
- No installer or release is created by this correction.


## 0.1.115 — Transactional Windows service-host staging
- Changed four-host staging to publish and validate all self-contained executables in a temporary workspace before modifying the versioned install directory.
- Promotes the complete host set only after every publish succeeds; removes any executables promoted by the current run if a later promotion fails.
- Extended Windows staging-plan checks for project presence, executable names and immutable payload policy.
- This remains a payload staging operation, not the product installer.

## 2026-11-22 — Windows ZIP extraction path hardening (v0.1.125)
- Offline installer archive validation now rejects Windows-invalid path segments, alternate data stream syntax, reserved DOS device names, trailing dots/spaces, control characters, and DOS reparse-point entries before extraction.
- Added Windows regression cases for alternate data streams, reserved device names and trailing dot/space paths.
- Root package and npm lockfile metadata advanced together to 0.1.125. Exact-head Windows CI is required; no real installation or signed release is claimed.

## 2026-11-22 — Offline installer ZIP validator parser correction (v0.1.126)
- Corrected the malformed PowerShell regex block in offline installer ZIP entry validation discovered by Windows CI.
- Restored reserved-device-name, duplicate-path, Unix symlink and DOS reparse-point checks before extraction.
- Root package and lockfile metadata advanced together. Exact-head Windows CI is required before accepting installer validation.
