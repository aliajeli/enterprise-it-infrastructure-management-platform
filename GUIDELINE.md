# Project guideline and development history

## Original master prompt — verbatim archive
The owner supplied `MASTER DEVELOPMENT PROMPT.txt` for this archive. The text between the markers below is an exact byte-for-byte copy of the supplied UTF-8 file, including its original line endings. SHA-256 of the supplied file: `38634f573b0391402a1b58ad927d133fa0ad2ca6551c8ea66180daddd3e24b16`. Later owner corrections remain separate and supersede conflicting provisions only where explicitly stated. The original conversation text was not independently compared byte-for-byte; this verifies fidelity to the supplied attachment.

<!-- BEGIN ORIGINAL MASTER PROMPT; SOURCE BYTES FOLLOW -->
# MASTER DEVELOPMENT PROMPT
# Enterprise IT Infrastructure Management Platform
## Complete Project Requirements, Architecture, Development, Release and Handover Specification

You are responsible for developing and maintaining a professional, modular, secure, scalable, and genuinely functional IT Infrastructure Management Platform.

This document is the master specification for the entire project.

All development activities, architectural decisions, implementation changes, testing, versioning, releases, and project handovers must follow this specification.

The first responsibility is to inspect the actual repository and understand its current state before implementing anything.

Do not assume the repository is empty or that any feature is missing without inspecting the actual source code.

---

# 1. PROJECT OBJECTIVE

Build a centralized IT Infrastructure Management Platform for managing multiple retail branches and their IT infrastructure.

The platform must manage:

- Branches and network connections.
- Routers and switches.
- Switch ports and VLAN information.
- Windows clients.
- Checkout systems.
- Windows Agents.
- Servers and virtual machines.
- Hikvision NVRs and cameras.
- POS terminals.
- Scales.
- PDAs.
- Printers.
- Software inventory.
- Remote access.
- Network monitoring.
- Package deployment.
- Store Commerce updates.
- Credentials and security.
- Application updates and releases.

The application must be installed on a central Windows management computer and accessible through a web browser over the local network.

The architecture must support future expansion in the number of branches, devices, users, and services.

Initial environment:

- 4 branches.
- 16 checkout systems.
- One central management computer.

These are initial quantities, NOT fixed limits.

Never hardcode these quantities into the application or database.

The project is initially intended for personal and internal IT team usage but must have a maintainable architecture suitable for future expansion.

# 2. MANDATORY TECHNOLOGY STACK

## Frontend

- Next.js App Router.
- React.
- TypeScript with strict mode.
- Tailwind CSS.
- shadcn/ui.
- Lucide icons.
- Motion for animations.
- ECharts for charts.
- TanStack Table.
- React Hook Form.
- Zod validation.

## Backend

- Node.js.
- TypeScript.
- PostgreSQL.
- Prisma ORM.
- WebSocket communication.
- Persistent background workers for long-running tasks.

The backend must be designed so that persistent WebSocket connections and background jobs do not depend on short-lived HTTP request execution.

Use a separate backend process or a technically justified custom server architecture where necessary.

## Windows Agent

- C#.
- Current supported .NET LTS version.
- Windows Service architecture.

## Terminal

- xterm.js.
- SSH backend such as ssh2.

## Remote Access

Evaluate Apache Guacamole or a technically justified alternative for RDP, VNC, and SSH.

## Excel

- ExcelJS.

## Testing

- Vitest.
- Playwright.
- GitHub Actions.

Use stable and mutually compatible package versions.

Document important version and architecture decisions.

Do not introduce unnecessary technologies or services.

# 3. WINDOWS DOMAINS AND NETWORK ENVIRONMENT

There are two Windows domains:

- GIG: central management computer and regular clients.
- OKCS: checkout computers.

The central management computer is joined to GIG.

The user has Administrator credentials in both domains.

Credential mapping:

- Client administration and Agent installation: GIG Administrator credentials.
- Checkout administration and Agent installation: OKCS Administrator credentials.

Do not assume that a trust relationship exists between GIG and OKCS.

The initial architecture must not depend on cross-domain trust.

All branches have network connectivity to the central management computer.

WinRM is currently disabled.

Initial Agent installation and routine Agent operations must not depend on WinRM.

Keep the installation process straightforward.

## Preferred initial remote installation

Use:

- SMB / ADMIN$ file transfer.
- Remote Service Control.
- Explicit credentials appropriate to the target domain.

The method is conditional on SMB, administrative shares, firewall rules, and remote service management being accessible.

Detect and report connectivity, authentication, authorization, and firewall failures separately.

GPO deployment may be considered as an optional future deployment method, not a mandatory prerequisite.

Do not make unnecessary changes to domain policies.

# 4. WINDOWS AGENT

Develop a standalone Windows Service using C# and .NET LTS.

The Agent must:

- Start automatically with Windows.
- Run independently of the browser.
- Connect outbound to the central server using HTTPS/WSS.
- Send heartbeat and system information.
- Collect software inventory.
- Execute only explicitly supported and allowlisted tasks.
- Maintain logs.
- Reconnect automatically after network interruptions.
- Report its version and SHA-256 hash.
- Support controlled upgrades.
- Report its actual operational status.
- Handle server unavailability.
- Recover from temporary communication failures.

Security requirements:

- Do not provide unrestricted remote shell execution.
- Do not allow arbitrary PowerShell execution.
- Use predefined structured task types.
- Validate all task parameters.
- Authenticate and authorize all commands.
- Log task execution and results.
- Never expose credentials in logs.
- Use secure communication.
- Reject unauthorized or malformed commands.

The Agent must not depend on WinRM for routine operations.

## Agent installation

Support deployment to:

- One selected computer.
- Multiple selected computers.
- All computers in a branch.
- All registered computers.

Before installation:

1. Check target connectivity.
2. Check whether an Agent already exists.
3. Detect installed version and hash.
4. Determine whether installation or upgrade is required.
5. Transfer the package.
6. Install or upgrade the service.
7. Verify service status.
8. Verify Agent connectivity with the central server.

Use GIG or OKCS Administrator credentials according to the target computer type.

## Agent upgrade

Use a safe upgrade process:

1. Transfer the new package.
2. Validate SHA-256.
3. Stage the new files.
4. Stop the existing service in a controlled manner.
5. Replace the files.
6. Verify installed files.
7. Restart the service.
8. Verify version and connectivity.

Never delete the working installation before the new package has been validated and staged.

# 5. CODE SIGNING AND DEVELOPMENT ENVIRONMENT

The project currently has no Code Signing Certificate.

Initial usage is personal and within a development environment.

Do not make purchasing or configuring a Code Signing Certificate a prerequisite for development, building, installation, or testing.

Important:

- Windows may display Unknown Publisher or SmartScreen warnings.
- Do not disable Windows Defender or other security controls.
- Do not implement security bypasses.
- Use SHA-256 to validate package integrity.
- Do not claim that SHA-256 alone proves publisher authenticity.
- Keep the architecture ready for future Authenticode signing.

# 6. BRANCH AND SITE MANAGEMENT

Each branch must support:

- Branch Name.
- Branch ID.
- Warehouse ID.
- Manager.
- Manager Phone.
- Deputy Manager.
- Deputy Manager Phone.
- Description.
- Status.

A branch can have multiple network connections.

Create a separate BranchLink entity:

- Name.
- Provider.
- Connection Type.
- WAN IP.
- Gateway.
- Bandwidth.
- Status.
- Description.

Do not use a fixed number of WAN connection fields inside Branch.

# 7. NETWORK EQUIPMENT MANAGEMENT

## MikroTik Routers

All branch routers are MikroTik devices.

Fields:

- Vendor.
- Model.
- Name.
- IP.
- Port.
- Branch.
- VLAN.
- Description.
- Credentials.

All MikroTik routers must be accessible through Winbox.

Allow the Winbox executable path to be configured in Settings.

A browser cannot directly launch an arbitrary desktop application.

Implement a secure Local Desktop Bridge running in the interactive Windows user session.

The Bridge must:

- Accept only authenticated local requests.
- Support only explicitly allowed applications and operations.
- Validate executable paths and arguments.
- Never put passwords in command-line arguments.
- Never expose an unrestricted process-launch endpoint.
- Reject untrusted origins and unauthorized requests.

## Switch Management

Fields:

- Vendor.
- Model.
- Name.
- Location.
- IP.
- Connection Type.
- Branch.
- Description.

Switch port information must be entered and maintained manually.

SwitchPort fields:

- Port Number.
- Status.
- VLAN.
- Connected IP.
- Connected Device.
- Description.
- Additional Details.

Do not make automatic SNMP/SSH port discovery mandatory in the initial version.

## Network Terminal

Provide a professional terminal interface similar to Termius.

Requirements:

- SSH connections.
- Multiple tabs.
- Background tab unread-output indicator.
- Multi-line command snippets.
- Fullscreen mode.
- Configurable font family and size.
- Reconnect support.
- Terminal output search.
- Session management.
- Secure credential selection.
- Confirmation for dangerous commands.

# 8. REMOTE ACCESS

## RDP / VNC / SSH

Provide remote access similar to Remote Desktop Manager.

Support:

- RDP.
- VNC.
- SSH.
- Multiple simultaneous sessions.
- Saved connection profiles.
- Credential selection.
- Session management.

Evaluate Apache Guacamole and document the selected architecture.

Consider the deployment environment carefully, especially if the central management computer runs Windows.

Do not select an architecture that cannot realistically run in the target environment.

## TeamViewer LAN

TeamViewer Incoming LAN Connection is enabled on all client computers.

The application must support launching TeamViewer LAN connections using the target computer's IP address.

Store the TeamViewer Master Password securely in Settings if required by the supported integration.

Do not assume that a particular TeamViewer CLI/API capability exists.

Inspect and test the installed TeamViewer version before implementing automated integration.

Use the Local Desktop Bridge for desktop application launching.

# 9. NVR AND CAMERA MANAGEMENT

All NVR devices are Hikvision.

Known models include:

- DS-7732NI-K4.
- DS-7732NXI-K4.

## NVR fields

- Name.
- Vendor.
- Model.
- Branch.
- VLAN.
- IP.
- Port.
- Username.
- Credential Reference.
- Firmware Version.
- Status.
- Last Sync.
- Description.

Support multiple credentials for NVR devices.

## Camera fields

- Name.
- IP.
- NVR.
- Channel Number.
- Branch.
- Status.
- Last Seen.
- Last Sync.
- Description.

Camera information must be retrieved from the associated NVR.

Investigate Hikvision ISAPI support and test compatibility with actual NVR models and firmware versions.

Required operations:

- Synchronize one NVR.
- Synchronize all NVRs.
- Synchronize NVRs by branch.
- Display last synchronization time.
- Display detailed synchronization errors.

Camera status must be derived from NVR channel status whenever possible, not merely from ICMP ping.

If a camera disappears from an NVR, mark it as inactive or removed.

Do not immediately delete its database record.

Provide configurable NVR administrator credentials in Settings.

# 10. OTHER INVENTORY MODULES

Implement CRUD functionality for all following equipment types.

## Clients

- Hostname.
- Username.
- IP.
- Domain.
- Branch.
- Agent Status.
- Agent Version.
- Description.

## Checkout Systems

- Vendor.
- Hostname.
- IP.
- Branch.
- Printer.
- Domain.
- Agent Status.
- Agent Version.
- Description.

## POS Terminals

- Vendor.
- Model.
- Firmware.
- IP.
- Terminal ID.
- Acceptance ID.
- Serial Number.
- Branch.
- Description.

## Scales

- Vendor.
- Model.
- Serial Number.
- IP.
- Stall.
- Branch.
- Description.

## Servers

- Vendor.
- Model.
- Name.
- ILO IP.
- ESXi Version.
- Branch.
- Description.

Do not restrict the database to exactly one server per branch.

## Virtual Machines

- Name.
- Hostname.
- IP.
- Domain.
- Server.
- Branch.
- Description.

## PDAs

- Model.
- IP.
- Section.
- Branch.
- Description.

## Printers

- Vendor.
- Model.
- Section.
- Branch.
- Description.

All modules must support appropriate CRUD operations, filtering, sorting, validation, and relationships.

# 11. INVENTORY IMPORT AND EXPORT

Support Excel import and export.

Requirements:

- Separate worksheet for each equipment category.
- Validate imported data.
- Report invalid rows and fields.
- Prevent unintended duplicate records.
- Show an import preview before saving.
- Support export of filtered data.
- Provide useful error reports.

Use ExcelJS.

# 12. MONITORING AND DASHBOARD

The main dashboard must display:

- Branch status.
- Checkout status.
- Agent status.
- Important system alerts.
- Recent operational events.

## Branch monitoring

Determine branch connectivity by pinging its router.

Allow configuration of:

- Ping interval.
- Timeout.
- Retry count.
- History retention.
- Concurrent monitoring limit.

Store branch monitoring history.

When a branch is selected:

- Display a larger historical chart.
- Display current equipment status.
- Show relevant connectivity information.

Only branch monitoring requires historical charts in the initial version.

Other equipment types only need:

- Online.
- Offline.
- Unknown.

Do not implement unnecessary historical charts for every equipment type.

Router ping alone does not prove that WAN or Internet connectivity is healthy.

Keep the monitoring architecture extensible for additional WAN health checks.

# 13. CHECKOUT MANAGEMENT

Create a dedicated Checkout Management module.

Features:

- Checkout list grouped by branch.
- Online/offline status.
- Agent version and hash.
- Installed software inventory.
- Software version comparison.
- Package deployment.
- Recheck operations.
- Remote access.
- Excel export.

Software inventory must include installed applications discovered from appropriate Windows sources, including:

- Registry uninstall entries.
- Supported Windows software inventory sources.
- Store Commerce.
- Store Commerce - Hyper.Commerce.

When a software item is selected, display all Checkout systems where it is installed, including version information.

Support Excel export of results.

## Package deployment

The operator must:

1. Select a package file.
2. Enter Package Folder Name.
3. Select target computers.

Target options:

- One Checkout.
- All Checkout systems in a branch.
- All Checkout systems.
- Manually selected Checkout systems.

Destination:

`C:\Source\Package\<YYYY-MM-DD>\`

Deployment workflow:

1. Check target connectivity.
2. Create destination directory.
3. Copy package.
4. Calculate source SHA-256.
5. Calculate destination SHA-256.
6. Compare hashes.
7. Retry a limited number of times if hashes do not match.
8. Record every operation.
9. Display green success or red failure status for each step.
10. Continue to the next target according to deployment policy.

Provide a detailed deployment report.

## Store Commerce update workflow

Use this workflow:

1. Check target connectivity.
2. Check whether Store Commerce is running.
3. Attempt graceful application shutdown.
4. Wait for a configurable period.
5. Force-close the application only if necessary.
6. Verify that the process has stopped.
7. Display the following message to the local interactive operator session whenever possible:

`Please do not open Store Commerce. The application is being updated.`

8. Locate the package:

`C:\Source\Package\<Package Folder Name>`

9. Locate the installer:

`Hyper.StoreCommerce.Installer.exe`

10. Execute:

`.\Hyper.StoreCommerce.Installer.exe install`

11. Execute with required elevation.
12. Capture standard output, standard error, and exit code.
13. Verify installed version.
14. Report every step and its result.

The IT operator coordinates with Checkout operators before deployment to ensure there are no open invoices or transactions.

Force-closing Store Commerce can cause data loss or unfinished transaction problems.

Clearly warn the operator before deployment and record approval.

Never silently terminate the application.

A dashboard notification alone is insufficient.

Notify the local interactive user session through the Agent whenever possible.

# 14. CLIENT MANAGEMENT

Create a dedicated Client Management module.

Features:

- Client list grouped by branch.
- Online/offline status.
- Agent version.
- Installed software inventory.
- TeamViewer LAN access.
- Agent installation and upgrade.
- Recheck operations.
- Excel export.

Use GIG Administrator credentials for Client administration.

# 15. AGENT AND SOFTWARE DEPLOYMENT MANAGEMENT

Support deployment to:

- One computer.
- Multiple selected computers.
- All computers in a branch.
- All computers.

Before deployment:

- Detect existing Agent version.
- Detect existing Agent hash.
- Determine whether installation or upgrade is required.

After deployment:

- Verify service status.
- Verify installed version.
- Verify hash.
- Verify connection to central server.

Provide progress information and detailed per-device results.

# 16. SETTINGS AND CREDENTIAL VAULT

Create a comprehensive Settings module.

## Application settings

- Application username/password.
- Recovery code.
- Monitoring configuration.
- Winbox executable path.
- TeamViewer configuration.
- NVR administrator credentials.
- Terminal font family and size.
- Theme selection.
- Application name and logo.

## Credential Vault

Support multiple saved credentials.

Credential fields:

- Name.
- Username.
- Password.
- Domain.
- Description.
- Credential Category.

Credential categories:

- GIG.
- OKCS.
- RDP.
- VNC.
- SSH.
- MikroTik.
- Switches.
- Hikvision NVR.
- TeamViewer.

A device can have multiple associated credentials.

The operator must be able to select the appropriate credential when connecting to a device.

Security:

- Hash application passwords using Argon2id.
- Encrypt stored equipment passwords using AES-256-GCM.
- Protect encryption keys using Windows DPAPI or an appropriate protected key-management mechanism.
- Never expose plaintext secrets in frontend responses or logs.
- Use role-based authorization.
- Audit sensitive credential operations.

## Recovery code

Generate a secure recovery code.

Store only its secure hash.

Recovery must be one-time use and securely implemented.

## User roles

Support:

- Admin.
- Operator.
- Viewer.

Implement permission checks in the backend, not only in the frontend.

## Audit log

Record important security and operational actions, including:

- Login events.
- Credential access.
- Device modifications.
- Agent installation and upgrade.
- Package deployment.
- Remote connection initiation.
- Configuration changes.
- Release and update operations.

# 17. USER INTERFACE AND DESIGN

The entire application UI must be in English.

Design requirements:

- Professional commercial software appearance.
- Modern enterprise dashboard.
- Component-based architecture.
- Consistent spacing and typography.
- Responsive layout.
- Accessible controls.
- Useful empty states.
- Loading states.
- Error states.
- Confirmation dialogs for destructive operations.

Supported themes:

- Light.
- Dark.
- Ocean.
- Midnight.

The login page should have a professional animated design.

Application name and logo must be configurable.

Use real database data.

Do not leave mock data in production workflows.

Test these screen sizes:

- 1280x720.
- 1366x768.
- 1600x900.
- 1920x1080.
- 2560x1440.
- 3840x2160.
- Tablet.
- Mobile.

Layout guidance:

- Use percentages for fluid widths where appropriate.
- Use rem for spacing and typography.
- Use px for borders and fine details.
- Use clamp(), minmax(), and responsive breakpoints where appropriate.
- Avoid arbitrary fixed dimensions that break at common resolutions.

# 18. DATABASE AND ARCHITECTURE

Use PostgreSQL and Prisma.

Design a normalized, maintainable database.

Requirements:

- Proper relationships and foreign keys.
- Appropriate indexes.
- Unique constraints where needed.
- Created/updated timestamps.
- Soft deletion where operational history must be preserved.
- Database migrations.
- Transactional operations where appropriate.
- Audit history for important changes.

Separate concerns into clear modules.

Do not place all application logic in a single file or oversized component.

Document the actual database schema and relationships in:

`docs/DATABASE_DESIGN.md`

Do not perform destructive database migrations without explicit review and a recovery plan.

# 19. GITHUB BRANCH STRATEGY

Use a private GitHub repository.

Exactly two permanent branches:

- `main`
- `beta`

Development workflow:

1. Develop and integrate changes on beta.
2. Run validation and tests.
3. Review and approve changes.
4. Merge approved changes into main.

Temporary branches may be used when technically necessary.

Temporary branches must not become permanent branches.

Document their purpose and lifecycle.

Do not create additional permanent branches.

Do not include references to AI tools, coding agents, or automated assistants in:

- Repository documentation.
- Commit messages.
- Branch names.
- Application UI.
- Changelogs.

# 20. AUTOMATIC VERSIONING — MANDATORY

Every Git commit pushed to GitHub must have a unique application version.

This requirement applies to:

- main.
- beta.
- Temporary branches.
- Any other development branch.

Use Semantic Versioning principles:

`MAJOR.MINOR.PATCH`

Version increment rules:

- PATCH: Bug fixes, minor corrections, and backward-compatible maintenance.
- MINOR: New backward-compatible features.
- MAJOR: Breaking changes, incompatible API changes, or major architectural changes.

For every commit:

1. Identify the nature and scope of the change.
2. Determine the appropriate version increment.
3. Update the application's version metadata.
4. Keep all relevant version files synchronized.
5. Associate the version with the exact Git commit.
6. Trigger the release pipeline.

Use a consistent versioning strategy.

Prefer Conventional Commits or another documented and enforceable commit classification mechanism.

Examples:

`fix(agent): improve reconnect handling`

`feat(nvr): add camera synchronization`

`feat!: redesign authentication API`

The release automation must correctly interpret the change type.

Documentation-only and maintenance commits must also receive a unique build/release version, even when the semantic version level does not require a feature-level increment.

Do not reuse an existing version.

Do not create duplicate tags.

## Branch-specific versioning

`main`:

- Stable release.
- Stable semantic version.
- Example: `1.4.0`

`beta`:

- Pre-release version.
- Example: `1.5.0-beta.12`

Temporary branches:

- Unique pre-release version.
- Include a sanitized branch identifier and unique build number or commit identifier.
- Example: `1.5.0-feature-terminal.4`

A release from beta or a temporary branch must never be presented as a stable main release.

The versioning implementation must avoid collisions between branches.

Use Git tags to identify the exact source commit for each release.

## Version metadata

Maintain a single authoritative application version source wherever technically practical.

Synchronize relevant version metadata across:

- Application frontend.
- Backend.
- Windows Agent where applicable.
- Installer.
- Release manifest.
- GitHub Release.

Display the installed application version in the application UI.

Also display:

- Release channel.
- Build identifier.
- Commit identifier where appropriate.

# 21. AUTOMATIC BUILD AND GITHUB RELEASE — MANDATORY

After every GitHub commit on every branch, automatically attempt to:

1. Validate the commit.
2. Determine the version.
3. Run required tests.
4. Run lint and type checking.
5. Build the frontend and backend.
6. Build the Windows Agent.
7. Prepare the application installation package.
8. Validate package contents.
9. Calculate SHA-256 checksums.
10. Generate the release manifest.
11. Create a GitHub Release.
12. Upload the installation package and required release assets.

Use GitHub Actions.

## Release channels

### main

Publish stable GitHub Releases.

- Stable version.
- Not marked as prerelease.
- Intended for normal installation and production use.

### beta

Publish GitHub Releases marked as prerelease.

- Beta version.
- Intended for testing.
- Must not overwrite stable releases.

### Temporary branches

Publish uniquely identified prerelease builds.

- Clearly identify the source branch.
- Clearly identify the commit.
- Never overwrite stable or beta releases.

## Release assets

Where applicable, include:

- Windows installer.
- Windows Agent package if separately distributed.
- Release manifest.
- SHA-256 checksum file.
- Release notes.
- Version information.

The installation package must be downloadable and usable to install or upgrade the application.

Do not publish an installer that has not passed the required build and validation stages.

If the build or mandatory tests fail:

- Mark the pipeline as failed.
- Do not publish a successful release.
- Preserve diagnostic logs.
- Report the exact failure.
- Do not falsely claim that a release is available.

## Installer requirements

The final installer architecture must be compatible with the target Windows environment.

It must support:

- Fresh installation.
- Upgrade.
- Preservation of application configuration.
- Preservation of user data.
- Database migration handling.
- Required service installation and configuration.
- Windows Agent installation where applicable.
- Uninstallation.
- Recovery from failed installation.
- Version verification.

Select the installer technology after inspecting the existing repository and validating the target architecture.

Do not assume that a particular installer framework is mandatory.

The installer must not silently overwrite user data.

## Release notes

Generate release notes from actual changes.

Include:

- Version.
- Release channel.
- Commit hash.
- Date.
- New features.
- Bug fixes.
- Breaking changes.
- Important migration notes.
- Known limitations.

Do not invent features or claim fixes that are not present.

# 22. APPLICATION UPDATE SYSTEM

Support application updates from GitHub Releases.

Release channels:

- Main: stable.
- Beta: prerelease.

Requirements:

- Manifest-based update mechanism.
- Detect installed version.
- Detect available version.
- Respect the selected release channel.
- Download only required files where practical.
- Verify SHA-256 integrity.
- Stage updates before installation.
- Preserve configuration and user data.
- Apply database migrations safely.
- Provide rollback.
- Report update status and errors.
- Record update activity in the Audit Log.

Do not automatically downgrade a stable installation to beta.

Do not automatically switch release channels without explicit user action.

A failed update must not leave the application unusable.

Prepare the architecture for future Authenticode signing.

Never treat SHA-256 as proof of publisher authenticity.

# 23. DOCUMENTATION — MANDATORY

Documentation is a required part of development, not an optional final step.

## README.md

Must accurately describe:

- Project overview.
- Features.
- Architecture.
- Technology stack.
- Prerequisites.
- Installation.
- Development setup.
- Database setup.
- Configuration.
- Agent installation overview.
- Build and update procedures.
- Release channels.
- Versioning.
- Security.
- Links to technical documentation.
- Release information.

README must reflect actual implementation.

## docs/GUIDELINE.md

This is the complete master project guideline and development history.

It must contain:

- Original master prompt.
- All requirements and corrections.
- All approved decisions and reasons.
- Chronological development history.
- Architecture decisions.
- Database design decisions.
- Versioning and release policy.
- Implementation status.
- Files created, modified, and removed.
- Database migrations.
- Commands executed.
- Errors encountered and solutions.
- Tests performed and actual results.
- Completed features.
- Partially completed features.
- Pending features.
- Known limitations.
- Unresolved questions.
- Build and deployment procedures.
- Installer generation procedures.
- Update and rollback procedures.
- Current project status.
- Exact next development steps.

Preserve the original prompt verbatim.

If requirements change, do not silently overwrite the original version.

Append the new version with its date and explain the changes.

## docs/HANDOVER.md

This file is the current operational snapshot of the repository.

It must be updated after every meaningful development milestone.

It must allow another developer or development environment to continue without guessing.

Required sections:

1. Project Overview.
2. Current Project Status.
3. Current Development Phase.
4. Current Git Branch.
5. Latest Commit Hash.
6. Current Application Version.
7. Latest Stable Release.
8. Latest Beta Release.
9. Latest Successful Installer Build.
10. Last Completed Task.
11. Current In-Progress Task.
12. Exact Next Action.
13. Pending Tasks.
14. Known Bugs.
15. Failed Tests.
16. Latest Successful Build.
17. Database Migration Status.
18. Required Environment Configuration.
19. Required Services.
20. Important Files and Directories.
21. Recent Changes.
22. Documentation Discrepancies.
23. Known Limitations.
24. Commands Required to Run and Test the Project.
25. Release Pipeline Status.

Every status must be based on verified repository information.

Never invent a commit hash, build result, test result, or release status.

If a value cannot be verified, explicitly write `Not verified` or `Unknown`.

## Additional technical documentation

Create and maintain these files as relevant:

- `docs/ARCHITECTURE.md`
- `docs/DATABASE_DESIGN.md`
- `docs/NETWORK_REQUIREMENTS.md`
- `docs/SECURITY_POLICY.md`
- `docs/AGENT_SPECIFICATION.md`
- `docs/DEPLOYMENT_WORKFLOWS.md`
- `docs/API_DOCUMENTATION.md`
- `docs/TESTING_STRATEGY.md`
- `docs/CHANGELOG.md`
- `docs/DECISION_LOG.md`
- `docs/RELEASE_PROCESS.md`
- `docs/VERSIONING_POLICY.md`

Keep documentation consistent with the actual code.

# 24. HANDOVER AND PROJECT CONTINUITY

The project must always be ready to be handed over to another developer or development environment.

When a new development session starts:

1. Read README.md.
2. Read docs/GUIDELINE.md.
3. Read docs/HANDOVER.md.
4. Read relevant technical documentation.
5. Inspect actual source code.
6. Inspect database schema and migrations.
7. Inspect tests.
8. Inspect Git history and current branch.
9. Inspect latest GitHub Releases and tags.
10. Compare documented status with actual implementation.

Do not assume that documentation is accurate without verification.

Before continuing development:

- Identify the last completed task.
- Identify incomplete work.
- Identify known issues.
- Identify failed tests.
- Identify current application version.
- Identify latest successful release.
- Determine the exact next task.
- Avoid repeating completed work.

If documentation and implementation disagree:

- Record the discrepancy.
- Determine actual state from source code and tests.
- Correct documentation where appropriate.
- Do not silently discard important historical decisions.

At the end of every meaningful task:

- Update HANDOVER.md.
- Update GUIDELINE.md.
- Update README.md when relevant.
- Update technical documentation when relevant.
- Update CHANGELOG.md.
- Update version metadata.
- Ensure the release pipeline is configured.
- Commit code and documentation together on the appropriate branch.

# 25. SECURITY AND OPERATIONAL REQUIREMENTS

All sensitive operations must be authenticated and authorized.

Requirements include:

- Backend authorization.
- Secure session management.
- Credential encryption.
- Secure key management.
- Input validation.
- Output encoding.
- Protection against common web vulnerabilities.
- Secure WebSocket authentication.
- Rate limiting where appropriate.
- Audit logging.
- Safe error handling.
- No secrets in source control.
- No secrets in frontend bundles.
- No plaintext passwords in logs.
- Safe backup and restore procedures.

Do not disable operating system security features to simplify development.

Do not expose unrestricted administrative operations through the browser.

# 26. TESTING AND QUALITY CONTROL

Use automated tests wherever practical.

Required checks:

- TypeScript type checking.
- ESLint.
- Unit tests.
- Integration tests.
- Database migration validation.
- Production build.
- Playwright UI tests for important workflows.
- Windows Agent build and relevant tests.
- Installer validation.
- Release manifest and checksum validation.
- Update and rollback validation.

GitHub Actions must run relevant checks.

Do not report a feature as completed merely because its UI exists.

A feature is complete only when:

- Frontend is implemented.
- Backend is implemented.
- Database integration works.
- Authorization is enforced.
- Error handling is implemented.
- Relevant tests pass.
- Documentation is updated.

Report actual test results.

Never claim tests passed if they were not executed.

# 27. DEVELOPMENT PHASES

Follow these phases in order.

Phase 1 — Repository Inspection and Project Assessment.

Phase 2 — Architecture and Database Validation.

Phase 3 — Application Foundation and Authentication.

Phase 4 — Inventory and Branch Management.

Phase 5 — Monitoring and Dashboard.

Phase 6 — Windows Agent.

Phase 7 — Client and Checkout Management.

Phase 8 — Package Deployment and Store Commerce Update.

Phase 9 — Network Equipment and Terminal.

Phase 10 — NVR and Camera Integration.

Phase 11 — Remote Access and Desktop Bridge.

Phase 12 — Security, Testing, Documentation, Versioning, Installer, and Release.

The order may be adjusted only when a technical dependency requires it.

Document the reason.

Versioning and release automation should be introduced early enough to ensure every subsequent development commit is traceable and produces a validated installation package.

# 28. FIRST ACTION — STRICTLY ENFORCED

DO NOT start major implementation immediately.

Your first task is Phase 1 only.

Inspect the actual repository and report:

1. Current directory structure.
2. Existing technology stack and versions.
3. Existing frontend and backend implementation.
4. Existing database schema and migrations.
5. Existing Agent implementation, if any.
6. Existing API endpoints.
7. Existing authentication and authorization.
8. Existing tests and their actual results.
9. Current Git branch and latest commit.
10. Existing documentation.
11. Existing GitHub Actions workflows.
12. Existing application versioning.
13. Existing Git tags and GitHub Releases.
14. Existing installer and packaging system.
15. Features already implemented.
16. Features partially implemented.
17. Features not implemented.
18. Bugs and technical debt.
19. Conflicts between documentation and actual source code.
20. Risks and architectural concerns.
21. Recommended next development task.

Do not overwrite existing functionality.

Do not rebuild working modules without a verified technical reason.

Do not claim that a feature exists unless you have verified its implementation.

After Phase 1, provide a detailed assessment report and wait for approval before beginning major implementation.

If the repository has not been cloned or access is unavailable, clearly report that Phase 1 cannot be completed against the actual repository.

Do not classify remote repository features as unimplemented based only on an empty local workspace.

# 29. REQUIRED COMPLETION REPORT

After every meaningful development task, provide:

- Task name.
- Objective.
- Files created.
- Files modified.
- Files removed.
- Database changes and migrations.
- Implementation details.
- Commands executed.
- Tests executed.
- Actual test results.
- Build result.
- Installer build result where applicable.
- Application version.
- Release channel.
- Git branch.
- Commit hash.
- GitHub Release URL if published.
- Known issues.
- Security considerations.
- Documentation updated.
- Remaining work.
- Exact next recommended task.

Keep README.md, GUIDELINE.md, HANDOVER.md, technical documentation, version metadata, and release information synchronized with the actual project.

# 30. FINAL PRINCIPLES

1. Build a genuinely functional IT management platform.
2. Prioritize security, reliability, and maintainability.
3. Do not repeat completed work.
4. Do not destroy working functionality.
5. Do not invent implementation status or test results.
6. Keep the architecture appropriate for the actual Windows target environment.
7. Keep documentation synchronized with implementation.
8. Assign a unique version to every GitHub commit.
9. Automatically build and publish a downloadable installer for every successful commit.
10. Maintain separate stable and prerelease release channels.
11. Make every release traceable to its exact Git commit.
12. Ensure that another developer can continue the project using the documentation and actual repository state.

**The final objective is a secure, maintainable, professional IT infrastructure management platform with a reliable Windows installation, automatic versioning, automated builds, downloadable releases, and safe update capabilities.**
<!-- END ORIGINAL MASTER PROMPT; SOURCE BYTES END -->

## Requirement index — non-authoritative summary
1. Central multi-branch IT infrastructure management; starting quantities not hard limits.
2. Mandatory Next.js/React/strict TypeScript/Tailwind/shadcn/Lucide/Motion/ECharts/TanStack/React Hook Form/Zod; Node/PostgreSQL/Prisma/WebSockets/persistent workers; C# .NET LTS Windows agent; xterm.js/SSH; assess Guacamole; ExcelJS; Vitest/Playwright/Actions.
3–5. GIG clients, OKCS checkouts, explicit respective admin credentials, no trust/WinRM dependency; conditional SMB/ADMIN$ and remote SCM; service agent, allowlisted tasks, safe staged upgrades and SHA-256 without signature bypass; no signing certificate prerequisite.
6–10. Branches and multiple links; MikroTik Winbox and secure interactive local bridge; manually maintained switch ports; terminal features; RDP/VNC/SSH and TeamViewer (version validation); Hikvision ISAPI and camera reconciliation; full inventory CRUD and relationships.
11–15. Excel preview/validation/export; branch router monitoring and history, current status for other equipment, no WAN-health inference; checkout/client management; software discovery, package and Store Commerce deployment with explicit approval and interactive notice; agent deployment and verification.
16–18. Settings, AES-GCM credential vault and DPAPI key protection, Argon2id, recovery, roles and audit; English responsive accessible four-theme UI; normalized PostgreSQL schema, migrations and safe history.
19–22. Private GitHub; main/beta permanent branches, temporary lifecycle; unique version per pushed commit, stable/prerelease distinction, validated installer and GitHub release, exact commit attribution, safe updates, integrity vs authenticity.
23–26. Mandatory README/guideline/handover/technical documentation, ongoing truthful handover, security and testing; no inventions, no AI references in repository text, commits, branch names, UI or changelogs.
27–30. Phased work, repository inspection first; completion reports; no major implementation before assessment approval; preserve functionality, traceability and handover.

## Subsequent corrections — 2026-11-18
Owner approved Phase 1 and authorized Phase 2 with these requirements:
1. Do not start application implementation yet. Phase 2 is strictly for architecture design, database modeling, technical validation, documentation, and foundational repository planning.
2. Before proceeding, verify and address the repository visibility discrepancy. The repository must be private. Do not expose or embed any credentials or access tokens.
3. Design the GitHub versioning and release pipeline carefully. Every pushed commit on every development branch must trigger an independent pipeline with a unique version. Successful commits must produce a standalone Windows installer and a corresponding GitHub Release. Failed builds or tests must never publish a successful release. Prevent duplicate versions, tag collisions, race conditions, and recursive workflow triggers.
4. The end-user installer must be self-contained. End users must not need Node.js, Python, Git, .NET SDK, or other developer tools installed separately. Evaluate the runtime packaging, PostgreSQL deployment, Windows services, upgrade, data preservation, uninstall, and rollback strategy before selecting the installer technology.
5. Evaluate the Windows deployment architecture against the actual target environment. Pay particular attention to Windows Service execution, interactive user sessions, Local Desktop Bridge, SMB-based Agent deployment, cross-domain credentials, and PostgreSQL lifecycle management.
6. Produce a complete initial database model, including entities, relationships, constraints, indexes, migration strategy, and data retention considerations.
7. For major architectural decisions, compare viable alternatives, document advantages and disadvantages, and explain the selected approach. Do not present unverified compatibility assumptions as established facts.
8. Create and maintain the foundational documentation, including README.md, docs/GUIDELINE.md, docs/HANDOVER.md, docs/ARCHITECTURE.md, docs/DATABASE_DESIGN.md, docs/SECURITY_POLICY.md, docs/NETWORK_REQUIREMENTS.md, docs/AGENT_SPECIFICATION.md, docs/DEPLOYMENT_WORKFLOWS.md, docs/RELEASE_PROCESS.md, docs/VERSIONING_POLICY.md, docs/DECISION_LOG.md, and docs/TESTING_STRATEGY.md.
9. Keep the original project requirements and all subsequent corrections in GUIDELINE.md. Do not silently remove, simplify, or change previously approved requirements.
10. Do not create application implementation, database migrations, installer packages, GitHub Releases, or implementation commits during this phase unless a specific foundational action is necessary and explicitly documented.

The owner also required the Phase 2 report to include the architecture and component diagram, ERD/schema proposal, Windows installer/deployment, security, branching/versioning/CI/release design, alternatives, risks/compatibility tests, updated documentation, exact changed-file list and decisions needing approval, and to stop before Phase 3 pending explicit approval. The correction was repeated after the owner reported private visibility. The owner later reported the previously exposed token revoked and supplied a screenshot showing the specified repository as private.

## Chronological history and actual status
* 2026-11-18: inspected empty workspace and remote unauthenticated GitHub metadata. At that time GitHub reported public, zero-size repository, no branches/tags/releases and empty commits/contents. Cloned empty repository; local branch `main` unborn and no commits. Phase 1 approved by owner.
* 2026-11-18: owner instructed Phase 2 only and required private visibility. Follow-up unauthenticated API returned 404; not alone proof of privacy. Owner reported token revoked and provided screenshot of the named repository settings explicitly showing private. Authenticated current remote branch, release and permissions status remains not verified.
* 2026-11-18: wrote Phase 2 design documentation in local working tree only. No implementation, migrations, installer, release, commit or push. Exact files and current actions: HANDOVER.md. The target Windows system, installed software and hardware were not accessible. At that time all design choices were proposals; later owner decisions are recorded below. Open issues included original verbatim archival, installer technology, bridge feasibility, release allocation and practical update authenticity.

## Decisions, test results, migration, procedures and next action
See DECISION_LOG.md, ARCHITECTURE.md, DATABASE_DESIGN.md, SECURITY_POLICY.md, NETWORK_REQUIREMENTS.md, AGENT_SPECIFICATION.md, DEPLOYMENT_WORKFLOWS.md, RELEASE_PROCESS.md, VERSIONING_POLICY.md, TESTING_STRATEGY.md and HANDOVER.md. These documents distinguish planned from verified behavior. No database changes, application builds, tests, installer builds or releases were performed. Environment inspection commands and results are in HANDOVER.md. No implementation or release can be claimed. Next: review the archived source and remaining technical details; perform validation only when separately authorized and await explicit Phase 3 authorization. Owner-approved decisions below supersede earlier unresolved proposals.

## Architecture review and corrections — 2026-11-18
The owner reviewed ARCHITECTURE.md, found it directionally acceptable but did not approve implementation, and required the following revisions:
1. Define the exact Windows service/process topology, responsibilities, dependencies, startup order, health checks, restart policies, logging, and shutdown behavior. Clarify whether the TLS edge, Next.js, API, and workers must run as separate Windows services.
2. Complete the Local Desktop Bridge security design. Specify origin validation, secure enrollment, authentication, short-lived request tokens, replay protection, application allowlisting, input validation, process-launch restrictions, and secure credential handoff. Do not expose a generic local command-execution interface.
3. Complete the Windows Agent deployment workflow. It must support:
  - Checkout devices using OKCS administrator credentials.
  - Client devices using GIG administrator credentials.
  - SMB/ADMIN$ and Remote Service Control where available.
  - No mandatory WinRM dependency.
  - Connectivity, permission, firewall, service creation, startup, enrollment, and verification checks.
  - Clear failure reporting and recovery.
4. Define the Agent enrollment and identity lifecycle, including one-time enrollment, per-agent identity, credential rotation, revocation, reinstall, and recovery.
5. Expand PostgreSQL and Windows installation architecture. Document database installation, service ownership, data directories, backup, restore, schema migration, upgrade, uninstall, and rollback. Application upgrades must never silently delete user data.
6. Provide a complete initial database ERD and data model covering all approved project entities, relationships, constraints, indexes, audit records, Agent tasks, deployment steps, software inventory, Branch monitoring history, NVRs, cameras, switches, switch ports, credentials, and equipment bindings.
7. Map every major project module to an explicit architectural component:
  - Inventory Management
  - Monitoring Engine
  - Agent Management
  - Deployment Engine
  - Network Management
  - CCTV Management
  - Remote Access
  - Credential Vault
  - Release and Update Management
  - Excel Import/Export
8. Document the complete Hikvision integration workflow using ISAPI, including NVR discovery, camera/channel synchronization, status interpretation, multiple credentials, removed cameras, and synchronization errors. Compatibility must remain unverified until tested against the actual NVR models and firmware.
9. Document the complete Checkout deployment and Store Commerce update workflow, including package copying, SHA-256 verification, retries, operator notification, graceful shutdown, forced shutdown, installer execution, output capture, version verification, and per-step reporting.
10. Expand Monitoring architecture to cover Branch router reachability, configurable intervals/timeouts/retries, history retention, concurrency limits, and the distinction between router reachability and actual WAN/Internet health.
11. Define the integration boundaries for Winbox, TeamViewer LAN, SSH, RDP, and VNC. Document which operations are performed by the central service and which require the operator's local Desktop Bridge. Do not claim automatic login or secure credential handoff without a tested implementation.
12. Expand the release and installer architecture. Every pushed commit must trigger an isolated pipeline with a unique version. Every successful commit must produce a standalone Windows installer and a matching GitHub Release. Failed builds or tests must not publish a successful release. Include concurrency control, tag collision prevention, channel rules, SHA-256 manifests, release asset structure, and rollback.
13. For all significant technology choices, compare alternatives and provide a clear recommendation with technical justification. Identify which decisions require an actual Windows proof of concept.
14. Update ARCHITECTURE.md and the relevant technical documents. Preserve all previously approved requirements. Do not silently remove, simplify, or replace requirements.

Owner restrictions: no application implementation, production migrations, release artifacts, unverified compatibility claims or irreversible repository changes. Remain in Phase 2. Provide change summary, diagram, ERD, unresolved decisions, risks and exact files modified; stop and await approval before Phase 3.

Revision implemented as local documentation changes only. No production code, schema, tests, installer, workflow or release created. At that milestone the original master prompt verbatim preservation remained open; it was later archived as recorded below.


## Final owner decisions and Phase 2 revision — 18 November 2026
The owner explicitly approved and made authoritative: (1) five separate Windows services (TLS Edge, Next.js, API/WebSocket, Worker, PostgreSQL), (2) date-only `C:\Source\Package\<YYYY-MM-DD>\`, with Package Folder Name as metadata and recorded exact path, (3) one-time initial installer bootstrap exception ending with the first genuinely installable/runnable independently tested Windows release, (4) separately hosted central Update Proxy with protected server-only GitHub App credentials and authenticated/authorized application clients, (5) a bounded Desktop Bridge security PoC requiring separate authorization, and (6) Tier 1 every-commit, Tier 2 Windows VM, Tier 3 relevant hardware testing; hardware absence must not block unrelated changes. These supersede conflicting earlier proposals. Owner also required full service lifecycles, ERD and deployment, proxy threat model and API contract, consistent security/release/version/testing docs, complete requirements preservation and no Phase 3, production implementation, migrations, installers or releases. These requirements are elaborated in DECISION_LOG.md and the current technical documents.

At this milestone the full original master prompt had not yet been archived verbatim. The owner later supplied the UTF-8 attachment, which has now been archived byte-for-byte above. Owner decisions above are recorded as a summary, not claimed as a verbatim archive of the complete latest instruction. No actual target validation or PoC has been performed.


## Source archival milestone — 2026-11-18
The owner supplied `MASTER DEVELOPMENT PROMPT.txt`; its complete bytes were embedded above without line-ending conversion. The source and extracted archive were checked for byte equality and SHA-256 equality. No credential-like GitHub token marker was found by a limited pattern check; this is not a comprehensive secret scan. This proves fidelity to the attachment, not an independent byte-by-byte comparison with the original conversation. Phase 2 remains in design and validation; no Phase 3 approval, implementation, production migration, installer, proof of concept, release or commit occurred. See HANDOVER.md for status and remaining technical validation.


## Public documentation mirror note
The separate public review mirror stores current documentation at its repository root. References to `docs/` in the verbatim master prompt and historical corrections describe the original application-repository requirements and are intentionally preserved; they are not links asserting that a `docs/` directory exists in this mirror. The preserved original bytes must never be rewritten for mirror navigation. See [README.md](README.md) for current mirror links and [HANDOVER.md](HANDOVER.md) for current state.


## Local final-upload preparation
A separate local `FINAL_UPLOAD` package restores the embedded master prompt to match the supplied original bytes (including CRLF) after earlier mirror normalization. The owner must review exact-byte preservation and Git line-ending settings before any future transfer. The source branch and historical artifacts were not modified. This package is for owner review, not evidence of deployment or publication.
