#!/bin/bash
# Headless background runs: harness ask starts harness-run detached in the background. Run: /bin/bash tests/headless-bg.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
FAKE_CLAUDE="$HERE/fake-claude"
RUNPIDS=$(mktemp)
trap 'for p in $(cat "$RUNPIDS" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -f "$RUNPIDS"; cd / && for d in $WORKS; do rm -rf "$d"; done' EXIT

# nrun ARGS... -> OUT, RC
nrun() {
  OUT=$(env -u HARNESS_ROLE \
    HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=10 \
    PATH="$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm($ENV{HRUN_ALARM_S} || 60);exec(@ARGV)' \
    /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
bsetup() {
  setup
  export FAKE_CLAUDE_MODE=success
  export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# analyst report\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
}
jqt() { jq -e "$@" >/dev/null; }
# live_runs RID — pids whose command line carries this run id (empty RID matches nothing)
live_runs() { [ -n "${1:-}" ] || return 0; pgrep -f "harness-run analyst $1 "; }
wait_no_runs() { local i=0; while [ $i -lt "${2:-150}" ] && [ -n "$(live_runs "$1")" ]; do sleep 0.1; i=$((i + 1)); done; }
# note_run — remember the runner of the current ask for the EXIT trap; sets RID RPID
note_run() {
  local i=0
  while [ $i -lt 100 ] && [ ! -s .harness/asks/analyst.pid ]; do sleep 0.1; i=$((i + 1)); done
  RID=$(awk 'NR == 1 { print $1 }' .harness/asks/analyst.pid 2>/dev/null); RPID=$(awk 'NR == 1 { print $2 }' .harness/asks/analyst.pid 2>/dev/null)
  [ -z "$RPID" ] || echo "$RPID" >> "$RUNPIDS"
}

# 1. bg success
bsetup
nrun ask analyst "q1"
check "bg success: rc 0" [ "$RC" -eq 0 ]
check "bg success: report printed" grep -q "analyst report" <<<"$OUT"
check "bg success: .stream written" grep -q "^[^ ]* .*\.jsonl$" .harness/asks/analyst.stream
check "bg success: exit.json rc 0" jqt '.rc == 0' .harness/asks/analyst.exit.json
check "bg success: runner log kept under .harness" [ -e .harness/asks/analyst.runner.log ]
nrun status
check "status after a run: idle" grep -Eq "^analyst +idle +hl" <<<"$OUT"

# 2. detachment + 3. environment
bsetup
export FAKE_CLAUDE_MODE=slow30 FAKE_ENV_DUMP="$WORK/env.dump"
MYPG=$(ps -o pgid= -p $$ | tr -d ' ')
( env -u HARNESS_ROLE CLAUDECODE=1 CLAUDE_CODE_AGENT=conductor CLAUDE_CODE_ENTRYPOINT=cli \
    HARNESS_POLL_SEC=0.2 \
    PATH="$FAKE_CLAUDE:$HERE/../bin:$PATH" /bin/bash "$HARNESS" ask analyst "q2" >"$WORK/ask.out" 2>&1 ) &
ASKPID=$!
note_run
check "detached: runner pid known" [ -n "$RPID" ]
PP=$(ps -o ppid= -p "$RPID" | tr -d ' '); PG=$(ps -o pgid= -p "$RPID" | tr -d ' ')
check "detached: runner ppid is 1" [ "$PP" = 1 ]
ok=0; [ -n "$PG" ] && [ "$PG" != "$MYPG" ] && ok=1
check "detached: runner pgid differs from the test shell" [ "$ok" = 1 ]
check "detached: runner leads its own session (pgid == pid)" [ "$PG" = "$RPID" ]
echo "detach evidence: runner pid $RPID ppid $PP pgid $PG (test shell pgid $MYPG)" >&2
wait "$ASKPID"
check "detached: ask rc 0" [ "$?" -eq 0 ]
OUT=$(cat "$WORK/ask.out")
check "env: dump written" [ -s "$WORK/env.dump" ]
check "env: no CLAUDECODE" not_grep "^CLAUDECODE=" "$WORK/env.dump"
check "env: no CLAUDE_CODE_AGENT" not_grep "^CLAUDE_CODE_AGENT=" "$WORK/env.dump"
check "env: no CLAUDE_CODE_ENTRYPOINT" not_grep "^CLAUDE_CODE_ENTRYPOINT=" "$WORK/env.dump"
check "env: HARNESS_ROLE=worker" grep -qx "HARNESS_ROLE=worker" "$WORK/env.dump"
check "env: PATH passes through" grep -q "^PATH=" "$WORK/env.dump"
unset FAKE_ENV_DUMP

# 6. status while running + 7. close refused / --force kills
bsetup
export FAKE_CLAUDE_MODE=hang
HRUN_ALARM_S=8 nrun ask analyst "q6" --timeout 3000
check "hang: ask times out with exit 4" [ "$RC" -eq 4 ]
note_run
nrun status
check "status while running" grep -Eq "^analyst +running +hl" <<<"$OUT"
nrun close analyst
check "close without --force refused (4)" [ "$RC" -eq 4 ]
check "close refused: run still alive" [ -n "$(live_runs "$RID")" ]
nrun close analyst --force
check "close --force rc 0" [ "$RC" -eq 0 ]
wait_no_runs "$RID"
check "close --force: no run left" [ -z "$(live_runs "$RID")" ]
check "close --force: exit.json killed signal" jqt '.killed == "signal"' .harness/asks/analyst.exit.json
nrun status
check "status after close: -" grep -Eq "^analyst +-$" <<<"$OUT"
check "close --force logged" grep -q '"event":"close".*"reason":"force_kill"' .harness/progress.jsonl

# 8. an interrupted ask leaves the run alive; a later report collects it
bsetup
export FAKE_CLAUDE_MODE=slow40
env -u HARNESS_ROLE HARNESS_POLL_SEC=0.2 \
    PATH="$FAKE_CLAUDE:$HERE/../bin:$PATH" /bin/bash "$HARNESS" ask analyst "q8" >"$WORK/ask.out" 2>&1 &
ASKPID=$!   # the harness ask itself (no wrapper subshell): TERM reaches it
note_run
kill -TERM "$ASKPID" 2>/dev/null; wait "$ASKPID" 2>/dev/null
check "interrupted: the ask died before collecting" not_grep "analyst report" "$WORK/ask.out"
check "interrupted: run survives the ask" [ -n "$(live_runs "$RID")" ]
i=0; while [ $i -lt 100 ] && [ ! -f .harness/asks/analyst.exit.json ]; do sleep 0.1; i=$((i + 1)); done
nrun report analyst
check "interrupted: report collects it" grep -q "analyst report" <<<"$OUT"
check "interrupted: report rc 0" [ "$RC" -eq 0 ]

tty_run() {
  env -u HARNESS_ROLE NO_COLOR=1 \
    HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=10 \
    PATH="$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm($ENV{HRUN_ALARM_S} || 60);exec(@ARGV)' \
    script -q /dev/null /bin/bash "$HARNESS" "$@" >"$WORK/tty.out" 2>&1 </dev/null
  RC=$?
  OUT=$(tr -d '\r' <"$WORK/tty.out")
}

# no-perl fallback launcher still runs the ask
bsetup
HARNESS_HL_NO_PERL=1 nrun ask analyst "q12"
check "no perl: rc 0" [ "$RC" -eq 0 ]
check "no perl: report printed" grep -q "analyst report" <<<"$OUT"

# 13. harness wait: 0 after completion, 4 on timeout, 3 when the runner is SIGKILLed; it never collects
bsetup
nrun ask analyst "q13a"
check "wait: setup ask ok" [ "$RC" -eq 0 ]
nrun wait analyst
check "wait done: rc 0" [ "$RC" -eq 0 ]
check "wait done: one line, collect hint" bash -c '[ "$1" = "done; collect: harness report analyst" ]' _ "$OUT"
nrun wait analyst
check "wait is idempotent: rc 0 again" [ "$RC" -eq 0 ]
check "wait does not collect (report untouched)" [ -f .harness/reports/analyst.md ]
nrun wait nosuchthing
check "wait: unknown target rc 1" [ "$RC" -eq 1 ]
bsetup
nrun wait analyst
check "wait: no ask rc 3" [ "$RC" -eq 3 ]
export FAKE_CLAUDE_MODE=slow60
nrun ask analyst "q13b" --timeout 1000
check "wait: slow ask left running (4)" [ "$RC" -eq 4 ]
note_run
nrun wait analyst --timeout 500
check "wait --timeout 500: rc 4 while running" [ "$RC" -eq 4 ]
check "wait timeout names the way on" grep -q "still running" <<<"$OUT"
nrun report analyst
check "report while running: exit 4, says how to wait" bash -c '[ "$1" = 4 ] && grep -q "still running (.*s); harness wait analyst blocks until done" <<<"$2"' _ "$RC" "$OUT"
nrun wait analyst
check "wait blocks until the run ends: rc 0" [ "$RC" -eq 0 ]
wait_no_runs "$RID"
bsetup
export FAKE_CLAUDE_MODE=hang
nrun ask analyst "q13c" --timeout 1000
check "wait kill: hung ask left running (4)" [ "$RC" -eq 4 ]
note_run
kill -KILL "$RPID" 2>/dev/null
nrun wait analyst --timeout 30000
check "wait after kill -KILL of the runner: rc 3" [ "$RC" -eq 3 ]
wait_no_runs "$RID"
for p in $(cat "$FAKE_DIR/claude.pids" 2>/dev/null); do kill "$p" 2>/dev/null; done

# 14. harness watch: tty only; finished run -> last lines rendered; live run -> followed to the end
bsetup
nrun ask analyst "q14"
check "watch: setup ask ok" [ "$RC" -eq 0 ]
nrun watch analyst
check "watch without a tty: refused rc 1" bash -c '[ "$1" = 1 ] && grep -q "human terminal" <<<"$2"' _ "$RC" "$OUT"
HRUN_ALARM_S=4 tty_run watch analyst   # stays alive on the final frame: only the alarm ends it
check "watch finished (tty): final dashboard frame, still alive until killed" bash -c '[ "$1" = 142 ] && grep -q "── Result ── ■ success" <<<"$2"' _ "$RC" "$OUT"
tty_run watch analyst -n 100
check "watch finished -n (tty): rendered lines, exits" bash -c '[ "$1" = 0 ] && grep -q "▶ fake-model" <<<"$2" && grep -q "■ success" <<<"$2" && grep -q "→ Bash echo hi" <<<"$2"' _ "$RC" "$OUT"
tty_run watch analyst -n 1
check "watch -n 1: one line" bash -c '[ "$(grep -c "■ success" <<<"$1")" = 1 ] && ! grep -q "fake-model" <<<"$1" && grep -q "■ success" <<<"$1"' _ "$OUT"
bsetup
export FAKE_CLAUDE_MODE=slow40
nrun ask analyst "q14b" --timeout 1000
check "watch live: slow ask left running (4)" [ "$RC" -eq 4 ]
note_run
HRUN_ALARM_S=47 tty_run watch analyst   # the final frame stays alive: the alarm (142) ends it
check "watch live: dashboard follows the run to its final frame, then stays alive" bash -c '[ "$1" = 142 ] && grep -q "── Brief ──" <<<"$2" && grep -q "── Result ── ■ success" <<<"$2"' _ "$RC" "$OUT"
wait_no_runs "$RID"

# 15. sleep-aware deadline: pure helper, injected timestamps
HL_SRC=$(sed -n '/^hl_clock_gap() {/,/^}/p;/^hl_deadline_bump() {/,/^}/p' "$HERE/../lib/harness-headless.sh")
gapchk() { /bin/bash -c "$HL_SRC"'
  [ "$(hl_clock_gap 100 102 2)" = 0 ] || exit 1
  [ "$(hl_clock_gap 100 115 2)" = 0 ] || exit 2
  [ "$(hl_clock_gap 100 116 2)" = 16 ] || exit 3
  [ "$(hl_clock_gap 100 1000 2)" = 900 ] || exit 4
  [ "$(hl_deadline_bump 100 102 2 500 2>&1)" = 500 ] || exit 5
  [ "$(hl_deadline_bump 100 1000 2 1500 2>/dev/null)" = 2400 ] || exit 6
  hl_deadline_bump 100 1000 2 1500 2>&1 >/dev/null | grep -q "clock jumped 900s (sleep?); deadline extended" || exit 7
  [ "$(hl_deadline_bump 100 1000 2 1500 300 1500 2>/dev/null)" = 1800 ] || exit 8
  [ "$(hl_deadline_bump 100 1000 2 2400 500 1500 2>/dev/null)" = 2500 ] || exit 9
  [ "$(hl_deadline_bump 100 1000 2 2100 300 1500 2>/dev/null)" = 2100 ] || exit 10
  hl_deadline_bump 100 1000 2 1500 300 1500 2>&1 >/dev/null | grep -q "clock jumped 300s" || exit 11
  exit 0'; }
gapchk; grc=$?
OUT="gap helper rc $grc"
check "clock gap: below threshold no extension, above extends by the gap, one stderr line" [ "$grc" -eq 0 ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
