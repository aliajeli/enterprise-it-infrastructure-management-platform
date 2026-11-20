# Local Preview — Manual Acceptance Guide

This guide validates the currently implemented browser workflows on an isolated Windows development machine. It is not a production deployment or a device-discovery test.

## Scope and prerequisites

- Windows 10/11 with Docker Desktop using Linux containers.
- Node.js 26.x and npm 11.x.
- Repository branch `phase3/m2-inventory-ui`, currently version `0.1.46`.
- Follow the README section **Quick local preview (Windows)** to start PostgreSQL, install dependencies, apply migrations, build, bootstrap the first administrator and start API/web in separate terminals.
- Open `http://127.0.0.1:3000`.

Use a disposable local database and synthetic branch/device details only. Do not enter production credentials, real SNMP community strings or sensitive inventory information.

## 1. First administrator and sign-in

1. Run `npm run bootstrap-admin` from an interactive PowerShell terminal.
2. Create a unique local administrator username and password when prompted.
3. Sign in through the browser.
4. Confirm the session reaches the application and that reloading the page preserves the authenticated session.
5. Sign out and confirm protected pages require authentication again.

Expected: no built-in/default administrator credentials are provided. The bootstrap command only creates the first administrator when the users table is empty.

## 2. Branch administration

1. As ADMIN, open **User management** at `/users`.
2. Create a test branch with a unique branch code (for example, `QA-001`) and a descriptive name.
3. Confirm the new branch appears in the branch list.
4. Edit its name and save; confirm the updated value persists after refresh.
5. Do not archive a branch containing test users unless you intend to verify the destructive access-revocation behavior.

Expected: branch codes are normalized to uppercase. Archiving a branch revokes current user grants; restoring the branch does not restore those grants automatically.

## 3. Create an operator and validate branch-scoped access

1. In **User management**, create a user with role **OPERATOR** and assign only the test branch.
2. Copy the one-time temporary password shown after creation. It is not displayed again.
3. Sign out as ADMIN and sign in as the new operator.
4. Complete the required password change if prompted.
5. Open **Device Inventory** at `/inventory`.
6. Confirm the operator can select the assigned active branch.
7. If another active test branch exists without a grant, confirm it is not listed as accessible.

Expected: an OPERATOR can use inventory only for active branches with a current access grant. The user-management page remains ADMIN-only.

## 4. Asset and switch-port metadata workflow

1. In the test branch inventory, create a switch asset using synthetic values:
   - Asset code: `QA-SW-001`
   - Name: `QA Access Switch`
   - Kind: `SWITCH`
   - Management IP: use a documentation-only address such as `192.0.2.10`; do not probe it.
   - Vendor/model/location: optional test values.
2. Open the switch and add a port with a unique interface index (for example, `1`).
3. Enter operator-maintained metadata: port name, alias, description, access VLAN (for example, `7`) and connected-device label (for example, `QA workstation`).
4. Save and reopen the port; confirm the metadata persists.
5. Edit the port again, clear Alias, Description, connected-device label and configured access VLAN, then save; confirm these fields are cleared and tagged VLANs can be emptied with a blank list.
6. Re-enter the metadata if you want to retain a populated sample for the remaining checks.
7. Edit the switch asset and update its description or location; confirm the change persists.
8. Clear an optional Management IP or MAC value using the UI's blank-field behavior and confirm it is removed after refresh.
9. If the UI displays observations, distinguish them from manually maintained port labels/VLAN metadata. Do not interpret absent observations as an offline device.

Expected: asset and port edits use version checks and are audited. The UI records inventory metadata; it does not configure a physical switch or discover live port state.

## 5. Role and authorization checks

1. As ADMIN, create a second test user with role **VIEWER** and grant the test branch.
2. Sign in as VIEWER and confirm the branch inventory is readable.
3. Attempt to open `/users`; confirm ADMIN-only access is denied or redirected.
4. Return as ADMIN and disable the VIEWER account.
5. Confirm the disabled account cannot establish a new authenticated session.
6. Re-enable the test account if further testing is needed.

Expected: VIEWER is read-only; user and branch administration are restricted to ADMIN. Role/status/access changes revoke sessions where implemented.

## 6. Concurrency and audit sanity checks

1. Open the same asset in two browser tabs.
2. Save a change in tab A.
3. Attempt to save stale data from tab B.
4. Confirm the stale update is rejected rather than silently overwriting the newer version.
5. Confirm successful create/update operations appear in the audit trail where the application exposes it.

Expected: optimistic version checks prevent lost updates. A conflict should be resolved by refreshing and applying the intended change to the latest record.

## Explicitly out of scope

- No synthetic device/port observations or online/offline status are seeded.
- No SNMP, SSH, ICMP, ISAPI, WinRM or Windows Agent discovery/monitoring is active.
- No subnet sweep, TCP/UDP port scan, port mapping, NAT/DST-NAT, firewall/address-list change or automatic MikroTik unblock is performed.
- No physical switch, router, NVR or camera configuration is changed.
- Credential Vault storage is not registered for production use; do not enter equipment secrets.
- This preview is not an installer and is not an upgrade/uninstall/rollback acceptance test.

## Reporting a preview result

When reporting a defect, include: application version, browser, Windows version, exact page, steps to reproduce, expected result, actual result, timestamp and relevant redacted browser/API error. Never include passwords, session cookies, tokens or production secrets.

## Resetting the local preview

To stop the database and preserve preview data:

```powershell
docker compose down
```

To delete the disposable preview database and all its data:

```powershell
docker compose down -v
```

The second command is destructive. Verify that the Compose project points only to the local preview database before using it.

## 7. Switch selection and dialog request consistency

1. Create two synthetic switch assets in the test branch, each with at least one port metadata row.
2. Open the first switch's port dialog, then immediately open the second switch before the first request completes (use browser throttling if needed).
3. Confirm the dialog displays only the second switch's port rows once loading finishes.
4. Repeat, but close the dialog while its port request is pending; confirm the closed dialog does not reappear and no stale port list is shown when another switch is opened.

Expected: late responses from an earlier selection are ignored. This protects UI state only; it does not cancel server-side work or perform network discovery.
