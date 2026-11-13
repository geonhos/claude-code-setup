#!/bin/bash
# Tests for the progress log, rotation and signal handling of
# bin/harness (against tests/fake-claude). Run: /bin/bash tests/progress.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
FAKE_BIN="$HERE/fake-claude"
pass=0
fail=0

WORKS=""
trap 'cd / && for d in $WORKS; do rm -rf "$d"; done' EXIT
setup() {
  WORK=$(mktemp -d)
  WORKS="$WORKS $WORK"
  export FAKE_DIR="$WORK/fake" FAKE_LOG="$WORK/claude.log"
  export HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=5 FAKE_CLAUDE_MODE=success
  mkdir -p "$FAKE_DIR"
  : > "$FAKE_LOG"
  unset FAKE_REPORT_CMD HARNESS_LOG_KEEP HARNESS_LOG_DAYS HARNESS_JSONL_MAX
  cd "$WORK" || exit 1
  env -u HERDR_ENV -u HARNESS_ROLE /bin/bash "$HARNESS" init --no-agent >/dev/null 2>&1
  printf 'fake/\nclaude.log\n' > .gitignore
}

GUARD="perl -e alarm(40);exec(@ARGV)"
run() {
  OUT=$(PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env -u HERDR_ENV -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>/dev/null)
  RC=$?
}
# runerr: same, stdout+stderr merged
runerr() {
  OUT=$(PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env -u HERDR_ENV -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi; }
logged() { grep -qF -- "$1" "$FAKE_LOG"; }
not_grep() { ! grep "$@"; }
not_logged() { ! grep -qF -- "$1" "$FAKE_LOG"; }
gitwork() { git init -q . && git config user.email t@t && git config user.name t && echo s > s.txt && git add s.txt .gitignore && git -c core.hooksPath=/dev/null commit -q -m s; }
hook_report() { # hook_report AGENT BODY -> FAKE_REPORT_CMD writing a report
  export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports; printf '$2' > $WORK/.harness/reports/$1.md"
}
jl() { jq -r "$1" "$WORK/.harness/progress.jsonl" 2>/dev/null | tail -n 1; }
nlines() { wc -l < "$1" | tr -d ' '; }
logfiles() { ls "$WORK"/.harness/log/*.md 2>/dev/null; }
lastjson() { printf '%s\n' "$1" >> .harness/progress.jsonl; }
# --- log + jsonl per ask: exit 0 ----------------------------------------------------
setup
hook_report analyst '# analyst report — find things\nstatus: done\n## Open questions\n- should we X?\n'
run ask analyst "Describe the repo"
check "log: ask rc unchanged" [ "$RC" -eq 0 ]
check "log: ask stdout is the report" [ "$OUT" = "$(printf '# analyst report — find things\nstatus: done\n## Open questions\n- should we X?')" ]
check "log: one log file" [ "$(logfiles | wc -l | tr -d ' ')" -eq 1 ]
check "log: file name" logfiles | grep -Eq '/[0-9]{8}-[0-9]{6}-analyst\.md$'
check "log: has instruction" grep -q "Describe the repo" "$(logfiles | head -1)"
check "log: has report" grep -q "status: done" "$(logfiles | head -1)"
check "jsonl: one line" [ "$(nlines .harness/progress.jsonl)" -eq 1 ]
check "jsonl: agent" [ "$(jl .agent)" = analyst ]
check "jsonl: exit" [ "$(jl .exit)" = 0 ]
check "jsonl: status" [ "$(jl .status)" = done ]
check "jsonl: summary" [ "$(jl .summary)" = "analyst report — find things" ]
check "jsonl: instr" [ "$(jl .instr)" = "Describe the repo" ]
check "jsonl: session" [ "$(jl .session)" = "sess-1" ]
check "jsonl: dur_s number" [ "$(jl '.dur_s|type')" = number ]
check "jsonl: ts" jq -e '.ts|test("^[0-9]{4}-")' .harness/progress.jsonl >/dev/null
check "jsonl: verify null for analyst" [ "$(jl '.verify')" = null ]
long=$(printf 'x%.0s' $(seq 1 300))
run ask analyst "$long"
check "jsonl: instr 160 chars" [ "$(jl '.instr|length')" -eq 160 ]

# --- exit 3 (no report), exit 4 (still running) ----------------------------------------------
setup
FAKE_CLAUDE_MODE=noreport run ask analyst "q"
check "exit3: rc" [ "$RC" -eq 3 ]
check "exit3: jsonl exit" [ "$(jl .exit)" = 3 ]
setup
FAKE_CLAUDE_MODE=slow30 run ask analyst "q" --timeout 1000
check "exit4: rc" [ "$RC" -eq 4 ]
check "exit4: jsonl exit" [ "$(jl .exit)" = 4 ]
sleep 3

# --- implementer: verify field, heads, brief ------------------------------------------------
setup; gitwork
mkdir -p .harness; printf '# Task: brief title\nBRIEF-BODY-LINE\n' > .harness/task-implementer.md
export FAKE_REPORT_CMD="cd $WORK && echo c > c.txt && git add c.txt && git -c core.hooksPath=/dev/null commit -q -m c; mkdir -p .harness/reports .harness/verify; printf '# r — did it\nstatus: partial\n' > .harness/reports/implementer.md; printf '{\"status\":\"fail\",\"attempts\":3,\"step\":\"test\",\"tail\":\"\"}' > .harness/verify/implementer.json"
run ask implementer "Read .harness/task-implementer.md and do it." --no-lane
check "impl: exit 5" [ "$RC" -eq 5 ]
check "impl: jsonl exit 5" [ "$(jl .exit)" = 5 ]
check "impl: jsonl verify fail" [ "$(jl .verify)" = fail ]
check "impl: jsonl status partial" [ "$(jl .status)" = partial ]
check "impl: head_before differs from head_after" [ "$(jl .head_before)" != "$(jl .head_after)" ]
check "impl: head_after is HEAD" [ "$(jl .head_after)" = "$(git rev-parse --short HEAD)" ]
check "impl: log has brief contents" grep -q BRIEF-BODY-LINE "$(logfiles | head -1)"

# --- logging never breaks an ask ------------------------------------------------------------------
setup
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness; echo notadir > .harness/log
runerr ask analyst "q"
check "logfail: rc still 0" [ "$RC" -eq 0 ]
check "logfail: warning on stderr" grep -qi "progress" <<<"$OUT"
setup
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness; mkdir .harness/progress.jsonl
run ask analyst "q"
check "logfail2: rc still 0" [ "$RC" -eq 0 ]

# --- progress.md ------------------------------------------------------------------------------------------
setup; gitwork
hook_report analyst '# analyst report — first thing\nstatus: done\n## Open questions\n- should we X?\n- none\n'
run ask analyst "one"
check "md: exists" [ -f .harness/progress.md ]
check "md: title" head -1 .harness/progress.md | grep -q "^# Progress — $(basename "$WORK")"
check "md: goal unset" grep -qx 'Goal: (unset)' .harness/progress.md
check "md: ask line" grep -q "analyst exit 0 .* — analyst report — first thing" .harness/progress.md
check "md: open questions" grep -q -- "- should we X?" .harness/progress.md
check "md: open questions skip none" not_grep -x -- "- none" .harness/progress.md
check "md: workers line" grep -q "analyst idle" .harness/progress.md
printf 'Ship the thing.\nSecond line.\n' > .harness/goal.md
hook_report analyst '# analyst report — second thing\nstatus: done\n'
run ask analyst "two"
check "md: goal shown" grep -qx 'Goal: Ship the thing. Second line.' .harness/progress.md
check "md: newest first" [ "$(grep -n 'second thing' .harness/progress.md | head -1 | cut -d: -f1)" -lt "$(grep -n 'first thing' .harness/progress.md | head -1 | cut -d: -f1)" ]
# cap: 40 prior lines -> 15 recent, <= 60 lines
i=0; while [ $i -lt 40 ]; do
  echo '{"ts":"2026-10-18T00:00:00Z","agent":"analyst","exit":0,"verify":null,"head_before":"a","head_after":"b","summary":"old","status":"done"}' >> .harness/progress.jsonl; i=$((i+1)); done
run ask analyst "three"
check "md: <= 60 lines" [ "$(nlines .harness/progress.md)" -le 60 ]
check "md: max 15 recent asks" [ "$(grep -c '^- 20' .harness/progress.md)" -eq 15 ]

# --- rotation -----------------------------------------------------------------------------------------------------
setup
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness/log
i=1; while [ $i -le 205 ]; do : > ".harness/log/20261001-000000-analyst-$i.md"; i=$((i+1)); done
run ask analyst "q"
check "rotate: newest 200 kept" [ "$(logfiles | wc -l | tr -d ' ')" -eq 200 ]
check "rotate: new log kept" [ "$(ls .harness/log | grep -c -- '-analyst.md$')" -ge 1 ]
setup
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness/log
: > .harness/log/20200101-000000-analyst.md; touch -t 202001010000 .harness/log/20200101-000000-analyst.md
: > .harness/log/20261001-000000-analyst.md
run ask analyst "q"
check "rotate: old by mtime deleted" [ ! -e .harness/log/20200101-000000-analyst.md ]
check "rotate: recent kept" [ -e .harness/log/20261001-000000-analyst.md ]
setup
hook_report analyst '# r\nstatus: done\n'
export HARNESS_JSONL_MAX=300
mkdir -p .harness
i=0; while [ $i -lt 10 ]; do echo '{"ts":"2026-10-18T00:00:00Z","agent":"analyst","exit":0,"summary":"padding padding padding"}' >> .harness/progress.jsonl; i=$((i+1)); done
run ask analyst "q"
check "rotate: jsonl gz exists" [ "$(ls .harness/progress.jsonl.*.gz 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
check "rotate: gz has old lines" [ "$(gzip -dc .harness/progress.jsonl.*.gz | wc -l | tr -d ' ')" -eq 10 ]
check "rotate: new jsonl has only new line" [ "$(nlines .harness/progress.jsonl)" -eq 1 ]

# --- usage errors inside the ask are logged (exit 1) ---------------------------------------
for bad in "--fresh --keep" "--timeout abc" "--timeout 0" "--bogus" "--worktree" "--base x" "--via x"; do
  setup
  runerr ask analyst "q" $bad
  check "usage ($bad): rc 1" [ "$RC" -eq 1 ]
  check "usage ($bad): progress line exit 1" [ "$(jl .exit)" = 1 ]
  check "usage ($bad): nothing sent" not_logged "claude: "
done
# --- signals: the ask wrapper ends with the real signal exit, logs it; the detached run survives (lib/harness-headless.sh hl_spawn_bg) -------------------------
sigtest() { # sigtest SIGNAL — start a slow ask, signal the wrapper while it waits
  setup
  FAKE_CLAUDE_MODE=slow300 PATH="$FAKE_BIN:$HERE/../bin:$PATH" env -u HERDR_ENV -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "long" > "$WORK/sig.out" 2>/dev/null &
  KP=$!
  i=0; while [ $i -lt 100 ] && [ ! -s "$FAKE_DIR/claude.pid" ]; do sleep 0.1; i=$((i+1)); done
  GC=$(cat "$FAKE_DIR/claude.pid" 2>/dev/null)
  kill -"$1" "$KP"; wait "$KP"; KRC=$?
  sleep 0.5
}
sigtest HUP
check "HUP: rc 129" [ "$KRC" -eq 129 ]
check "HUP: jsonl exit 129" [ "$(jl .exit)" = 129 ]
check "HUP: run survives the wrapper" kill -0 "$GC"
kill "$GC" 2>/dev/null   # do not leak the fake run
sigtest TERM
check "TERM: rc 143" [ "$KRC" -eq 143 ]
check "TERM: jsonl exit 143" [ "$(jl .exit)" = 143 ]
check "TERM: run survives the wrapper" kill -0 "$GC"
kill "$GC" 2>/dev/null   # do not leak the fake run
check "TERM: log written" [ "$(logfiles | wc -l | tr -d ' ')" -eq 1 ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
