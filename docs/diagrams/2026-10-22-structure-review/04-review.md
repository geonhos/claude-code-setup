# 04 Structure review (2026-10-22)

| Sev | Weakness | Evidence | Fix |
|---|---|---|---|
| high | Per-role timeout lives only in skill text; follow-up asks without `--timeout` get 600 s while the implementer Stop hook alone can take 600 s → exit 4 / INTERRUPTED | H:63, conductor.md:104 | Role-aware default inside harness (implementer 1740000) |
| high | Completion depends on frontmatter Stop hooks; a stale worker or a silent hook shows only as 30 s exit 3 or a full-timeout wait (hit again on 2026-10-22 analyst ask) | H:974–1010, H:1074 | Store agent-file hash at spawn, respawn on mismatch |
| med | `.harness` resolved from `$PWD`, worker names from git toplevel → two conductors in subdirs share a worker, one never sees its report | H:99–117 | Anchor `.harness` at toplevel |
| med | One report/current/marker slot per role → no parallel asks per role | H:56–63 | Key paths by ask-id, or document |
| med | Role lists and defaults duplicated in 4 places | H:56, V:239, I:48, H:1135 | Single JSON source; glob test suites |
| med | "last jsonl record per agent" scan repeated 3×; `--via` parsed twice | H:321, H:569, H:1360 | Extract `last_ask_record` |
| low | cwd check passes when herdr gives no cwd; verify skips without jq | H:137, V:18 | Fail unless an override env is set |
| low | `bin/harness` is a 1601-line monolith | wc -l | Split into `lib/` modules |

## herdr fit
Metrics (2026-09-24..10-22): 97 asks, 37.8 % abnormal (analyst 76.5 %), 35 of them exit 3/4/late.
herdr fits watching and answering workers (exit 2 flow). It has no completion signal, so the
harness rebuilds one from Stop-hook markers, 2 s polling, 30 s grace and screen state; most
abnormal exits come from that layer. Option: run analyst/reviewer headless
(`claude -p --agent <role> --output-format json`, process exit = done) and keep a pane only for
the implementer. Reopens decision 0001.

## Speed
Median / p95: analyst 150 / 1097 s, implementer 202 / 745 s, reviewer 167 / 412 s.

| Cause | Fix |
|---|---|
| advisor calls inside workers (2 in a 3m46s analyst ask) | disable or cap at 1 in worker prompts |
| implementer pane closes on success → respawn + re-read every ask | `close_after_ask.implementer=never`, keep `/clear`; put file:line in briefs |
| Stop hook runs lint + full tests each turn | affected suites only; full run before commit |
| opus analyst + reviewer | sonnet for lookups; skip review on small changes |
| completion-detection overhead | fix the two high items above |
| one slot per role → serial pipeline | per-ask slots + worktrees (Top 10 #5) |
