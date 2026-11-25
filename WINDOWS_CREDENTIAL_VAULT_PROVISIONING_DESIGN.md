# Windows Credential Vault Provisioning Design

> **Implementation update (0.1.223): a candidate handle-relative provisioner and SYSTEM fixture tests exist; hosted CI passed policy, fault and limited concurrency tests. Actual service-SID transaction, ancestor trust, independent security review and supported Windows Server acceptance remain open. Orchestration mutation and real credential persistence remain disabled. Earlier design-only wording below is historical; see [HANDOVER](HANDOVER.md).**


Status: design baseline; implementation and target-Windows acceptance are pending.

## Purpose and security boundary

The Credential Vault storage helper deliberately refuses to operate unless the fixed
`%ProgramData%\\EnterpriseIT\\CredentialVault` directory and its `keyring.lock`
file already exist. It validates the opened objects by handle, including a protected
DACL with exactly two allow ACEs (the API service SID and LocalSystem), full-control
masks, and an owner equal to the API service SID. It also rejects reparse points.

The current installer/orchestrator does not create this store. The orchestration
preflight is a presence/reparse guard, not a provisioner. This document defines the
required provisioning contract; it does not claim that provisioning is implemented.

## Required ordering

1. Stage immutable application and helper payloads.
2. Create/configure the `EnterpriseITApi` SCM service and enable its unrestricted
   service SID. Do not start it.
3. Resolve the service SID from SCM (`sc.exe showsid EnterpriseITApi`) and validate
   the canonical `S-1-5-80-...` SID format.
4. Provision the Vault directory and lock file as an elevated installer operation.
5. Re-open and validate both objects by handle. Any mismatch aborts installation.
6. Only after successful Vault validation may the orchestrator proceed with the
   remaining service provisioning and start sequence.
7. API service startup remains blocked until the keyring helper can acquire and
   validate the lock file.

The provisioner must be idempotent for an already-correct store. It must never
silently repair, replace, take ownership of, or loosen an existing store whose
owner, DACL, file type, volume, or reparse status is unexpected.

## Exact object security descriptor

Both the Vault directory and `keyring.lock` must have:

- Owner: the exact `EnterpriseITApi` service SID.
- Protected DACL (inheritance disabled).
- Exactly two explicit, non-inherited allow ACEs:
  - API service SID: `FILE_ALL_ACCESS` / `0x001F01FF`.
  - LocalSystem (`S-1-5-18`): `FILE_ALL_ACCESS` / `0x001F01FF`.
- No additional ACEs, deny ACEs, callback ACEs, inherited ACEs, or generic/broader
  principals.

The canonical SDDL shape is:

```text
O:<API_SERVICE_SID>D:P(A;;FA;;;<API_SERVICE_SID>)(A;;FA;;;SY)
```

The runtime helper's current `VerifyAcl` implementation is authoritative for the
exact owner, protected DACL, ACE count, ACE flags, qualifiers, masks, and principals.
The provisioner must produce a descriptor that passes that verifier without
weakening it.

## Creation and validation requirements

- Use native Windows security-descriptor APIs and pass an explicit security
  descriptor at object creation time; do not create a permissive object and later
  attempt to tighten it.
- Create the directory and lock file with create-new semantics. If either already
  exists, open the existing object without following reparse points and validate
  it; do not overwrite it.
- Open path components with reparse-point awareness. Reject junctions, symlinks,
  mount points, non-directory parents, and volume-boundary changes.
- Validate the parent chain from the OS-known ProgramData directory through
  `EnterpriseIT` and into `CredentialVault`. Parent trust must be established
  before creating children; merely checking a leaf's attributes is insufficient.
- Validate directory/file type, owner, protected DACL, volume identity, and reparse
  status from handles, not from path-only `Get-Item` or `Test-Path` checks.
- The lock file must be a regular, non-reparse file. It may be zero length; it is
  an exclusion primitive, not a secret store.
- Hold no persistent lock handle from the elevated provisioner. The runtime helper
  owns exclusive lock acquisition when the API performs a keyring transaction.
- Do not place secrets, DPAPI master material, recovery private keys, or keyring
  contents in installer arguments, environment variables, logs, or temporary
  files.
- Never change firewall rules, router configuration, MikroTik policy, NAT,
  DST-NAT, or port mappings as part of Vault provisioning.

## Failure and recovery behavior

Provisioning is fail-closed. On any API failure, unexpected existing object,
unexpected parent security, reparse point, volume mismatch, or post-create
verification mismatch:

- Stop before starting EnterpriseITApi.
- Do not delete or replace an unexpected pre-existing object.
- If this invocation created a new object and a later step fails, remove only that
  exact object using its retained handle and only if its file identity still matches
  the identity captured at creation.
- If cleanup cannot be proven safe, leave the object in place, report a generic
  provisioning failure, and require an administrator-led inspection.
- Never attempt broad recursive cleanup of ProgramData.

## Required tests before integration

1. Fresh provisioning produces a directory and lock file accepted by the runtime
   helper's exact ACL verifier.
2. A second run is idempotent and preserves file identity and bytes.
3. Wrong owner, unprotected DACL, extra ACE, inherited ACE, wrong mask, and
   unexpected principal are rejected without mutation.
4. Directory and lock-file reparse points are rejected.
5. Parent reparse points, untrusted parent write permissions, and volume changes
   are rejected.
6. Existing directory/file collisions are not overwritten.
7. Failure after directory creation cleans up only the exact newly-created object;
   injected cleanup failure remains fail-closed.
8. Concurrent installer attempts cannot replace or race the directory/lock object.
9. API startup is not attempted if provisioning or post-create validation fails.
10. A clean supported Windows Server VM validates provisioning under the actual
    elevated installer token and runtime access under `NT SERVICE\\EnterpriseITApi`.

## Current implementation status

- Runtime helper handle-based owner/DACL and reparse checks: implemented in source;
  supported Windows Server adversarial acceptance remains pending.
- Orchestration presence and reparse preflight: implemented and regression-tested.
- Elevated Vault directory/lock provisioner: not implemented.
- Parent trust/ACL validation for the provisioner: not implemented.
- Node keyring adapter registration and durable credential persistence: not enabled.
- Installer/release integration and clean-VM acceptance: not complete.

Do not mark the Credential Vault, Windows installer, or deployment phase complete
until the required tests and target-OS acceptance gates have passed.
