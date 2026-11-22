# Windows Credential Recovery Architecture

**Status:** Approved architecture; implementation and production acceptance are not complete.

## Decision

USB and other removable media are not required. Windows local operation and disaster recovery use two independent protection paths for each credential's random data-encryption key (DEK):

- Local operation: machine-scope DPAPI, bound to the dedicated Windows service SID and installation ID.
- Disaster recovery: RSA-3072 public-key wrapping with OAEP-SHA-256. The private key is held outside the operational environment in an organization-managed password manager.

The application never needs the recovery private key during normal operation.

## Envelope format

Each credential receives a fresh random 32-byte DEK. The secret is encrypted with AES-256-GCM, using a fresh 12-byte nonce and a 16-byte authentication tag. Authenticated additional data (AAD) is a canonical, fixed-order encoding of:

- envelope format version;
- installation ID;
- credential ID;
- credential purpose/type;
- DEK/key version.

Persist the ciphertext, data nonce, authentication tag, DPAPI-protected DEK, RSA-wrapped DEK, recovery public-key ID and algorithm identifiers. Never persist a plaintext DEK.

The DPAPI wrapper is host-bound and service-identity-bound. The RSA wrapper is independent of the host and permits controlled recovery. Both wrappers protect the same DEK; they are not cascaded encryption layers. AES-GCM authenticates the credential and its context.

## Public-key enrollment

The installer receives an authenticated recovery public key through an explicit, integrity-checked input. It validates RSA key size and algorithm parameters, computes a stable fingerprint, and pins the key ID/fingerprint in protected installation metadata. Missing, malformed, weak or unexpected keys cause a fail-closed preflight error before any service or database mutation.

The installer must not generate an untracked recovery key pair, silently substitute a key, or accept a public key merely because it is present in the payload. The expected fingerprint must be conveyed through a separately trusted channel.

## Private-key custody

The private key is not deployed to the server and is never included in:

- Git repository or CI artifacts;
- installer or offline deployment payload;
- application database or routine database backup;
- service configuration, environment variables, command-line arguments or logs.

Store it in an organization-managed password manager with MFA, least-privilege access, audited emergency retrieval and an independent encrypted backup. Keep recovery instructions and key identifiers with the custody record, not the private key in operational configuration. Dual authorization is recommended for emergency retrieval where supported.

The password manager is a custody location only. Runtime application services must not call the password manager or hold its credentials.

## Recovery procedure

1. Provision a clean replacement Windows host and install the approved application payload.
2. Verify the installation ID, recovery key ID and public-key fingerprint against the recovery record.
3. Obtain the private key through the approved, audited custody process.
4. Use a dedicated, non-interactive recovery utility to unwrap the DEK in memory and verify the AES-GCM tag and canonical AAD.
5. Re-protect the DEK with the replacement host's DPAPI scope and new dedicated service SID.
6. Verify service-identity decryption against a non-production known-answer credential before enabling production services.
7. Record operator, key ID, timestamps and result; never record secret, DEK, private key or passphrase.

The recovery utility must not place plaintext secrets or key material in files, process arguments, environment variables, logs or crash diagnostics. It must fail closed on key-ID mismatch, malformed envelope, AAD mismatch, authentication failure or unavailable private key.

## Rotation and revocation

Recovery keys are versioned. New credentials use the active public key. Existing credentials retain their prior RSA wrapper until a tested rewrap operation succeeds. Retire an old private key only after inventory proves that no required credential envelope depends on it, or after all such envelopes have been rewrapped and independently verified.

A suspected private-key compromise requires an incident response: revoke the affected key ID, provision a new key pair, rotate affected database credentials and rewrap remaining envelopes. Preserve an auditable record without retaining secret material.

## Acceptance gates

- Cryptographic unit tests: valid round trip; ciphertext, nonce, tag and AAD tampering; wrong private key; wrong key ID; unsupported format; malformed and oversized input.
- DPAPI integration tests under the dedicated service identity; verify machine and service-SID binding.
- Public-key enrollment tests: invalid key size/algorithm, fingerprint mismatch, absent key and substitution attempts all fail before host mutation.
- Recovery drill on a clean Windows host with a different machine identity and service SID.
- Verify private key absence from server, payload, installer, logs, process arguments and environment.
- Verify credential rotation, recovery-key rotation, revocation and interrupted-rewrap behavior.
- Only after all gates pass may PostgreSQL administrator credential persistence and production credential use be enabled.

## Current implementation boundary

This document defines the approved target architecture. The current TypeScript credential envelope uses an AES-GCM KEK wrapper and the existing DPAPI helper protects service-bound key material. They do not yet implement the dual DPAPI/RSA DEK wrapper described here. PostgreSQL bootstrap still has a transient plaintext password-file staging step; this design does not claim to eliminate that path. Installer integration, recovery utility, durable bootstrap state machine, API/Worker role provisioning and clean Windows Server acceptance remain open.
