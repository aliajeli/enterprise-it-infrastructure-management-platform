# Windows installer host preflight — v0.1.50

> **Current implementation status (0.1.223): preflight schema 2 separates `hostReady` from overall `ready`; supported-host checks do not authorize installation, and mutation remains disabled. ZIP inspection is not complete JSON validation or proof of authenticity/installability. See [README](README.md) and [HANDOVER](HANDOVER.md).**


## Purpose and scope

The PowerShell preflight is the first executable host-readiness gate for the future offline Windows installer. It verifies only baseline conditions that can be established without changing the host:

- Windows operating system.
- 64-bit operating system.
- Elevated PowerShell process.
- Ready local fixed volumes backing Program Files and ProgramData.
- A configurable minimum free-space floor on both volumes (10 GB by default).

The default free-space value is a preliminary staging floor, not a capacity guarantee or a final product requirement. It must be recalculated after the full five-service payload, PostgreSQL binaries, runtime dependencies, logs, database growth and backup-retention requirements are sized.

## Run

From an elevated PowerShell session at the repository root:

```powershell
.\scripts\windows\installer-preflight.ps1 -MinimumFreeSpaceGB 10
```

The script emits a JSON report. Exit code 0 means all evaluated baseline checks passed; exit code 2 means at least one required check failed.

Run the pure evaluation tests on Windows:

```powershell
pwsh -NoProfile -File scripts\windows\test-installer-preflight.ps1
```

The Windows CI job runs these tests automatically.

## Safety properties

This script is intentionally read-only. It does not create or delete files/directories, change NTFS ownership or ACLs, register or stop Windows services, bind or probe network ports, alter Windows Firewall, initialize or modify PostgreSQL, write application configuration, or access credentials. It does not perform network discovery and does not contact managed devices.

## Explicit limitations

A passing preflight is not an installer and does not prove that the host is supported. The supported Windows client/server matrix, exact five SCM service names and identities, port allocation, TLS edge implementation, PostgreSQL service provisioning, service dependency/readiness checks, keyring path/ACL hardening, and offline payload composition remain separate gates. No service or application is installed by this milestone.
