# API contract and implementation status

The complete platform API described below is still a design target. The following M1 subset is implemented and CI-verified; all other candidate routes and event contracts remain planned, not implemented.

## Implemented M1 API subset

| Method | Route | Behavior |
|---|---|---|
| GET | /health/live | Process liveness only; does not imply readiness. |
| GET | /health/ready | Checks database connectivity and presence of the initial users schema. |
| POST | /api/v1/auth/login | Validates username/password and issues an opaque server-side session cookie. |
| GET | /api/v1/session | Validates the cookie, session expiry/revocation, user status and auth epoch; returns a minimal principal. |
| POST | /api/v1/auth/logout | Revokes the current session and clears its cookie. |

Authentication implementation details:

- Argon2id password hashing; 14–128 character password policy for initial credentials.
- Generic invalid-credential response, dummy hash for unknown usernames, PostgreSQL-backed failed-login counter and 15-minute lockout after five consecutive failures.
- Login route throttling of five attempts per 15 minutes per source IP; global API throttle of 120 requests per minute. The rate-limit store is process-local and assumes the current single API service instance.
- 256-bit random session token; only its SHA-256 digest is stored in PostgreSQL.
- HttpOnly, SameSite=Lax, Path=/ cookie; Secure in production; no Domain attribute; 12-hour absolute expiry.
- Exact Origin validation for state-changing browser requests; CORS is not enabled.
- API binds to loopback. Only loopback proxy peers are trusted for forwarded client IP; the TLS Edge must overwrite X-Forwarded-For.
- The first administrator is created only through the interactive local bootstrap CLI.

Not yet implemented: user-management endpoints, password change/recovery, branch CRUD, operational device APIs, WebSocket contracts, Agent enrollment, job operations, and final operator/viewer action permissions. Server-side authorization primitives exist, but no operational mutation endpoint is exposed.

## Planned API contract

The sections below define the future API boundaries and candidate route shapes; they are not a claim of implementation. Exact resources, schemas and protocol versions require approval during implementation. Server-side RBAC is mandatory for every request and message; no secret is returned to the browser.

## Transport, versions, authentication
All external application HTTP and WebSocket traffic uses HTTPS/WSS through the Windows TLS edge; internal listeners are restricted and authenticated. Candidate prefix `/api/v1`, explicit content type, UTC timestamps, documented backward compatibility and deprecation. Login creates opaque Secure HttpOnly SameSite session cookies with CSRF/origin protections; password Argon2id, rate limiting, rotation/revocation and session expiration. Agent uses separate per-device enrolled identity over authenticated WSS, not human sessions. Proxy clients use separately provisioned scoped installation identities, not GitHub credentials. Admin/operator/viewer rights and branch/device scope checked server-side, including credential usage, update initiation, bridge capabilities and job operations.

## Common behavior
Candidate JSON error `{ "error": { "code": "VALIDATION_ERROR", "message": "...", "requestId": "...", "details": [{ "field": "...", "code": "..." }] } }`; stable codes, sanitized details, no stack/credential leakage. 400 validation, 401 unauthenticated, 403 forbidden, 404 absent/unauthorized per policy, 409 conflict, 429 throttled, 5xx operational errors. Pagination: opaque signed or validated cursor, bounded `limit`, deterministic sort and next cursor; filtering/sorting whitelisted. Mutations validate with Zod and DB constraints; conditional version/ETag for concurrent edits. Destructive actions require confirmation/audit. For async creation, scoped `Idempotency-Key` uniquely identifies actor+operation+payload hash, with atomic record and replay of original response; mismatched reuse returns conflict. Document TTL, retry behavior and no guarantee of exactly-once physical side effects.

## Candidate application resources
* `/auth/login`, `/auth/logout`, `/auth/recovery`, `/session`; rate-limited and audited. Roles/credentials have narrowly privileged management endpoints; secrets accepted only over TLS and never returned.
* `/branches`, `/branches/{id}/links`, `/devices` and typed subresources for routers, switches/manual ports, computers/checkouts, servers/VMs, POS, scales, PDAs, printers, NVRs and cameras. CRUD, validated relations, soft deletion, filtering/sorting and audit.
* `/branches/{id}/monitoring` and `/branches/{id}/probes`; settings configure interval, timeout, retries, concurrency and retention. Router reachability is not Internet health. `/nvrs/{id}/sync` and branch/all sync create authorized durable jobs; GET exposes last attempt, last successful sync and sanitized errors.
* `/software`, `/computers/{id}/software`, `/imports`, `/exports`, `/packages`; Excel imports preview and validate before authorized transactional commit, exports scope filters and audit. Package ID is metadata; date-only target directory and actual filenames/digests stored per job target.
* `/jobs`, `/jobs/{id}`, `/jobs/{id}/targets`, `/jobs/{id}/events`, `/jobs/{id}/cancel`; create 202 with durable job reference, lifecycle queued/running/succeeded/failed/cancelled/needs-reconciliation, step attempts/timestamps and safe results. Cancel best effort; do not pretend side effect is rolled back. Store Commerce forced shutdown requires recorded explicit scoped approval and warning.
* `/connections`, `/sessions`, `/bridge/enrollments`, `/bridge/capabilities`: server validates device, user, allowed operation and target scope, signs short-lived bridge-bound single-use capability with no password. Browser receives no GitHub or equipment secrets. SSH uses authenticated WSS bound to user/session/device, host-key checks and per-session authorization.
* `/updates/status`, `/updates/check`, `/updates/apply`, `/updates/{id}`: admin authorization, explicit channel and no automatic downgrade or stable→beta switch, detailed status/audit. Application updater independently authenticates to proxy; browser doesn't receive private repository metadata or tokens.

## Proxy API (separate server)
Candidate `/v1/channels/{channel}/releases` and `/v1/releases/{releaseId}/assets/{assetId}`. Authenticate installation/client, authorize channel/asset for every request, return only sanitized approved manifest and asset stream; no arbitrary URL, paths or GitHub credential. Apply size bounds, checksums, anti-downgrade/channel policy, rate limits, cache revocation, audit and classified upstream unavailable errors. SHA-256 is not publisher authenticity. Endpoint details and client credential mechanism remain unimplemented.

## WebSocket and Agent protocol
Separate operator and agent channels with authenticated handshake, Origin checks for browsers and server-side scope on every event. Candidate events `job.updated`, `target.step.updated`, `monitor.updated`, `alert.created`, `agent.heartbeat`, `agent.task`, `agent.task.result`, and `ssh.output`; include event ID, schema version, correlation, UTC time and scoped resource, never secrets. Use bounded payload, backpressure, replay cursor/reconnect semantics and periodic authorization revalidation. Agent protocol requires single-use enrollment, per-device key proof, task UUID/nonce/expiry, allowlisted structured types/parameter bounds, idempotency and sanitized result; reject arbitrary shell or PowerShell. Disconnect/reconnect and revocation invalidate sessions, with uncertain outcomes reconciled rather than blindly repeated.
