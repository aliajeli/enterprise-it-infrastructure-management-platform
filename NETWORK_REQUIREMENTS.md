# Network requirements — proposed, unvalidated

* Operator browsers and agents reach central HTTPS/WSS over an administrator-selected TCP port, proposed 443; DNS, certificate SAN and trust must match. Reverse proxy internal ports and PostgreSQL bind loopback only. Permit only necessary Windows firewall rules; no global disable.
* Central worker to monitored routers: ICMP echo if permitted. ICMP blocks/ACLs produce unknown or unreachable, not proof of branch WAN or Internet failure. Configure interval, timeout, retries, concurrency and retention.
* Central to NVR: HTTPS/HTTP ISAPI port per device with approved network policy; test model/firmware paths, authentication and channel status. Prefer HTTPS with validated certificate. Do not silently downgrade TLS.
* Agent initial deployment: central to target SMB TCP 445 and remote SCM/RPC endpoint mapper TCP 135 plus negotiated dynamic RPC ports as configured by Windows/firewalls; verify exact protocol/port needs against target, including SMB signing, DNS and policy. ADMIN$ and service rights required; no WinRM or trust assumption. Explicit GIG credentials for clients, OKCS for checkouts. Detect DNS, connectivity, authentication, share and SCM authorization/service failure separately; an inaccessible target may not reveal whether firewall or service is responsible, so report evidence and uncertainty.
* SSH device port configured per profile, host key verified. RDP, VNC and TeamViewer require each selected client's actual network paths and policies; Winbox port as configured. Guacamole, if chosen later, adds authenticated operator-to-gateway and gateway-to-target routes. Desktop bridge is local to the operator, not a network listener.
* No target OS, topology, DNS, routing, domain policy, firewall or protocol path has been tested. Clarify Windows edition/build, administrative privilege, 64-bit architecture, domain DNS and GIG-to-OKCS credential behavior with owner.

## Check matrix to validate on target
| Source → destination | Purpose | Required evidence |
|---|---|---|
| Agent → central | TLS/WSS enrollment and ongoing task/heartbeat | DNS, certificate trust/SAN, proxy/firewall and revocation behavior. |
| Central worker → checkout/client | SMB 445/ADMIN$ and remote SCM/RPC | Test OKCS vs GIG explicit credentials separately, no domain trust, share permissions, TCP 135 and negotiated RPC ports; identify exact firewall rule at site. |
| Operator browser → bridge | Native messaging/OS-user-scoped local IPC | Browser and extension deployment, exact trusted origin, user/session ACL and replay tests; no LAN-exposed listener. |
| Central → NVR | ISAPI channel config and runtime state | Each actual model/firmware, HTTPS certificate/authentication, permission and XML behavior. |
| Central → network device | ICMP and SSH | ACLs, timeout/rate limits, host-key verification and status interpretation. |
| Operator or optional gateway → devices | Winbox/TeamViewer/RDP/VNC | Installed client capabilities, paths and ports, routing and safe credential handling; no assumed login support. |

## Update Proxy paths
The owner-operated proxy is separate from the installation. Installed updater → proxy requires trusted HTTPS, its own scoped installation identity and allowed outbound firewall path; proxy → GitHub requires outbound HTTPS to fixed, allowlisted endpoints and a server-side GitHub App credential. Proxy clients must not directly access private GitHub release APIs or receive their tokens. The exact proxy host, DNS, certificate, deployment platform and egress configuration are not yet verified. The central Windows edge remains the only externally exposed application listener; proxy exposure is separately governed and authenticated.
