#!/bin/bash
# Headless runs without herdr (v24 PR 1): harness ask with no usable herdr
# starts harness-run detached in the background. Run: /bin/bash tests/headless-bg.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
FAKE_CLAUDE="$HERE/fake-claude"
RUNPIDS=$(mktemp)
trap 'for p in $(cat "$RUNPIDS" 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -f "$RUNPIDS"; cd / && for d in $WORKS; do rm -rf "$d"; done' EXIT

# a herdr that must never run: logs and exits 99
NOHERDR=$(mktemp -d); WORKS="$WORKS $NOHERDR"
cat > "$NOHERDR/herdr" <<'EOS'
#!/bin/bash
echo "herdr $*" >> "${NOHERDR_CALLS:?}"
exit 99
EOS
chmod +x "$NOHERDR/herdr"

# nrun ARGS... -> OUT, RC: no herdr in the environment (HERDR_* unset), a trap herdr on PATH
nrun() {
  OUT=$(env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HARNESS_ROLE -u HARNESS_VIEWER \
    NOHERDR_CALLS="$WORK/herdr.calls" HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=10 \
    PATH="$NOHERDR:$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm($ENV{HRUN_ALARM_S} || 60);exec(@ARGV)' \
    /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
bsetup() {
  setup
  : > "$WORK/herdr.calls"
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
no_herdr_calls() { [ ! -s "$WORK/herdr.calls" ]; }

# 1. bg success
bsetup
nrun ask analyst "q1"
check "bg success: rc 0" [ "$RC" -eq 0 ]
check "bg success: report printed" grep -q "analyst report" <<<"$OUT"
check "bg success: note on stderr" grep -q "running analyst in the background" <<<"$OUT"
check "bg success: herdr never called" no_herdr_calls
check "bg success: .run viewer=bg" grep -qx "viewer=bg" .harness/asks/analyst.run
check "bg success: .stream written" grep -q "^[^ ]* .*\.jsonl$" .harness/asks/analyst.stream
check "bg success: exit.json rc 0" jqt '.rc == 0' .harness/asks/analyst.exit.json
check "bg success: runner log kept under .harness" [ -e .harness/asks/analyst.runner.log ]
nrun status
check "status without a pane: idle bg" grep -Eq "^analyst +idle +bg +hl" <<<"$OUT"

# 2. detachment + 3. environment
bsetup
export FAKE_CLAUDE_MODE=slow30 FAKE_ENV_DUMP="$WORK/env.dump"
MYPG=$(ps -o pgid= -p $$ | tr -d ' ')
( env -u HERDR_ENV -u HARNESS_ROLE CLAUDECODE=1 CLAUDE_CODE_AGENT=conductor CLAUDE_CODE_ENTRYPOINT=cli \
    HERDR_PANE_ID=w1:p1 HERDR_SOCKET_PATH=/nowhere NOHERDR_CALLS="$WORK/herdr.calls" HARNESS_POLL_SEC=0.2 \
    PATH="$NOHERDR:$FAKE_CLAUDE:$HERE/../bin:$PATH" /bin/bash "$HARNESS" ask analyst "q2" >"$WORK/ask.out" 2>&1 ) &
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
check "env: no HERDR_*" not_grep "^HERDR_" "$WORK/env.dump"
check "env: no CLAUDECODE" not_grep "^CLAUDECODE=" "$WORK/env.dump"
check "env: no CLAUDE_CODE_AGENT" not_grep "^CLAUDE_CODE_AGENT=" "$WORK/env.dump"
check "env: no CLAUDE_CODE_ENTRYPOINT" not_grep "^CLAUDE_CODE_ENTRYPOINT=" "$WORK/env.dump"
check "env: HARNESS_ROLE=worker" grep -qx "HARNESS_ROLE=worker" "$WORK/env.dump"
check "env: PATH passes through" grep -q "^PATH=" "$WORK/env.dump"
unset FAKE_ENV_DUMP

# 4. a failed split falls back to the background (auto and explicit viewer=pane)
bsetup
touch "$FAKE_DIR/split_fail"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=10 \
  PATH="$FAKE_BIN:$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm(60);exec(@ARGV)' env -u HARNESS_ROLE -u HARNESS_VIEWER /bin/bash "$HARNESS" ask analyst "q4" 2>&1); RC=$?
check "auto: split failure falls back, rc 0" [ "$RC" -eq 0 ]
check "auto: note printed" grep -q "running analyst in the background" <<<"$OUT"
check "auto: run is bg" grep -qx "viewer=bg" .harness/asks/analyst.run
check "auto: no pane run attempted" not_logged "pane run"
bsetup
touch "$FAKE_DIR/split_fail"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_VIEWER=pane HARNESS_POLL_SEC=0.2 \
  PATH="$FAKE_BIN:$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm(60);exec(@ARGV)' env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "q4b" 2>&1); RC=$?
check "viewer=pane: split failure falls back to bg, rc 0" [ "$RC" -eq 0 ]
check "viewer=pane: split failure note" grep -q "running analyst in the background" <<<"$OUT"

# 5. viewer=none with herdr available: no pane at all
bsetup
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_VIEWER=none HARNESS_POLL_SEC=0.2 \
  PATH="$FAKE_BIN:$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm(60);exec(@ARGV)' env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "q5" 2>&1); RC=$?
check "none: rc 0" [ "$RC" -eq 0 ]
check "none: no pane split" not_logged "pane split"
check "none: run is bg" grep -qx "viewer=bg" .harness/asks/analyst.run

# 6. status while running + 7. close refused / --force kills
bsetup
export FAKE_CLAUDE_MODE=hang
HRUN_ALARM_S=8 nrun ask analyst "q6" --timeout 3000
check "hang: ask times out with exit 4" [ "$RC" -eq 4 ]
note_run
nrun status
check "status while running shows bg" grep -Eq "^analyst +running +bg +hl" <<<"$OUT"
nrun close analyst
check "close without --force refused (4)" [ "$RC" -eq 4 ]
check "close refused: run still alive" [ -n "$(live_runs "$RID")" ]
nrun close analyst --force
check "close --force rc 0" [ "$RC" -eq 0 ]
wait_no_runs "$RID"
check "close --force: no run left" [ -z "$(live_runs "$RID")" ]
check "close --force: exit.json killed signal" jqt '.killed == "signal"' .harness/asks/analyst.exit.json
check "close --force: no herdr call" no_herdr_calls
nrun status
check "status after close: -" grep -Eq "^analyst +-$" <<<"$OUT"
check "close --force logged with pane -" grep -q '"event":"close".*"pane":"-".*"reason":"force_kill"' .harness/progress.jsonl

# 8. an interrupted ask leaves the run alive; a later report collects it
bsetup
export FAKE_CLAUDE_MODE=slow40
env -u HERDR_ENV -u HARNESS_ROLE NOHERDR_CALLS="$WORK/herdr.calls" HARNESS_POLL_SEC=0.2 \
    PATH="$NOHERDR:$FAKE_CLAUDE:$HERE/../bin:$PATH" /bin/bash "$HARNESS" ask analyst "q8" >"$WORK/ask.out" 2>&1 &
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
  env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH -u HARNESS_ROLE NO_COLOR=1 \
    NOHERDR_CALLS="$WORK/herdr.calls" HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=10 \
    PATH="$NOHERDR:$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm($ENV{HRUN_ALARM_S} || 60);exec(@ARGV)' \
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
tty_run watch analyst
check "watch finished (tty): rendered lines" bash -c 'grep -q "▶ fake-model" <<<"$1" && grep -q "■ success" <<<"$1" && grep -q "→ Bash echo hi" <<<"$1"' _ "$OUT"
tty_run watch analyst -n 1
check "watch -n 1: one line" bash -c '[ "$(grep -c "■ success" <<<"$1")" = 1 ] && ! grep -q "fake-model" <<<"$1" && grep -q "■ success" <<<"$1"' _ "$OUT"
bsetup
export FAKE_CLAUDE_MODE=slow40
nrun ask analyst "q14b" --timeout 1000
check "watch live: slow ask left running (4)" [ "$RC" -eq 4 ]
note_run
tty_run watch analyst
check "watch live: follows the run to its result, rc 0" bash -c '[ "$1" = 0 ] && grep -q "■ success" <<<"$2"' _ "$RC" "$OUT"
wait_no_runs "$RID"
check "watch live: no tail left behind" bash -c '! pgrep -f "tail -n \+1 -F .*analyst" >/dev/null'

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
