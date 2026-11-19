# M1 — User lifecycle and administration design

**Status:** Owner-approved role/action matrix recorded on 2026-11-19. Server-side policy primitives and role-matrix tests are included in the M1 completion branch. Operational inventory/device endpoints remain unimplemented; Windows and production database evidence remain outstanding.

## Role boundary

- **ADMIN:** global branch scope; only role allowed to provision users, change non-admin user roles/status, reset non-admin passwords, and manage branch records and branch grants.
- **OPERATOR:** assigned-branch scope. May create/edit inventory records and switch-port/VLAN metadata and run non-destructive discovery and synchronization. Cannot change live device configuration, start remote sessions, use stored credentials, create/execute deployments, or force-close Store Commerce by default.
- **VIEWER:** assigned-branch read-only access to inventory and switch metadata; no mutation or operational action.
- **ADMIN:** global scope and all declared platform capabilities, including user/branch/settings administration and privileged operational actions. Destructive Store Commerce force-close still requires a separate explicit per-operation approval and warning; the ADMIN role alone is not that approval.
- The API does not permit creating or promoting users to ADMIN. The first ADMIN is created by the one-time local bootstrap CLI. Additional ADMIN promotion remains a separately controlled owner procedure.
- This matrix is owner-approved on 2026-11-19. It defines policy only; it does not claim that the future operational modules or endpoints are already implemented.

## User provisioning and lifecycle

- Only an authenticated ADMIN may list users, create OPERATOR/VIEWER accounts, change non-admin user roles/status, reset non-admin passwords or replace branch grants.
- New accounts receive a cryptographically random temporary password. It is returned exactly once in the create-user response, never stored in plaintext, audit metadata, URL, command line or logs.
- New accounts have `mustChangePassword=true`; they must change the temporary password before entering the workspace.
- Usernames are normalized using the same NFKC/lowercase policy as login.
- OPERATOR and VIEWER accounts must have at least one active branch grant. ADMIN has global scope and does not need branch grants.
- Disabling a user, changing their role, changing their password or issuing an administrator reset increments `authEpoch` and revokes all active sessions transactionally.
- User records are disabled, not hard-deleted. Branch grants are revoked, not deleted. Audit history remains append-only.
- Admin password recovery issues a one-time random temporary password only for an active non-admin account. The endpoint is rate-limited, ADMIN-only, self-reset is rejected, administrator recovery is excluded, the response is `no-store`, and all previous sessions are revoked. The user must change the temporary password at next login.
- No email address or verified external recovery channel exists in the current user model; therefore self-service email recovery is intentionally not offered.

## Branch lifecycle

- Branches can be created and edited by ADMIN only. Edits require the current integer `version`; stale updates return HTTP 409 to prevent lost updates.
- Archive is a soft-delete operation: set `status=INACTIVE`, set `deletedAt`, increment `version`, revoke every active user-branch grant and append an audit event in one database transaction.
- Restore clears `deletedAt`, sets `status=ACTIVE`, increments `version` and appends an audit event.
- **Restore never restores old branch grants.** Access must be explicitly re-granted after restore. This prevents a previously revoked assignment from silently becoming effective again.
- Hard deletion is not exposed. Branch IDs and audit history remain stable.
- The active-code constraint permits reusing a code after its branch is archived. If another active branch has since claimed that code, restore returns HTTP 409; rename the active branch or choose another code before retrying.
- The branch list includes archived records for administrative recovery; user assignment only offers active, non-archived branches.

## API controls

- Every user/branch management endpoint resolves the server-side session and checks role ADMIN. Client-side route hiding is not an authorization control.
- Operational authorization is expressed through a closed `PlatformAction` union and a single server-side role policy. Branch-owned requests must pass both `canPerformAction` and `hasBranchScope` via `hasBranchActionAccess`; a role capability never bypasses branch assignment.
- OPERATOR and VIEWER grants are effective only for active, non-archived branches and unrevoked grants. ADMIN has global branch scope.
- The policy helper is not a substitute for route enforcement: each future operational HTTP route and WebSocket/job command must call the appropriate authorization helper before reading or mutating resources.
- State-changing requests also pass the exact Origin check and API rate limit.
- User-list responses never include password hashes or temporary passwords.
- Temporary credentials are returned only by the relevant create/reset response with `Cache-Control: no-store`; API responses are globally marked private/no-store.
- Branch assignment accepts only existing, active, non-deleted branches; duplicate IDs are rejected.
- User role/status/reset and branch edit/archive/restore operations write audit events transactionally with their state changes.
- Optimistic branch version checks return conflict rather than overwriting concurrent updates.

## Remaining M1 acceptance gates

1. Enforce the approved action policy in each operational route, WebSocket event and durable job handler as those modules are implemented; policy primitives and unit tests alone do not expose operational APIs.
2. Backup/restore is exercised against the intended production PostgreSQL service, including encryption/key recovery, restore to a clean instance, consistency checks and evidence capture. CI integration is not a substitute for production evidence.
3. Windows service identities, ACLs, startup dependencies and API/database integration are validated on a clean target Windows VM. The five-service production topology is not yet implemented, so this cannot be truthfully marked complete here.
4. Final PR review and green CI on the exact completion branch head.

## Explicitly out of scope

- User self-registration, MFA, self-service password recovery, and external email/SMS delivery.
- Creating or promoting additional ADMIN users through the API.
- Operator permissions to initiate deployments, remote sessions, credential use, live device configuration or force-close actions (explicitly denied by the approved matrix).
- Production backup/restore or Windows service compatibility claims without target-environment evidence.
