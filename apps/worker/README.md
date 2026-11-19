
# Background Worker

**Status: service foundation only; no task handlers are registered.**

The Worker is a separate process, as required by the approved five-service Windows architecture. It uses PostgreSQL-backed discovery-run leases and never claims a source unless a handler is explicitly registered. The current milestone intentionally registers no handlers, so queued discovery work remains untouched.

Implemented queue primitives:

- Atomic claim using `FOR UPDATE SKIP LOCKED`.
- Owner-bound lease and heartbeat renewal.
- Expired lease recovery.
- Bounded exponential retry and maximum-attempt handling.
- Owner-bound completion/failure and cancellation acknowledgement.
- Empty handler allow-list fails closed and cannot consume a queued run.

Not implemented in this milestone:

- SNMP/SSH/Agent/ISAPI handlers.
- Credential vault or secret retrieval.
- API endpoints to enqueue/cancel discovery runs.
- Windows service installation, supervision and readiness integration.
- Live device communication.

Do not deploy this process as a production discovery service until handler registration, queue integration tests, credential controls and Windows service tests are complete. No network device is contacted by this Worker.
