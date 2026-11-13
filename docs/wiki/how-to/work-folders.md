---
type: how-to
status: active
updated: 2026-11-13
sources: [commit 41b679b, "#63", "#59", tests/lane.test.sh]
verified_by: tests/lane.test.sh
---
# Per-issue work folders (git worktrees)

Code changes happen in `../<repo>-<issue#>` on branch `<feat|fix|docs>/<issue#>-<slug>`, never in the primary folder. Claude creates and removes them; `harness ask implementer` in the primary folder is refused (`--no-lane` for tasks that change nothing in the repo, logged as `no_lane` in progress.jsonl).

- **Create.** `harness lane <issue#> [slug] [--type feat|fix|docs]`: fetches origin, branches from origin's default branch, runs `harness init` there, runs `lane_setup` from `.claude/harness.json` (e.g. `"lane_setup": "npm ci"`; a failure is reported, the folder stays) and prints the absolute path. `"lane_copy": [".env", "cfg/local.json"]` in the same file copies those files from the primary folder into the new folder (relative paths, no `..`; missing ones are noted and skipped; default: copy nothing). Claude fills `lane_copy` once per repo after looking at its ignored files. Run again to reuse an existing folder or branch. The slug comes from the issue title (`gh`), kebab-case, 30 chars.
- **Parallel asks.** `harness -C <path> ask implementer '...'`, then `-C <path> wait|report|status`. State (`.harness/`) is per folder, so implementers in different folders run at once. Use an absolute path: the conductor gate rejects `..`. Run tasks in parallel only when their file sets do not overlap.
- **Watch** (human terminal): `/watch implementer` prints `harness -C <path> watch implementer` (or `harness watch <role>` in the primary folder) for the user to run in another tab. `harness lane ls` lists issue, branch, path, PR state and running workers.
- **Remove.** `harness lane rm <issue#|path> [--force]` only when the PR is MERGED or CLOSED **and** the local HEAD equals the PR's `headRefOid` (`gh pr view`); otherwise it refuses, so unpushed commits are never lost. Also refuses while a worker runs there, with uncommitted changes, on a detached HEAD, and when an ignored file (not `.harness/`, `node_modules/`, `dist/`, `build/`, `.venv/`, `target/`, `.next/`, `coverage/`, `__pycache__/`) is missing in or differs from the primary folder (an identical copy such as `.env` is fine). Removes the folder and local branch (`-D`); for MERGED it deletes the remote branch with `--force-with-lease=<branch>:<headRefOid>` (later pushes keep it), a CLOSED PR keeps it. `--force` prints how many commits are lost first.

**Risks.** Dependencies are installed per folder (use `lane_setup`). The editor still shows the primary folder. Parallel folders share ports and databases. Parallel PRs touching the same files conflict on merge.
