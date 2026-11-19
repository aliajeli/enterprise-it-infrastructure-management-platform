# Credential Vault Independent Recovery Design

Status: design proposal; implementation and operational approval required  
Version: 1.0  
Date: 2026-11-20

## 1. Objective and non-goals

Provide a recovery path for Credential Vault key material after loss of the original Windows host, while remaining independent of Windows DPAPI machine scope. A successful recovery must restore access to historical credential ciphertext without ever placing plaintext KEKs in a normal backup, export file, log, command line, environment variable, or temporary file.

This document does not authorize production credential storage, automatic discovery, or release. The keyring Storage Helper and DPAPI Helper remain unregistered.

## 2. Threat model and trust boundaries

Assume:
- The original Windows host, its OS disk, and DPAPI machine state can be permanently lost.
- Database backups and recovery packages may be copied, disclosed, or modified by an attacker.
- An attacker may obtain the database and encrypted recovery package but must not obtain the offline recovery private keys.
- A compromised API process may invoke the DPAPI helper only when running under the provisioned dedicated service SID; it may still access plaintext KEKs in process memory while authorized operations execute.
- An ordinary domain administrator, interactive user, Operator, or Viewer must not be able to export or restore key material merely by invoking an executable.

Trust anchors:
1. Dedicated Windows service SID and installer-provisioned filesystem ACLs on the active host.
2. Recovery encryption public key pinned in installer-provisioned, ACL-protected configuration.
3. Offline recovery private key held outside the production host, preferably in an HSM or hardware-backed key store with dual-control custody.
4. Separate offline signing key used to authenticate recovery package manifests.

The recovery private keys must never be stored on the production server, in the application database, in the same backup repository as the recovery package, or in the same cloud account without an independently controlled security boundary.

## 3. Key hierarchy

- Each credential retains its own random 256-bit DEK and AES-256-GCM envelope.
- A versioned 256-bit KEK wraps each DEK.
- The active KEK and historical KEKs are DPAPI-protected under LocalMachine scope with optional entropy bound to the installation ID and dedicated service SID. This is the online keyring.
- For disaster recovery only, each KEK version is independently wrapped to an offline RSA-3072 recovery public key using RSA-OAEP-SHA256. The recovery private key is not present on the host.
- A separate RSA-3072 signing key signs the exact canonical manifest bytes with RSA-PSS-SHA256. Do not reuse the encryption keypair for signing.

The recovery copy is an additional envelope for each KEK, not a replacement for DPAPI. DPAPI remains the online protection mechanism; offline RSA recovery is the independent disaster-recovery mechanism.

## 4. Recovery package format

Package format identifier: `EIT-CREDENTIAL-RECOVERY`; format version: 1.

The signed manifest must contain:
- format identifier and version;
- immutable installation ID;
- creation timestamp in UTC;
- recovery encryption key ID and signing key ID;
- ordered key entries, each with key version, creation timestamp, DPAPI keyring format version, and Base64 RSA-OAEP wrapped 32-byte KEK;
- explicit algorithm identifiers and fixed parameters;
- package sequence number and previous-package digest where available.

The manifest must not contain:
- plaintext KEKs or DEKs;
- credential secrets or credential ciphertext;
- passwords, passphrases, private keys, tokens, or environment values;
- filesystem paths, hostnames, user names, or unnecessary infrastructure metadata.

Canonicalization: serialize with a fixed property order, UTF-8 without BOM, no insignificant whitespace, and deterministic array ordering by key version. The verifier must parse, validate all fields and bounds, reserialize, and require byte-for-byte equality before signature verification. Sign the exact canonical bytes with RSA-PSS-SHA256. Reject unknown fields and algorithms in v1; do not silently downgrade.

Bounds:
- maximum 64 KEK entries, matching the current keyring capacity;
- exactly 32 bytes per unwrapped KEK;
- maximum manifest size 64 KiB;
- strict Base64 validation and exact decoded ciphertext length for the configured RSA modulus;
- reject duplicate key versions, duplicate package sequence numbers, invalid timestamps, unknown key IDs, wrong installation ID, and unsupported formats.

The package contains only encrypted KEKs and metadata. It does not include a database backup. Database backup and recovery package must be versioned and retained as separate artifacts with a shared restore record.

## 5. Export workflow

1. Require ADMIN authorization, recent MFA, and a second authorized approver for export/rotation/recovery operations.
2. Verify the online keyring, active key, every retained historical key, and all database key-version references before export.
3. For each retained KEK, unprotect it using the existing DPAPI helper under the dedicated service SID, wrap it immediately to the pinned recovery public key, and zero the temporary plaintext buffer on a best-effort basis.
4. Build and sign the canonical manifest using the offline signing system. The signing private key must not be copied to the application host. If remote HSM signing is used, it must require a narrowly scoped, audited signing request and dual approval.
5. Write only the encrypted package to a user-selected destination through a safe export API. Do not write plaintext KEKs to disk or temporary files. Avoid logging package contents or sensitive metadata.
6. Record actor, approver, key IDs, key versions, package digest, timestamp, destination classification (not full path), and result in the tamper-resistant audit trail.
7. Verify the completed package by re-reading it and checking canonical form and signature. Do not claim a backup is recoverable until the independent restore drill passes.

Export must never silently omit a historical KEK. If any key version cannot be unwrapped, wrapped, or verified, fail the entire export.

## 6. Restore workflow on a clean Windows host

1. Install the same product version or a migration-compatible version. Provision the same dedicated service identity/service SID, fixed ProgramData directory, lock file, helper executable ACLs, and exact DACLs through the signed installer.
2. Restore the matching database backup into an isolated environment. Keep API and Worker discovery disabled.
3. Import the recovery package through a dedicated recovery utility, not through a general API endpoint.
4. Verify the package signature against a pre-provisioned trusted signing public key; validate canonical bytes, algorithms, bounds, package sequence, installation ID and key versions.
5. Obtain the offline recovery private key through an HSM/hardware-backed provider. Require dual control and an explicit restore approval. Do not place private key material in files, process arguments, environment variables, logs, clipboard, or application settings.
6. Unwrap every KEK in memory, validate exact 32-byte length, and immediately re-protect it with DPAPI on the new host under the dedicated service SID and the original immutable installation ID.
7. Persist the new DPAPI-protected keyring atomically through the Windows Storage Helper. Read it back, unprotect each entry, and compare in constant time before declaring success.
8. Verify every credential ciphertext can be authenticated/decrypted in a controlled test against its AAD metadata; do not reveal secret values in the UI or logs.
9. Reconcile the restored database's key-version references. No key version may be removed while any credential record or retained backup requires it.
10. Keep the service in maintenance mode until the owner approves a restore report. Re-enable API and Worker separately; never automatically start discovery after restore.

The installation ID remains unchanged across host recovery because it participates in credential AAD and DPAPI entropy. The DPAPI-protected bytes are regenerated for the new machine; the immutable installation ID and credential AAD are not rewritten.

## 7. Rotation, retirement and revocation

- Recovery encryption and signing key IDs are versioned independently from KEK versions.
- Rotation requires a new public key to be provisioned before it becomes active.
- Generate a new signed recovery package containing every retained KEK under the new recovery public key; verify a restore drill before retiring the old recovery key.
- Retain old offline private keys while any retained package or backup depends on them.
- KEK retirement is a separate audited operation requiring database reference accounting and backup-retention analysis. The current 64-version fail-closed limit remains; no automatic deletion is allowed.
- If an offline private key is suspected compromised, freeze exports/restores, rotate to a new keypair, generate a new package, verify clean restore, and document exposure of all packages encrypted to the compromised key.

## 8. Operational custody

Minimum recommended custody:
- Recovery encryption private key: offline HSM or hardware-backed token, two-person approval.
- Recovery signing private key: separate HSM/key slot and separate authorization.
- Recovery public keys and key IDs: installed through signed installer/configuration; fingerprint independently recorded.
- Recovery package: at least two encrypted copies in separate administrative/security domains, one offline or immutable.
- Database backups: encrypted, integrity-checked, retained separately, and tested together with the matching recovery package.
- Access logs: immutable or append-only, independently monitored, and never contain plaintext key material.

A printed recovery code or human-memorable password is not an acceptable substitute for a high-entropy private key unless a separately reviewed threshold-secret design is approved.

## 9. Required acceptance tests

The feature cannot be enabled until all of these pass on supported Windows Server versions:

1. Export contains only wrapped KEKs; binary/text scans and instrumentation show no plaintext key persistence.
2. Invalid signature, unknown signing key ID, modified manifest, noncanonical JSON, duplicate version, invalid Base64, wrong installation ID, unsupported algorithm and oversized package all fail closed.
3. Recovery encryption private key absent from the production host and process environment.
4. Authorized export requires ADMIN, MFA and second approval; OPERATOR and VIEWER are denied.
5. Restore to a clean second Windows Server with no original DPAPI state succeeds using the offline key.
6. Every restored KEK version matches the expected version and decrypts test envelopes with correct AAD; wrong AAD fails.
7. Missing/wrong private key, damaged package, stale package, database/package mismatch and interrupted restore leave the service disabled and the prior keyring intact.
8. Concurrent export/rotation/restore operations serialize and are audited.
9. Crash and power-loss tests confirm atomic keyring persistence and no partial package acceptance.
10. Restore report, audit events and recovery custody are reviewed by an independent operator.

## 10. Open decisions before implementation

- Select supported HSM/hardware-backed recovery provider and Windows CNG integration.
- Approve two-person custody and MFA/approval workflow.
- Decide package delivery and retention policy.
- Define backup-to-package matching and package sequence authority.
- Define supported Windows Server versions and clean-host restore lab.
- Approve signing and encryption key rotation intervals and incident response.
- Approve recovery utility deployment and publisher-signing trust.

Until these decisions are approved and acceptance tests pass, independent recovery is designed but not implemented. The DPAPI keyring remains machine-bound and unsuitable as the sole production recovery mechanism.
