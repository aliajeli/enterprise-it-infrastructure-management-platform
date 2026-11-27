# Windows LAN preview

This is the first workstation/LAN evaluation path. It runs on a Windows 10/11 workstation; it is not a Windows Server deployment and does not configure routers, NAT, port forwarding, or managed devices.

## Prerequisites

- Windows 10/11, 64-bit.
- Node.js 26.x and npm 11.x.
- Docker Desktop using Linux containers, running and healthy.
- PowerShell 7 recommended.
- A Windows network profile marked **Private** for LAN access.

The first version uses the existing local-preview stack: PostgreSQL runs in Docker and the API/web applications run as the signed-in Windows user. Node.js and Docker Desktop are prerequisites; this is not yet the self-contained offline installer.

## Start

From the repository root, run:

~~~powershell
pwsh -NoProfile -File scripts\windows\start-lan-preview.ps1 -BootstrapAdmin
~~~

Omit `-BootstrapAdmin` after the first administrator has been created. The script creates a local `.env` with a generated database password if one does not already exist, starts the loopback-only database, validates and migrates the schema, builds the workspaces, and starts API and web processes in the background.

The API listens only on `127.0.0.1:13001`. PostgreSQL is published only on `127.0.0.1:5432`. Only the web application listens on all workstation interfaces at TCP 3000.

The script prints the workstation's LAN IPv4 address. From another computer on the same LAN, open `http://WORKSTATION-LAN-IP:3000` and sign in using the administrator account created during bootstrap. Do not expose TCP 3000 to public networks.

## Windows Firewall

If LAN clients cannot connect, allow inbound TCP 3000 only on the Windows **Private** profile and only from `LocalSubnet`. To let the script create this rule, run an elevated PowerShell session:

~~~powershell
pwsh -NoProfile -File scripts\windows\start-lan-preview.ps1 -ConfigureFirewall
~~~

The script does not change firewall settings unless this switch is explicitly supplied. It never changes router/firewall appliances, NAT, port mapping, or MikroTik configuration.

## Stop and preserve data

~~~powershell
pwsh -NoProfile -File scripts\windows\stop-lan-preview.ps1
~~~

This stops the API/web process trees and the local PostgreSQL container while preserving the Docker volume. Do not use `docker compose down -v` unless you intentionally want to delete all preview database data.

Logs and process state are stored under `%LOCALAPPDATA%\EnterpriseIT\LanPreview`.

## Current limitations

- This is a source-checkout preview, not an EXE installer.
- Node.js 26, npm 11 and Docker Desktop are required.
- The development web server is used for rapid testing, not production performance.
- The first start may take several minutes while dependencies and builds are prepared.
- The app retains its existing login and authorization model. LAN reachability does not disable authentication.
- Device discovery, SNMP polling, SSH, NVR integration, and router/firewall changes are not enabled by this launcher.