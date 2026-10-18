#!/bin/bash
# Tests for the progress log, rotation, ctx reading and worker context reset in
# bin/harness (against tests/fake-herdr). Run: /bin/bash tests/progress.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
FAKE_BIN="$HERE/fake-herdr"
pass=0
fail=0

WORKS=""
trap 'cd / && for d in $WORKS; do rm -rf "$d"; done' EXIT
setup() {
  WORK=$(mktemp -d)
  WORKS="$WORKS $WORK"
  export FAKE_DIR="$WORK/fake" FAKE_LOG="$WORK/herdr.log"
  export HARNESS_PROJECTS_DIR="$WORK/projects"
  export HARNESS_CLEAR_INTERVAL=0 HARNESS_CLEAR_POLLS=3
  mkdir -p "$FAKE_DIR"
  : > "$FAKE_LOG"
  unset FAKE_PROMPT_HOOK FAKE_CLEAR HARNESS_CTX_RESET HARNESS_LOG_KEEP HARNESS_LOG_DAYS HARNESS_JSONL_MAX
  cd "$WORK" || exit 1
  printf 'fake/\nherdr.log\nprojects/\n' > .gitignore
}

GUARD="perl -e alarm(10);exec(@ARGV)"
run() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD /bin/bash "$HARNESS" "$@" 2>/dev/null)
  RC=$?
}
# runerr: same, stdout+stderr merged
runerr() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi; }
logged() { grep -qF -- "$1" "$FAKE_LOG"; }
not_grep() { ! grep "$@"; }
not_logged() { ! grep -qF -- "$1" "$FAKE_LOG"; }
gitwork() { git init -q . && git config user.email t@t && git config user.name t && echo s > s.txt && git add s.txt .gitignore && git -c core.hooksPath=/dev/null commit -q -m s; }
hook_report() { # hook_report AGENT BODY -> FAKE_PROMPT_HOOK writing a report
  export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '$2' > $WORK/.harness/reports/$1.md"
}
jl() { jq -r "$1" "$WORK/.harness/progress.jsonl" 2>/dev/null | tail -n 1; }
nlines() { wc -l < "$1" | tr -d ' '; }
logfiles() { ls "$WORK"/.harness/log/*.md 2>/dev/null; }
# the encoding rule lives in bin/harness (project_dir_name), reached via _projdir
projdir() { echo "$HARNESS_PROJECTS_DIR/$(HERDR_ENV=1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" /bin/bash "$HARNESS" _projdir)"; }
lastjson() { printf '%s\n' "$1" >> .harness/progress.jsonl; }
# transcript SESSION CACHE_READ [CREATE] [INPUT]
transcript() {
  mkdir -p "$(projdir)"
  { printf '{"type":"user","message":{"content":"hi"}}\n'
    printf '{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' "${4:-2}" "${3:-0}" "$2"
    printf '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":999999}}}\n'
    printf 'not json\n'
  } > "$(projdir)/$1.jsonl"
}

# --- log + jsonl per ask: exit 0 ----------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
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
check "jsonl: session" [ "$(jl .session)" = "sess-analyst-0" ]
check "jsonl: dur_s number" [ "$(jl '.dur_s|type')" = number ]
check "jsonl: ts" jq -e '.ts|test("^[0-9]{4}-")' .harness/progress.jsonl >/dev/null
check "jsonl: verify null for analyst" [ "$(jl '.verify')" = null ]
long=$(printf 'x%.0s' $(seq 1 300))
run ask analyst "$long"
check "jsonl: instr 160 chars" [ "$(jl '.instr|length')" -eq 160 ]

# --- exit 3 (no report): screen tail in log ----------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
run ask analyst "q"
check "exit3: rc" [ "$RC" -eq 3 ]
check "exit3: jsonl exit" [ "$(jl .exit)" = 3 ]
check "exit3: log has screen" grep -q "fake screen line" "$(logfiles | head -1)"

# --- exit 2 (blocked), exit 4 (busy) ---------------------------------------------------------
setup
echo blocked > "$FAKE_DIR/live.analyst"
run ask analyst "q"
check "exit2: rc" [ "$RC" -eq 2 ]
check "exit2: jsonl exit" [ "$(jl .exit)" = 2 ]
setup
echo working > "$FAKE_DIR/live.analyst"
run ask analyst "q"
check "exit4: rc" [ "$RC" -eq 4 ]
check "exit4: jsonl exit" [ "$(jl .exit)" = 4 ]

# --- implementer: verify field, heads, brief ------------------------------------------------
setup; gitwork
echo idle > "$FAKE_DIR/live.implementer"
mkdir -p .harness; printf '# Task: brief title\nBRIEF-BODY-LINE\n' > .harness/task-implementer.md
export FAKE_PROMPT_HOOK="cd $WORK && echo c > c.txt && git add c.txt && git -c core.hooksPath=/dev/null commit -q -m c; mkdir -p .harness/reports .harness/verify; printf '# r — did it\nstatus: partial\n' > .harness/reports/implementer.md; printf '{\"status\":\"fail\",\"attempts\":3,\"step\":\"test\",\"tail\":\"\"}' > .harness/verify/implementer.json"
run ask implementer "Read .harness/task-implementer.md and do it."
check "impl: exit 5" [ "$RC" -eq 5 ]
check "impl: jsonl exit 5" [ "$(jl .exit)" = 5 ]
check "impl: jsonl verify fail" [ "$(jl .verify)" = fail ]
check "impl: jsonl status partial" [ "$(jl .status)" = partial ]
check "impl: head_before differs from head_after" [ "$(jl .head_before)" != "$(jl .head_after)" ]
check "impl: head_after is HEAD" [ "$(jl .head_after)" = "$(git rev-parse --short HEAD)" ]
check "impl: log has brief contents" grep -q BRIEF-BODY-LINE "$(logfiles | head -1)"

# --- logging never breaks an ask ------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness; echo notadir > .harness/log
runerr ask analyst "q"
check "logfail: rc still 0" [ "$RC" -eq 0 ]
check "logfail: warning on stderr" grep -qi "progress" <<<"$OUT"
setup
echo idle > "$FAKE_DIR/live.analyst"
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness; mkdir .harness/progress.jsonl
run ask analyst "q"
check "logfail2: rc still 0" [ "$RC" -eq 0 ]

# --- progress.md ------------------------------------------------------------------------------------------
setup; gitwork
echo idle > "$FAKE_DIR/live.analyst"
hook_report analyst '# analyst report — first thing\nstatus: done\n## Open questions\n- should we X?\n- none\n'
run ask analyst "one"
check "md: exists" [ -f .harness/progress.md ]
check "md: title" head -1 .harness/progress.md | grep -q "^# Progress — $(basename "$WORK")"
check "md: goal unset" grep -qx 'Goal: (unset)' .harness/progress.md
check "md: ask line" grep -q "analyst exit 0 .* — analyst report — first thing" .harness/progress.md
check "md: open questions" grep -q -- "- should we X?" .harness/progress.md
check "md: open questions skip none" not_grep -qx -- "- none" .harness/progress.md
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
echo idle > "$FAKE_DIR/live.analyst"
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness/log
i=1; while [ $i -le 205 ]; do : > ".harness/log/20261001-000000-analyst-$i.md"; i=$((i+1)); done
run ask analyst "q"
check "rotate: newest 200 kept" [ "$(logfiles | wc -l | tr -d ' ')" -eq 200 ]
check "rotate: new log kept" [ "$(ls .harness/log | grep -c -- '-analyst.md$')" -ge 1 ]
setup
echo idle > "$FAKE_DIR/live.analyst"
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness/log
: > .harness/log/20200101-000000-analyst.md; touch -t 202001010000 .harness/log/20200101-000000-analyst.md
: > .harness/log/20261001-000000-analyst.md
run ask analyst "q"
check "rotate: old by mtime deleted" [ ! -e .harness/log/20200101-000000-analyst.md ]
check "rotate: recent kept" [ -e .harness/log/20261001-000000-analyst.md ]
setup
echo idle > "$FAKE_DIR/live.analyst"
hook_report analyst '# r\nstatus: done\n'
export HARNESS_JSONL_MAX=300
mkdir -p .harness
i=0; while [ $i -lt 10 ]; do echo '{"ts":"2026-10-18T00:00:00Z","agent":"analyst","exit":0,"summary":"padding padding padding"}' >> .harness/progress.jsonl; i=$((i+1)); done
run ask analyst "q"
check "rotate: jsonl gz exists" [ "$(ls .harness/progress.jsonl.*.gz 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
check "rotate: gz has old lines" [ "$(gzip -dc .harness/progress.jsonl.*.gz | wc -l | tr -d ' ')" -eq 10 ]
check "rotate: new jsonl has only new line" [ "$(nlines .harness/progress.jsonl)" -eq 1 ]

# --- ctx reading / status column ---------------------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
echo idle > "$FAKE_DIR/live.reviewer"
echo "sess-rev" > "$FAKE_DIR/session.reviewer"
transcript sess-analyst-0 134572 2750 2
run status
check "ctx: analyst 137k" grep -Eq "^analyst +idle +w1:p2 +137k$" <<<"$OUT"
check "ctx: missing transcript -" grep -Eq "^reviewer +idle +w1:p2 +-$" <<<"$OUT"
check "ctx: dead agent line" grep -Eq "^implementer +-$" <<<"$OUT"
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q"
check "ctx: ctx_before in jsonl" [ "$(jl .ctx_before)" = 137324 ]
check "ctx: ctx_after null after the reset (new session)" [ "$(jl .ctx_after)" = null ]
setup
echo idle > "$FAKE_DIR/live.reviewer"
hook_report reviewer '# r\nVERDICT: PASS\n'
run ask reviewer "q"
check "ctx: unknown -> null" [ "$(jl .ctx_before)" = null ]

# --- context reset: implementer ---------------------------------------------------------------------------------------------------------
setup; gitwork
echo idle > "$FAKE_DIR/live.implementer"
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset impl: rc 0" [ "$RC" -eq 0 ]
check "reset impl: /clear sent" logged "agent prompt implementer /clear"
check "reset impl: no --wait on /clear" not_logged "/clear --wait"
check "reset impl: no respawn" not_logged "pane close"
check "reset impl: real prompt after clear" [ "$(grep -n 'agent prompt implementer /clear' "$FAKE_LOG" | cut -d: -f1)" -lt "$(grep -n 'agent prompt implementer do' "$FAKE_LOG" | cut -d: -f1)" ]

setup; gitwork
echo idle > "$FAKE_DIR/live.implementer"; echo w1:p5 > "$FAKE_DIR/pane.implementer"
mkdir -p .harness; echo "implementer w1:p5" > .harness/panes
export FAKE_CLEAR=stuck
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset stuck: rc 0" [ "$RC" -eq 0 ]
check "reset stuck: pane closed" logged "pane close w1:p5"
check "reset stuck: respawned" logged "agent start implementer"
check "reset stuck: ask output is the report" [ "$OUT" = "$(printf '# r\nstatus: done')" ]
unset FAKE_CLEAR

setup; gitwork
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset: fresh spawn needs no clear" not_logged "/clear"

setup; gitwork
echo idle > "$FAKE_DIR/live.implementer"
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it" --keep
check "keep: rc 0" [ "$RC" -eq 0 ]
check "keep: no clear" not_logged "/clear"

# --- context reset: analyst/reviewer threshold, --fresh ---------------------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
transcript sess-analyst-0 50000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q"
check "analyst low ctx: no clear" not_logged "/clear"
setup
echo idle > "$FAKE_DIR/live.analyst"
transcript sess-analyst-0 130000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q"
check "analyst high ctx: clear" logged "agent prompt analyst /clear"
check "analyst high ctx: ctx_before logged" [ "$(jl .ctx_before)" = 130002 ]
setup
echo idle > "$FAKE_DIR/live.analyst"
transcript sess-analyst-0 130000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q" --keep
check "analyst high ctx --keep: no clear" not_logged "/clear"
setup
echo idle > "$FAKE_DIR/live.analyst"
transcript sess-analyst-0 50000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q" --fresh
check "analyst --fresh: clear" logged "agent prompt analyst /clear"
setup
echo idle > "$FAKE_DIR/live.analyst"
transcript sess-analyst-0 50000
export HARNESS_CTX_RESET=40000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q"
check "HARNESS_CTX_RESET honoured" logged "agent prompt analyst /clear"
setup
run ask analyst "q" --fresh --keep
check "fresh+keep is a usage error" [ "$RC" -eq 1 ]

# --- reset skipped after an unclean ask ----------------------------------------------------------------------------------------------------
reset_after() { # reset_after AGENT EXIT [flag] — a logged ask with EXIT, then a new ask
  setup; gitwork
  echo idle > "$FAKE_DIR/live.$1"
  mkdir -p .harness
  lastjson "{\"ts\":\"2026-10-18T00:00:00Z\",\"agent\":\"$1\",\"exit\":$2}"
  hook_report "$1" '# r\nstatus: done\n'
  runerr ask "$1" "do it" ${3:-}
}
reset_after implementer 0
check "after exit 0: reset" logged "agent prompt implementer /clear"
for e in 3 4 5; do
  reset_after implementer $e
  check "after exit $e: no clear" not_logged "/clear"
  check "after exit $e: stderr notice" grep -qx "keeping context (last ask exit $e)" <<<"$OUT"
done
reset_after implementer 5 --fresh
check "after exit 5 --fresh: reset" logged "agent prompt implementer /clear"
setup; gitwork
echo idle > "$FAKE_DIR/live.implementer"; mkdir -p .harness
lastjson '{"ts":"t","agent":"implementer","exit":5}'
lastjson '{"ts":"t","agent":"analyst","exit":0}'
lastjson '{"ts":"t","agent":"implementer","exit":null,"late":true}'
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "other agents/late lines do not hide the last exit" not_logged "/clear"

# --- late report archived, never deleted unlogged --------------------------------------------------------------------------------
setup
echo working > "$FAKE_DIR/live.analyst"
run ask analyst "first"
check "late: first ask exit 4" [ "$RC" -eq 4 ]
echo idle > "$FAKE_DIR/live.analyst"
mkdir -p .harness/reports
printf '# LATE REPORT title\nstatus: partial\n' > .harness/reports/analyst.md
hook_report analyst '# r\nstatus: done\n'
run ask analyst "second"
check "late: archive file" [ "$(ls .harness/log/*-analyst-late.md 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
check "late: archive has the report" grep -q "LATE REPORT title" .harness/log/*-analyst-late.md
check "late: jsonl line" [ "$(jq -c 'select(.late == true) | [.exit, .status, .summary]' .harness/progress.jsonl)" = '[null,"partial","LATE REPORT title"]' ]
check "late: in progress.md" grep -q "analyst late report .* — LATE REPORT title" .harness/progress.md
# an already logged report is not archived again
run ask analyst "third"
check "logged report not archived twice" [ "$(ls .harness/log/*-analyst-late.md | wc -l | tr -d ' ')" -eq 1 ]
check "logged report: sha stored" [ -n "$(jl .report_sha | grep -v null)" ]
setup
echo idle > "$FAKE_DIR/live.analyst"
hook_report analyst '# r\nstatus: done\n'
run ask analyst "a"
run ask analyst "b"
check "normal flow: no late archive" [ "$(ls .harness/log/*-late*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]

# --- transcript dir encoding ----------------------------------------------------------------------------------------------------------------------
setup
mkdir -p "$WORK/a_b c é한.d" && cd "$WORK/a_b c é한.d" || exit 1
check "encode: every non-alnum char (not byte) is -" [ "$(projdir | sed 's#.*/##')" = "$(printf %s "$(pwd -P)" | perl -CS -pe 's/[^A-Za-z0-9]/-/g')" ]
check "encode: tail is a-b-c----d" [ "$(projdir | sed 's#.*/##' | sed 's#.*\(a-b-c-*d\)$#\1#')" = "a-b-c----d" ]
echo idle > "$FAKE_DIR/live.analyst"
transcript sess-analyst-0 134572 2750 2
run status
check "encode: ctx read in an odd cwd" grep -Eq "^analyst +idle +w1:p2 +137k$" <<<"$OUT"
cd "$WORK"

# --- ctx: whole-file scan -------------------------------------------------------------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
transcript sess-analyst-0 134572 2750 2
i=0; while [ $i -lt 400 ]; do echo '{"type":"progress","data":{}}' >> "$(projdir)/sess-analyst-0.jsonl"; i=$((i+1)); done
run status
check "ctx: assistant line beyond 200 lines back" grep -Eq "^analyst +idle +w1:p2 +137k$" <<<"$OUT"

# --- ask wrapper killed mid-wait ------------------------------------------------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
mkdir -p "$WORK/tmp"
export FAKE_PROMPT_HOOK="echo REPLAYED >> $WORK/tmp/harness-ask.*; sleep 3"
TMPDIR="$WORK/tmp" HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" /bin/bash "$HARNESS" ask analyst "long" > "$WORK/killed.out" 2>/dev/null &
KP=$!
i=0; while [ $i -lt 50 ] && ! grep -q REPLAYED "$WORK"/tmp/harness-ask.* 2>/dev/null; do sleep 0.1; i=$((i+1)); done
kill -TERM "$KP"; wait "$KP"; KRC=$?
unset FAKE_PROMPT_HOOK
OUT=$(cat "$WORK/killed.out")
check "kill: exit 143" [ "$KRC" -eq 143 ]
check "kill: stdout replayed" [ "$OUT" = REPLAYED ]
check "kill: temp file gone" [ -z "$(ls "$WORK/tmp" 2>/dev/null)" ]
check "kill: jsonl exit 143" [ "$(jl .exit)" = 143 ]
check "kill: log written" [ "$(logfiles | wc -l | tr -d ' ')" -eq 1 ]

# --- spawn env ----------------------------------------------------------------------------------------------------------------------------------------------
setup
run spawn analyst
check "spawn: auto-compact window env" logged "--env CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000"
check "spawn: role env kept" logged "--env HARNESS_ROLE=worker"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
