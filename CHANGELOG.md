# Changelog

## 2026-11-19 — primary-repository review, archival repair and status refresh
- Performed a comprehensive Phase 2 architecture and documentation consistency review of the transferred primary-repository baseline (22-commit history, `main` at `f606762`); findings, evidence and owner questions recorded in `PHASE2_REVIEW_2026-11-19.md`.
- Repaired `GUIDELINE.md`: restored the 1536 original CRLF line-ending bytes of the archived master prompt that were normalized to LF during the repository transfer. The embedded prompt again matches the recorded source SHA-256 (`38634f57…`) and the file again matches its package-manifest SHA-256 (`2a14f841…`, 55234 bytes). No prompt content or wrapper text changed.
- Completed the `README.md` documentation index (changelog, Desktop Bridge PoC specification, historical review and handover reports, manifest, checksums, current review report).
- Added a current primary-repository snapshot section to `HANDOVER.md` and labeled the pre-transfer "Current package" wording as historical; no historical text removed.
- Recomputed `FINAL_FILE_MANIFEST.md` and `SHA256SUMS.txt` against the post-repair tree as directed by `TRANSFER_STATUS.md`; both now also cover `TRANSFER_STATUS.md` and the new review report. Pre-repair values remain in commit `f606762`.
- Verified: repository private; zero releases, tags and workflows; all relative Markdown links resolve; `sha256sum -c SHA256SUMS.txt` passes for every listed file; limited secret-pattern scan found no credential-like values.
- No application implementation, migrations, installers, releases, workflow changes, repository settings changes or PoC execution. Phase 3 remains not started.

### Corrections and additions — same day, owner-authorized
- Corrected the per-file transfer commit count (20 → 19) and the `f606762` UTC timestamp (07:09:03Z → 06:39:03Z) in `PHASE2_REVIEW_2026-11-19.md` and the `HANDOVER.md` snapshot.
- Restored the historical `**Current package:**` label in `HANDOVER.md` byte-for-byte (owner-selected option B); the historical/superseded qualifier now sits on a separate preceding line, so all pre-transfer text is retained 100% verbatim.
- Extended the review report with Appendix A (public-mirror exposure assessment: two post-review mirror commits, aggregated package tree, published Git bundle of private review-branch history; zero credential-pattern matches across 413 scanned records; containment recommendations) and Appendix B (recommended `GUIDELINE.md` byte-preservation strategy: `.gitattributes` `-text` plus archival-region SHA-256 validation — proposal documented, not implemented), with new evidence E-15…E-20.
- Recomputed `FINAL_FILE_MANIFEST.md` and `SHA256SUMS.txt` a second time after these corrections; `sha256sum -c` passes for all 21 entries.
- Documentation only: no settings, visibility, hook, workflow or Git-history changes; the pull request remains open and unmerged; Phase 3 remains not started.

### Owner decision recorded — same day, owner-authorized documentation update
- Recorded the owner-approved decision of 2026-11-19 in `DECISION_LOG.md`: the temporary public documentation mirror `aliajeli/testing` has been **permanently deleted by the owner**, and the primary private repository `aliajeli/enterprise-it-infrastructure-management-platform` is the **sole authoritative project repository**. The change is purely additive — the six owner-approved architectural decisions of 2026-11-18 are unchanged.
- Explicitly recorded in the decision entry: deletion does **not** recall content already cloned, downloaded, crawled, indexed or cached while the mirror was public; no GitHub Support cache purge is claimed or verified; no offline archival copy is claimed to have been created (**Not verified**). The decision entry also lists the point-in-time statements in other documents that it supersedes.
- `PHASE2_REVIEW_2026-11-19.md`: Q-03 closed as **RESOLVED by owner decision**; F-09 and S-1 updated; §7 deferred list and §9 P1 list annotated; Appendix A extended with "Current state" and "Outcome of the owner decision" subsections and temporal framing that separates the verified historical public exposure (retained as history) from the post-deletion state; new evidence E-21 (read-only deletion verification).
- `HANDOVER.md`: snapshot rows updated for consistency (new "Sole authoritative repository" row; next-action question list). All historical pre-transfer text remains byte-for-byte verbatim.
- `FINAL_FILE_MANIFEST.md` and `SHA256SUMS.txt` recomputed a third time, after all other changes; `sha256sum -c` passes for all 21 entries.
- Documentation only: no settings, visibility, branch protection, webhook, workflow, hook or Git-history changes; no branches created or deleted; the pull request remains open and unmerged; `main` unchanged; Phase 3 remains not started.

## Unreleased — 2026-11-18
- Drafted architecture, security, database, deployment, testing and release design documentation.
- Recorded repository visibility evidence and outstanding validation gaps.
- No application features, migrations, installer, releases or tests implemented.
- Expanded the proposed Windows service topology, bridge security, Agent identity/deployment, monitoring, CCTV, installation, data relationships, and per-commit release design after architecture review. No compatibility tests performed.
- Recorded owner-approved service, package-path, bootstrap, update-proxy, bridge-PoC and tiered-testing decisions; updated related design and planned API documentation. No implementation or compatibility validation.
- Archived the owner-supplied master prompt verbatim and verified the embedded bytes against the source file.
- Prepared a public documentation-mirror review snapshot; the initial package and subsequent corrections were published in earlier mirror commits. The local independent-review branch was not verified on GitHub.
- Prepared a local root-level owner-review package; reconciled handover, release-policy proposal wording, archival line endings and checksums. No GitHub operation or Phase 3 work performed during this milestone.

## 2026-11-19 — successful PR #1 squash merge and post-merge reconciliation (R1)
- **Independently verified:** GitHub PR metadata reports [PR #1](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/1) **MERGED** at `2026-11-19T07:58:59Z`; its merge commit is `eb8b704f945ca4c5199d97a6a8c4bd286068cfbb`. GitHub commit metadata shows one parent (`f60676205bcf9ff7f5608f0e3b3074a76bdb3776`) and the squashed review changes. Remote `main` resolves to that SHA. Earlier entries describing PR #1 as open/unmerged are preserved as historical records.
- **Independently verified:** authenticated repository metadata reports private visibility; the remote main tree is untruncated and contains 22 root files. There are zero releases, tags and workflows at reconciliation time.
- **Owner-reported versus independently observed:** the owner confirmed deletion of `aliajeli/testing` on 2026-11-19. The prior independent unavailability checks (404 anonymously/authenticated and absence from the authenticated repository list) remain recorded as review evidence E-21; R1 does not claim to have witnessed the deletion. Deletion does not prove prior copies, clones, downloads or caches were recalled. Token revocation remains owner-reported, not independently reverified.
- Reconciled current SECURITY_POLICY.md repository/exposure wording, the GUIDELINE.md maintained repository-location wrapper, DECISION_LOG.md custody/supersession status and HANDOVER.md operational snapshot; appended a dated supersession note to TRANSFER_STATUS.md. Historical review reports, earlier changelog entries and pre-transfer handover records remain unchanged.
- Preserved GUIDELINE.md immutable lines 6–1544 byte-for-byte and the source archive invariant (39181 bytes; SHA-256 `38634f573b0391402a1b58ad927d133fa0ad2ca6551c8ea66180daddd3e24b16`). All six owner-approved architectural decisions and their detailed elaborations remain unchanged. Recomputed FINAL_FILE_MANIFEST.md, then SHA256SUMS.txt last; integrity results accompany the R1 PR.
- Documentation only: no application code, migrations, installers, workflows, settings, permissions, hooks, webhooks, branch protection or remote-branch deletion. No `.gitattributes` or Appendix B implementation (Q-02 undecided); Q-07 remains an owner decision. Phase 2 remains active; Phase 3 was not started and the Desktop Bridge PoC was not executed. Submit R1 for owner review; do not merge it.

### PR #2 review corrections — 2026-11-19
- Clarified archival measurement scopes in HANDOVER.md using exact baseline/PR-head Git blobs and a reproducible byte-comparison procedure: complete protected lines 6–1544 are 39,295 bytes; the embedded original prompt alone is 39,181 bytes. The earlier audit's assignment of 39,181 bytes to the complete line range was a scope-labeling error. The 114-byte difference consists of two marker lines and one separator LF, not altered source bytes. GUIDELINE.md is unchanged by this follow-up.
- Replaced HANDOVER.md's temporary session-branch entry with PR #2 as the dated owner-review item, recorded the head SHA observed when preparing the snapshot, and required live GitHub PR/main verification before action. A snapshot cannot embed its own future commit SHA; the updated head is reported in PR #2 and Git history. Historical sections and all six architectural decisions remain unchanged.
- Recomputed the manifest and then checksums last; repeated archival, decision-preservation, historical-record, checksum and relative-link checks. Documentation only; Phase 3 not started, Desktop Bridge PoC not executed, Q-02 not implemented, and PR #2 not merged.

## 2026-11-19 — Phase 3 authorized; initial platform foundation
- Owner explicitly authorized Phase 3 implementation.
- Added the initial Next.js App Router web workspace using strict TypeScript and Tailwind CSS.
- Added a responsive infrastructure overview shell with truthful empty states; no simulated inventory, monitoring or service health.
- Added the Phase 3 milestone plan, refreshed the repository landing page and changelog, and added a current Phase 3 operational snapshot to HANDOVER.md.
- Selected Node.js 26 Active LTS, Next.js 16.4.6, PostgreSQL 18 and Prisma ORM 7 GA as the initial compatibility baseline; exact dependency installation and clean-runner verification remain pending.
- No API, database migration, Windows service, Agent, Desktop Bridge, installer, release workflow or production integration is claimed as implemented.
- No repository settings, branch protection, hooks, webhooks or permissions were changed.

## 2026-11-19 — M0 quality-gate scaffolding
- Added an explicit ESLint CLI gate using the official Next.js 16 Core Web Vitals and TypeScript flat configurations.
- Added root and web-workspace lint scripts and documented the local validation sequence.
- Added a Node.js 26 runtime selector file.
- Dependency installation, lockfile generation and execution of lint/typecheck/build remain pending a network-enabled Node.js 26 runner.
- Added a native, keyboard-accessible mobile navigation disclosure menu and made the active Overview item a real navigation link.

## 2026-11-19 — M0 validation and dependency lockfile bootstrap
- Added a Node.js 26 GitHub Actions validation workflow covering dependency installation, dependency-tree verification, ESLint, TypeScript and production build.
- Added a safe lockfile bootstrap job: dependency lifecycle scripts are disabled while generating the lockfile, and the workflow commits only the lockfile to the active feature branch.
- Committed the generated npm v3 lockfile using Node.js 26.13.1/npm 11.20.0.
- The first lint run found two internal anchor elements; both were replaced with Next.js Link components.
- GitHub Actions run 44490452757 passed dependency installation, dependency-tree verification, lint, typecheck and production build for the application source. That run preceded the lockfile commit; a fresh npm ci run against the committed lockfile is still required.

## 2026-11-19 — M0 unit and dependency-security gates
- Added Vitest 5.1.1 and server-rendered dashboard smoke tests covering truthful empty states and navigation semantics.
- Added a high-severity threshold npm dependency audit to the GitHub Actions validation workflow.
- Optimized lockfile bootstrap to skip registry resolution once the lockfile is already tracked.
- The committed-lockfile CI run passed npm ci, dependency-tree verification, ESLint, TypeScript and production build; the expanded test and audit gates are now being validated.
- Refreshed and committed the npm lockfile after adding Vitest 5.1.1; the first npm ci attempt correctly detected the stale lockfile and failed closed. A new clean-runner validation is required against the refreshed lockfile.

## 2026-11-19 — M0 completed
- Completed M0 on Node.js 26.13.1/npm 11.20.0 with a committed npm v3 lockfile and a clean `npm ci` install.
- GitHub Actions run 44491419345 passed dependency-tree verification, `npm audit --audit-level=high` (0 vulnerabilities), ESLint, TypeScript, Vitest (2 tests) and production build.
- M0 acceptance criteria are met. M1 identity, access control and persistence is the next milestone; no production integration is claimed.

## 2026-11-19 — M1 Prisma security patch update
- Dependency audit found high-severity advisories in Prisma 7.9.1 transitive dependencies (deepmerge-ts and mysql2).
- Updated the pinned Prisma 7 packages to 7.10.1, a patch release that updates dependencies with security advisories. Prisma 8 remains a release candidate and is not adopted.
- Prisma 7.10.1 migration/schema validation and the refreshed lockfile must pass the complete CI gate before the M1 branch is considered validated.
- Bound API proxy trust to loopback peers so rate limiting and audit IP attribution can use the reverse proxy's forwarded client IP. Documented that the edge proxy must overwrite X-Forwarded-For.
- Added a disposable-PostgreSQL integration test for branch-grant partial uniqueness and append-only audit enforcement, plus a Windows runner smoke gate for the native Argon2id binding and API build.
- Added an interactive, one-time administrator bootstrap CLI protected by a PostgreSQL advisory lock; it refuses to create an account if any user already exists and never accepts passwords in command-line arguments.
- Added server-side branch-scope and administrator capability primitives. Operational permission mutations remain disabled pending owner approval of the exact role/action matrix.
- Added a browser sign-in form, session-gated dashboard shell and logout control. The UI uses same-origin API routes and HttpOnly cookies; no session token is stored in browser storage.
