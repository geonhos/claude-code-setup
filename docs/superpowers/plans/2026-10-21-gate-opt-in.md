# Plan: gate only inside herdr, fail closed (Top 10 #4a)

Source: `.harness/review-critique-detail.md` §1.4, §1.5, Top 10 #4.
User choices (2026-10-21): keep the global `agent=conductor` and add a `HERDR_ENV`
guard; do 4a now, and #4b (shrinking the gate toward `permissions`) as a separate design.

## Task 1 — gate
- `claude/hooks/conductor-gate.sh`: after the worker check, `HERDR_ENV != 1` → exit 0.
- Unparseable input or missing `tool_name` → deny with a fixed reason (stderr note kept).
- Matcher unchanged (rationale in decision 0005).

## Task 2 — tests
- `tests/gate.test.sh`: `run_gate`/`nojq` set `HERDR_ENV=1` explicitly, so the suite does
  not depend on the caller's env. Flip garbage/missing-tool to deny, and add empty input,
  worker garbage → allow, 7 off-herdr cases, 1 on-herdr control and the deny reason.
- Red check: the new suite against `HEAD:claude/hooks/conductor-gate.sh` fails 10 checks.

## Task 3 — docs
- Decision 0005, gotcha `daemon-inherits-worker-env`, index lines, log line.
- README gate paragraph; conductor.md escape-hatch paragraph.

## Out of scope / follow-ups
- #4b: permissions rules + a small gate; most of the gate suite rewritten.
- Detecting a stale worker env (dead `HERDR_PANE_ID`): needs a herdr call per tool use,
  so it is too slow for a PreToolUse hook. Revisit with #4b.
- Review: 174e159 and this change were made in a session that had inherited
  `HARNESS_ROLE=worker`. Both need `/review` from a real conductor before merge.
