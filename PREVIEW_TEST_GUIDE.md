# Local Preview — Manual Acceptance Guide

This guide validates the currently implemented browser workflows on an isolated Windows development machine. It is not a production deployment or a device-discovery test.

## Scope and prerequisites

- Windows 10/11 with Docker Desktop using Linux containers.
- Node.js 26.x and npm 11.x.
- Repository branch `phase3/m2-inventory-ui`, currently version `0.1.84`.
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


## 8. Switch-port observation history API

1. With the disposable PostgreSQL integration database enabled, run the inventory API integration test suite.
2. Confirm a port with two synthetic observations returns the newest observation first.
3. Request the history with `limit=1&offset=1`; confirm the second page contains the older observation while `page.total` remains 2.
4. Confirm a VIEWER with branch access can read history, and a port ID that does not belong to the requested switch returns 404.

Expected: history is read-only, branch-authorized and paginated. The endpoint does not trigger discovery and does not expose raw discovery metadata.


## 9. Switch-port observation history UI

1. Open a synthetic switch and expand its port list.
2. Select **View history** for a port with observations.
3. Confirm rows are newest-first and show observed time, source, administrative/operational state, VLAN, speed, IP and MAC.
4. Confirm the total count and Previous/Next controls work when more than 10 observations exist.
5. Use a port with no observations and confirm the empty state appears.
6. Use browser throttling to start a history request, then close the history panel; confirm a late response cannot repopulate the closed panel.

Expected: history is a read-only view of already-recorded data. Opening it does not trigger SNMP polling, port scanning, NAT/port mapping or switch configuration.


## 10. Branch-scoped inventory CSV export

1. Select a test branch and confirm the inventory list shows its matching asset count.
2. Apply a search term and/or equipment-type filter; export CSV.
3. Open the downloaded file in a spreadsheet application and verify only records matching the selected branch and filters are present, including assets beyond the first 100 rows when available.
4. Confirm commas, quotation marks and multiline descriptions remain in one correctly parsed cell.
5. Confirm values beginning with `=`, `+`, `-` or `@` are exported as text to reduce spreadsheet formula-injection risk.
6. Confirm the export action is disabled while the list is loading and while an export is in progress.
7. For a test dataset above 10,000 matching assets, confirm the UI asks the operator to narrow filters rather than downloading a truncated file.

Expected: export reads existing inventory only. It does not poll devices, initiate SNMP/ICMP scans, modify MikroTik rules or change equipment configuration.


## 11. Windows installer host preflight (read-only)

Run from an elevated PowerShell session on a Windows x64 test host:

```powershell
.\\scripts\\windows\\installer-preflight.ps1 -MinimumFreeSpaceGB 10
```

The command emits a JSON report and exits with code `0` only when Windows, x64, elevation and the Program Files/ProgramData local fixed-volume checks pass; exit code `2` means one or more required checks failed. The default 10 GB threshold is a preliminary staging floor and must be revisited after payload sizing. The script is read-only: it does not create directories, alter ACLs, register services, bind or probe ports, change firewall policy, initialize PostgreSQL or install the application.

Expected: this check is only a host prerequisite baseline. A passing report does not establish supported-OS certification, service readiness, successful installation or production suitability.


## 12. Windows API service-host readiness and shutdown smoke checks (development validation)

On a disposable Windows x64 test host with the API payload staged in the documented immutable layout:

1. Start the API host under a test service identity and verify that the host does not complete startup while PostgreSQL is unavailable.
2. Start the disposable PostgreSQL instance and confirm the API host completes startup only after `GET http://127.0.0.1:13001/health/ready` returns HTTP 200.
3. Keep the database unavailable for the full 60-second startup budget; confirm the host fails startup and terminates the Node child process tree.
4. Request a normal service stop and confirm the host's newline-delimited `SHUTDOWN` command is accepted, Fastify closes and Prisma disconnects before the 20-second graceful-stop limit.
5. Confirm no external address, managed-device address, alternate port or non-loopback endpoint is contacted by the readiness probe.

Expected: the readiness probe targets only the API process's fixed loopback health endpoint. This is not a network discovery operation and does not contact switches, routers, NVRs or MikroTik. These checks still require execution on a real disposable Windows host; CI compilation alone is not acceptance evidence.


## 13. Windows API service identity gate (clean-VM integration test)

On a disposable, clean Windows VM after an administrator has provisioned the exact `EnterpriseITApi` service name and configured its service SID as enabled:

1. Start the host through SCM under the dedicated `NT SERVICE\\EnterpriseITApi` virtual service account.
2. Confirm startup proceeds only when the exact service SID is present as the token user or as an enabled, non-deny-only token group.
3. Run negative controls under LocalSystem, an interactive administrator, a standard user and an unrelated service identity; confirm the host fails before starting Node.
4. If feasible in a dedicated test service, configure the expected service SID as disabled and confirm startup fails closed.
5. Confirm the host itself accepts the Node child only when the child process token contains the same exact enabled, non-deny-only service SID as the parent. The host performs this check with query-only token access and terminates the child on mismatch. Use a test-only diagnostic harness only as independent corroboration; do not log or export the full token.
6. Confirm the host does not create the service, change service configuration, grant privileges or modify ACLs at runtime.

Expected: identity mismatch prevents API process launch. This test requires a real Windows SCM service configuration; compilation in GitHub Actions does not prove the service identity or child-token behavior.


## 14. Windows API child-process lifecycle policy unit tests

The Windows CI workflow runs:

```powershell
dotnet test apps/api/windows/service-host-tests/EnterpriseIT.ApiServiceHost.Tests.csproj --configuration Release
```

The test project covers an already-exited child, successful termination/reap, an exit race during the kill request, kill failure propagation, bounded reap timeout, external cancellation propagation, unexpected kill-state failure propagation and rejection of a non-positive reap deadline and rejection of a wait that completes without confirming process exit. These deterministic tests do not install a Windows service and do not replace the clean-VM SCM/service-SID/process-tree acceptance checks in the provisioning design.


## 15. Windows API graceful-shutdown orchestration unit tests

The Windows-targeted service-host test project exercises the production shutdown coordinator used by NodeApiProcessService.StopAsync. Tests cover an already-exited child, successful graceful command/wait, a broken control pipe, graceful deadline expiry, host cancellation followed by child cleanup, unexpected control-channel state, a wait that completes without child exit, and invalid timeout configuration.

These tests use injected delegates and do not launch a real Node process or install a Windows SCM service. They complement, but do not replace, clean-VM tests for the dedicated service identity, inherited child token, actual process-tree termination and service stop behavior.


## 16. Windows API Service Host — real SCM smoke acceptance

The Windows CI job runs scripts/windows/test-api-service-host-scm.ps1. It publishes the .NET host into an isolated temporary layout, builds a controlled child executable at the fixed runtime/node.exe path, and creates a temporary EnterpriseITApi SCM service using NT SERVICE\EnterpriseITApi with an unrestricted service SID.

The smoke test checks parent and child service-SID validation, loopback readiness, graceful shutdown through the stdin control pipe, SCM transition to Stopped, and absence of the child process after stop. It then repeats startup with readiness intentionally unavailable and verifies the host fails startup without orphaning the child. The script deletes its temporary service and payload in a finally block and refuses to overwrite a pre-existing service.

This is a hosted Windows runner integration smoke, not a substitute for clean Windows Server VM acceptance, installer-created immutable ACLs, SCM recovery-policy verification, or the complete five-service installation/upgrade/uninstall tests.


## 17. SCM harness command tokenization correction

Version 0.1.69 corrects the PowerShell invocation of sc.exe so each option name and value are passed as separate native arguments. The preceding Windows run built the host and passed all 17 lifecycle tests, but failed before service creation. Re-run the exact-head Windows CI before treating SCM acceptance as passed.


## 18. Virtual service-account SCM argument correction

Version 0.1.70 also separates the sc.exe config obj= and password= option tokens from their values. SCM acceptance remains pending until the new exact-head Windows run completes.


## 19. Service SID and virtual-account provisioning order

Version 0.1.71 changes the temporary SCM smoke sequence: configure SERVICE_SID_TYPE_UNRESTRICTED first, then assign the NT SERVICE\EnterpriseITApi virtual account. The preceding run created the service but received Windows error 1057 while resolving the account. Exact-head Windows CI is required to validate the new order.


## 20. Quote virtual service account in SCM configuration

Version 0.1.72 quotes the NT SERVICE\EnterpriseITApi account value and empty password value in the native sc.exe config call. The previous runner verified SERVICE_SID_TYPE_UNRESTRICTED was applied, then failed with Win32 1057 parsing the account. Exact-head Windows CI remains the acceptance gate.


## 21. Create the virtual account with the service

Version 0.1.73 creates the temporary SCM service with obj= "NT SERVICE\EnterpriseITApi" in the sc.exe create call and deliberately omits password=. The prior config approach returned Win32 1057 even after the service SID was enabled. The Windows CI run is the acceptance gate for this provisioning sequence.


## 22. Hosted-runner SCM identity constraint

Version 0.1.74 uses LocalService only for the hosted Windows CI smoke because the runner returned Win32 1057 when assigning NT SERVICE\EnterpriseITApi during both service creation and reconfiguration. The test still enables SERVICE_SID_TYPE_UNRESTRICTED, validates the EnterpriseITApi SID in the host and child tokens, and grants the temporary payload access by the exact service SID.

This is not the production account choice. The installer remains required to configure NT SERVICE\EnterpriseITApi and verify it on a clean supported Windows Server VM.


## 23. Canonical LocalService name for SCM smoke

Version 0.1.75 passes NT AUTHORITY\LocalService as the temporary SCM test account instead of the short alias. The previous Windows run failed with 1057 during CreateService. The production virtual service account requirement remains unchanged.


## 24. LocalService account-name separator

Version 0.1.76 corrects the CI harness account literal to NT AUTHORITY\LocalService with one separator. The prior Windows runner failed at CreateService because the script supplied a doubled separator. Exact-head CI remains required.


## 25. Literal LocalService assertion

Version 0.1.77 changes the service-account assertion from regex matching to a literal wildcard comparison. The previous Windows run successfully created the service and enabled its SID, then failed on regex parsing of the backslash in NT AUTHORITY\LocalService.


## 26. Failed-start SCM state assertion

Version 0.1.78 verifies the authoritative service state becomes Stopped and no child process remains after readiness is deliberately unavailable. It no longer requires Start-Service to throw synchronously, because SCM may accept the start request and report the host's later startup failure asynchronously.


## 27. API Windows Service Host runtime acceptance — v0.1.78

Exact-head Windows CI passed on both Push run 44906623563 and PR run 44906628820. The Windows job passed the real SCM smoke, all 17 service-host lifecycle tests, DPAPI/keyring helper checks, installer preflight tests, Windows API typecheck/tests and API build.

The SCM smoke validates the service SID and child token under a temporary LocalService account because the hosted runner returned Win32 1057 for NT SERVICE virtual-account assignment. This does not waive production provisioning: the installer must configure NT SERVICE\EnterpriseITApi and validate the installed service on a clean supported Windows Server VM.


## Windows API service provisioning policy (v0.1.80)

The provisioning script is not part of the ordinary source preview. On a disposable elevated Windows Server VM only, stage the immutable payload under %ProgramFiles%\\EnterpriseIT\\<version>, inspect the script with -WhatIf first, and verify the service identity, service SID, recovery actions and ACLs. Do not run it on production before clean-VM acceptance and a backup/rollback plan. The script does not start the service; PostgreSQL and protected configuration must be ready first.


## Provisioning dry-run behavior (v0.1.81)

Invoke the provisioning script with `-WhatIf` on a disposable Windows test host to inspect the intended operation. The script must return an explicit dry-run result without calling SCM service creation, service SID lookup or ACL mutation. A real provisioning run is privileged and must be restricted to a clean test VM until acceptance is complete.


## Windows service deployment boundary (v0.1.82)

The five-service Windows deployment is not yet available as an installable preview. The current API service-host/provisioning slice is not a complete installer. Do not register Worker, Web, Edge or PostgreSQL services manually using guessed executable paths or service identities. See `WINDOWS_SERVICE_DEPLOYMENT_DECISIONS.md` for the current service contract and remaining acceptance gates. The local Docker-based preview remains the supported way to exercise the application UI; it does not validate Windows SCM deployment.

## 18. Worker loopback readiness endpoint (development validation)

Build and start the Worker against the disposable local PostgreSQL database:

    npm run build --workspace @platform/worker
    npm run start --workspace @platform/worker

From another terminal, check its fixed loopback readiness endpoint:

    Invoke-RestMethod http://127.0.0.1:13002/health/ready

Expected: HTTP 200 with {"status":"ready"} while PostgreSQL accepts the health query. If PostgreSQL becomes unavailable, the endpoint returns HTTP 503 with {"status":"not_ready"} and does not expose database error details. The listener binds only to 127.0.0.1.

Stop the Worker with Ctrl+C and confirm it exits without waiting for the full polling interval. No discovery source handler is registered in this milestone; no queued discovery run should be claimed or processed. This is a Node process readiness check, not Windows SCM installation or service-identity acceptance.

## 19. Windows Web service payload and readiness

Build Web, then stage its standalone output into a disposable versioned payload:

    npm run build --workspace @platform/web
    pwsh -NoProfile -File scripts/windows/stage-web-standalone.ps1 -StandaloneDirectory apps/web/.next/standalone -InstallRoot $env:ProgramFiles\EnterpriseIT\0.1.84

The staging script copies standalone dependencies, static assets, public assets and the launcher. The host expects runtime\node.exe and apps\web\.next\standalone\service-entry.cjs.

Provision only after staging the complete versioned payload:

    pwsh -NoProfile -File scripts/windows/provision-web-service.ps1 -InstallRoot $env:ProgramFiles\EnterpriseIT\0.1.84

Provisioning configures identity, service SID, recovery and immutable payload ACLs; it does not start the service. On a clean Windows Server acceptance VM, verify the only Web listener is 127.0.0.1:13000 and query http://127.0.0.1:13000/health/ready. Confirm /api still rewrites to API and Web has no database credentials. CI policy tests do not prove actual virtual-account acceptance.
