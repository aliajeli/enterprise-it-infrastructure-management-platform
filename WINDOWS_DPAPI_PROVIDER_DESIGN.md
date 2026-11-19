# Windows Credential Key Protection — implementation design

**Status:** Design gate; no production DPAPI provider or recovery mechanism is implemented by this document.

## Security objectives

- Keep the AES-256-GCM envelope format in `apps/api/src/security/credential-vault-crypto.ts`; platform key protection must remain behind `CredentialKeyProvider`.
- Protect each 256-bit KEK with Windows DPAPI using machine scope, while binding decryption to the dedicated service identity through DPAPI optional entropy derived from a stable installation identifier and the service SID.
- Restrict keyring and helper access through explicit NTFS ACLs. The service identity must be a dedicated virtual/service account, not an interactive administrator or LocalSystem by default.
- Never pass key material in process arguments, environment variables, temporary plaintext files, logs, crash reports or command-line diagnostics.
- Fail closed on unsupported OS, missing helper, ACL mismatch, malformed keyring, unknown key version, DPAPI failure or recovery mismatch.

## Process boundary

The proposed Windows helper is a small, self-contained .NET 10 LTS executable, launched by an absolute installer-owned path. Node.js communicates over stdin/stdout using a length-prefixed binary protocol. The request contains an operation code, bounded payload length, installation identifier and opaque bytes; the response contains a status code and bounded opaque bytes. stdout is protocol-only. stderr is captured into a bounded buffer and sanitized; no key or plaintext is ever written there. No shell is used, and executable path/ACL/signature are validated during installation and service startup.

The helper performs only DPAPI Protect/Unprotect operations. It does not accept arbitrary commands, paths, process launch requests or caller-supplied DPAPI flags. Machine scope is fixed in code. Entropy is computed internally from a domain separator, installation ID and service SID; callers cannot choose an arbitrary entropy value. The helper validates framing, maximum message size, operation and key length before invoking DPAPI.

## Keyring and ACL model

The persistent key registry stores version IDs and DPAPI-protected KEK blobs only. It stores no plaintext KEK. Writes use a same-directory temporary file with restrictive inherited ACLs, flush-to-disk, atomic replacement and rollback-safe backup handling. The installation directory is created by the installer with an explicit DACL granting access only to the service SID, SYSTEM and Administrators; inheritance from user-writable parent directories is disabled. The provider must verify the expected owner and DACL before reading or replacing key material. It must not attempt to repair ACLs silently.

The active key version is explicit. Rotation creates a new random 32-byte KEK, persists and verifies its protected blob before switching the active version. Old versions remain decrypt-capable while any credential references them. Deletion requires a database reference count of zero and a separate audited administrative operation. Concurrent API instances are not supported for a local DPAPI keyring; a single-host service lock and atomic replacement are mandatory. Multi-host deployments require a different KMS/HSM design.

## Recovery is independent of DPAPI

Machine-scoped DPAPI blobs cannot be restored on a replacement host. Recovery therefore uses a separately generated recovery KEK that is not derived from DPAPI, the service SID, machine secrets, or the application binary. The recovery KEK must be generated and held through an owner-controlled offline custody process (for example, an HSM or encrypted removable recovery medium with split custody). The recovery export contains the KEK version registry encrypted under this independent recovery KEK, with authenticated metadata and a documented format version. The recovery KEK must never be stored beside the application, database, backup, DPAPI blob or service configuration.

A recovery drill must restore the exported key registry on a clean Windows host with a different machine identity and service SID, re-protect the recovered KEKs under the new host's DPAPI scope, then decrypt known non-production test credentials and verify AAD binding. The drill must prove that the old and new key versions remain available as expected. Until this passes, credential persistence and all production credential use remain disabled.

## Required implementation sequence

1. Build the helper and unit-test its binary framing, bounds and fail-closed behavior.
2. Add Windows-only DPAPI Protect/Unprotect integration tests under a dedicated non-admin service identity; verify machine scope and entropy binding.
3. Implement and test installer-created ACLs and provider ACL verification.
4. Implement persistent keyring atomicity, locking, versioning and rotation.
5. Implement independent recovery export/import and clean-machine restore drill.
6. Only then add Prisma credential records, ADMIN-only management APIs, audit and secret-redaction tests.

## Explicit non-goals

- No PowerShell helper, shell invocation, environment-variable key, plaintext key file, automatic firewall change, remote KMS assumption or DPAPI-only disaster recovery.
- No API route or discovery handler is enabled by this design.
- No real equipment credential may be entered until all mandatory gates above pass.
