# Windows Keyring Handle-Relative Filesystem Primitive

**Milestone:** 0.1.144  
**Status:** Handle-relative leaf open, rename and in-process failure cleanup are implemented. Crash-orphan enumeration and Windows adversarial acceptance remain open.

## Implemented operations

- The helper retains the ProgramData -> EnterpriseIT -> CredentialVault directory chain for the transaction. The Vault directory handle requests FILE_ADD_FILE and FILE_DELETE_CHILD for same-directory create and replace operations.
- Fixed leaf files are opened with NtCreateFile and OBJECT_ATTRIBUTES.RootDirectory.
- Lock acquisition, registry read/existence check and temporary-file creation are relative to the retained Vault handle.
- Registry replacement uses NtSetInformationFile(FileRenameInformation) with the retained Vault handle as RootDirectory.
- Temporary-file writes and flushes use RandomAccess directly on the SafeFileHandle. The helper does not wrap the handle in an owning FileStream.
- On every pre-rename failure after successful file creation, cleanup marks the exact temporary file handle for deletion with NtSetInformationFile(FileDispositionInformation). This includes failures during ACL/type verification and failures that previously occurred before FileStream construction.
- The temporary handle is closed after successful rename and before the committed destination is reopened for read-back.
- The committed registry is reopened relative to the Vault handle. Its volume/file ID is compared with the source handle identity, and its ACL, type, length and bytes are checked.

## Remaining limitations

- Abrupt process termination can leave a temporary file behind. There is no handle-relative directory enumeration or automatic crash-orphan cleanup yet. Such files are not safely removed by the current transaction cleanup.
- Native rename/disposition behavior and sharing semantics still require execution on each supported Windows Server baseline.
- There is not yet a provisioned-Service-SID positive integration suite or concurrent namespace-race acceptance suite. CI compilation is not proof of adversarial correctness.
- Parent owner/DACL baselines and exact Vault directory policy remain subject to the hardening review.
- The Node keyring adapter remains unregistered. Credential persistence is not enabled.

## Required acceptance gates

1. Exercise relative rename/replace and disposition deletion on supported Windows Server versions.
2. Verify old registry preservation for failures before rename and identity/byte verification after rename.
3. Add failure injection at create, ACL verification, write, flush, rename and read-back.
4. Add handle-relative directory enumeration for crash-leftover temporary entries; delete only an opened, identity-verified file handle.
5. Exercise concurrent rename/delete/junction replacement attempts while the chain is held.
6. Run positive transactions under the installer-provisioned dedicated service SID and test cross-process locking, crash recovery and power-loss behavior.
7. Only after all acceptance gates pass may the Node storage client be registered.

## Safety and release constraints

No subnet or port scanning, port mapping, NAT/DST-NAT, SNMP SET, firewall changes or automatic MikroTik unblocking. No production credential persistence, Worker discovery activation, installer or GitHub Release is implied by this primitive.
