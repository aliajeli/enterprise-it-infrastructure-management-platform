# Windows Credential Keyring Storage Adapter — implementation contract

**Status:** Design gate; no production storage adapter is implemented by this document.  
**Applies to:** Credential Vault keyring on Windows Server under the dedicated API service identity.  
**Security posture:** Fail closed. Until the adapter and its Windows integration tests pass, the keyring remains test-only and real equipment credentials must not be entered.

## 1. Scope and non-goals

Implement the existing `CredentialKeyringStorage` contract using a fixed-purpose .NET 10 helper. The adapter persists only the versioned JSON keyring containing DPAPI-protected KEK blobs. It must never persist plaintext KEKs or credential secrets.

The helper is not a general filesystem broker. It must not accept arbitrary paths, shell commands, caller-selected ACLs, or arbitrary file operations. It must not alter Windows services, firewall rules, RouterOS settings, network configuration, or equipment.

The existing DPAPI operation remains separate. The storage helper may share the binary framing library, but it must not weaken the DPAPI helper's fixed-purpose protocol or expose key material through command-line arguments, environment variables, logs, exception text, or temporary plaintext files.

## 2. Fixed storage identity and path

- Resolve the service identity from the actual process token; require a configured dedicated virtual service account / service SID. Do not silently fall back to LocalSystem, an interactive administrator, or the launching user's profile.
- Resolve the service SID from the process token and validate that it is a service SID. The installer must provision the service identity before the API service starts.
- The only permitted storage root is `%ProgramData%\\EnterpriseIT\\CredentialVault\\`, resolved from the OS-known CommonApplicationData location. The registry filename is fixed as `keyring.v1.json`; the lock filename is fixed as `keyring.lock`.
- No request frame may contain a path, filename, drive, UNC location, alternate stream, or path component.
- Canonicalize the resolved root and every opened handle. Reject reparse points, symbolic links, mount-point redirection, unexpected volume/final paths, alternate data streams, and any attempt to escape the fixed root. Use handle-based checks to avoid check-then-open path races.
- Create the directory hierarchy only beneath the trusted ProgramData root. Do not follow pre-existing reparse points. If an existing directory or file has an unexpected owner or DACL, stop; do not silently repair or broaden it during normal reads/writes.

## 3. Owner and DACL policy

The installer is responsible for creating the storage directory and service identity before first launch. The helper verifies security on every operation, not only at initialization.

Expected security descriptor:
- Owner: the dedicated API service SID.
- Explicit allow ACEs only: the dedicated API service SID (required read/write/delete-child rights on the storage directory; required read/write rights on keyring and lock files) and `NT AUTHORITY\\SYSTEM` (full control).
- No Administrators, Users, Authenticated Users, Everyone, interactive user, or unrelated service SID ACE.
- Protected DACL; inheritance disabled on the CredentialVault directory and each managed file. No inherited or deny ACEs are accepted in the initial policy.
- No unrecognized ACE type, object ACE, callback ACE, or duplicate ACE. Compare normalized SID, ACE type, inheritance flags, and exact access mask against the policy; do not merely check that the expected SIDs appear.
- Owner and DACL are verified using the opened handle's security descriptor to reduce path substitution races. Verify parent directory, lock file and keyring file before use. A missing keyring is valid only during initialize; missing or malformed lock infrastructure is an error.

If an ACL mismatch is found, return a generic security failure, do not read or overwrite the keyring, and require an explicit installer repair procedure with audit. The runtime helper must not automatically broaden access or take ownership.

## 4. Cross-process transaction lock

The lock must cover the complete `CredentialKeyringStorage.withExclusiveLock` callback, including read, DPAPI calls, atomic write, read-back verification and rotation. A process-local JavaScript mutex is insufficient.

Use a long-lived helper session for each storage transaction:
1. The Node adapter starts the fixed helper executable with no arguments and no secret-bearing environment variables.
2. The helper validates its own executable/runtime context and service SID, verifies the storage directory and lock-file ACL, then acquires a named mutex or exclusive lock with a fixed application namespace and a restrictive security descriptor.
3. The helper retains ownership for the full transaction while accepting only bounded `READ`, `WRITE_ATOMIC` and `END` protocol messages. The helper must not release the lock between individual storage calls.
4. The Node adapter associates storage calls with the active async transaction context; nested/re-entrant transactions are rejected. Concurrent operations in one process are serialized, while other API processes block with a bounded timeout.
5. On normal completion, send `END` and release the lock. On process crash, pipe closure, cancellation or timeout, the helper exits and the OS releases the lock. Abandoned mutex/lock state is treated as a reason to re-verify the complete registry and ACL before continuing.
6. A lock timeout is a hard error. Do not bypass the lock or fall back to an unlocked read/write.

If a named mutex is selected, its DACL must be restricted to the service SID and SYSTEM; validate abandoned-mutex behavior and ensure ownership/release occur on the same helper thread. If an exclusive lock file is selected, use a handle held open with sharing denied for the entire transaction and verify its ACL before acquisition. The final implementation must choose one primitive and test it across separate OS processes.

## 5. Atomic durable write

- Serialize and validate the complete bounded registry before opening the destination.
- Create a unique temporary file in the same directory using create-new semantics; never use a shared predictable temp name.
- Open with restrictive sharing and non-inheritable handles. Apply the exact protected owner/DACL before writing; verify it through the handle.
- Write UTF-8 bytes, flush managed buffers, then call `FlushFileBuffers` on the file handle.
- Replace the destination atomically on the same volume using a Windows replacement primitive (`ReplaceFileW` for an existing destination; a write-through same-directory move for first creation). Never delete the old keyring before the replacement is committed.
- Re-open the committed destination by handle, verify canonical path, owner/DACL, length bounds and exact bytes. The keyring layer then parses it and performs its existing DPAPI read-back verification.
- On failure, leave the last committed registry intact, remove only the helper-created temporary file after verifying it is still beneath the fixed root, and return a generic error. Do not emit registry contents or protected blobs to logs.
- Test power-loss/interrupted-write behavior as far as Windows CI can simulate; document that CI fault injection is not a substitute for a real VM crash/power-loss drill.

## 6. Binary helper protocol

Extend the fixed-purpose helper with a versioned, length-prefixed binary session protocol over stdin/stdout. Stderr is discarded by the Node client and must never contain request data or secrets.

Required message types:
- `BEGIN_TRANSACTION`: acquire and verify lock; response indicates success/failure only.
- `READ_REGISTRY`: return a bounded registry payload or an explicit not-found status. No paths are accepted.
- `WRITE_REGISTRY_ATOMIC`: accept one bounded UTF-8 JSON payload; reject malformed framing, oversized payloads and invalid UTF-8.
- `END_TRANSACTION`: flush protocol state and release the lock.
- `ERROR`: stable generic status codes only; never include OS exception messages, paths, SIDs beyond non-secret diagnostics, file contents or cryptographic bytes.

Protocol requirements: reject unknown versions/opcodes, truncated frames, trailing bytes, repeated BEGIN, READ/WRITE outside a transaction, duplicate END, oversized messages and unexpected extra input. Apply an idle/overall timeout. Zero mutable request/response buffers where practical. The helper must not log raw frames.

## 7. Node adapter contract

- Implement `CredentialKeyringStorage` only on Windows and only when running under the provisioned service identity. Non-Windows construction/registration must fail closed.
- The configured helper path is a fixed installer-owned absolute path. Verify its canonical location and ACL before launch; a merely absolute path is not sufficient.
- The adapter must use `spawn` without a shell and without caller-controlled arguments. It must enforce response-size limits, strict framing, exit-code checks, timeouts and process cleanup.
- `withExclusiveLock` creates one helper session and retains it through the callback. `read` and `writeAtomic` are legal only in that session. No unlocked fallback is allowed.
- The storage adapter must not return raw helper diagnostics to HTTP clients. All errors are generic and secret-safe.

## 8. Windows acceptance tests

Run these tests on Windows CI with the actual .NET helper and separate OS processes, not only mocks:
1. Provisioned service SID can initialize, read, rotate and read back the registry.
2. A second process cannot enter a transaction until the first releases the lock; lock timeout is deterministic.
3. Process termination while holding the lock releases it; the next process can recover after ACL and registry validation.
4. Concurrent independent processes rotating the keyring produce unique monotonically increasing versions without lost updates.
5. Interrupted atomic write preserves the previous valid registry; orphan temp files are safely cleaned without following reparse points.
6. Tampered owner, inherited ACE, extra SID ACE, wrong access mask, missing SYSTEM ACE and reparse-point substitution all fail closed without reading or changing registry contents.
7. Path traversal, UNC paths, alternate data streams and caller-supplied path fields are impossible at the protocol boundary.
8. Oversized, malformed, truncated, replayed/out-of-order and unknown protocol frames are rejected.
9. Corrupt JSON, invalid Base64, missing registry, malformed protected blobs and DPAPI failure produce generic errors and no secret-bearing output.
10. A normal user, local Administrators member and unrelated service SID cannot read or modify the registry or acquire the transaction lock.
11. API process restart and helper crash do not leave stale lock ownership or accept an unverified registry.
12. A clean Windows VM install provisions the service SID and ACL before the API starts; upgrade preserves the keyring and permissions.

## 9. Rollout and release gates

Implementation order:
1. Add protocol contract tests and helper-side path/ACL primitives.
2. Implement the helper session and cross-process transaction lock.
3. Implement read and atomic replace with exact ACL verification.
4. Implement the Node adapter and wire it only in the Windows service composition root.
5. Run the complete Windows integration suite and existing Linux/PostgreSQL CI on the exact commit.
6. Perform clean-VM install/upgrade and crash-recovery drills.
7. Only then consider independent recovery export/custody and credential database/API work.

Until all gates pass: keep the adapter unregistered, keep Worker discovery handlers empty, do not store real equipment credentials, do not enable SNMP/SSH/ISAPI polling, and do not publish an installer or Release.


## 10. Version 1 wire contract — frozen before helper implementation

All integers are unsigned big-endian. Each frame is exactly:

| Offset | Size | Field |
|---:|---:|---|
| 0 | 1 byte | Protocol version, exactly `1` |
| 1 | 1 byte | Opcode |
| 2 | 4 bytes | Payload length |
| 6 | declared length | Payload |

The maximum payload is 32 KiB. The complete frame must contain exactly the declared number of payload bytes; truncated frames, trailing bytes, unknown opcodes, unsupported versions and invalid UTF-8 registry payloads are rejected. No path, SID, ACL, command line or caller-selected operation parameter is carried in a frame.

Request opcodes: `BEGIN_TRANSACTION=0x01`, `READ_REGISTRY=0x02`, `WRITE_REGISTRY_ATOMIC=0x03`, `END_TRANSACTION=0x04`. Response opcodes: `BEGIN_OK=0x81`, `READ_RESULT=0x82`, `WRITE_OK=0x83`, `END_OK=0x84`, `ERROR=0xff`. `READ_RESULT` begins with a one-byte status (`0` = registry found followed by exact UTF-8 JSON bytes; `1` = not found and no remaining bytes). `ERROR` contains exactly one stable error code byte; it never carries OS exception text, paths or registry content. Empty control responses have zero-length payloads.

This commit adds only the Node-side framing codec and unit contract tests. The .NET helper does not yet implement these operations, the adapter is not registered, and no Windows filesystem ACL or atomic-write claim is made. The helper implementation must consume this exact contract and add Windows process/ACL integration tests before production registration.


## 11. Node helper-session transport milestone

Added a Windows-only, deliberately unregistered Node transport client for the frozen v1 protocol. It starts the helper without a shell or arguments, retains one helper process across the full keyring callback, serializes in-process transactions, rejects nested/out-of-transaction access, enforces frame bounds and operation ordering, and kills the helper on protocol/operation failure. Unit tests use an in-memory fake process to verify transaction framing and fail-closed boundaries.

This is transport groundwork, not a usable storage adapter: the .NET helper still does not implement the storage opcodes, service SID and exact NTFS ACL verification are not implemented, no cross-process lock or atomic filesystem write exists, and the client is not registered. Do not enable credential persistence or enter real equipment credentials.


## 12. First Windows helper implementation milestone (0.1.18)

Added a separate .NET 10 Windows executable at `apps/api/windows/keyring-storage-helper`. It implements the frozen v1 session frame contract and fixed-purpose operations only: begin transaction, read the one fixed registry, atomically write bounded UTF-8 JSON, and end transaction. It accepts no path, SID, ACL, command, or environment-supplied storage override.

Security behavior is intentionally fail-closed:
- Requires exactly one service SID in the current process token; interactive users, LocalSystem without the dedicated service SID, and unrelated service identities fail.
- Requires the installer-provisioned fixed ProgramData directory and lock file to exist. It does not create or repair them.
- Uses a fixed lock file opened with exclusive sharing for the full helper session; process exit releases the OS handle.
- Checks owner, protected DACL, exact two allow ACEs (service SID and SYSTEM), exact Full Control masks, and reparse-point status using opened handles.
- Reads only the fixed registry path and bounds content to 32 KiB.
- Creates a random same-directory temporary file with a protected explicit owner/DACL, flushes it to disk, replaces the destination using same-volume write-through move semantics, and verifies the committed file through a handle.
- Uses a bounded idle read timeout and stable generic protocol errors; no exception details or filesystem paths are returned on stdout.

This is an implementation milestone, not production acceptance. No installer provisioning for the service SID/directory/lock file exists yet; therefore the helper is expected to fail closed on an unprovisioned host. Windows CI currently builds the executable but does not yet run dedicated-service-SID ACL, multi-process contention, tamper, or crash-recovery integration tests. The Node transport remains unregistered. Do not enter real equipment credentials or enable discovery.


## 13. Fail-closed process smoke and service SID token resolution (0.1.21)

The helper resolves the dedicated service SID from either the token's User SID or token Groups, deduplicates it, and requires exactly one unique `S-1-5-80-...` identity. It never falls back to LocalSystem or an interactive user identity.

Windows CI now launches the built helper as a separate process on the unprovisioned hosted runner, sends a BEGIN frame, and verifies the exact generic ERROR response, non-zero process exit, and empty stderr. This confirms the helper rejects the runner's unprovisioned identity/storage context without leaking diagnostics. It is not a substitute for integration tests under the installer-provisioned service identity.


## 14. Helper process shutdown contract (0.1.25)

After the helper acknowledges END_TRANSACTION with END_OK, the Node client closes helper stdin and waits for the process close event. Exit code 0 is required. A non-zero exit or timeout fails the enclosing storage transaction; it is not converted into a successful callback result. The client kills the helper on shutdown failure and releases its in-process transaction queue in a finally path. Unit tests cover successful exit and non-zero exit after END_OK.

This confirms process lifecycle only; it does not establish installer provisioning, ACL correctness under a provisioned service SID, or cross-process filesystem acceptance.
