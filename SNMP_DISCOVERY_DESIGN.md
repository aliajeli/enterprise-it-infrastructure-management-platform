# SNMP discovery — read-only design and MikroTik safety

**Status:** Design only. No SNMP transport, Worker, discovery API or credential vault is implemented. No real device has been contacted by this project.

## 1. Scope and safety boundary

The goal is to enrich an already registered switch asset with timestamped observations: vendor/model/system description, firmware where exposed, interface index/name, administrative and operational state, speed, VLAN membership and learned MAC-to-port associations where supported.

This is **not** a port scanner, subnet mapper, NAT helper or switch-configuration tool. Discovery targets only an explicitly registered device management IP selected by an authorized operator.

Hard prohibitions:

- No subnet sweep, address-range discovery, TCP connect scan, UDP port scan, port-range probing or arbitrary target/port supplied by the browser.
- No port mapping in the sense of probing open ports; no NAT, DST-NAT, port-forward or firewall changes.
- No SNMP SET or write-capable operation. Only GET, GETNEXT and bounded GETBULK.
- No automatic changes to MikroTik RouterOS firewall filters, PSD rules, address lists, SNMP service settings or management services.
- No automatic unblock, alternate-port probing or aggressive retry loop if a router appears to block the management source IP.
- No plaintext SNMP community string or SNMPv3 authentication/privacy secret in asset fields, logs, browser payloads or general API responses.

## 2. MikroTik-specific protection

Some MikroTik deployments use firewall rules or PSD/port-scan detection that can add a source address to a dynamic block list. The exact behavior depends on the site's RouterOS rules and their order; the application must not assume every timeout means an IP ban.

Required behavior:

1. The operator selects one existing MikroTik asset and starts a manual discovery run.
2. The worker sends SNMP only to that asset's configured management IP and configured SNMP port (default UDP/161).
3. SNMPv3 authPriv is preferred. SNMPv2c is available only as an explicit administrator-configured, read-only fallback. No credential guessing.
4. Limit each target to one active SNMP session. Use bounded GETBULK responses and conservative configurable timeouts. Initial retry policy: at most one delayed retry for a transient timeout, then stop that target for the run. Numeric defaults require hardware lab validation.
5. If the target is unresponsive or filtering/blocking is suspected, stop all requests to that target for the current run and open a per-target circuit breaker. Do not try other ports, other protocols or repeated credentials.
6. Report a neutral state such as `NO_RESPONSE` or `FILTERED_OR_BLOCKED`. Report `BLOCKED` only when independent RouterOS/firewall evidence confirms an address-list or filter action.
7. Require the network administrator to configure an allow rule for the management server source IP to the router's SNMP UDP/161 service, with rule order checked against PSD/drop rules. This is a deployment prerequisite, not an automated product action.

The application never changes the router's firewall and never attempts to remove the management IP from a MikroTik address list.

## 3. Protocol and OID strategy

- Prefer SNMPv3 authPriv with unique per-device credentials and explicit algorithms supported by the target.
- Support SNMPv2c only for a read-only community configured by an administrator. SNMPv1 is not a default option.
- Use standard MIBs first: SNMPv2-MIB for system identity; IF-MIB/ifXTable for ifIndex, interface description/name/alias, admin/oper state, speed and counters; BRIDGE-MIB/Q-BRIDGE-MIB for forwarding database and VLAN membership where exposed.
- Vendor-specific MikroTik/Cisco MIBs are optional adapters after standard MIB support; do not make the core data model depend on one vendor.
- Use GETBULK with a bounded max-repetitions value and strict response-size/OID-count limits. Reject malformed, out-of-scope and unexpected OID responses.
- IP-to-port mapping is best effort. A switch forwarding table commonly gives MAC-to-port; IP-to-MAC may require a separate router ARP table or another L3 source. Do not infer an IP-to-port relationship if the source data is unavailable.
- RouterOS API and SSH are not part of the first SNMP slice. They require separate explicit credentials, allowlists, host-key verification where applicable and review.

## 4. Scheduling and rate limits

Proposed initial limits, to be validated in a lab before release:

- One active session per device; no concurrent jobs against the same target.
- Small bounded GETBULK batches; never retrieve an unbounded subtree.
- Configurable request timeout and no more than one delayed retry per target per run.
- Configurable minimum interval between scheduled runs; proposed starting interval is five minutes per device, not a high-frequency poll.
- A per-target circuit breaker suppresses further requests after repeated failures and requires operator review or a cool-down before the next attempt.
- Global worker concurrency is separately bounded. Manual and scheduled jobs share the same per-target limiter.
- Cancellation must stop pending requests and prevent new requests from being issued.

These are conservative starting proposals, not measured guarantees for every router or firmware.

## 5. Data model and authority

Existing schema components on the M2 branch:

- `DiscoveryRun`: branch, optional target asset, initiator, source, status, timestamps, counters and sanitized error fields.
- `SwitchProfile`: system identity, firmware, reported port count and latest discovery status/time.
- `SwitchPort`: stable per-switch ifIndex and operator-maintained alias, description, configured VLANs and connected-device label.
- `PortObservation`: append-only timestamped state, VLAN, IP/MAC, speed and source provenance.

Discovery writes observations; it must never overwrite operator-maintained port metadata. Failed or partial discovery must not delete assets or ports. Do not place credentials in rawMetadata. Before production, review whether run records need explicit policy version, attempt number, rate-limit outcome and transport error classification.

## 6. Prerequisites and implementation order

The current repository has no Background Worker implementation or credential vault. The existing DiscoveryRun model is not a functioning job queue. Implement in this order:

1. Durable PostgreSQL job queue/Worker with lease ownership, expiry, bounded retry, idempotency, cancellation, audit and crash recovery.
2. Credential vault with envelope encryption, Windows DPAPI-protected key material, strict service identity/ACL, rotation, backup and restore/recovery tests. The browser receives only opaque credential references.
3. Branch-scoped discovery API that accepts an existing asset ID and an approved profile, not arbitrary IP ranges, ports or raw OIDs.
4. SNMPv3 read-only transport and schema validation, with strict target allowlisting and per-device rate limits.
5. SNMPv2c explicit read-only compatibility where necessary.
6. Unit tests, protocol simulator tests, firewall/rate-limit tests, then controlled Cisco/MikroTik hardware tests on the exact model and RouterOS/firmware.
7. Only after acceptance, enable scheduled discovery and expose observations in the inventory UI.

## 7. Acceptance tests

- Verify only the selected asset IP and UDP/161 are contacted; no other host or port receives traffic.
- Assert SNMP SET, subnet sweep, port-range scan, NAT/firewall changes and automatic unblock are impossible through API and Worker.
- Simulate timeout, packet loss, rate limiting and blocked source behavior; verify bounded retry, circuit breaker, cancellation and sanitized reporting.
- Verify credentials are encrypted at rest, never returned by API and absent from logs, errors and audit metadata.
- Verify branch scope and roles at API and job execution time, not only when a job is queued.
- Verify partial discovery appends only valid observations and does not erase existing asset/port metadata.
- Test Cisco and MikroTik hardware with explicit administrator-approved firewall allowlisting; record model, firmware, RouterOS version and actual packet rate.

**Release gate:** until the Worker, vault, API, simulator tests and target hardware acceptance pass, the feature remains design-only and the UI must not claim live discovery.
