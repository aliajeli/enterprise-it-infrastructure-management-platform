# Windows Credential Key Protection — implementation design

> **Implementation update (0.1.225): candidate DPAPI and keyring helpers and a TypeScript client exist with hosted fixture coverage, but they are not production-wired or independently approved, and recovery and real service-identity acceptance remain open. No real credentials should be entered. See [HANDOVER](HANDOVER.md).**


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

Machine-scoped DPAPI blobs cannot be restored on a replacement host. Recovery therefore uses an independent public-key envelope; removable media is not required and the private key is never installed on an operational server.

For each protected credential, generate a cryptographically random 256-bit data-encryption key (DEK). Encrypt the credential with AES-256-GCM using a fresh 96-bit nonce and a 128-bit authentication tag. Bind immutable context as AAD: format version, installation ID, credential ID, credential purpose/type and key version. The persisted envelope contains ciphertext, nonce, tag and two independent wrappers for the same DEK:

1. **Local-use wrapper:** protect the DEK with machine-scope DPAPI through the existing service-bound helper contract, with entropy bound to the dedicated service SID and installation ID. Only the dedicated service identity may unwrap it during normal operation.
2. **Recovery wrapper:** wrap the DEK with the recovery RSA public key using RSA-3072 OAEP with SHA-256. Store the public-key identifier and wrapped DEK with the envelope. The corresponding private key is held outside the operational environment.

The recovery public key is provisioned during installation through an authenticated, integrity-checked input. Its fingerprint and key identifier are pinned in installation metadata. The installer must reject an absent, malformed, weak or unexpected key; it must never silently generate a replacement recovery identity. Public-key rotation is explicit and versioned: new credentials use the new key, existing envelopes retain their prior recovery wrapper until a verified rewrap completes. Revocation and retirement require an audited rewrap/recovery plan.

The recovery private key is stored in an organization-managed password manager protected by MFA and least-privilege access. Enable audited emergency access and maintain an independent encrypted backup of the private-key material and recovery instructions. The password manager is a custody location, not a runtime dependency. Do not place the private key in the repository, installer, offline payload, application host, database, routine database backup, logs or environment variables. Do not transmit it to application services.

Recovery on a replacement host is an explicit administrative operation: obtain the private key through the approved custody process, unwrap the DEK, verify the authenticated context, and re-protect the DEK under the replacement host's DPAPI scope and new service identity. The recovery process must not emit plaintext credentials to disk, command-line arguments, environment variables or logs. If the recovery private key is unavailable or the authentication tag/AAD check fails, fail closed; do not fall back to an unprotected secret.

A recovery drill must use a clean Windows host with a different machine identity and service SID. Restore a non-production credential envelope, unwrap its DEK with the recovery private key, verify AAD and AES-GCM authentication, re-protect it with the new host's DPAPI scope, then prove that the service identity can decrypt the known test credential. Also verify that the old host cannot be assumed to decrypt on the new host without recovery. Record key IDs, test outcomes and operator identity without recording secret or key material.

## Key custody and operational controls

- Generate the RSA-3072 key pair using an approved cryptographic provider; keep the private key exportable only as required by the organization's recovery custody process and protect the exported representation with a strong passphrase and password-manager controls.
- Separate operational administration from recovery-key custody. Require MFA and audited privileged access; use dual authorization for emergency private-key retrieval where the organization's password manager supports it.
- Maintain an independent encrypted backup and periodically test that it can be restored. A password-manager account alone is not an adequate disaster-recovery plan.
- Record key identifier, public-key fingerprint, creation/activation/retirement times and rotation events. Never record private-key bytes, passphrases or plaintext DEKs.
- Treat a compromised recovery private key as a credential incident: revoke its key ID, rotate affected credentials and rewrap under a newly approved public key.

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
