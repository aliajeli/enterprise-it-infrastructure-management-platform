# Windows Keyring Handle-Relative Filesystem Primitive

**Milestone:** 0.1.34 groundwork  
**Status:** Isolated compile-time primitive; not wired into keyring storage and not security-approved.

## Purpose

WindowsDirectoryHandleChain introduces a narrow primitive for acquiring and retaining:

- local volume root
- ProgramData
- EnterpriseIT
- CredentialVault

The volume root is opened from the OS-known CommonApplicationData location. Each child is opened relative to its already-open parent using NtCreateFile and OBJECT_ATTRIBUTES.RootDirectory. Directory handles deny FILE_SHARE_DELETE and remain owned by one disposable chain object. Child names are fixed; no caller-provided path is accepted.

For each opened component the primitive verifies directory type, rejects reparse points, verifies the volume serial, and obtains the file ID from the opened handle.

## Important limitations

This milestone deliberately does not change Program.cs storage operations. Existing lock, read, write, replace and cleanup operations remain path-based. The new chain is not called by the helper, the Node client remains unregistered, and no credential may be stored through it.

The class also does not establish the complete security proof:
- Parent owner/DACL baselines and the exact vault ACL are not checked.
- The ProgramData path is constrained to the standard local <drive>:\\ProgramData layout; nonstandard deployments fail closed.
- File IDs are collected but no operation yet consumes them for before/after identity binding.
- Native interop layouts and share-mode behavior require supported-Windows-version testing.
- Share-mode pinning alone is not claimed to prevent every rename or namespace race.

## Native API contract

- NtCreateFile opens only one fixed single-component child relative to a retained parent handle.
- OBJECT_ATTRIBUTES uses OBJ_CASE_INSENSITIVE and a non-null RootDirectory.
- CreateDisposition is FILE_OPEN; runtime does not create or repair directories.
- CreateOptions includes FILE_DIRECTORY_FILE, FILE_OPEN_REPARSE_POINT and FILE_SYNCHRONOUS_IO_NONALERT.
- Share access is read/write only; delete sharing is omitted.
- NTSTATUS is translated through RtlNtStatusToDosError; native diagnostics are not sent over the helper protocol.
- Parent handles are held with DangerousAddRef across the native call and disposed in reverse chain order.

## Required next implementation gates

1. Add a Windows test harness on supported Windows Server images; verify directory type, reparse rejection, volume identity and file-ID stability.
2. Exercise concurrent rename/delete/junction replacement attempts while the chain is held. Tests must prove operations cannot be redirected, not merely that an open succeeded.
3. Add parent-component owner/DACL policy checks and exact vault ACL verification against handles.
4. Extend the transaction object so lock, registry, temporary-file creation, rename/replace, read-back and cleanup are all relative to retained directory handles. No path-based fallback.
5. Add file identity checks before and after every mutation, and fail closed on any mismatch.
6. Add crash/failure injection and multi-process lock tests under the provisioned dedicated service SID.
7. Only after the full Windows acceptance suite passes may the Node storage client be registered.

## Safety and release constraints

No subnet or port scanning, port mapping, NAT/DST-NAT, SNMP SET, firewall changes or automatic MikroTik unblocking. No production credential storage, Worker discovery activation, installer or GitHub Release is part of this milestone.
