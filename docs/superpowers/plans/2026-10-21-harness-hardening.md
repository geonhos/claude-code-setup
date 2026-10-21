# Harness hardening (critique Top 10 items 1–3)

Source: `.harness/review-critique-detail.md` §1.1, §1.2, §1.3, §5. Keep it small: no new subsystems beyond what each task needs.
Branch: `feature/v9-harness-hardening` (from main). One commit per task. bash 3.2 compatible (no `declare -A`). Tests run via the repo's existing test entry point (`./install.sh --test` or whatever tests/ uses) and must pass.

## Task 1 — Repo-scoped worker names + cwd verification (critique §1.2)

Problem: `bin/harness:37` hard-codes `analyst implementer reviewer`; `bin/harness:72` uses `herdr agent get "$1"` without checking the worker's cwd, so a conductor in repo A can drive repo B's worker.

Do:
- Worker herdr name = `<role>-<repo8>` where `<repo8>` is the first 8 hex of a hash of `git rev-parse --show-toplevel` (fallback `$PWD` outside git). Keep the CLI role names (`harness ask implementer ...`) unchanged; map role → herdr name internally in one helper.
- After any `herdr agent get`, compare `.cwd` (resolve symlinks, `pwd -P`) with the repo top-level; if the worker is not inside this repo, refuse with a clear error and a distinct non-zero exit (document which code; do not reuse 2/3/4/5 semantics — pick e.g. 6 and add it to conductor.md's exit-code section).
- `harness spawn`/`status`/`report` use the scoped names. Migration: if an old unscoped worker exists for this repo (cwd matches), print a one-line hint; do not auto-kill.
- Update conductor.md, skills, README/docs mentions of worker names only where they would now be wrong.
- Tests (fake herdr ok): scoped name generation; refusal when cwd differs; acceptance when cwd is a subdir of the repo.

Done: tests pass; commit `fix(harness): scope herdr worker names per repo and verify worker cwd`.

## Task 2 — PoC: does a native subagent with `model:` avoid the conductor's model? (critique §1.1)

Problem: `claude/hooks/conductor-gate.sh:35` claims "Native subagents inherit the Fable model"; docs (https://code.claude.com/docs/en/sub-agents) say `model:` in subagent frontmatter overrides it. The whole herdr layer rests on this premise.

Do (measure, don't redesign):
- In a scratch dir outside the repo (or a temp worktree), define a throwaway subagent with `model: sonnet` and run a headless session (`claude -p --output-format json ...`, plain session with the gate off, e.g. `HARNESS_ROLE=worker claude --agent solo -p ...`) that delegates one trivial read task to it via the Agent tool.
- From the JSON output (`modelUsage` / per-model usage, `total_cost_usd`) record which models were billed and roughly how many tokens each. Also note the parent-context cost of the subagent's returned result.
- Write findings to `docs/research/2026-10-21-subagent-model-poc.md`: exact commands, raw relevant JSON fields, conclusion (premise true/false), and what it implies for the gate message and the herdr layer. Do NOT change the gate or conductor yet — only fix the gate's MSG_AGENT text if the premise is proven false (make it factually correct, keep the deny).

Done: doc committed; commit `docs(research): measure subagent model override (premise check)`.

## Task 3 — Deterministic completion: Stop-hook done marker + report mtime (critique §1.3)

Problem: `bin/harness:635` relies on `herdr agent prompt --wait` + screen-regex idle; ~38% of 61 asks ended abnormally (exit 3/4/late). herdr `--wait` does not track turns.

Do:
- Each `harness ask` generates an ask-id and writes it where the worker's Stop hook can find it (e.g. `.harness/asks/<role>.current` containing ask-id + start epoch). 
- Worker Stop hook (extend the existing `bin/harness-verify` stop path or add a small hook; workers only, HARNESS_ROLE=worker) writes `.harness/done/<role>.<ask-id>` with session_id and timestamp when the turn ends — only after verify passed/gave up, and respect `stop_hook_active` (don't mark done on a blocked continuation).
- `harness ask` completion = marker file for this ask-id exists AND report file mtime > ask start. idle/done from herdr becomes a secondary signal only (e.g., idle without marker after a grace period → existing exit 3 path; marker without fresh report → exit 3).
- Keep exit-code semantics 2/3/4/5 unchanged. Background-subagent waits inside a worker must not produce a false exit 3 (marker only on real Stop).
- Wire the hook in install.sh for worker sessions; idempotent.
- Tests (fake herdr + simulated hook): marker+fresh report → 0; idle without marker → waits then 3; stale report from previous ask → not accepted; stop_hook_active → no marker.

Done: tests pass; commit `feat(harness): detect worker completion via Stop-hook marker instead of idle heuristic`.

## Task 4 — Pane lifecycle: auto-close idle workers (user request)

Problem: worker panes live forever once spawned; they keep context, hold a herdr name, and clutter the workspace.

Do (first check what herdr itself offers: `herdr pane --help`, `herdr agent --help`, close/kill/exit commands; use herdr's own close rather than sending `/exit` text if available):
- `harness close <role>|--all`: gracefully end the worker (send `/exit` or herdr close), wait, verify the pane is gone; refuse if the worker is `working` or `blocked` unless `--force`.
- Auto-close policy, opt-in via `.harness/config` (or env) with a sane default:
  - `close_after_ask=never|on_success` (per role; e.g. implementer `on_success` since its context is cleared every ask anyway).
  - `idle_ttl_minutes` (default e.g. 30): on every `harness` invocation (ask/status/spawn), reap scoped workers of THIS repo (Task 1 names + cwd check) that are idle/done longer than the TTL and have no pending report to collect. No daemon.
- `harness ask` auto-spawns a closed worker as today (confirm the spawn path still works after close).
- Never close a worker with an uncollected report or one in another repo.
- Log closes to progress.jsonl (`event: close`, reason).
- Tests (fake herdr): close refuses while working; TTL reaping skips other-repo and fresh workers; ask after close respawns.

Done: tests pass; commit `feat(harness): close idle worker panes (harness close + idle TTL)`.

## After
`/review` the branch vs main, then PR.
