---
type: how-to
status: active
updated: 2026-11-13
sources: [commit 41b679b, "#63", "#59", tests/lane.test.sh]
verified_by: tests/lane.test.sh
---
# Per-issue work folders (git worktrees)

Code changes happen in `../<repo>-<issue#>` on branch `<feat|fix|docs>/<issue#>-<slug>`, never in the primary folder. Claude creates and removes them; `harness ask implementer` in the primary folder is refused (`--no-lane` for tasks that change nothing in the repo, logged as `no_lane` in progress.jsonl).

- **Create.** `harness lane <issue#> [slug] [--type feat|fix|docs]`: fetches origin, branches from origin's default branch, runs `harness init` there, runs `lane_setup` from `.claude/harness.json` (e.g. `"lane_setup": "npm ci"`; a failure is reported, the folder stays) and prints the absolute path. Run again to reuse an existing folder or branch. The slug comes from the issue title (`gh`), kebab-case, 30 chars.
- **Parallel asks.** `harness -C <path> ask implementer '...'`, then `-C <path> wait|report|status`. State (`.harness/`) is per folder, so implementers in different folders run at once. Use an absolute path: the conductor gate rejects `..`. Run tasks in parallel only when their file sets do not overlap.
- **Watch** (human terminal): `harness -C <path> watch implementer`. `harness lane ls` lists issue, branch, path, PR state and running workers.
- **Remove.** `harness lane rm <issue#|path> [--force]` only when the PR is MERGED or CLOSED **and** the local branch head equals the PR's `headRefOid` (`gh pr view`); otherwise it refuses, so unpushed commits are never lost. Refuses while a worker runs there or with uncommitted changes. Removes the folder and local branch (`-D`); deletes the remote branch only for MERGED and only if it still exists (a CLOSED PR keeps it). `--force` prints how many commits are lost first.

**Risks.** Dependencies are installed per folder (use `lane_setup`). The editor still shows the primary folder. Parallel folders share ports and databases. Parallel PRs touching the same files conflict on merge.
