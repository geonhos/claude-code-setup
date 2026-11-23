---
type: troubleshooting
status: active
updated: 2026-11-23
sources: [ask 1795065904-88000-10413, ask 1795071884-55567-28410, "#180", "#186", "#205", "#225", "#230", "#207", "#212", "#221", ask 1795354201-6196-21605, ask 1795398684-34820-25967, install.sh:39-40, install.sh:120-123]
verified_by: human (read install.sh)
---
# A temp worktree fails worktree-guard in every suite of the repo

**Symptom.** `./install.sh --test` or `harness-verify run all` ends with `FAILED: the test run registered temp worktrees of <repo>` and `FAILED suites: worktree-guard` while every other suite is green. The listed path is a reviewer's `.../base` or `.../head` under a temp dir (`/tmp/rv169.log`: `.../tmp.coCCbfiAh0/base`; #207, #221: `tmp.80AXTXFjcs/head`).

**Cause.** The guard snapshots the `git worktree list` paths under `/var/folders`, `/tmp` and `/var/tmp` (also with a `/private` prefix) before the run (install.sh:39-40) and fails on any new one after it (install.sh:120-123). The registry is per repository (`git -C "$REPO" worktree list`), not per checkout: a temp worktree that any session creates while another session's suite runs fails that suite. A sibling directory of the repo is outside the watched prefixes. No suite adds a worktree of `$REPO` (`git grep 'worktree add' -- tests` hits only temp repos: tests/gate.test.sh:607,654, tests/harness.test.sh:420,438, tests/lane.test.sh:211), so a foreign path ending in `/head` is another session's review worktree for a remote head (`tmp.80AXTXFjcs/head` at d46095a, #207; `tmp.vHJOTms4Jo/head` at cc47e1f, #221), not a test leak.

**Fix.** Create review worktrees as non-temp siblings (`../<repo>-review-<short-sha>`, `../<repo>-review-base-<short-sha>`), never under `mktemp -d` (claude/agents/reviewer.md:33). Remove only your own. If the guard fails on someone else's temp worktree, wait and rerun once; never remove it: it is a live worktree (on 2026-11-22 an implementer ran `git worktree remove` on a reviewer's, as #207 proposed; that fix is wrong). Verify the head in a worktree or work folder, never by checking out in the live checkout (issue #225, the #215 review on 2026-11-23). A reviewer that dies leaves its non-temp sibling worktree behind and nothing removes it; `harness lane ls` shows it as a row `#` with an empty branch (detached HEAD). Remove it with `git worktree remove <path>`, or as the conductor `harness lane rm <path> --force` (a detached folder needs `--force`; workers cannot run `harness lane`; lib/harness-lane.sh `lane_rm`).

**Evidence.** Reviews on 2026-11-19 (#165 round, #169 round; #180, #186) hit it with their own base worktree. Another session's head worktree: at least four runs on 2026-11-22/23 (#207, #221, the #174 review, a primary sync run). Rule in claude/agents/reviewer.md:33 (#205, #213).
