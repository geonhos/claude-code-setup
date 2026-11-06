# Karpathy A/B — why so small (evidence detail)

Data: branch `research/karpathy-ab` (b215b1e), `docs/research/karpathy-ab/`. All 24 session
transcripts exist: `~/.claude/projects/<scratch>-karpathy-ab-clones-<RUN>/<session_id>.jsonl`
(session_id from `runs/<RUN>.json`). Thinking blocks are redacted (empty); tool calls, visible text,
the system prompt (`prompt_snapshot`) and request blobs are intact. Scripts used: <scratch>/kab-scripts/*.py (throwaway).

## H1 Overlap — mostly supported (via implementer.md, not AGENTS.md)
Installed `--agent implementer` = `~/.claude/agents/implementer.md` → repo `claude/agents/implementer.md`
(last change e74a78e, 2026-11-03, before the runs; confirmed in transcript system prompt "You are the **implementer**").
| Principle | Already covered by | Genuinely new |
|---|---|---|
| 1 Think before coding | implementer.md:34-36 "pick the smallest reasonable reading and say so under Open questions"; :85 Open questions | state assumptions *before* editing; list interpretations; push back. "If uncertain, ask / stop" is unusable: headless `-p`, `--disallowedTools=AskUserQuestion` |
| 2 Simplicity | implementer.md:34 "Implement exactly the instruction"; AGENTS.md:20 (bases 77252a8 only) no new mechanism | no speculative abstraction/config/error handling; "200→50 lines" |
| 3 Surgical | implementer.md:34 (exactly the instruction), :47-48 (don't discard others' changes) | don't touch adjacent code/comments; mention, don't delete dead code; remove only own orphans |
| 4 Goal-driven | implementer.md:37-45 (run tests, add tests, affected suites), :56-65 (hooks are the gate), :84; AGENTS.md "All must pass before a commit" (:24 at 77252a8, :18–20 at other bases); every brief has its own test steps (T1 "Use TDD") | written plan with per-step verify — redundant in practice |
AGENTS.md at bases (62–69 lines) has no behavioural rule besides tests/bash 3.2/wiki. Overlap lives in the agent prompt + briefs.

## H2 Prescriptive briefs — supported
- T1 (high): file+line refs (harness-verify:32-34, :243, :274/:283, harness ~:1083), 4 numbered fix steps, named test files, commit messages.
- T2 (high): sections A/B/E fix mechanism (`&` + `wait <pid>`, `HARNESS_TEST_SERIAL`), files, wording rules, 3+1 verify runs.
- T3 (very high): pure move, function list, loader order, purity-diff command. Zero room.
- T4 (high structure, stale premise): 4 commits with exact contents; but commits 2/3 were already done at base. The brief itself *orders* "add a gate test per form if missing" and "update conductor.md … so it matches", so the baseline's "scope" penalties (R17 11 allow tests, conductor.md edit) are partly penalties for obeying the brief.

## H3 Ceiling/measurement — supported
- 96 scores: correctness 4/5 = 22/24, scope 4/5 = 22/24, simplicity 4 = 16/24 (default), verification 2–3 = 18/24.
- Pooled sd 0.49 includes between-task spread; the design is task-balanced, so use the within-cell residual sd = 0.29 (df 16) → SE(diff) 0.12 → 80%-power MDE ≈ 0.33; CI of +0.062 ≈ [−0.19, +0.31], excludes 0.5. Power was adequate for the pre-registered bar; the effect is genuinely small.
- Cancellation: the 4-dim mean nets correctness −0.25 vs scope +0.25 / simplicity +0.17; the task mean nets T4 +0.58 vs T1 −0.42.
- Grader inconsistency, T2: five of six T2 runs share the `set -e` background-subshell construct `( suite >out; echo $? >rc … ) &` (baseline-1/2/3, karpathy-2/3 diffs). Grader docked only R10 (k3, corr 3), gave R18 (k2, identical construct) 5 and baselines 4/4/5. Only R03 (k1, bare `wait "$p"` under set -e) has a distinct defect.
- T3: six near-identical pure moves scored 5/5/5/3 except R12 verification 5 — driven by the final message, not code.
- Verification: 22/24 final messages are just `REPORT:` pointers. But the reports are recoverable: 23/24 transcripts contain the `cat > .harness/reports/implementer.md` heredoc (T2-baseline-1 not found by the regex).

## H4 Behaviour change — process unchanged; output changed in ~4/12 K runs, mixed direction
- output_tokens (includes redacted thinking) −4.6% in K: no extra deliberation despite "Think Before Coding".
| metric (mean B / K) | B | K |
|---|---|---|
| tool calls | 12.3 | 11.8 |
| read sub-commands before first edit | 11.4 | 14.5 |
| first edit at call # | 3.3 | 4.0 |
| visible text messages | 2.8 | 2.8 |
| reports with non-"none" Open questions | 1/12 (T4-b1) | 2/12 (T2-k2, T4-k3) |
- No run in either arm states assumptions or a plan before editing; pre-edit text is e.g. "Tests fail as expected (red)".
- Zero mentions of "principle", "surgical", "simplicity", "assumption", "Working principles" in any assistant text or tool input (only "karpathy" from the clone path).
- Work style identical: few huge batched Bash calls, edits via `python3 - <<` / `sed -i` (Edit tool almost unused), commit, `install.sh --test`, report heredoc. No Skill/Agent/advisor calls in any run.
- Tests run in both arms comparably (T1 TDD red→green in all 6).
- Slightly more reading before the first edit in K (+3 sub-commands), within task noise (T4-k1 22 vs T4-k2 9).

## H5 Task mix — supported, and the drops have specific mechanisms
- T3: identical diffs (+325.7/−321.7 both arms); no room.
- T1 drop: base test `tests/verify.test.sh:250` "stop/ask from a subdirectory of the repo: root is the cwd" encodes the old behaviour. All 3 baselines + K3 rewrote it; K1 and K2 kept it and added a "cwd that has its own .harness stays" exception to `enter_root` (diff comments: "a deliberate nested root"). Inferred (no mentions, thinking redacted): preserve-existing-behaviour (principle 3) overriding the brief — more code, not "simplicity cutting". 2/3 vs 0/3, one-sided Fisher p ≈ 0.2.
- T2 drop: mostly grader inconsistency (above); one real defect in K1.
- T4 gain: gate file touched B 3/3 vs K 1/3; conductor.md B 1/3 vs K 2/3; added gate-test lines B 2/12/0, K 13/0/5. Reference touches neither. The gain rests on K2 (R16, 5/5/5/4) and partly K3; K1 looks like a baseline.

## H6 Placement/dilution — supported
- Principles: 66 lines / 2,372 chars appended after AGENTS.md line 62–69, inside the CLAUDE.md system-reminder of the first user turn.
- Same initial context: system prompt 17.7k chars (implementer body 3.8k), tool schemas ~47.5k, superpowers SessionStart injection ~36k (`<EXTREMELY_IMPORTANT>`, in both arms), CLAUDE.md/AGENTS.md ~4.8–7.6k, brief 2.4–5.7k → principles ≈ 2% of ~110k chars.
- Conflicts: "If uncertain, ask/stop" vs headless + AskUserQuestion disabled + implementer.md:35-36 "pick the smallest reading"; "Loop until verified" vs implementer.md:39-45/56 (limited suite runs, hooks decide); brief-mandated extras (T4) vs "every changed line traces to the request".
- Blinding leak: the clone cwd (`…/clones/T4-karpathy-2`) appears in the agent's environment, so the run could see its condition name.
