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


## Read-only SNMP discovery safeguards — mandatory design constraints

The first network-device discovery implementation is limited to explicitly registered device management IPs. It is not a subnet scanner or a port mapper.

- Send SNMP requests only to the configured target IP and configured SNMP port (default UDP/161). Prefer SNMPv3 authPriv. SNMPv2c is permitted only when an administrator explicitly configures a read-only community; never guess or brute-force credentials.
- Use only SNMP GET, GETNEXT and bounded GETBULK reads. SNMP SET is prohibited. Do not probe TCP/UDP port ranges, perform TCP connect scans, sweep subnets, discover arbitrary hosts, or use NAT/DST-NAT/port-forward rules.
- Never create, change or remove MikroTik firewall/NAT/address-list rules, RouterOS services, or SNMP configuration automatically. Never attempt an automatic unblock after a device or management source is blocked.
- A network administrator must explicitly permit the management server's source IP to reach the device's SNMP UDP/161 service, with firewall ordering reviewed against any PSD/port-scan detection and drop rules. The application must not make this firewall change itself.
- Conservative initial execution limits are proposed: one active SNMP session per target, low bounded GETBULK repetition, a configurable request timeout, at most one delayed retry, and a per-target circuit breaker. Final numeric defaults require lab testing against the actual MikroTik/Cisco models and RouterOS/firmware versions.
- On timeout, rate-limit indication, or evidence of filtering/blocking, stop requests to that target for the current run; do not escalate to alternate ports or repeated probes. Record `NO_RESPONSE` or `FILTERED_OR_BLOCKED` unless router/firewall logs independently confirm an IP block. Do not mislabel a timeout as a confirmed block.
- Discovery is append-only: record timestamped port observations and source provenance. Never overwrite operator-maintained alias, description, configured VLAN or connected-device labels. Partial/failed runs must not delete assets or ports.
- IP-to-port correlation is best-effort only. A switch may expose learned MAC-to-port data while IP-to-MAC requires a separate ARP/L3 source; missing data must remain unknown rather than inferred.

These constraints are specified in [SNMP_DISCOVERY_DESIGN.md](SNMP_DISCOVERY_DESIGN.md). No SNMP polling, port scan, port mapping, NAT edit or MikroTik firewall change is implemented by the current inventory UI.
