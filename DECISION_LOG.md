# Decision log

Historical proposals are retained for context. The owner-approved decisions in the final section override earlier conflicting proposals. Implementation details remain subject to technical validation.

1. Separate persistent Node API/WebSocket/worker services and Next frontend on Windows, versus serverless/custom monolith. Benefit: durable work and clear ownership; cost: service supervision and packaged runtime complexity.
2. PostgreSQL durable jobs rather than in-memory queue or new broker. Benefit: fewer services and transactions; cost: lock/lease and scale testing.
3. Dedicated bundled PostgreSQL vs shared database: self-contained install and isolation vs ongoing data/backup/major upgrade ownership. External instance is optional future work.
4. WiX Burn/MSI candidate vs Inno Setup/MSIX: Windows install/upgrade model vs tool complexity; defer final choice to Windows prototype and legal/dependency validation.
5. Native operator-session bridge for RDP/VNC/vendor applications vs mandatory Linux Guacamole: avoids extra always-on platform; embedded browser and secure credential handoff remain unproven. Optional Guacamole requires separate Linux deployment.
6. DPAPI-wrapped AES key vs plaintext or external KMS: reasonable Windows local deployment, but machine-bound key recovery must be explicitly solved.
7. .NET 10 LTS self-contained Windows agent vs framework-dependent runtime: no separate runtime prerequisite; larger payload and patch obligations.
8. Per-commit version reservations, dispatch and release manifest vs automated version commits: avoids recursion and ties artifacts to source; relies on robust allocator, push reconciliation and policy. Multi-commit pushes and channel reuse present unresolved guarantees.
9. Expand/contract database changes with backup/restore vs destructive migrations or automatic downgrade: safer and auditable, but rollback may lose post-backup writes and needs operational coordination.
10. Historical proposal: date/folder nested package path. **Superseded** by the owner-approved date-only destination in the final decisions below.

References: Next standalone https://nextjs.org/docs/app/api-reference/config/next-config-js/output ; Microsoft .NET support https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core ; GitHub event docs https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#push ; GitHub release API https://docs.github.com/en/rest/releases/releases ; Guacamole https://guacamole.apache.org/doc/gug/guacamole-architecture.html ; PostgreSQL Windows https://www.postgresql.org/download/windows/ . None of these substitutes for testing the target machine.

## Revision after architecture review — 2026-11-18
11. Five separate SCM services (PostgreSQL, edge, Next, API and worker) are owner-approved and required; consolidation is not permitted. Validate exact service host, order, liveness/readiness and shutdown on actual Windows. API hosts persistent SSH sessions; worker handles queued work. TLS/mTLS identity forwarding has not been selected or validated.
12. Prefer a managed browser extension/native-messaging bridge plus authenticated user-scoped IPC over network loopback; demands browser deployment and proof of origin, bootstrap and replay controls. No generic process runner, no untested credential handoff.
13. Recommend agent-generated asymmetric keys and one-time bound enrollment tickets, pending secure bootstrap and target tests; a stolen ticket can impersonate the target and attestation remains unresolved.
14. Retain earlier WiX/MSI candidacy and dedicated PostgreSQL; final selections require offline Windows proof of concept, licensing, recoverable key management and failure testing. Never silently delete user data.
15. Recommend a durable commit-intake ledger and independent isolated run for each eligible commit, atomic version reservations and draft-before-publish; the exact non-lossy allocation/backfill substrate and branch attribution are unresolved, not a proven GitHub-only guarantee.
16. ISAPI only for registered NVRs; no subnet scanning by default and do not mark cameras removed after partial/failed sync. All model/firmware behavior remains unverified.

## Owner-approved decisions — 18 November 2026
These decisions are authoritative and do not require renewed owner selection; implementation details and evidence remain unverified.
1. **Separate Windows services:** five independently supervised TLS Edge, Next.js, API/WebSocket, Worker and dedicated PostgreSQL services; do not consolidate. Requires Windows readiness, account and recovery PoC.
2. **Date-only package destination:** `C:\Source\Package\<YYYY-MM-DD>\`; Package Folder Name is metadata, not a nested directory. Persist and reuse exact path. Supersedes historical nested-path proposal.
3. **One-time bootstrap exception:** initial validation/documentation commits need not publish a functional installer before a genuinely installable application exists; transition on first independently Windows-tested installable runnable release. No fake installer; full per-commit policy thereafter.
4. **Central Update Proxy:** separate server-side protected GitHub App or justified identity; installed applications and browsers contain no reusable GitHub repository secrets. Authentication, authorization, cache, audit, channel and authenticity requirements remain subject to implementation/testing.
5. **Desktop Bridge PoC:** bounded isolated practical security PoC, separately authorized before execution; not production bridge approval.
6. **Tiered testing:** Tier 1 every commit; Tier 2 Windows VM installer/service testing; Tier 3 relevant real hardware on integration changes and before compatibility claims. Unrelated changes are not blocked by absent hardware.

## Decision details — OWNER APPROVED — 2026-11-18
The following expand the six approved decisions without changing them. Every implementation status is **Not implemented / not verified**.

### 1. Separate Windows services
- **Decision:** Independently supervise TLS Edge, Next.js Web, API/WebSocket, Background Worker and dedicated PostgreSQL; do not consolidate.
- **Reasoning:** Failure isolation, durable connections/jobs and constrained service responsibilities.
- **Consequences:** Five service identities, startup/readiness coordination, supervision, logging and lifecycle operations.
- **Related:** [Architecture](ARCHITECTURE.md), [Deployment](DEPLOYMENT_WORKFLOWS.md), [Security](SECURITY_POLICY.md).
- **Validation required:** Real Windows account permissions, port isolation, mTLS forwarding, readiness, restart and rollback. **Status:** Designed; not implemented/tested.

### 2. Date-only package destination
- **Decision:** `C:\Source\Package\<YYYY-MM-DD>\` only; Package Folder Name is metadata, never a nested directory. Store the exact target path in the Deployment Job and reuse it.
- **Reasoning:** Resolves the originally inconsistent path requirements with one owner-selected rule.
- **Consequences:** Same-day filename conflicts must fail safely; preserve approval and Store Commerce transaction safeguards.
- **Related:** [Deployment](DEPLOYMENT_WORKFLOWS.md), [Database](DATABASE_DESIGN.md).
- **Validation required:** Actual checkout file transfer, hashes, retries, locking and installer path. **Status:** Designed; not implemented/tested.

### 3. One-time installer bootstrap exception
- **Decision:** Initial bootstrap commits may run validation without publishing a functioning installer. End the exception at the first genuine installable/runnable application commit after independent clean Windows installation and operational validation; thereafter every eligible commit follows full release gates.
- **Reasoning:** An installable application cannot exist before implementation.
- **Consequences:** No fake release or installer; failed mandatory gates cannot publish success.
- **Related:** [Versioning](VERSIONING_POLICY.md), [Release process](RELEASE_PROCESS.md), [Testing](TESTING_STRATEGY.md).
- **Validation required:** Offline clean Windows install, operation, upgrade/rollback, release gating. **Status:** Policy designed; not implemented/tested.

### 4. Central Update Proxy
- **Decision:** A central proxy accesses private releases using a protected server-side GitHub App or justified identity; installed clients never contain reusable repository secrets.
- **Reasoning:** Protect private repository credentials while distributing authorized releases.
- **Consequences:** Additional separately hosted service, installation identity, authorization, audited cache and operational ownership. SHA-256 alone is not publisher authenticity.
- **Related:** [Security](SECURITY_POLICY.md), [Architecture](ARCHITECTURE.md), [API](API_DOCUMENTATION.md), [Deployment](DEPLOYMENT_WORKFLOWS.md).
- **Validation required:** Identity provisioning, authorization, fixed asset allowlists, cache revocation, availability and signing. **Status:** Designed; not implemented/tested.

### 5. Desktop Bridge PoC
- **Decision:** Prepare a bounded isolated security-focused PoC; execute only with separate authorization. No production Bridge work in Phase 2.
- **Reasoning:** Browser-to-native launches and safe credential handoff cannot be assumed.
- **Consequences:** PoC must evaluate actual supported applications, pairing, origins, replay, user isolation and restricted launch.
- **Related:** [Bridge PoC](DESKTOP_BRIDGE_POC.md), [Security](SECURITY_POLICY.md), [Architecture](ARCHITECTURE.md).
- **Validation required:** Run the separately authorized PoC on controlled Windows/browser/vendor versions. **Status:** Planned; not executed.

### 6. Tiered testing
- **Decision:** Tier 1 every commit, Tier 2 Windows VMs, Tier 3 real target/hardware testing for relevant integrations and compatibility claims.
- **Reasoning:** Preserve useful feedback for unrelated changes without inventing hardware compatibility.
- **Consequences:** Missing hardware leaves relevant capabilities unverified but does not block unrelated UI or documentation work; missing mandatory release gates prevents successful publication.
- **Related:** [Testing strategy](TESTING_STRATEGY.md), [Release process](RELEASE_PROCESS.md).
- **Validation required:** Implement and exercise all tiers with recorded evidence. **Status:** Designed; not implemented/tested.
## Owner-approved decision — 19 November 2026 (repository custody)

This section records a decision made by the owner. It concerns repository custody, not architecture: it does not add to, modify or supersede any of the six owner-approved architectural decisions dated 2026-11-18, which remain authoritative and unchanged. No architectural decision is made here on the owner's behalf.

### Deletion of the temporary public documentation mirror; sole authoritative repository
- **Decision (owner-confirmed, 2026-11-19):** the temporary public documentation mirror `aliajeli/testing` has been **permanently deleted** by the owner. The primary private repository `aliajeli/enterprise-it-infrastructure-management-platform` is the **sole authoritative project repository** for all project documentation, decisions, source code, releases and history.
- **Reasoning:** the mirror's purpose (pre-transfer independent review) ended when the documentation package was transferred to and verified in the primary repository. Its continued public availability exposed the complete internal design and operational documentation set — including full Git history and a published bundle of private review-branch history — with no remaining review benefit. See [PHASE2_REVIEW_2026-11-19.md](PHASE2_REVIEW_2026-11-19.md), finding F-09 and Appendix A.
- **Consequences:** one authoritative location for documentation and decisions; review artifacts are henceforth transferred only by git-native push to the private primary repository, never via public mirrors, bundles or archives. Historical statements describing the mirror as intentionally public are superseded by this decision (listed below). Historical reports remain unchanged; maintained operational wrappers may be explicitly reconciled without rewriting their archived evidence.
- **Explicitly not implied by the deletion:** deletion does **not** recall, invalidate or remove any copy that was cloned, downloaded, crawled, indexed, forked or otherwise captured while the repository was public (public from 2026-11-19T03:54:58Z until deletion). Content already taken must continue to be treated as potentially held by third parties.
- **Not claimed and not verified:** no GitHub Support cache purge has been performed or verified, and none is claimed here; no offline archival copy is claimed to have been created, and whether the owner holds one is **Not verified**. Read-only verification of the deletion (HTTP 404 both anonymously and with the owner token; absent from the owner's authenticated repository list, which does include private repositories) is recorded as evidence E-21 in [PHASE2_REVIEW_2026-11-19.md](PHASE2_REVIEW_2026-11-19.md).
- **Archival continuity:** the owner-supplied master prompt remains preserved byte-exactly inside the primary repository's `GUIDELINE.md` (archival-region SHA-256 `38634f573b0391402a1b58ad927d133fa0ad2ca6551c8ea66180daddd3e24b16`), repaired in PR #1 and cross-verified against the mirror's historical ZIP copy before deletion; that public copy is no longer reachable. **Post-merge reconciliation, 2026-11-19 (R1):** GitHub independently confirms PR #1 merged at `2026-11-19T07:58:59Z` with squash commit `eb8b704f945ca4c5199d97a6a8c4bd286068cfbb`, now verified as remote `main`. The repaired bytes are therefore on `main`, not pending merge.
- **Follow-up still required (unchanged by this decision):** harden the operational surface described in the documentation — management-plane access restrictions, vendor management interfaces, remote-access settings, credential hygiene and confirmation that the previously exposed token remains revoked — per [NETWORK_REQUIREMENTS.md](NETWORK_REQUIREMENTS.md) and [SECURITY_POLICY.md](SECURITY_POLICY.md).
- **Related:** [HANDOVER.md](HANDOVER.md), [TRANSFER_STATUS.md](TRANSFER_STATUS.md), [PHASE2_REVIEW_2026-11-19.md](PHASE2_REVIEW_2026-11-19.md) (F-09, Q-03 resolved, Appendix A), [DOCUMENTATION_REVIEW_REPORT.md](DOCUMENTATION_REVIEW_REPORT.md) (historical).
- **Status:** owner decision recorded 2026-11-19; the deletion itself was executed by the owner outside this repository. No repository settings, visibility, branch protection, webhook, workflow, hook or Git history was modified by this documentation-only change.

### Historical statements superseded by this decision
The following historical statements state or imply that the temporary mirror is intentionally public, or that its contents remain published. This decision supersedes them with respect to mirror status. R1 reconciliation (2026-11-19) corrects the maintained SECURITY_POLICY.md and GUIDELINE.md wrappers and adds a dated TRANSFER_STATUS.md note; historical reports and archived prompt bytes remain unchanged:
- [SECURITY_POLICY.md](SECURITY_POLICY.md) — "The separate documentation review mirror is intentionally public." Retained as a labeled historical quotation, not current policy.
- [GUIDELINE.md](GUIDELINE.md) — maintained wrapper, former "Public documentation mirror note": "The separate public review mirror stores current documentation at its repository root." Superseded by the primary-repository custody decision and corrected in the maintained wrapper only; the immutable archival region (lines 6–1544) is untouched.
- [TRANSFER_STATUS.md](TRANSFER_STATUS.md) — "This transfer does not certify that every historical copy in the temporary public mirror or its Git history has been sanitized."
- [HANDOVER.md](HANDOVER.md) — pre-transfer historical sections describing the mirror (retained verbatim; the current snapshot section at the top records the deletion).
- [DOCUMENTATION_REVIEW_REPORT.md](DOCUMENTATION_REVIEW_REPORT.md), [FINAL_HANDOVER_REPORT.md](FINAL_HANDOVER_REPORT.md) — mirror-era review records.


## Owner-approved role/action matrix — 19 November 2026

The owner explicitly approved the following distinction between ADMIN, OPERATOR and VIEWER. This decision governs all future inventory, switch, device, monitoring, remote-session, credential and deployment modules.

- **ADMIN:** global branch scope; user, branch, permission and settings administration; all declared platform actions. Store Commerce force-close still requires explicit per-operation approval and a warning; role membership alone is not approval.
- **OPERATOR:** only within actively assigned branches; may read/write inventory records and switch-port/VLAN metadata and run non-destructive discovery and synchronization. Denied by default: live device configuration changes, remote sessions, stored credential use, deployment creation/execution, Store Commerce force-close, user/branch/settings administration.
- **VIEWER:** only within actively assigned branches; read-only inventory and switch-port/VLAN metadata. No mutations or operational actions.
- **Enforcement:** authorization must be checked server-side for every HTTP request, WebSocket event and durable job handler. Branch-owned operations require both the action capability and an active, non-revoked grant on an active branch. Client-side hiding is not security.
- **Implementation boundary:** the closed action policy and unit tests may be implemented in M1. Operational endpoints and modules remain unimplemented until their own milestones; this decision does not claim those features exist.
- **Status:** owner-approved; policy implementation and unit tests are being added to PR #6. No PR merge or repository settings change is authorized by this decision.
