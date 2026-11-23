---
type: troubleshooting
status: active
updated: 2026-11-23
sources: [ask 1795065904-88000-10413, ask 1795071884-55567-28410, "#180", "#186", "#205", "#225", "#207", "#221", install.sh:39-40, install.sh:120-123]
verified_by: human (read install.sh)
---
# A temp worktree fails worktree-guard in every suite of the repo

**Symptom.** `./install.sh --test` or `harness-verify run all` ends with `FAILED: the test run registered temp worktrees of <repo>` and `FAILED suites: worktree-guard` while every other suite is green. The listed path is a reviewer's `.../base` or `.../head` under a temp dir (`/tmp/rv169.log`: `.../tmp.coCCbfiAh0/base`; #207, #221: `tmp.80AXTXFjcs/head`).

**Cause.** The guard snapshots the `git worktree list` paths under `/var/folders`, `/tmp` and `/var/tmp` (also with a `/private` prefix) before the run (install.sh:39-40) and fails on any new one after it (install.sh:120-123). The registry is per repository (`git -C "$REPO" worktree list`), not per checkout: a temp worktree that any session creates while another session's suite runs fails that suite. A sibling directory of the repo is outside the watched prefixes.

**Fix.** Create review worktrees as non-temp siblings (`../<repo>-review-<short-sha>`, `../<repo>-review-base-<short-sha>`), never under `mktemp -d` (claude/agents/reviewer.md:33). Remove only your own. If the guard fails on someone else's temp worktree, wait and rerun once; never remove it. Verify the head in a worktree or work folder, never by checking out in the live checkout (issue #225, the #215 review on 2026-11-23).

**Evidence.** Reviews on 2026-11-19 (#165 round, #169 round; #180, #186) hit it with their own base worktree; #207 and #221 hit it from another session's head worktree. Rule in claude/agents/reviewer.md:33 (#205, #213).
