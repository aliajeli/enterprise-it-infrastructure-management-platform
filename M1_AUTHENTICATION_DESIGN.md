# M1 — Authentication, identity and persistence design

**Status:** implementation in progress; operational role-permission matrix remains owner-pending.

## Runtime boundaries

- The Next.js application is the browser-facing UI only.
- The Fastify API is a separate service and binds to loopback by default (127.0.0.1:13001).
- The TLS Edge / reverse proxy is the only externally reachable entry point. The browser uses same-origin /api routes; API CORS is not opened. In local development, Next.js rewrites proxy /api and /health to the loopback API.
- PostgreSQL is accessed through the dedicated database package and Prisma 7.10.1's PostgreSQL driver adapter.

## Authentication controls

- Passwords are stored only as Argon2id PHC hashes. Initial parameters: 19,456 KiB memory, 2 iterations, parallelism 1, 32-byte output and 16-byte salt. Re-evaluate on target Windows server hardware before production.
- Password policy: 14–128 Unicode code points, at most 1,024 UTF-8 bytes, no control characters. No arbitrary composition rules.
- Usernames are NFKC-normalized, trimmed, lowercased and restricted to 3–64 ASCII letters, digits, dot, underscore and hyphen.
- Unknown usernames use a dummy Argon2id hash and the same generic 401 Invalid username or password response to reduce account enumeration.
- Failed attempts are counted atomically in PostgreSQL. Five consecutive failures set a 15-minute account lockout. Login route throttling is five attempts per 15 minutes per source IP; the Fastify rate-limit store is process-local and assumes the current single API service instance.
- Session secrets contain 256 bits of cryptographic randomness. Only SHA-256 digests are stored in PostgreSQL.
- Session cookies are HttpOnly, SameSite=Lax, Path=/, Secure in production and have no Domain attribute. Production uses the __Host-platform_session prefix.
- Sessions have a 12-hour absolute lifetime. authEpoch allows password/status/role changes to invalidate every prior session.
- State-changing browser requests require an exact configured Origin. CORS is not enabled.
- Fastify trusts forwarded client IP information only from loopback peers. The TLS Edge must overwrite X-Forwarded-For; it must not append an untrusted client-supplied chain. The API remains bound to 127.0.0.1.
- Authentication events are written to the audit log. Passwords, session secrets and raw tokens must never be logged.

## Persistence model

- users: normalized unique username, password hash, role, status, auth epoch, failed-login count and lock expiry.
- sessions: token hash, auth-epoch snapshot, absolute expiry, revocation, last-seen and limited request metadata.
- recovery_codes: one-way code hashes and expiry/consumption state; recovery endpoints are not enabled yet.
- branches: minimal branch identity with soft deletion and version field.
- user_branch_access: grant/revoke history with a partial unique index for one active grant per user/branch.
- audit_events: append-only operational security history. A PostgreSQL trigger rejects UPDATE and DELETE. User records are disabled rather than hard-deleted.

## Initial roles and unresolved permission matrix

The database supports ADMIN, OPERATOR and VIEWER. Branch grants are persisted separately from roles. The proposed baseline is:

- ADMIN: global scope and security/user administration.
- OPERATOR: assigned-branch scope; operational mutations only after the owner-approved action matrix is finalized.
- VIEWER: assigned-branch read-only scope.

**Owner confirmation required:** exact permission/action matrix, who may grant branch access, and whether operators may execute deployment/remote-access actions. Until approved, no user-management, branch-grant or operational mutation endpoints are exposed.

## Bootstrap and operations

- No default username/password and no seeded production account.
- A one-time, local administrator bootstrap command is required before production use; it must run interactively, refuse to run if any user already exists, and never accept a password in command-line arguments or logs. This command is not implemented yet.
- prisma migrate deploy is the deployment migration command. Never run migrate reset against an existing environment.
- CI applies migrations to a disposable PostgreSQL 18 service and verifies partial branch-grant uniqueness plus the append-only audit trigger. A Windows runner separately validates the native Argon2id binding, API typecheck and API build. Production migration must be preceded by a verified backup and restore test.
- Database credentials remain server-side and are not copied to the browser or Windows Agent.

## Current API surface

- GET /health/live: process liveness only.
- GET /health/ready: database/schema readiness.
- POST /api/v1/auth/login: create a server-side session.
- GET /api/v1/session: return the authenticated principal.
- POST /api/v1/auth/logout: revoke the current session.

The administrator bootstrap command is implemented. Password recovery, user-management API and the operational permission matrix are not implemented.