# Code Mode A/B experiment, analyst role (#239, option 1)

Date 2026-11-25, CC 2.1.332, main 89e0472. Pre-registered sections (task, launch lines, rule) were
written before any run.

## Chosen ask

- Ask: analyst ask of 2026-11-16 01:13Z, "#105 shrink inventory: get below 8,423 lines without
  removing features" (archive `.harness/log/20261116-101321-analyst.md`, stream
  `.harness/log/20261116-100911-analyst.jsonl.gz`; pre-ask-id era row, no ask_id in progress.jsonl).
- Base 43fc5a7..43fc5a7 (progress head_before = head_after; the brief names 43fc5a7).
- Original: exit 0, 251 s (result duration_ms 245351), 34 turns, $2.534, 32 tool_use blocks,
  opus (claude-opus-5-5), CC 2.1.325. One denial (built-in rm safety check).
- Why: read-heavy (git archive/wc, grep for callers, read tests/prompts), git only, no `gh`, no
  network, writes only `.harness/shrink2-inventory.md`, needs no `.harness/` input file, full brief
  recoverable. Deviation: cost $2.534 is 1% above the ~$2.5 cap. Alternatives rejected: viewer
  redesign (11-12) counts 93 stream logs that are now pruned; worktree-per-ask (11-13) has 18
  turns and needs `.harness/` plans; every other ask ≥ 11-12 within the limits used `gh`.
- Brief: `code-mode-experiment/brief.md`; known-good report: `code-mode-experiment/known-good-report.md`.

## Launch lines (cwd = fresh clone at 43fc5a7, branch main forced there, brief copied to
`.harness/task-analyst.md`; stdin = "Read .harness/task-analyst.md and do it.")

A:
```
env -u HERDR_PANE_ID HARNESS_ROLE=worker perl -e 'alarm 900; exec @ARGV' \
  claude -p --agent analyst --output-format stream-json --verbose --include-hook-events \
  --disallowedTools=AskUserQuestion --permission-mode auto --permission-prompts none \
  --no-session-persistence < prompt > A<r>.jsonl 2> A<r>.err
```
B: the same plus `--settings '{"env":{"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"1"}}'`.

Differences from `bin/harness-run:70-71`: `--no-session-persistence` (no transcript), no
`--resume`, no harness state in the clone (no `.harness/asks/`), so the Stop hook
`harness-verify done analyst` finds no `asks/analyst.current` and returns at once
(bin/harness-verify:328): the report gate never nudges. Same in both arms. Script: run.sh in
scratch dir <tmpdir>

## Pass / fail (fixed before the runs)

PASS = median cost OR median wall time of arm B ≥ 25% below arm A, AND every B report matches the
known-good findings as well as the A reports do, AND 0 whole-script refusals across the 3 B runs.
Otherwise FAIL. Wall time = result `duration_ms`.

## Results

**Stopped after round 2 (N=2 per arm, 4 runs) on the budget rule.** Spend after round 2 = $20.02;
a third round would cost about $9-12 (round 2 cost $12.09), past the $25 hard stop.

Code Mode on in B: in CC 2.1.332 the init `tools` list has **no `REPL` entry** in either arm
(B lists Bash/Read last plus the deferred MCP tools). Every B tool call has a `toolu_cc_*` id and A
has none, so Code Mode was on; the REPL tool_use and its result are not in the stream at all.
REPL script count is therefore estimated (runs of inner calls between model messages): 15 in B1, 15 in B2.

| Run | Round | Cost $ | duration_ms (sum of results) | runner wall s | Turns | out tok | cache write | cache read | main tool_use (cc) | subagent tool_use | Agent spawns | compactions | denials |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A1 | 1 | 2.906 | 339,271 | 340 | 44 | 20,723 | 214,869 | 3,066,047 | 42 (0) | 0 | 0 | 1 | 0 |
| B1 | 1 | 5.025 | 254,272 | 256 | 32 | 14,215 | 200,415 | 1,215,895 | 206 (206) | 38 | 2 | 1 | 0 |
| A2 | 2 | 5.901 | 414,638 (391,951 + 22,687) | 477 | 43 (39+4) | 20,250 | 213,789 | 3,301,235 | 40 (0) | 28 | 1 (background, then woke) | 1 | 0 |
| B2 | 2 | 6.186 | 490,139 | 492 | 34 | 18,720 | 206,111 | 1,423,425 | 339 (339) | 70 | 2 | 1 | 0 |

Token columns are the main session's result `usage` (subagent tokens are only in the cost).
A2 had two result events: it waited on a background Agent, ended a turn, and was woken by the
task notification (4 more turns); cost is cumulative, so the last value is the run's cost.

Measurement caveats (neither changes the verdict):
- A2 cost: both result events carry identical `total_cost_usd` and `modelUsage` (costUSD 5.9013,
  cacheRead 5,561,933), although the wake segment read 462,982 cache tokens more. So the wake
  segment is probably not counted: A2 may be ~$0.2-0.3 higher, which makes A's median ~$4.55 and B
  ~+23% instead of +27%. Still FAIL.
- Time: duration_ms leaves out A2's ~62 s background-wait idle. By runner wall time the medians are
  A 408.5 s (340-477) and B 374 s (256-492), so B is ~8% faster. Still far from 25%.

Per arm (N=2, median = mean): cost A $4.40 (2.91-5.90) vs B $5.61 (5.03-6.19) → **B +27%**;
time A 377 s (339-415) vs B 372 s (254-490) → **B −1%**; turns A 43.5 (43-44) vs B 33 (32-34) → B −24%.
Main-session cache reads drop ~58% in B, but B spawned 2 subagents in both runs (A in one), and
subagent tokens dominate the bill. Original archived run (CC 2.1.325): $2.53, 245 s, 34 turns, no subagent.

### Denials and hooks
- 0 `permission_denials`, 0 `system/permission_denied` events in all 4 runs → **0 whole-script refusals**.
- PreToolUse fired for every inner call under its normal tool name (B1: 242 hooks = 244 calls − 2
  Agent calls, which the gate matcher `Edit|Write|Read|Grep|Glob|Bash` does not cover; B2: 407 = 409 − 2).
  Subagent inner calls (`parent_tool_use_id` set) also fired it. No PreToolUse for REPL itself (not in matcher).
- Stop fired once per run (A2 twice, once per turn), exit 0, no output: in a clone with no
  `.harness/asks/analyst.current` `harness-verify done analyst` returns at once (bin/harness-verify:328).
- Every run auto-compacted once (B1: 125,946 → 20,395 tokens). All clones stayed clean (`git status` empty).

### Quality (each run vs the 11 known-good findings K1-K11)
K1 9,386 now / 963 gap; K2 no-feature-loss total + target unreachable; K3 `last_ask_record` dead
(bin/harness:109-127); K4 metrics clear/late/pane remnants unused; K5 suites redefine helpers instead of
harness-lib.sh; K6 gate.test probes duplicated by gate-denied.list; K7 source dedupe (headless
wait/ask loops, verify loader, gate paths); K8 prompt/doc rule duplication; K9 tests of removed
behaviour (`.harness/done` in verify.test); K10 dashboard is the one feature whose removal alone
reaches the target, lanes/open-watch/short reads do not; K11 2-4 risk-ordered batches with totals.

| Run | Missing / partial / conflicting | Score |
|---|---|---|
| A1 | K9 missing; K7 partial (only poll loops); K10 says lanes "barely enough" (own total 430) | 9.5/11 |
| A2 | K9 partial (pane-era asserts, not `.harness/done`) | 10.5/11 |
| B1 | K4 missing | 10/11 |
| B2 | K4 partial (`by_runner` only); **K10 conflicts**: recommends removing `harness metrics` + comment cuts, rejects the dashboard as protected | 9.5/11 |

All four reproduce the headline (≈9,386, target unreachable without a feature cut, last_ask_record,
gate-list duplicates, helper consolidation); totals differ widely (A 430/582, B 580/674, known-good
392). B matches about as well as A (A 9.5-10.5, B 9.5-10); B2's different feature choice is the one
headline divergence.

## Verdict: FAIL

Cost median B is 27% higher (needed ≥25% lower); time median 1% lower (needed ≥25% lower).
Quality condition ≈ met (B 9.5-10 vs A 9.5-10.5); refusal condition met (0). The cost/time
condition fails, so FAIL. Deviation from the plan: N=2 per arm, not 3 (budget stop).

What N=2 supports: within-arm spread is huge (A cost 2.91-5.90, ×2; B time 254-490 s, ×1.9),
and the arms overlap on both cost and time, so N=2 cannot show any difference in time. It can say
B did not show a ≥25% saving: B's cheapest run ($5.03) is above A's median ($4.40). What drove cost
in both arms is subagent fan-out, which neither arm controls; a cleaner test would pin it (e.g.
`--disallowedTools Agent` in both arms).

## Spend and files
Total $20.02 (A1 2.906 + B1 5.025 + A2 5.901 + B2 6.186). Raw streams `code-mode-experiment/{A1,B1,A2,B2}.jsonl`,
stderr `*.err` (empty), each run's `.harness/` output (report, shrink2-inventory.md) in `*-harness/`,
`runs.txt`, `clones.txt`. Clones left in place for the conductor to remove (worker rule: no `rm`):
the four `tmp.*` dirs in `clones.txt`, plus scratch `tmp.t5PYB8iIq2` (run.sh).
