# Project handover

## Current snapshot — M1 lifecycle completion (2026-11-19)

**Snapshot observed:** 2026-11-19, development branch `phase3/m1-completion` at `4f99330ffe5d61c862c196bfa2b0d6e6c59dddb7`. This is a development handover, not a production-readiness assertion.

| Item | Verified state |
|---|---|
| Authoritative repository | `aliajeli/enterprise-it-infrastructure-management-platform` — Private |
| Default branch | `main` at `b7dc102bc7293817d10022176ac7fe5627d015ca` at last verified baseline |
| M0 | Complete and merged — PR #3 |
| M1 identity foundation | Merged — PR #4 |
| M1 user/branch administration | Implemented on PR #5 branch; PR #5 remains Draft/open/unmerged |
| M1 completion work | [PR #6](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/6), Draft/open/unmerged, based on PR #5; branch lifecycle and administrator password recovery added |
| Branch lifecycle | Edit with optimistic version; soft archive; restore; audit events; archive revokes grants and restore does not reinstate them |
| Password recovery | ADMIN-issued one-time temporary password for active non-admin users; no-store response, forced change, session revocation, auth epoch increment and audit |
| CI for completion work | [Run 44516741144](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44516741144) **passed** on exact head `d1ed6d209a33e9923a376c7769bbc2491fcfaa68` in [run 44517063564](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44517063564): platform validation, Windows API runtime smoke, lockfile bootstrap, PostgreSQL integration, disposable backup/restore smoke, lint, typecheck and production build all succeeded. Earlier intermediate runs were cancelled or failed during backup-smoke development and are not treated as successful evidence |
| M1 remaining acceptance gates | Owner-confirmed OPERATOR/VIEWER action matrix; clean target-Windows validation of service identities/ACL/startup/API integration; production PostgreSQL encrypted backup/restore and key-recovery evidence; final code review and green CI |
| Not implemented | Five Windows services, Background Worker, Windows Agent, monitoring, switch/NVR integrations, Desktop Bridge PoC, Store Commerce deployment, installer, updater and release automation |
| Security boundaries | All user/branch management routes remain ADMIN-only. OPERATOR/VIEWER operational mutation rights are not enabled. No ADMIN creation/promotion via API |
| Repository administration | No repository settings, branch protections, permissions, hooks, webhooks or workflow administration settings changed |
| Desktop Bridge | PoC not executed; separate authorization remains required |
| Release/production | No installer, tag, release or production deployment claimed |

### M1 completion implementation details

- Branch edits require the current version and return conflict on stale writes.
- Archiving is transactional: mark inactive/deleted, revoke active branch grants, and append audit event.
- Restore makes the branch active but intentionally leaves old grants revoked; an administrator must reassign access.
- Password reset is deliberately admin-mediated because no verified email/SMS recovery channel exists. Self-service recovery is not exposed.
- PostgreSQL integration tests passed for these paths on run 44516741144. The custom-format PostgreSQL backup/restore smoke test also passed on that run. The explicit PostgreSQL host was added to `pg_restore` after the initial backup-smoke failure; the corrected backup/restore smoke passed on run 44517063564.

### Owner decision still required

The only product-policy decision that cannot safely be inferred from code is the operational distinction between OPERATOR and VIEWER. Until confirmed, both remain read-only for infrastructure resources. The conservative role model is documented in `M1_USER_MANAGEMENT_DESIGN.md`.

### Next actions

1. Wait for the final branch-head CI run and fix any failures.
2. Open a follow-up Draft PR targeting `phase3/m1-user-management`; keep PR #5 and the follow-up unmerged until owner review.
3. Collect Windows service and PostgreSQL backup/restore evidence in the intended environment.
4. Confirm the OPERATOR/VIEWER action matrix before enabling operational actions.
5. Only after M1 acceptance, start M2 inventory and switch-port management.

---

## Historical snapshot — M0 foundation (2026-11-19)



**Snapshot observed:** 2026-11-19T08:54:00Z (UTC). This section supersedes the earlier Phase 2 snapshot below; historical evidence and decisions remain preserved.

| Item | Current verified state |
|---|---|
| Authoritative repository | `aliajeli/enterprise-it-infrastructure-management-platform` — Private |
| Default branch | `main` at `60b0e515896c6db1e3d3469f834866e76d0198ca` |
| Current phase | **Phase 3 — Implementation**, explicitly authorized by the owner on 2026-11-19 |
| Active development branch | `phase3/platform-foundation` |
| Current implementation commit | `65ae3036437923288b27914b06be84cf3cddeaaa` |
| Active pull request | [PR #3 — initial platform web foundation](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/3), open, draft, base `main`; not merged |
| First milestone | M0 — repository and application foundation, **completed 2026-11-19** |
| Implemented scope | Initial Next.js App Router workspace, strict TypeScript configuration, Tailwind CSS integration, responsive infrastructure overview shell with truthful empty states, Phase 3 plan, refreshed landing page/changelog, ESLint 9 flat configuration using the official Next.js 16 Core Web Vitals and TypeScript presets, root/workspace lint scripts, and `.nvmrc` Node 26 selector, native keyboard-accessible mobile navigation, a GitHub Actions validation workflow for Node.js 26, and a Vitest 5.1.1 dashboard smoke-test baseline and a high-severity npm dependency audit gate |
| Not implemented | Authentication, API, database schema/migrations, Windows services, worker, Agent, monitoring, NVR/switch integrations, Desktop Bridge, installer, updater and release automation |
| Dependency reproducibility | `package-lock.json` is committed (lockfileVersion 3), refreshed to include Vitest 5.1.1 using Node.js 26.13.1/npm 11.20.0. A clean `npm ci` validation against this refreshed lockfile passed |
| Validation | GitHub Actions run [44491419345](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/actions/runs/44491419345) passed all current gates on branch head `bd4eaf84`: `npm ci`, dependency-tree verification, `npm audit --audit-level=high` (0 vulnerabilities), ESLint, TypeScript, Vitest (1 file / 2 tests) and production build. The separate lockfile bootstrap job completed successfully. M0 acceptance criteria are met. PR remains draft and must not be merged/released until the committed-lockfile run passes |
| Execution environment limitation | Available execution environment reports Node.js 22.16.0/npm 10.9.2, below the selected Node.js 26 baseline; outbound DNS/network access is unavailable. GitHub-hosted runners successfully provision Node.js 26.13.1/npm 11.20.0. This limitation concerns the current assistant execution container, not the owner's workstation |
| Architectural constraints | All six owner-approved decisions in `DECISION_LOG.md` remain binding. Five independent Windows services remain required |
| Repository administration | No repository settings, branch protection, hooks, webhooks or permissions changed. Added a project-level CI validation workflow; no release workflow or production deployment workflow was added |
| Desktop Bridge | PoC not executed; it remains a separately authorized isolated task |

### Next actions

1. Merge the reviewed M0 foundation PR after confirming its current head and green CI status.
2. Begin M1 identity, access control and persistence on a new feature branch, starting with a threat-reviewed authentication/session design and Prisma schema/migration plan.
3. Keep production readiness and Windows installer claims blocked until the relevant M1–M8 acceptance criteria are independently validated.

---

## Historical snapshot — primary repository (2026-11-19, post-merge R1)

**Snapshot observed:** 2026-11-19T08:27:09Z (UTC). This is a dated record, not continuously current status. Before acting, verify live PR/main state from GitHub with `gh pr view 2 --json state,headRefOid,baseRefName,url` and `git ls-remote origin refs/heads/main`. The authoritative repository/default branch is the primary private repository's `main`; a temporary Arena session branch is only a PR source, not a replacement authoritative development branch.

This section is the operative handover snapshot for the primary private repository. The "Current package" paragraph and sections A–G below it were written **before** the transfer and describe the local `FINAL_UPLOAD` draft and the temporary public mirror; they are retained unchanged as history. Where they state that the package has not been transferred to the primary repository, [TRANSFER_STATUS.md](TRANSFER_STATUS.md) and this section supersede them: the transfer was completed and is recorded in commit `f60676205bcf9ff7f5608f0e3b3074a76bdb3776`.

| Item | Value (verified 2026-11-19 unless noted) |
|---|---|
| Repository | `aliajeli/enterprise-it-infrastructure-management-platform` — primary, private (GitHub API metadata `private: true`) |
| Sole authoritative repository | This primary private repository — owner-approved decision of 2026-11-19, recorded in [DECISION_LOG.md](DECISION_LOG.md). The temporary public documentation mirror https://github.com/aliajeli/testing was **permanently deleted by the owner** (owner-confirmed; independently checked read-only: HTTP 404 anonymously and with the owner token, and absent from the owner's authenticated repository list, which does include private repositories). Deletion does **not** recall content already cloned, downloaded, crawled, indexed or cached while the mirror was public, and no GitHub Support cache purge or offline archival copy is claimed or verified. Historical references to the mirror elsewhere in this file are retained verbatim as history |
| Default branch / latest commit on `main` | `main` / `eb8b704f945ca4c5199d97a6a8c4bd286068cfbb` — PR #1 squash merge (2026-11-19T07:58:59Z); independently verified via GitHub commit/PR metadata and `git ls-remote origin refs/heads/main` |
| PR #1 | **MERGED**, squash commit `eb8b704f945ca4c5199d97a6a8c4bd286068cfbb`, merged at `2026-11-19T07:58:59Z`; [PR #1](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/1). The review report's open/unmerged wording is historical |
| Historical transfer history | 22 commits at pre-merge review time (not the current post-merge count): root `c509d99` (README baseline, 06:37:26Z), 19 per-file transfer commits (06:37:51Z–06:38:36Z), `b6bd6d8` (README landing page — the commit referenced by TRANSFER_STATUS.md, 06:38:54Z), `f606762` (TRANSFER_STATUS.md, 06:39:03Z). Review clones may be shallow; unshallow before history verification |
| Current development phase | Phase 2 — Architecture, Design, Documentation and Technical Validation Planning. Phase 3 not authorized and not started |
| Current owner-review item | [PR #2](https://github.com/aliajeli/enterprise-it-infrastructure-management-platform/pull/2) — **OPEN, unmerged** at the snapshot observation; documentation-only R1 reconciliation against `main`. Do not merge it |
| PR #2 head observed at snapshot preparation | `2561d5052bce7875cbe27b2579a6ab6fedd1561c` — input to these review corrections, not a claim that it remains the live head. The commit containing this updated snapshot necessarily follows that SHA; obtain its exact SHA from live PR metadata/Git history rather than attempting a self-referential commit hash |
| Current application version | Not applicable — no application and no version metadata exist yet (bootstrap period per [DECISION_LOG.md](DECISION_LOG.md) decision 3). Version assignment for documentation-only commits is an open owner question (see [PHASE2_REVIEW_2026-11-19.md](PHASE2_REVIEW_2026-11-19.md) §8) |
| Latest stable / beta release, tags | None — zero releases, zero tags (verified via GitHub API) |
| Latest installer build | None — no installer, build system or application source exists |
| GitHub Actions / release pipeline status | Not configured — zero workflows (verified via GitHub API). None were created or modified during the review |
| Branch protection (`main`, future `beta`) | Historical review observation: protection settings unreadable (HTTP 403); `beta` absent at that review. Not reverified by R1; no protection enabled or settings changed. Q-07 remains an owner decision |
| Database migration status | None — no schema, migrations or database exist |
| Required environment / services / run-and-test commands | Not applicable — documentation-only repository |
| Documentation baseline and integrity | **22 tracked root files**, verified in the remote tree at `eb8b704` and the R1 working tree (historical transfer baseline: 21 at `f606762`). PR #1 delivered the GUIDELINE.md archival repair. R1 refreshes [FINAL_FILE_MANIFEST.md](FINAL_FILE_MANIFEST.md) (20 content entries) and [SHA256SUMS.txt](SHA256SUMS.txt) (21 entries including the manifest, excluding itself); verify with `sha256sum -c SHA256SUMS.txt` |
| Last completed task | PR #1 successfully squash-merged; post-merge remote verification completed. Its Phase 2 review findings remain recorded as historical evidence in [PHASE2_REVIEW_2026-11-19.md](PHASE2_REVIEW_2026-11-19.md) |
| In-progress task | Owner review of PR #2, including the archival measurement-scope clarification and dated HANDOVER snapshot corrections. Update this existing PR only, rerun integrity checks and stop for owner review; do not open a replacement PR |
| Known documentation discrepancies | Historical pre-transfer wording in this file, [FINAL_HANDOVER_REPORT.md](FINAL_HANDOVER_REPORT.md) and [DOCUMENTATION_REVIEW_REPORT.md](DOCUMENTATION_REVIEW_REPORT.md) describes the temporary mirror and the untransferred local package; retained as history, superseded by this snapshot and TRANSFER_STATUS.md. Full list in the review report §4 |
| Exact next action | Verify live PR #2/main status from GitHub, then owner-review the existing PR #2 and its latest correction commit; do not merge it during this task. Remaining review-report §8 questions still require owner decisions, including Q-02 (archival byte-preservation mechanism; Appendix B not implemented) and Q-07 (branch protection; not enabled). Q-03 is resolved. Stop and wait; no Phase 3 authorization is implied and no Desktop Bridge PoC may run |

## GUIDELINE archival measurement clarification — 2026-11-19 (PR #2 review)

The previous audit wording “lines 6–1544 = 39,181 bytes” conflated the **embedded source prompt** with the **complete protected region**. It is not a valid measurement of those complete lines. The PR description's 39,295-byte protected-region count and 39,181-byte source-prompt count measure different scopes, not different archived versions. Historical review reports remain unchanged; this clarification defines the scopes explicitly.

Compared exact Git objects (no text-mode decoding or newline conversion):
- Baseline commit `eb8b704f945ca4c5199d97a6a8c4bd286068cfbb`, GUIDELINE blob `5cf1fe00f420226716fab36a6f26828d005fb547`.
- PR #2 head observed before these corrections: commit `2561d5052bce7875cbe27b2579a6ab6fedd1561c`, GUIDELINE blob `2dc1d0c82503df0ff26a68b41f4644a76ba87b5d`. This follow-up does not modify GUIDELINE.md at all, so the corrected PR head retains this same blob.

**Exact boundaries (zero-based, half-open byte offsets in both blobs):**
- Complete protected region: `[626, 39921)`, physical lines 6–1544 inclusive. Starts with `<!-- BEGIN ORIGINAL MASTER PROMPT; SOURCE BYTES FOLLOW -->` plus LF (59 bytes); ends with `<!-- END ORIGINAL MASTER PROMPT; SOURCE BYTES END -->` plus LF (54 bytes).
- Embedded original prompt: `[685, 39866)`, excluding both markers and the one LF separator at `[39866, 39867)` immediately before the closing marker. This source has 1,536 CRLF pairs and no terminal newline. No `strip`/`rstrip` or line-ending normalization is applied.
- Maintained wrapper outside the protected region: concatenate prefix `[0, 626)` and suffix `[39921, EOF)` in that order, with no inserted separator. This is the measured outside region; historical wrapper passages are not thereby authorized for rewriting.

| Scope | Baseline bytes | PR-head bytes | Baseline SHA-256 | PR-head SHA-256 |
|---|---:|---:|---|---|
| Complete protected region | 39295 | 39295 | `70c4863fb97824a35e22a084e78d7916646d0038fe8c681d1c10f142020f8932` | `70c4863fb97824a35e22a084e78d7916646d0038fe8c681d1c10f142020f8932` |
| Embedded original prompt | 39181 | 39181 | `38634f573b0391402a1b58ad927d133fa0ad2ca6551c8ea66180daddd3e24b16` | `38634f573b0391402a1b58ad927d133fa0ad2ca6551c8ea66180daddd3e24b16` |
| Maintained wrapper outside protected region | 15939 | 16674 | `0d69334d899b483dd1d34b7ec686badc101c90343ec6335a812dfdb67384dab5` | `9614fb40ee0df15618e0b01b6f6009ab18e45102bb4e9a188f3e15d1e20ef4c6` |

The protected-region difference from the source size is exactly **114 bytes = 59 + 1 + 54**. Wrapper size increased by 735 bytes in R1's maintained repository-location correction; none of those bytes are inside the protected region. Both protected scopes are byte-identical, not merely hash-equal.

Reproduce against the baseline, original PR head and live locally fetched PR head (replace `HEAD` with the fetched head SHA if necessary):

```sh
python3 - <<'PYCODE'
import hashlib, subprocess
begin = b'<!-- BEGIN ORIGINAL MASTER PROMPT; SOURCE BYTES FOLLOW -->\n'
end = b'<!-- END ORIGINAL MASTER PROMPT; SOURCE BYTES END -->\n'
versions = []
for ref in ('eb8b704f945ca4c5199d97a6a8c4bd286068cfbb',
            '2561d5052bce7875cbe27b2579a6ab6fedd1561c', 'HEAD'):
    d = subprocess.check_output(['git', 'show', ref + ':GUIDELINE.md'])
    assert d.count(begin) == d.count(end) == 1
    a, e = d.index(begin), d.index(end)
    z = e + len(end)
    assert d[e-1:e] == b'\n' and d[e-2:e] != b'\r\n'
    parts = (d[a:z], d[a+len(begin):e-1], d[:a] + d[z:])
    assert parts[0] == b''.join(d.splitlines(keepends=True)[5:1544])
    assert (a, z) == (626, 39921)
    assert tuple(map(len, parts[:2])) == (39295, 39181)
    versions.append(parts)
    for scope, data in zip(('protected', 'source', 'outside-wrapper'), parts):
        print(ref, scope, len(data), hashlib.sha256(data).hexdigest())
assert all(v[:2] == versions[0][:2] for v in versions)
assert versions[1] == versions[2]  # follow-up leaves entire GUIDELINE blob unchanged
PYCODE
```

*Historical — pre-transfer; superseded by the snapshot above.*

**Current package:** `FINAL_UPLOAD` is a local root-level owner-review draft based on local branch `phase2/final-documentation-corrections`, commit `4dea17d1bdc02e2b5e00aaefc0d759094011b915`, with further uncommitted package-only reconciliation. No GitHub operations occurred during this local finalization. It has not been verified or transferred to the private primary repository. See [FINAL_HANDOVER_REPORT.md](FINAL_HANDOVER_REPORT.md).

## A. Current repository state
- **Public documentation mirror:** https://github.com/aliajeli/testing — intentionally public, for review; not the private application repository.
- **Branch:** `main`, as observed on the public mirror at review start.
- **Published temporary-mirror snapshots:** initial package `94fdb5a35d6ed6774954a06c8fa0f0d9d7220e92`; subsequent corrections `a19fce5c5e2c632ada3ff3748a11a541d0853a30`, committer timestamp `2026-11-19T09:46:29+03:30`. The latter was verified as `main` at review start.
- **Publication scope:** The documentation package has been published to the temporary mirror at the commit above. That publication is not publication to the main project repository. The owner reports that the main repository has not yet received the documentation; its current private contents were not independently verified. The corrections in `a19fce5c5e2c632ada3ff3748a11a541d0853a30` are published to the temporary mirror. Further independent-review corrections are on local branch `phase2/final-documentation-corrections`; remote publication remains unverified. A commit cannot embed its own final hash without changing that hash; obtain this review branch’s exact local commit using `git rev-parse HEAD`, and verify its remote ref separately after any authorized push. No unverified branch SHA is asserted here.
- **Last verified mirror synchronization:** `a19fce5c5e2c632ada3ff3748a11a541d0853a30` on `main`. A prior review used the session-provided date 2026-11-18, while host and remote commit timestamps showed 2026-11-19; that discrepancy has not been reconciled.
- **Current prepared file inventory:** `README.md`, `AGENT_SPECIFICATION.md`, `API_DOCUMENTATION.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `DATABASE_DESIGN.md`, `DECISION_LOG.md`, `DEPLOYMENT_WORKFLOWS.md`, `DESKTOP_BRIDGE_POC.md`, `DOCUMENTATION_REVIEW_REPORT.md`, `GUIDELINE.md`, `HANDOVER.md`, `NETWORK_REQUIREMENTS.md`, `RELEASE_PROCESS.md`, `SECURITY_POLICY.md`, `TESTING_STRATEGY.md`, `VERSIONING_POLICY.md`. These documents are in the published mirror under `prepared/`; `MANIFEST.md` and `SHA256SUMS.txt` are at mirror root. The corrections in `a19fce5` are published; the subsequent independent review changes are local until independently verified on a remote branch.
- **Actual application repository:** separate, private; current authenticated contents, branch, releases and permissions **Not verified** in this review. The mirror's public visibility is intentional.

## B. Current project phase
Phase 2 — Architecture, Design, Documentation and Technical Validation Planning. No Phase 3 authorization has been given. Do not implement the application, production Agent or Bridge, create production migrations or releases, build installers, execute the Bridge PoC, or configure production release workflows during this task.

## C. Approved architectural decisions
[DECISION_LOG.md](DECISION_LOG.md) records six owner-approved decisions: five separate services; date-only package destination with identifier metadata; one-time installer bootstrap exception; central private-release Update Proxy; bounded, separately authorized Bridge PoC; and three-tier testing. These decisions are authoritative; technical implementation and compatibility remain unverified.

## D. Completed documentation work
- [README.md](README.md): review-mirror purpose and index.
- [GUIDELINE.md](GUIDELINE.md): original owner-supplied requirements archive and development history. This local package restores the archived original bytes from the supplied source and compares them byte-for-byte; the earlier published mirror copy was LF-normalized and not byte-identical. Neither was independently compared against the conversation.
- [ARCHITECTURE.md](ARCHITECTURE.md), [DATABASE_DESIGN.md](DATABASE_DESIGN.md), [DECISION_LOG.md](DECISION_LOG.md): topology, logical data model, decisions.
- [SECURITY_POLICY.md](SECURITY_POLICY.md), [NETWORK_REQUIREMENTS.md](NETWORK_REQUIREMENTS.md): proposed trust boundaries and network requirements.
- [AGENT_SPECIFICATION.md](AGENT_SPECIFICATION.md), [DEPLOYMENT_WORKFLOWS.md](DEPLOYMENT_WORKFLOWS.md), [DESKTOP_BRIDGE_POC.md](DESKTOP_BRIDGE_POC.md): Agent, installation and separately authorized PoC designs.
- [API_DOCUMENTATION.md](API_DOCUMENTATION.md): proposed, unimplemented API.
- [VERSIONING_POLICY.md](VERSIONING_POLICY.md), [RELEASE_PROCESS.md](RELEASE_PROCESS.md), [TESTING_STRATEGY.md](TESTING_STRATEGY.md): proposed delivery and test gates.
- [CHANGELOG.md](CHANGELOG.md) and [DOCUMENTATION_REVIEW_REPORT.md](DOCUMENTATION_REVIEW_REPORT.md): history and current review findings.

## E. Unverified assumptions
Windows edition/architecture, service accounts, service readiness/restart behavior, edge mTLS/identity forwarding, service-to-service authentication, firewall/network access, and certificate provisioning are untested. PostgreSQL bundled installation, backup/restore, DPAPI key recovery, migrations, major upgrade and rollback are untested. GIG/OKCS explicit-credential deployment without trust using SMB/ADMIN$/SCM, Agent enrollment/rotation/revocation and Session Helper delivery are untested. Bridge browser integration, isolation, replay resistance, app launch and credential handoff are untested; PoC not executed. Hikvision model/firmware and ISAPI behavior, camera reconciliation, MikroTik/Winbox, TeamViewer LAN, SSH/RDP/VNC, ICMP monitoring and real Store Commerce deployment are untested. GitHub per-commit dispatch/allocator/concurrency, installer/upgrade, private Update Proxy, signing, release and update behavior are untested. Features remain unimplemented unless independently verified otherwise.

## F. Outstanding tasks
| Status | Task |
|---|---|
| Completed | Original ZIP prompt and this local package prompt match the owner-supplied file; earlier published mirror copies have CRLF-to-LF differences. |
| Designed | Five-service topology, date-only package path, Agent/Bridge/proxy boundaries, database model and release/testing policy. |
| Pending validation | Windows, database, security, integration, installer, CI and hardware checks listed above. |
| Pending validation | Owner review of public-mirror security findings and archival CRLF differences; GitHub publication of the separate local review branch remains unverified. |
| Not started | Application implementation, production migrations, installer, production release workflow and Bridge PoC. |

## G. Exact next action
Provide this local package for owner review and wait for explicit feedback and authorization. Do not publish, merge, transfer to the main repository or start Phase 3.

## Historical context
An earlier application-repository inspection reported an empty clone before the repository became private. A later persisted workspace lost some Git metadata. Those historical facts do not describe this public mirror, which has the verified `main` commit and documentation listed above. The six decisions were approved on 2026-11-18. Documentation-only source archival and design reviews did not implement or validate the application.
