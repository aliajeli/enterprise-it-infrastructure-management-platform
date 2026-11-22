## Implementation status update — 2026-11-23 (branch revision 0.1.137)

The first parent-chain mitigation is now wired into the helper transaction lifecycle. `WindowsDirectoryHandleChain.OpenKnownProgramData()` acquires the local volume root and opens ProgramData, EnterpriseIT and CredentialVault relative to retained parent handles. It rejects reparse-point directory components and volume changes. These handles are held from BEGIN until process exit and are opened without FILE_SHARE_DELETE. Vault owner/DACL checks use the retained Vault handle.

This partially mitigates F-01 and F-02 at the parent-directory level. It does **not** close either finding completely: the helper's lock, registry, temporary-file, replacement and cleanup operations still resolve leaf names through paths. F-03 and F-04 are unchanged. No positive provisioned-Service-SID integration or adversarial namespace tests have been added, so F-05 remains blocking. The Node keyring adapter remains unregistered; no credential persistence or production approval is granted.

