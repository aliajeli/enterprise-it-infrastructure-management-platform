## Implementation status — v0.1.52

The repository now contains an initial .NET 10 SCM host project at `apps/api/windows/service-host`. It launches a fixed Node runtime/API entry point, strips inherited process environment variables before adding a narrow allowlist, and requests graceful shutdown through a private stdin control message. The API handles that message by closing Fastify and disconnecting Prisma.

This is a buildable implementation scaffold, not an installer-ready service. The following remain mandatory before registration or production use: provision `NT SERVICE\\EnterpriseITApi` with an explicit service SID; validate the effective token SID and privileges; prove the child process inherits the enabled SID; apply and verify immutable binary ACLs; implement readiness/health supervision and bounded recovery policy; and run clean-VM Windows integration tests. The service host currently assumes the future immutable version-directory layout (`runtime/node.exe` and `apps/api/dist/server.js`). It does not install files, create identities, modify ACLs, provision configuration, open firewall ports or register itself with SCM.

# Windows Service Host and Credential Vault Provisioning Contract

**Status:** Architecture/provisioning design gate. This document does not install services, create identities, provision ACLs, or register the keyring adapter.

## 1. Decisions and boundaries

- Run the API under a dedicated virtual Windows service account, provisioned as `NT SERVICE\\EnterpriseITApi`; never use LocalSystem or an interactive administrator as a fallback.
- Register the SCM service with an explicit service SID and verify at runtime that the SID is present as the token user or as an enabled, non-deny-only token group. A SID merely present in TokenGroups is not sufficient.
- A small .NET 10 Windows Service Host using `Microsoft.Extensions.Hosting.WindowsServices` is the preferred SCM integration. It supervises the Node API process, forwards stop/start lifecycle, applies bounded shutdown, and restarts only under a documented failure policy. It must not contain credential material or broaden the Node process token.
- The Node API process and its fixed-purpose DPAPI/keyring helpers run under the same API service token. This inheritance is a hypothesis to prove with a real Windows service integration test; do not assume child processes retain the enabled service SID.
- Do not grant the Worker service access to the local keyring. If a separate Worker service is introduced, it receives its own identity and uses an authenticated, narrowly scoped API contract; it never reads KEKs or raw keyring files.
- The Node API remains a network service bound to explicitly configured interfaces. Windows Service registration does not authorize broad firewall changes or public exposure.

## 2. Identity provisioning

1. Installer creates the virtual service account identity by selecting the stable SCM service name; no password is stored.
2. Installer configures the service SID type explicitly and verifies the resulting SID with Windows account translation before any application service starts.
3. SCM service logon rights and required privileges are minimal. Do not add the identity to local Administrators, Backup Operators, or interactive logon groups.
4. Service recovery actions are bounded and documented; repeated crashes enter a visible failed state rather than restart-looping indefinitely.
5. At startup, the API host records only non-secret identity metadata (service name/SID and validation result) in a protected operational log. It never logs tokens, environment secrets, key material, or DPAPI blobs.
6. Installer starts the helper/API only after the service identity, executable ACLs, ProgramData hierarchy, and keyring directory have been provisioned and verified.

## 3. Filesystem layout and ACL ownership

**Immutable binaries:**
- `%ProgramFiles%\\EnterpriseIT\\<version>\\` contains the .NET host, pinned Node runtime, API/web/worker distributions, and fixed helper executables.
- SYSTEM and Administrators may service/replace binaries. The API service SID receives read/execute only. The service cannot modify its own host, Node runtime, helper executable, scripts, or package payload.
- The helper path is resolved from an installer-owned manifest and checked for canonical path, expected file identity, signature/hash policy, and non-writable parent directories before launch.

**Mutable state:**
- `%ProgramData%\\EnterpriseIT\\` is the protected application data root. Installer provisions the hierarchy before service startup; runtime helper never creates directories or repairs ACLs.
- `CredentialVault\\` owner is the API service SID. Its protected DACL contains exactly the service SID and SYSTEM according to the frozen keyring storage policy. Registry and lock files are provisioned with exact file ACLs and fixed names.
- Database data, application logs, backups, update staging, and uploaded packages use separate subdirectories and separate ACL policies. Credential keyring files must not share a directory with logs, uploads, or web-served content.
- Uninstall removes binaries and service registrations but retains database, vault, configuration, and backups by default. Data/key deletion is a separate explicitly confirmed operation.

## 4. ProgramData path-component verification

The current helper opens and validates the final `CredentialVault` directory handle but does not yet establish a complete trusted chain from the OS-known ProgramData directory through every parent component. This remains a production blocker.

Before any registry or lock operation, the final implementation must:

1. Resolve ProgramData from the OS-known CommonApplicationData API; reject UNC, device namespace, alternate stream, relative, or unexpected volume paths.
2. Open ProgramData and each expected child component individually with directory semantics and `FILE_FLAG_OPEN_REPARSE_POINT`; verify each handle is a directory, not a reparse point, and resides on the expected volume.
3. Obtain canonical final paths and stable file IDs from opened handles; verify each child is beneath the previously verified parent and that the chain is exactly `ProgramData -> EnterpriseIT -> CredentialVault`.
4. Validate parent owner/DACL against a documented trusted Windows baseline. Do not require the API service SID to own ProgramData itself; require that untrusted principals cannot replace or redirect the managed child directories.
5. Hold directory handles with sharing semantics that prevent rename/delete substitution for the duration of each transaction, and verify the file handle's volume/file identity remains beneath the held root before read, write, replace, or cleanup.
6. Reject reparse points at every level, including lock file, registry file, temporary file, and parent directory. Do not rely on `Directory.Exists`, `File.Exists`, string-prefix checks, or a final-component check as the security boundary.
7. Fail closed on any path/ACL/identity ambiguity. Normal runtime must never take ownership, broaden ACLs, create missing parent directories, or silently repair tampering.

Implementation must explicitly analyze Windows sharing modes, existing-handle races, directory rename semantics, junctions, mount points, volume changes, and replacement behavior. A sequence of path-based checks without a handle-bound chain is not sufficient proof against TOCTOU.

## 5. Process supervision and shutdown

- Host launches a fixed Node executable and fixed entry point from the immutable version directory; no shell, caller-controlled command, or arbitrary arguments.
- No secret is passed in command-line arguments or environment variables. Service credentials and key material are obtained only through the approved vault interfaces after provisioning.
- Host captures bounded stdout/stderr; logs are structured, sanitized, and secret-redacted. Child stdout is not treated as an unrestricted log sink if any helper protocol shares that channel.
- SCM stop first stops accepting new work, signals the Node API, drains bounded in-flight requests, stops the Worker queue, then terminates the child only after the configured grace period. Forced termination is audited.
- Host verifies child exit code and process tree cleanup. A stuck or orphaned child leaves the service in a failed state and is surfaced to the operator.
- Startup readiness requires DB connectivity, migration compatibility, required local paths, and API health. Liveness and readiness are separate; an unready API must not accept credential or discovery requests.

## 6. Install, upgrade, repair, and uninstall contract

**Fresh install:** preflight OS/architecture, disk space, privileges, existing service names, port conflicts, ProgramData parent chain, and existing application data. Stage signed/verified payloads; create identities; create protected directories and ACLs; provision service configuration; initialize database and migrations under controlled locks; verify helper and API startup; only then mark install complete.

**Upgrade:** verify package authenticity and monotonic version; stage a new immutable version directory; preserve the existing service SID and keyring ACL; quiesce jobs; take a consistent recoverable database/config/data/vault backup; apply reviewed migrations; atomically switch service binary path/configuration; start and health-check; retain previous binaries and backups through the rollback window. Never overwrite the current version in place.

**Repair:** inspect and report identity, ACL, service config, path-chain, and file-integrity differences. Repair requires an explicit elevated installer action and an audit record; runtime helper does not self-heal.

**Uninstall:** stop services, remove SCM registrations and versioned binaries, preserve user data and vault by default, and display the exact retained data locations. Deletion requires a separate explicit confirmation and recovery policy.

## 7. Required Windows integration tests

- Run the real helper as the provisioned virtual service account with service SID enabled; prove positive DPAPI protect/unprotect and keyring initialize/read/write/rotate.
- Run as LocalSystem, local Administrator, standard user, unrelated service SID, disabled service SID group, and deny-only service SID; all must fail closed.
- Verify the Node child process inherits exactly the expected enabled service SID and no unexpected privilege escalation.
- Substitute junctions/reparse points at ProgramData, EnterpriseIT, CredentialVault, lock, registry, and temp paths; all operations must fail without touching redirected content.
- Race directory rename/replacement and file replacement while transactions run; prove handle-bound path identity prevents escape/TOCTOU.
- Tamper owner, protected DACL, inheritance, ACE order/type/mask, and SYSTEM/service SID entries; helper refuses to read or overwrite.
- Exercise separate-process lock contention, helper termination, interrupted atomic replace, crash recovery, and concurrent key rotations.
- Validate fresh install, upgrade, repair, uninstall-retain-data, explicit data deletion, and rollback on clean Windows Server VMs.

## 8. Release gates

No production storage adapter registration, real credential persistence, discovery handler, installer, or Release until the service host, service SID provisioning, immutable executable ACLs, complete path-component hardening, actual Windows integration tests, independent recovery drill, and install/upgrade/uninstall/rollback tests pass on a clean supported Windows Server image.
