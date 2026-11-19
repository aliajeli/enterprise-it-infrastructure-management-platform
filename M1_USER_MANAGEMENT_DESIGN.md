# M1 — User lifecycle and administration design

**Status:** M1 application scope implemented in the completion branch; automated CI and PostgreSQL integration evidence pending. Owner confirmation of the final OPERATOR/VIEWER action matrix and real Windows/production operational evidence remain explicit acceptance gates.

## Role boundary

- **ADMIN:** global branch scope; only role allowed to provision users, change non-admin user roles/status, reset non-admin passwords, and manage branch records and branch grants.
- **OPERATOR:** assigned-branch scope. Read-only in M1. No device, network, remote-session, credential, deployment or force-close mutation is enabled until the owner confirms the action matrix.
- **VIEWER:** assigned-branch read-only scope.
- The API does not permit creating or promoting users to ADMIN. The first ADMIN is created by the one-time local bootstrap CLI. Additional ADMIN promotion remains a separately controlled owner procedure.
- This is a conservative technical baseline, not a final owner-approved operational permission matrix.

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
- A unique active branch code cannot be reused while the archived record exists; restore or choose another code.
- The branch list includes archived records for administrative recovery; user assignment only offers active, non-archived branches.

## API controls

- Every user/branch management endpoint resolves the server-side session and checks role ADMIN. Client-side route hiding is not an authorization control.
- State-changing requests also pass the exact Origin check and API rate limit.
- User-list responses never include password hashes or temporary passwords.
- Temporary credentials are returned only by the relevant create/reset response with `Cache-Control: no-store`; API responses are globally marked private/no-store.
- Branch assignment accepts only existing, active, non-deleted branches; duplicate IDs are rejected.
- User role/status/reset and branch edit/archive/restore operations write audit events transactionally with their state changes.
- Optimistic branch version checks return conflict rather than overwriting concurrent updates.

## Remaining M1 acceptance gates

1. Owner confirms the exact OPERATOR versus VIEWER action matrix before any operational permission is exposed.
2. Backup/restore is exercised against the intended production PostgreSQL service, including encryption/key recovery, restore to a clean instance, consistency checks and evidence capture. CI integration is not a substitute for production evidence.
3. Windows service identities, ACLs, startup dependencies and API/database integration are validated on a clean target Windows VM. The five-service production topology is not yet implemented, so this cannot be truthfully marked complete here.
4. Final PR review and green CI on the exact completion branch head.

## Explicitly out of scope

- User self-registration, MFA, self-service password recovery, and external email/SMS delivery.
- Creating or promoting additional ADMIN users through the API.
- Operator permissions to initiate deployments, remote sessions, credential use, device configuration or force-close actions until owner confirmation.
- Production backup/restore or Windows service compatibility claims without target-environment evidence.
