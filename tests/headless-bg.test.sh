#!/bin/bash
# Headless runs without herdr (v24 PR 1): harness ask with runner=headless and no usable herdr
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
  export HARNESS_RUNNER_ANALYST=headless HARNESS_RUNNER_REVIEWER=headless FAKE_CLAUDE_MODE=success
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
check "bg success: .harness/panes untouched" [ ! -s .harness/panes ]
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
check "detached: runner pgid differs from the test shell" [ -n "$PG" ] && [ "$PG" != "$MYPG" ]
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

# 4. auto fallback to the background on a failed split; explicit viewer=pane keeps exit 1
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
check "viewer=pane: split failure exits 1" [ "$RC" -eq 1 ]
check "viewer=pane: no background run" [ ! -e .harness/asks/analyst.pid ] && [ ! -e .harness/asks/analyst.exit.json ]

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

# 11. TTL reap with no pane
bsetup
nrun ask analyst "q11"
check "ttl: setup ask ok" [ "$RC" -eq 0 ]
check "ttl: .finished stamped" [ -f .harness/asks/analyst.finished ]
check "ttl: .session present before" [ -f .harness/asks/analyst.session ]
touch -t 199912312300 .harness/asks/analyst.current; touch -t 200001010000 .harness/reports/analyst.md; touch -t 200001010100 .harness/asks/analyst.finished
HARNESS_IDLE_TTL_MINUTES=1 nrun status
check "ttl: .session dropped" [ ! -e .harness/asks/analyst.session ]
check "ttl: .finished dropped" [ ! -e .harness/asks/analyst.finished ]
check "ttl: close event pane - reason ttl" grep -q '"event":"close".*"pane":"-".*"reason":"ttl"' .harness/progress.jsonl
check "ttl: herdr never called" no_herdr_calls

# 9. close_after_ask on_success closes a background run (no pane to close)
bsetup
HARNESS_CLOSE_AFTER_ASK_ANALYST=on_success nrun ask analyst "q9"
check "on_success: rc 0" [ "$RC" -eq 0 ]
check "on_success: closed (bg)" grep -q "closed analyst (bg)" <<<"$OUT"
check "on_success: .session gone" [ ! -e .harness/asks/analyst.session ]
check "on_success: close event pane - reason after_ask" grep -q '"event":"close".*"pane":"-".*"reason":"after_ask"' .harness/progress.jsonl
check "on_success: herdr never called" no_herdr_calls

# 10. a --worktree ask runs in the background without herdr
bsetup
git init -q . && git config user.email t@t && git config user.name t
echo one > a.txt && git add a.txt && git commit -qm one
mkdir -p .git/info && echo '.harness/' >> .git/info/exclude
WTROOT="$WORK.wt"; WORKS="$WORKS $WTROOT"
export HARNESS_WT_ROOT="$WTROOT" HARNESS_NO_AUTOCLOSE=1
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md"
nrun ask analyst "q10" --worktree
check "worktree bg: rc 0" [ "$RC" -eq 0 ]
check "worktree bg: report printed" grep -q "analyst report" <<<"$OUT"
check "worktree bg: herdr never called" no_herdr_calls
check "worktree bg: checkout removed" [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ]
check "worktree bg: registry pane empty" bash -c 'for f in .harness/wt/*.json; do [ -e "$f" ] || exit 1; jq -e "(.pane // \"\") == \"\"" "$f" >/dev/null || exit 1; done'
unset HARNESS_WT_ROOT HARNESS_NO_AUTOCLOSE

# no-perl fallback launcher still runs the ask
bsetup
HARNESS_HL_NO_PERL=1 nrun ask analyst "q12"
check "no perl: rc 0" [ "$RC" -eq 0 ]
check "no perl: report printed" grep -q "analyst report" <<<"$OUT"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
