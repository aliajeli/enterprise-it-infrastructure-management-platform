# Windows service deployment decisions

Status: implementation contract for the Windows deployment workstream. This document does not claim that all five services are implemented or accepted.

## Required service topology

The production management host has five independently supervised Windows services. They must not be collapsed into one process or one SCM service.

| Logical service | SCM service name | Immutable payload entry point | Private listener / endpoint | Current state |
|---|---|---|---|---|
| TLS edge | `EnterpriseITEdge` | Dedicated .NET 10 edge host (YARP proof of concept) | LAN HTTPS/WSS :443; proxies only to loopback backends | Host, route policy, TLS validation and provisioning foundation implemented; clean-VM certificate acceptance pending |
| Next.js UI | `EnterpriseITWeb` | Dedicated .NET 10 SCM host + bundled Node 26 + Next standalone launcher | `127.0.0.1:13000` | Host, launcher, staging and provisioning policy implemented; clean-VM virtual-account acceptance pending |
| API/WebSocket | `EnterpriseITApi` | Existing .NET 10 host + bundled Node API | `127.0.0.1:13001` | Host runtime and initial provisioning script exist |
| Worker | `EnterpriseITWorker` | Dedicated .NET 10 host + bundled Node worker | Health only on `127.0.0.1:13002` | Host, parent/child service SID validation, bounded lifecycle and provisioning policy implemented; protected DB configuration and clean-VM acceptance pending |
| PostgreSQL | `EnterpriseITPostgreSQL` | Pinned PostgreSQL 18 Windows distribution | `127.0.0.1:5432` only | EDB 18.7-1 binaries with SHA-256 staging, SCRAM initialization and native virtual-account SCM provisioning implemented; clean-VM lifecycle acceptance pending |

Service names above are application-owned names. The PostgreSQL registration name is not assumed to be the upstream installer default; packaging must register and verify the selected name explicitly.

## Runtime and routing decisions

- **Edge prototype:** use .NET 10 Generic Host with YARP as the reverse-proxy implementation candidate. It terminates TLS and forwards HTTP/WebSocket traffic only to the loopback Next.js and API listeners. This is a prototype selection, not production approval. Production acceptance requires certificate lifecycle tests, private-key ACL validation, forwarded-header trust restrictions, WebSocket behavior, request-size/time limits, and confirmation that internal ports are not exposed on LAN interfaces.
- **Web:** use Next.js `output: "standalone"`, the pinned Node 26 runtime, and a fixed loopback bind at port 13000. Static assets and required standalone tracing files must be staged in the immutable version directory. The web process must not receive database credentials.
- **API:** retain the existing fixed Node entry point, readiness endpoint and .NET 10 SCM host. The API remains loopback-only at port 13001.
- **Worker:** use a separate .NET 10 SCM host and a fixed Node entry point. Add a loopback-only readiness endpoint at port 13002. The worker must not bind a LAN listener and must not claim jobs for which no handler is registered. It receives only its required database connection configuration and must not access the local credential keyring.
- **Database:** package a pinned PostgreSQL 18 Windows distribution. The service binds only to loopback. Application and migration roles are separate; migrations run as a controlled deployment operation, not as a standing superuser application identity. Major-version upgrades are explicit backup/restore or tested `pg_upgrade` operations, never silent installer behavior.

## Identity and filesystem policy

- API, Web, Worker and Edge each use a distinct dedicated Windows service identity; do not run them as LocalSystem or as an interactive administrator.
- The preferred identity form is a per-service virtual account (for example, `NT SERVICE\\EnterpriseITWorker`) with an enabled unrestricted service SID. Each host validates its own SID in both parent and child process tokens before readiness.
- PostgreSQL must run under a dedicated low-privilege identity that owns only its data and required runtime paths. Virtual-account compatibility with the selected PostgreSQL distribution must be proven before choosing it; do not silently fall back to LocalSystem.
- Versioned Program Files payloads are immutable to service identities. Each service receives read/execute access only to its own payload and explicitly required shared runtime files. ProgramData state/config/log/data directories have separate ACLs.
- Secrets are not passed in command-line arguments or inherited from an unrestricted machine environment. Each service receives only its own required protected configuration.

## Startup and health ordering

1. Validate OS, architecture, elevation, disk and port conflicts.
2. Provision PostgreSQL files, data directory, identity, ACLs and loopback-only configuration; initialize or upgrade only through an explicit database lifecycle operation.
3. Verify database readiness and apply migrations with the controlled migration identity.
4. Provision API and Worker identities, hosts and payload ACLs; start and verify API readiness before dependent UI/Edge checks.
5. Provision Web and verify its local readiness endpoint and API rewrite behavior.
6. Provision Edge, validate certificate/private-key access and upstream health, then expose the LAN HTTPS listener.
7. Verify all five SCM configurations, identities, recovery actions, listener bindings and end-to-end HTTPS/WSS health.

Each service has bounded startup, graceful shutdown and child-process reaping. A service that cannot prove readiness fails closed. SCM recovery is bounded and must not create restart loops.

## Port and network safety boundary

- Only Edge may listen on the intended LAN interface, and only on the explicitly configured HTTPS port (default 443).
- Web, API, Worker health and PostgreSQL listeners are loopback-only.
- No automatic Windows Firewall, MikroTik, NAT, DST-NAT, port-forward or router address-list changes are performed by the installer.
- No device discovery, port scanning, subnet sweeping or automatic unblock behavior is part of service provisioning.
- A listener/port conflict is a preflight failure with an actionable diagnostic; the installer must not silently select a different port.

## Release gates still required

- PostgreSQL binaries pinned to EDB 18.7-1 with SHA-256 sidecar validation and native service provisioning; complete dependency/license inventory and validate clean-VM install/upgrade, data ownership and backup/restore.
- Complete protected Worker database configuration, then run clean-VM virtual-account acceptance. Worker SCM host, parent/child SID validation, bounded lifecycle tests and provisioning policy are implemented and included in hosted Windows CI and the exact-head Push/PR runs completed successfully. The Web host, parent/child service SID validation, bounded lifecycle tests and provisioning policy are implemented and pass hosted Windows CI; clean-VM virtual-account acceptance remains pending.
- Validate Edge TLS certificate import, private-key ACLs, SNI/hostname validation, WSS proxying and failure behavior on a clean supported Windows Server VM.
- Implement provisioning scripts and policy tests for all services; verify idempotency and refuse unexpected pre-existing services.
- Run a clean supported Windows Server VM acceptance using the actual virtual service accounts. Hosted CI's LocalService SCM smoke is not proof of production virtual-account provisioning.
- Verify five independent SCM services, service recovery configuration, private listener bindings and end-to-end health.
- Complete protected ProgramData provisioning, Credential Vault security review and backup/restore before any production installer claim.

Until all gates pass, milestone 4 remains active. API, Web, Worker, Edge and PostgreSQL service foundations are implemented (5/5); protected Worker database configuration, integrated orchestration, certificate/private-key acceptance, PostgreSQL clean-VM lifecycle and actual virtual-account acceptance remain open. This is not completion of the five-service deployment.
