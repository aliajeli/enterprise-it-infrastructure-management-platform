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

## Unreleased — 2026-11-18
- Drafted architecture, security, database, deployment, testing and release design documentation.
- Recorded repository visibility evidence and outstanding validation gaps.
- No application features, migrations, installer, releases or tests implemented.
- Expanded the proposed Windows service topology, bridge security, Agent identity/deployment, monitoring, CCTV, installation, data relationships, and per-commit release design after architecture review. No compatibility tests performed.
- Recorded owner-approved service, package-path, bootstrap, update-proxy, bridge-PoC and tiered-testing decisions; updated related design and planned API documentation. No implementation or compatibility validation.
- Archived the owner-supplied master prompt verbatim and verified the embedded bytes against the source file.
- Prepared a public documentation-mirror review snapshot; the initial package and subsequent corrections were published in earlier mirror commits. The local independent-review branch was not verified on GitHub.
- Prepared a local root-level owner-review package; reconciled handover, release-policy proposal wording, archival line endings and checksums. No GitHub operation or Phase 3 work performed during this milestone.
