# Failure retros + metrics (critique Top 10 #7)

Source: `.harness/review-critique-detail.md` §6.4 (writes, metrics), §6.5 (failure modes). Branch `feature/v11-retro-metrics`, stacked on `feature/v10-wiki` (PR #14). bash 3.2. No gardener skill yet.

Principle: retros only on failure, batched, evidence-cited, short; metrics computed from data the harness already writes. Nothing writes to the wiki except through `docs/wiki/inbox/`.

## Task 1 — Retro candidates (automatic, no model call)
At the end of every `harness ask` / `harness report`, if the ask is a **trigger**, write `.harness/retro/<ask-id>.json`:
- triggers: exit ∉ {0}, except a reviewer exit 5 (a FAIL verdict is a normal outcome — trigger only on the *second* consecutive reviewer FAIL for the same branch/range, or skip; pick the simpler rule and document it); implementer verify attempts ≥ 2; a late report (collected via `harness report` after a non-zero ask).
- content: ask_id, role, exit, verify attempts, duration, brief path, log path, report path, timestamp. **No screen text, no prompt text** (secrets/privacy).
- `rotate_logs` must not delete a log referenced by a pending candidate.
- Print one stdout line: `retro: candidate queued (<reason>) — run 'harness retro' when the task is done`.

## Task 2 — `harness retro [--dry-run]` (one batched analyst ask)
- Collect all pending candidates. If none: print `retro: nothing pending`, exit 0.
- Write `.harness/task-retro.md`: for each candidate, the evidence paths; instructions for the analyst: per candidate (or per group of candidates with the same cause), write ≤120 words with **Symptom / Cause / Next time** and a mandatory `Evidence:` line (ask-id + file:line or log path). First check `docs/wiki/index.md`: if an existing gotcha covers it, write a one-line "recurrence of <page>" note instead of a new lesson (this feeds the 2+ recurrence promotion rule). Output files go to `docs/wiki/inbox/<date>-retro-<ask-id>.md`. Do not edit wiki pages. No fluff, no success stories.
- Run it as `harness ask analyst 'Read .harness/task-retro.md and do it.' --via retro --fresh` (add `retro` to the allowed `--via` values; routing log should record it).
- On analyst exit 0: move processed candidates to `.harness/retro/done/`. Otherwise keep them pending.
- `--dry-run` prints the candidates and the brief path without asking.

## Task 3 — `harness metrics [--since YYYY-MM-DD] [--json]`
From `.harness/progress.jsonl` (+ docs/wiki), default window = last 28 days, also show the previous equal window for comparison:
- asks per role; exit distribution; **abnormal rate** = exit ∉ {0,5} + late, per role and total;
- implementer verify-failure rate (exit 5) and mean verify attempts if recorded;
- reviewer FAIL rate (exit 5 / reviewer asks);
- median/95p duration per role;
- retro: pending candidates, processed, recurrences noted ("recurrence of" lines in inbox);
- wiki: active/stale/draft pages, inbox items + oldest age, index lines, SessionStart wiki bytes.
Plain text table by default; `--json` for machines. Pure jq/awk, no new deps. Handle old progress lines that lack newer fields.

## Task 4 — Wiring and docs
- `claude/agents/conductor.md`: one short paragraph — when `retro: candidate queued` appears, finish the current piece of work, then run `harness retro` once (batched); run `harness metrics` when the user asks how the harness is doing or before proposing harness changes.
- AGENTS.md: mention `harness metrics` and that retros feed `docs/wiki/inbox/`.
- README usage lines.
- Wiki: a decision page `decisions/0004-failure-only-batched-retros.md` (why failure-only, why batched, why no screen text) + index + log line.

## Tests
Fake herdr: trigger/no-trigger matrix (0, 3, 4, 5 implementer, 5 reviewer, late report, verify attempts); candidate content has no screen/prompt text; rotate_logs keeps referenced logs; `harness retro --dry-run` and the real path with fake analyst (moves candidates on 0, keeps on non-zero); metrics on a fixture progress.jsonl (known numbers incl. old-format lines) in text and `--json`. `./install.sh --test` + `harness wiki-lint` pass.

## Done
One commit per task; `/review`; PR against `feature/v10-wiki`.
