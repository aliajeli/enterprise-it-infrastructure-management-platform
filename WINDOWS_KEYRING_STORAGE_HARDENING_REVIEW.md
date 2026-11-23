## Implementation status update — 2026-11-23 (revision 0.1.145)

Exact-head hosted CI for commit `603af65f33cbac61083c81e7ae6c7a72c7368e20` completed successfully in both Push validation and PR validation. The Windows API runtime smoke job passed in both workflows. This confirms the tested hosted workflow only; it does not establish native filesystem behavior on supported Windows Server versions or a positive transaction under the provisioned `NT SERVICE\\EnterpriseITApi` identity.

A focused review of `WindowsDirectoryHandleChain.OpenKnownProgramData()` and the provisioning scripts found a remaining policy gap. The chain retains handles for the volume root, ProgramData, EnterpriseIT and CredentialVault and checks each opened directory for directory type, reparse status and volume identity. It does not retrieve or validate the owner/DACL of ProgramData or EnterpriseIT. The helper's exact two-ACE owner/DACL check applies to the Vault directory and managed leaf files only.

Do not solve this by imposing the Vault leaf's exact two-ACE policy on ProgramData. ProgramData is OS-managed and needs a supported-Windows-version trust baseline. EnterpriseIT and CredentialVault are application-owned and need an explicit installer provisioning contract, including owner, protected/inherited DACL policy, service SID lifecycle and the pre-created `keyring.lock`. The currently reviewed service provisioning scripts create API database configuration directories but do not provision this keyring hierarchy and lock file. Until installer behavior and expected descriptors are specified, adding parent ACL checks would risk rejecting legitimate supported hosts or encoding an unsafe assumed baseline.

**Disposition:** parent owner/DACL verification is not implemented in this revision. F-01/F-02 remain open. Next prerequisite is to define and implement installer provisioning and a versioned ACL policy for each parent component, then add handle-based positive/negative ACL tests on clean supported Windows Server VMs. F-03 remains open for crash-orphan enumeration, failure injection and adversarial identity/race acceptance. F-04/F-05 remain open for native Windows Server and provisioned-Service-SID acceptance. The Node adapter remains unregistered and production credential persistence remains disabled.

---

## Implementation status update — 2026-11-23 (revision 0.1.144)

The retained CredentialVault directory handle now requests both FILE_ADD_FILE (0x2) and FILE_DELETE_CHILD (0x40). The first is required for relative temporary-file creation; the second is required for replacement semantics when FileRenameInformation is asked to replace an existing destination. The directory ACL remains independently checked by the helper. This is a static access-mask correction; native replacement still requires execution on supported Windows Server baselines.

F-01/F-02 remain open for parent-directory owner/DACL verification and complete namespace-race acceptance. F-03 remains open for crash-orphan enumeration, failure injection and adversarial identity/race acceptance. F-04/F-05 remain open pending Windows Server and provisioned-Service-SID acceptance. The Node adapter remains unregistered; production credential persistence remains disabled.

---

## Implementation status update — 2026-11-23 (revision 0.1.143)

The helper's temporary-file write path now uses RandomAccess directly against the SafeFileHandle rather than an owning FileStream. This closes a cleanup gap: if ACL/type verification or setup failed after the temporary file was created but before the old FileStream construction point, the previous code disposed the handle without marking the file for deletion. The revised finally block attempts handle-based FileDispositionInformation for every pre-rename failure while the exact created handle remains open. After a successful rename, the source handle is closed before the destination is reopened for identity/ACL/type/length/byte verification.

This is in-process failure cleanup only. Abrupt process termination can still leave orphan temporary entries; handle-relative directory enumeration and crash-orphan cleanup have not been implemented. Earlier wording that described "orphan cleanup" as implemented was inaccurate and is corrected in the handle-relative filesystem design. F-03 remains open for crash-orphan enumeration, failure injection and adversarial identity/race acceptance. F-04/F-05 remain open pending supported Windows Server native-operation and provisioned-Service-SID acceptance. The Node adapter remains unregistered and production credential persistence remains disabled.

---

## Implementation status update — 2026-11-23 (branch revision 0.1.142)

The helper now performs lock acquisition, registry reads, temporary-file creation, atomic replacement and orphan cleanup relative to the retained Vault directory handle. Rename uses `NtSetInformationFile(FileRenameInformation)` with the Vault handle as `RootDirectory`; deletion uses `FileDispositionInformation` against the still-open temporary-file handle. The Vault directory handle is opened with FILE_ADD_FILE so relative temp creation and rename have the required directory access. The temporary file is opened with DELETE access. Its file identity is captured before rename, then the committed destination is reopened relative to the Vault handle and required to retain the same identity before read-back verification. The source handle is closed before reopening the destination. Lock contention retries native sharing/lock violation codes; a missing pre-provisioned lock file still fails closed. Missing-registry first-run handling remains limited to Win32 file-not-found (error 2).

This removes the known path-based leaf mutation calls from the helper, but it is not security acceptance. F-05 remains blocking because positive provisioned-Service-SID, crash/restart, adversarial namespace and target Windows Server tests are not present. Broader transaction and recovery identity tests remain required. The Node keyring adapter remains unregistered; no credential persistence or production approval is granted.

---

## Implementation status update — 2026-11-23 (branch revision 0.1.141)

The 0.1.140 relative-open change is now the active implementation for lock acquisition, registry reads/existence checks and temporary-file creation. Review of the new call path found that `OpenVaultFile` translates a missing leaf into a `Win32Exception`, while the caller had incorrectly expected an invalid handle. The helper now treats Win32 file-not-found (error 2) as the expected first-run absence only; access denied, reparse/type violations, and all other native failures continue to fail closed.

This is a correctness fix, not completion of handle-relative storage. Atomic replacement and orphan cleanup still resolve names through Win32 paths. F-03 and F-04 remain open; F-05 remains blocking because positive provisioned-Service-SID and adversarial namespace tests are not present. File identity metadata is queried on open but is not yet retained and compared across rename/commit. The Node keyring adapter remains unregistered; no credential persistence or production approval is granted.

---

## Implementation status update — 2026-11-23 (branch revision 0.1.137)

The first parent-chain mitigation is now wired into the helper transaction lifecycle. `WindowsDirectoryHandleChain.OpenKnownProgramData()` acquires the local volume root and opens ProgramData, EnterpriseIT and CredentialVault relative to retained parent handles. It rejects reparse-point directory components and volume changes. These handles are held from BEGIN until process exit and are opened without FILE_SHARE_DELETE. Vault owner/DACL checks use the retained Vault handle.

This partially mitigates F-01 and F-02 at the parent-directory level. It does **not** close either finding completely: the helper's lock, registry, temporary-file, replacement and cleanup operations still resolve leaf names through paths. F-03 and F-04 are unchanged. No positive provisioned-Service-SID integration or adversarial namespace tests have been added, so F-05 remains blocking. The Node keyring adapter remains unregistered; no credential persistence or production approval is granted.

---

# Windows Credential Keyring Storage — Security Hardening Review

**Review date:** 2026-11-20  
**Reviewed revision:** `f428f63a7a30fdd67b5da9bd42cce94d4debd019`  
**Status:** Blocking security review; no production approval  
**Scope:** `apps/api/windows/keyring-storage-helper/Program.cs`, the storage design contract, and the service-host provisioning contract.

## Executive finding

The helper has meaningful fail-closed controls: a fixed registry and lock filename, service-SID resolution, exact owner/DACL checks on selected handles, reparse-point checks, bounded protocol frames, an exclusive lock-file handle, bounded registry reads, temporary-file creation, flush-to-disk, replacement, and read-back verification.

Those controls do **not** yet establish that every filesystem operation remains attached to the same trusted directory and file identities throughout a transaction. The storage adapter must remain unregistered. Do not store real equipment credentials or treat this helper as production-ready.

## Findings

### F-01 — Parent path components are not pinned and validated (High)

`VerifyDirectory()` opens and checks only the final `%ProgramData%\\EnterpriseIT\\CredentialVault` directory. The parent components are traversed by ordinary path resolution and are not independently opened, identity-checked, and retained. A final-directory ACL check does not prove that the path was reached through the intended trusted parent chain.

**Required correction**
- Resolve the OS-known ProgramData directory and open it as a directory handle.
- Validate that it is the expected local volume/path and is not a reparse point. Treat ProgramData's OS-managed ACL as a distinct trust policy; do not require the vault's exact two-ACE policy on ProgramData.
- Open `EnterpriseIT` relative to the pinned ProgramData handle, then `CredentialVault` relative to the pinned EnterpriseIT handle. Validate each component's type, reparse status, volume identity, final identity and expected owner/DACL policy.
- Retain all directory handles through the entire transaction. Do not close them after validation and then resume path-based access.
- Reject unexpected mount-point/reparse traversal, volume changes, UNC/device paths, alternate data streams and unexpected final paths.

A Win32 path check followed by a later Win32 path open is not sufficient. Prefer handle-relative opens (for example, a carefully reviewed `NtCreateFile` path using `OBJECT_ATTRIBUTES.RootDirectory`) for child components and managed files. If a native API is introduced, document structure layout, NTSTATUS translation, supported Windows versions and disposal semantics, and cover it with Windows tests.

### F-02 — Directory handles allow delete sharing (High)

The current directory verification open uses `FILE_SHARE_DELETE`. This permits compatible rename/delete opens while the helper retains its directory handle. Consequently, a successful validation does not by itself prevent a later path-based operation from resolving to a substituted directory entry.

**Required correction**
- Open and retain directory handles with sharing that denies delete/rename for the protected transaction where compatible with Windows filesystem semantics.
- Verify the chosen share-mode behavior on supported Windows Server versions and with antivirus/backup/indexing software present.
- Where share-mode pinning is insufficient, perform all descendant operations relative to the retained directory handle and verify file identity immediately before and after mutation.
- Add a concurrent adversarial test that attempts rename, junction replacement and directory substitution while a transaction is active. The attacker must not redirect a read, write, replace or cleanup operation.

Do not assume that removing `FILE_SHARE_DELETE` alone proves the whole path chain safe.

### F-03 — Temporary-file cleanup is path-based and suppresses errors (High)

The cleanup path checks `File.Exists(temp)`, opens the temp path, verifies that handle, then calls `File.Delete(temp)`. The final delete resolves the name again; it is not bound to the verified handle. The broad catch also hides cleanup failures, making orphan state difficult to diagnose safely.

**Required correction**
- Track the exact helper-created temporary file identity and delete that exact entry relative to the pinned directory handle.
- Before deletion, verify the entry still names the expected file ID and volume. Never delete a substituted object.
- Treat unexpected identity/ACL/reparse changes as a security failure; do not silently continue as if cleanup succeeded.
- Keep cleanup diagnostics generic and secret-free, but expose a stable internal error category and an auditable operational signal.
- Add tests for temp-file replacement between verification and deletion, orphan temp files, and cleanup after helper termination.

### F-04 — Atomic replacement is not yet handle-relative (High)

The current implementation creates and flushes a same-directory temp file, calls `MoveFileExW(temp, Registry, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)`, then reopens the destination by path. Same-directory write-through replacement is useful, but path-based source/destination resolution is still coupled to the mutable directory namespace.

**Required correction**
- Keep the temp and destination bound to the pinned directory and verify their file IDs/volume before mutation.
- Prefer a reviewed handle-relative rename/replace operation (for example, `SetFileInformationByHandle` with the appropriate rename information class and a directory root handle), or provide a documented Windows-specific proof and adversarial tests for the selected alternative.
- Ensure the previous committed registry remains intact if replacement fails. Do not implement delete-then-move.
- Reopen/read back relative to the pinned directory and verify the exact committed file identity, ACL, length and bytes.
- Test failure injection at create, partial write, flush, rename/replace, and read-back stages. A VM power-loss drill remains a separate release gate.

### F-05 — Windows acceptance coverage is insufficient (High)

The current workflow builds the helper and verifies fail-closed behavior on an unprovisioned hosted runner. It does not exercise the positive path under an installer-provisioned dedicated service SID, real ACLs, cross-process lock contention, directory substitution or interrupted replacement.

**Required correction**
Create a dedicated Windows integration test harness that provisions a disposable service identity and exact test directory ACLs, runs the helper as that identity, and cleans up only its own test resources. Required cases:
1. Positive BEGIN/READ/WRITE/END transaction under the provisioned service SID.
2. A normal user, local administrator without the service SID, LocalSystem without the service SID, and unrelated service SID are rejected.
3. Exact owner/DACL acceptance; inherited, extra, deny, callback, object, duplicate, wrong-mask and missing-SYSTEM ACE rejection.
4. Reparse point/junction/mount-point substitution at each path component is rejected.
5. Concurrent rename/delete/replacement attempts cannot redirect operations while a transaction is held.
6. Two independent helper processes serialize on the lock; timeout is bounded; termination releases the lock.
7. Interrupted writes preserve the last committed registry; orphan cleanup never follows a substituted name.
8. Malformed/truncated/oversized/reordered protocol frames and malformed registry JSON fail closed.
9. No secrets, registry payloads, OS exception details or filesystem paths appear in stdout, stderr, logs or process arguments.
10. Upgrade and service restart preserve the keyring and ACLs; uninstall behavior is tested without silently deleting recovery material.

The hosted Windows runner must actually execute these tests. A compile-only step or unprovisioned-identity smoke is not a substitute.

## Implementation sequence

1. Introduce a small Windows filesystem abstraction around safe handles and explicit ownership/disposal. Keep it internal to the helper.
2. Implement trusted parent-chain acquisition and validation; return a transaction-scoped object that owns all directory handles.
3. Move lock, registry read, temp creation, replacement, read-back and cleanup to operations rooted in that transaction object.
4. Add stable file identity checks (volume serial + file ID) and exact ACL checks for every managed object.
5. Add Windows adversarial integration tests before changing the production helper behavior.
6. Run exact-head Push and PR CI, then perform a clean Windows Server VM provisioning/upgrade/crash-recovery drill.
7. Only after all gates pass may the Node client be registered.

## Explicit non-goals and safety constraints

- No TCP/UDP scanning, port-range probing, NAT/DST-NAT/port mapping, SNMP SET, firewall modification, RouterOS changes or automatic unblock behavior.
- No fallback to LocalSystem or an interactive administrator.
- No caller-supplied paths, filenames, ACLs, commands or storage overrides.
- No automatic ACL repair or key deletion on validation failure.
- No Credential API wiring, Worker discovery handler activation, real-device secret entry, installer or Release in this milestone.

## CI evidence at review time

- `f428f63a7a30fdd67b5da9bd42cce94d4debd019`: PR workflow concluded `action_required`; GitHub reported zero jobs and zero check runs for this SHA. This is not a test failure, but it is not a successful validation either.
- `d947b5b3a9f574fa601496545137d4276954448e`: earlier Push and PR workflows completed successfully. The only subsequent commit to `f428f63` changed the root lockfile metadata; successful validation of the parent must not be represented as exact-head validation.

