# M1 — User lifecycle and administration design

**Status:** implementation slice in progress. This document records the conservative baseline being implemented; operational device/job permissions remain a separate owner-confirmation item.

## Role boundary

- ADMIN: global branch scope; only role allowed to create/disable users, change user roles and grant/revoke branch access.
- OPERATOR: assigned-branch scope. Read-only in this milestone; operational mutations remain disabled until the owner confirms the action matrix.
- VIEWER: assigned-branch read-only scope.
- The API does not permit creating or promoting users to ADMIN. The first ADMIN is created by the one-time local bootstrap CLI. Additional ADMIN promotion remains a separately controlled owner procedure.

## User provisioning

- Only an authenticated ADMIN may list users, create OPERATOR/VIEWER accounts, change their role/status or replace branch grants.
- New accounts receive a cryptographically random temporary password. It is returned exactly once in the create-user response, never stored in plaintext, audit metadata, URL, command line or logs.
- New accounts have mustChangePassword=true. The user must change the temporary password before accessing the platform workspace.
- Usernames are normalized using the same NFKC/lowercase policy as login.
- OPERATOR and VIEWER accounts must have at least one active branch grant. ADMIN has global scope and does not need branch grants.
- Disabling a user, changing their role or changing their password increments authEpoch and revokes all active sessions.
- User records are disabled, not hard-deleted. Branch grants are revoked, not deleted. Audit history remains append-only.

## Password lifecycle

- The first administrator chooses a password during the interactive bootstrap.
- Provisioned users receive a random temporary password and must change it after their first successful login.
- Password changes require the current password, including when changing a temporary password. On success, all sessions are revoked and the user must sign in again.
- Recovery-code records exist in the schema, but self-service recovery and admin reset flows are not enabled in this slice.

## API controls

- Every user-management endpoint resolves the server-side session and checks role ADMIN. Client-side route hiding is not an authorization control.
- State-changing requests also pass the exact Origin check and API rate limit.
- User-list responses never include password hashes or temporary passwords.
- The temporary password is returned only by the create-user call with Cache-Control: no-store.
- Branch assignment accepts only existing, active, non-deleted branches; duplicate IDs are rejected.
- User status/role changes revoke sessions transactionally and write audit events in the same transaction.

## Explicitly out of scope

- Operator permissions to initiate deployments, remote sessions, credential use, device configuration or force-close actions.
- User self-registration, multi-factor authentication, self-service password recovery and admin password-reset endpoints.
- Creating or promoting additional ADMIN users through the API.

These boundaries preserve least privilege while the full operator/viewer operational permission matrix remains owner-pending.