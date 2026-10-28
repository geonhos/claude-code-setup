#!/bin/bash
# Headless runner (decision 0007): bin/harness ask/report/close with runner=headless against
# tests/fake-herdr + tests/fake-claude. Run: /bin/bash tests/headless.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
FAKE_CLAUDE="$HERE/fake-claude"

# hrun ARGS... -> OUT, RC. Like run(), with the fake claude on PATH and a longer alarm.
hrun() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=5 \
    PATH="$FAKE_BIN:$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm($ENV{HRUN_ALARM_S} || 60);exec(@ARGV)' \
    env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
hsetup() {
  setup
  export HARNESS_RUNNER_ANALYST=headless HARNESS_RUNNER_REVIEWER=headless
  export FAKE_CLAUDE_MODE=success
  export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# analyst report\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
}
jqt() { jq -e "$@" >/dev/null; }
lastprog() { tail -n 1 .harness/progress.jsonl 2>/dev/null; }
# killpids FILE — kill exactly the pids a test recorded (no pattern kills anywhere in tests/)
killpids() { local p; for p in $(cat "$1" 2>/dev/null); do kill "$p" 2>/dev/null; done; return 0; }
# live_runs RID — pids whose command line carries this run id (empty RID matches nothing)
live_runs() { [ -n "${1:-}" ] || return 0; pgrep -f "harness-run analyst $1 "; }
# wait_no_runs <run-id> [tenths] — until no process of that run is left (the watchdog reaps the
# group in steps: claude dies first, the pipeline's subshells a moment later; 15 s cap)
wait_no_runs() { local i=0; while [ $i -lt "${2:-150}" ] && [ -n "$(live_runs "$1")" ]; do sleep 0.1; i=$((i + 1)); done; }
claude_runs() { grep -c '^claude: ' "$FAKE_LOG"; }

# 1. success
hsetup
hrun ask analyst "q1"
check "success: rc 0" [ "$RC" -eq 0 ]
check "success: report printed" grep -q "analyst report" <<<"$OUT"
check "success: no agent start" not_logged "agent start"
check "success: pane split once, plain" logged "pane split"
check "success: pane run harness-run" logged "harness-run"
check "success: claude -p stream-json" logged "--output-format stream-json"
check "success: instruction on stdin" logged "claude stdin: q1"
check "success: progress runner" jqt '.runner == "headless" and .exit == 0 and .turns == 3 and (.cost_usd > 0.01)' <<<"$(lastprog)"
check "success: progress clear none" jqt '.clear == "none"' <<<"$(lastprog)"
sl=$(lastprog | jq -r '.stream_log // empty')
check "success: stream_log exists" test -f "${sl:-/nonexistent}"
check "success: exit.json for the ask" grep -q "\"ask_id\":\"$(cut -d' ' -f1 .harness/asks/analyst.current)\"" .harness/asks/analyst.exit.json

# 2. reviewer verdicts
hsetup
export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# r\nVERDICT: FAIL\n' > $WORK/.harness/reports/reviewer.md"
hrun ask reviewer "q"
check "reviewer FAIL: rc 5" [ "$RC" -eq 5 ]
hsetup
export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# r\nno verdict\n' > $WORK/.harness/reports/reviewer.md"
hrun ask reviewer "q"
check "reviewer no verdict: rc 3" [ "$RC" -eq 3 ]

# 3. failures without a report -> 3
hsetup; export FAKE_CLAUDE_MODE=noreport
hrun ask analyst "q"
check "noreport: rc 3" [ "$RC" -eq 3 ]
check "noreport: says no report" grep -q "without a report" <<<"$OUT"
hsetup; export FAKE_CLAUDE_MODE=error
hrun ask analyst "q"
check "error: rc 3" [ "$RC" -eq 3 ]
check "error: names the result" grep -q "error_during_execution" <<<"$OUT"
hsetup; export FAKE_CLAUDE_MODE=maxturns
hrun ask analyst "q"
check "maxturns: rc 3" [ "$RC" -eq 3 ]
check "maxturns: --keep hint" grep -q -- "--keep" <<<"$OUT"

# 4. hang + close --force
hsetup; export FAKE_CLAUDE_MODE=hang
( hrun ask analyst "q" --timeout 60000; echo "$RC" > "$WORK/ask.rc"; echo "$OUT" > "$WORK/ask.out" ) &
bg=$!
i=0; while [ $i -lt 50 ] && [ ! -f .harness/asks/analyst.pid ]; do sleep 0.2; i=$((i + 1)); done
hrun close analyst
check "close live run: rc 4" [ "$RC" -eq 4 ]
check "close live run: still registered" grep -q '^analyst ' .harness/panes
hrun close analyst --force
check "close --force: rc 0" [ "$RC" -eq 0 ]
wait "$bg"
check "close --force: running ask returned 3" [ "$(cat "$WORK/ask.rc")" -eq 3 ]
check "close --force: killed signal" jqt '.killed == "signal"' .harness/asks/analyst.exit.json
check "close --force: pane closed" logged "pane close"
check "close --force: registry empty" not_grep '^analyst ' .harness/panes
sleep 0.3
check "close --force: no leftover fake claude" not kill -0 "$(cat "$FAKE_DIR/claude.pid")"
check "close --force: logged force_kill" grep -q force_kill .harness/progress.jsonl

# 5. slow run: ask times out (4), report collects later
hsetup; export FAKE_CLAUDE_MODE=slow30
hrun ask analyst "q" --timeout 1000
check "slow: rc 4" [ "$RC" -eq 4 ]
check "slow: still running message" grep -q "still running" <<<"$OUT"
hrun report analyst
check "report while running: rc 4" [ "$RC" -eq 4 ]
i=0; while [ $i -lt 50 ] && [ ! -f .harness/asks/analyst.exit.json ]; do sleep 0.2; i=$((i + 1)); done
hrun report analyst
check "report after finish: rc 0" [ "$RC" -eq 0 ]
check "report after finish: report printed" grep -q "analyst report" <<<"$OUT"
check "late line has runner" grep -q '"late":true' .harness/progress.jsonl

# 6. second ask while running -> 4, no second run
hsetup; export FAKE_CLAUDE_MODE=slow30
hrun ask analyst "q" --timeout 500
n=$(grep -c 'pane run' "$FAKE_LOG")
hrun ask analyst "q2" --timeout 500
check "busy: rc 4" [ "$RC" -eq 4 ]
check "busy: no second pane run" [ "$(grep -c 'pane run' "$FAKE_LOG")" -eq "$n" ]
sleep 4

# 7. fresh by default, --keep resumes
hsetup
hrun ask analyst "a"
hrun ask analyst "b"
check "fresh: no --resume" not_logged "--resume"
hrun ask analyst "c" --keep
check "keep: --resume sess-2 (the previous run)" logged "--resume sess-2"
check "keep: progress resume true" jqt '.resume == true' <<<"$(lastprog)"
hsetup
hrun ask analyst "a" --keep
check "keep w/o session: note" grep -q "no previous session" <<<"$OUT"
check "keep w/o session: fresh" not_logged "--resume"

# 8. pane reuse
hsetup
hrun ask analyst "a"; hrun ask analyst "b"
check "reuse: one split" [ "$(grep -c 'pane split' "$FAKE_LOG")" -eq 1 ]
touch "$FAKE_DIR/closed.w1:p2"
hrun ask analyst "c"
check "closed pane: re-split" [ "$(grep -c 'pane split' "$FAKE_LOG")" -eq 2 ]

# 9. watchdog
hsetup; export FAKE_CLAUDE_MODE=hang HARNESS_HL_MAX_S=1
hrun ask analyst "q" --timeout 30000
check "watchdog: rc 3" [ "$RC" -eq 3 ]
check "watchdog: killed:watchdog" jqt '.killed == "watchdog"' .harness/asks/analyst.exit.json
unset HARNESS_HL_MAX_S

# 10. harness-run refuses without HARNESS_ROLE=worker
hsetup
OUT=$(env -u HARNESS_ROLE PATH="$HERE/../bin:$PATH" /bin/bash "$HERE/../bin/harness-run" analyst x . 2>&1); RC=$?
check "harness-run: refuses non-worker" [ "$RC" -ne 0 ]

# 11. harness-view golden output
hsetup
OUT=$(printf '%s\n' \
  '{"type":"system","subtype":"init","model":"m1","permissionMode":"auto","cwd":"/r","session_id":"abcdef12345"}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"hello"},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}' \
  '{"type":"result","subtype":"success","is_error":false,"num_turns":2,"duration_ms":2000,"total_cost_usd":0.5,"permission_denials":[]}' \
  | NO_COLOR=1 "$HERE/../bin/harness-view" 2>&1)
check "view: init line" grep -q "▶ m1" <<<"$OUT"
check "view: text" grep -q "hello" <<<"$OUT"
check "view: tool" grep -q "→ Bash" <<<"$OUT"
check "view: result" grep -q "■ success" <<<"$OUT"
OUT=$(printf 'junk\n{"type":"x"}\n' | NO_COLOR=1 "$HERE/../bin/harness-view" 2>&1); RC=$?
check "view: tolerates junk" [ "$RC" -eq 0 ]

# 12. claude does not start
hsetup; export FAKE_CLAUDE_MODE=nostart
hrun ask analyst "q"
check "nostart: rc 1" [ "$RC" -eq 1 ]

# 13. config + env
setup
export FAKE_CLAUDE_MODE=success
unset HARNESS_RUNNER_ANALYST HARNESS_RUNNER_REVIEWER
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
hrun ask analyst "q"
check "default runner: pane (agent start)" logged "agent start"
check "default runner: no harness-run" not_logged "harness-run"
setup
mkdir -p .harness; echo '{"runner":{"analyst":"headless"}}' > .harness/config.json
export FAKE_CLAUDE_MODE=success FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# analyst report\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
unset HARNESS_RUNNER_ANALYST
hrun ask analyst "q"
check "config headless: rc 0" [ "$RC" -eq 0 ]
check "config headless: no agent start" not_logged "agent start"
setup
mkdir -p .harness; echo '{"runner":{"analyst":"headless"}}' > .harness/config.json
export HARNESS_RUNNER_ANALYST=pane FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
hrun ask analyst "q"
check "env overrides config: pane" logged "agent start"
unset HARNESS_RUNNER_ANALYST FAKE_PROMPT_HOOK

# 14. permission mode other than auto: warning; ## Run line in the ask log
hsetup; export FAKE_PERM=default
hrun ask analyst "q"
check "perm: warning printed" grep -qi "warning.*permission.*default" <<<"$OUT"
unset FAKE_PERM
hsetup
hrun ask analyst "q"
check "perm auto: no warning" not_grep "permission mode" <(printf '%s' "$OUT")
logf=$(ls .harness/log/*-analyst.md | head -n 1)
check "run line: section in the log" grep -q '^## Run' "$logf"
check "run line: result turns cost stream" grep -Eq 'result success.*turns 3.*cost.*0\.01.*stream .*\.jsonl' "$logf"

# 15. a run that dies before init: no stale session id suggested; --keep falls back explicitly
hsetup
hrun ask analyst "first"
check "stale sid: first run wrote sess-1" [ "$(cat .harness/asks/analyst.session)" = sess-1 ]
export FAKE_CLAUDE_MODE=hangpre
( hrun ask analyst "second" --timeout 60000; echo "$OUT" > "$WORK/ask2.out" ) &
bg=$!
i=0; while [ $i -lt 50 ] && ! grep -q . .harness/asks/analyst.pid 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
check "stale sid: cleared at ask start" [ ! -s .harness/asks/analyst.session ]
kill -9 "$(awk 'NR == 1 { print $2 }' .harness/asks/analyst.pid)"
killpids "$FAKE_DIR/claude.pids"
wait "$bg"
OUT=$(cat "$WORK/ask2.out")
check "stale sid: run gone reported" grep -q "gone without a result" <<<"$OUT"
check "stale sid: old session not suggested" not_grep "sess-1" <(printf '%s' "$OUT")
export FAKE_CLAUDE_MODE=success
hrun ask analyst "third" --keep
check "stale sid: --keep resumes the last successful session" logged "--resume sess-1"
check "stale sid: --keep says where it came from" grep -q "progress.jsonl" <<<"$OUT"

# 15b. --keep fallback: last *successful* session only; a close is a boundary
hsetup
hrun ask analyst "ok"
check "keep ok: first run sess-1" [ "$(cat .harness/asks/analyst.session)" = sess-1 ]
export FAKE_CLAUDE_MODE=error
hrun ask analyst "bad"
check "keep ok: failed run got sess-2" [ "$(cat .harness/asks/analyst.session)" = sess-2 ]
export FAKE_CLAUDE_MODE=hangpre
( hrun ask analyst "dies" --timeout 60000; echo "$OUT" > "$WORK/ask3.out" ) &
bg=$!
i=0; while [ $i -lt 50 ] && ! grep -q . .harness/asks/analyst.pid 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
kill -9 "$(awk 'NR == 1 { print $2 }' .harness/asks/analyst.pid)"
killpids "$FAKE_DIR/claude.pids"
wait "$bg"
export FAKE_CLAUDE_MODE=success
hrun ask analyst "keep" --keep
check "keep ok: resumes the last successful session, not the failed one" logged "--resume sess-1"
check "keep ok: not the failed session" not_logged "--resume sess-2"
check "keep ok: note says successful" grep -q "last successful" <<<"$OUT"

hsetup
hrun ask analyst "ok"
export FAKE_CLAUDE_MODE=hangpre
( hrun ask analyst "dies" --timeout 60000 ) &
bg=$!
i=0; while [ $i -lt 50 ] && ! grep -q . .harness/asks/analyst.pid 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
kill -9 "$(awk 'NR == 1 { print $2 }' .harness/asks/analyst.pid)"
killpids "$FAKE_DIR/claude.pids"
wait "$bg"
export FAKE_CLAUDE_MODE=success
hrun close analyst
hrun ask analyst "after close" --keep
check "keep close: no resume across a close" not_logged "--resume"
check "keep close: says a close ended it" grep -q "closed" <<<"$OUT"
check "keep close: runs fresh" grep -q "running fresh" <<<"$OUT"

# 15b2. a worktree ask's run (ask_id set) is never the session a plain --keep resumes
hsetup
hrun ask analyst "ok"
rm -f .harness/asks/analyst.session
printf '%s\n' '{"ts":"2026-10-28T00:00:00Z","agent":"analyst","runner":"headless","result":"success","session":"sess-wt","ask_id":"1-2-3","wt":"/x/wt","base":"b"}' >> .harness/progress.jsonl
hrun ask analyst "keep" --keep
check "keep leak: resumes the plain ask's session" logged "--resume sess-1"
check "keep leak: never the worktree ask's session" not_logged "--resume sess-wt"

# 15c. close ends the conversation: --keep after a close of a healthy idle worker runs fresh
hsetup
hrun ask analyst "ok"
check "keep healthy close: ask rc 0 (142 = the alarm killed a slow ask before it stamped the report)" [ "$RC" -eq 0 ]
check "keep healthy close: session recorded" [ "$(cat .harness/asks/analyst.session)" = sess-1 ]
hrun close analyst
check "keep healthy close: session file removed by close" [ ! -e .harness/asks/analyst.session ]
hrun ask analyst "after" --keep
check "keep healthy close: no resume" not_logged "--resume"
check "keep healthy close: note" grep -q "running fresh" <<<"$OUT"

# 16. watchdog does not outlive an killed harness-run
hsetup; export FAKE_CLAUDE_MODE=hang HARNESS_HL_MAX_S=4
( hrun ask analyst "q" --timeout 60000 ) &
bg=$!
i=0; while [ $i -lt 50 ] && ! grep -q . .harness/asks/analyst.pid 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
rid=$(awk 'NR == 1 { print $1 }' .harness/asks/analyst.pid)
kill -9 "$(awk 'NR == 1 { print $2 }' .harness/asks/analyst.pid)"
killpids "$FAKE_DIR/claude.pids"
sleep 2.5
wait_no_runs "$rid"
check "watchdog orphan: gone once harness-run is" [ -z "$(live_runs "$rid")" ]
for p in $(live_runs "$rid"); do kill "$p" 2>/dev/null; done
wait "$bg"
unset HARNESS_HL_MAX_S

# 16b. a SIGKILLed harness-run leaves claude (ppid 1): the watchdog must reap it, by run identity
hsetup; export FAKE_CLAUDE_MODE=hang HARNESS_HL_MAX_S=600
( hrun ask analyst "q" --timeout 60000 ) &
bg=$!
i=0; while [ $i -lt 50 ] && ! grep -q . .harness/asks/analyst.pid 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
i=0; while [ $i -lt 50 ] && ! [ -s "$FAKE_DIR/claude.pid" ]; do sleep 0.2; i=$((i + 1)); done
rid=$(awk 'NR == 1 { print $1 }' .harness/asks/analyst.pid)
cpid=$(cat "$FAKE_DIR/claude.pid")
check "orphan: claude running before the kill" kill -0 "$cpid"
kill -9 "$(awk 'NR == 1 { print $2 }' .harness/asks/analyst.pid)"
i=0; while [ $i -lt 40 ] && kill -0 "$cpid" 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
check "orphan: claude reaped after harness-run was SIGKILLed" not kill -0 "$cpid"
wait_no_runs "$rid"
check "orphan: no harness-run process left" [ -z "$(live_runs "$rid")" ]
for p in $(live_runs "$rid"); do kill "$p" 2>/dev/null; done
kill "$cpid" 2>/dev/null
wait "$bg"
unset HARNESS_HL_MAX_S

# 16c. direct runs (no herdr): zombie runner, TERM-proof claude, foreign process, live-script safety
hdirect() { # hdirect MODE MAX_S -> starts harness-run under a parent that never reaps it; sets RID RPID
  FAKE_CLAUDE_MODE=$1
  mkdir -p .harness/asks
  printf 'x\n' > .harness/asks/analyst.prompt; printf 'resume=\nmax_s=%s\n' "$2" > .harness/asks/analyst.run
  rm -f "$FAKE_DIR/claude.pids"
  # perl forks the runner and then sleeps without wait(): a SIGKILLed runner stays a zombie
  HARNESS_ROLE=worker FAKE_CLAUDE_MODE=$1 PATH="$FAKE_CLAUDE:$HERE/../bin:$PATH" \
    perl -e 'unless (fork) { open STDOUT, ">/dev/null"; open STDERR, ">&STDOUT"; exec @ARGV } sleep 12' \
    /bin/bash "${HR_BIN:-$HERE/../bin/harness-run}" analyst RUN-$$-$1 "$PWD" &
  i=0; while [ $i -lt 50 ] && ! grep -q . .harness/asks/analyst.pid 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
  i=0; while [ $i -lt 50 ] && ! [ -s "$FAKE_DIR/claude.pids" ]; do sleep 0.1; i=$((i + 1)); done
  RID=$(awk 'NR == 1 { print $1 }' .harness/asks/analyst.pid); RPID=$(awk 'NR == 1 { print $2 }' .harness/asks/analyst.pid)
  CPID=$(sed -n 1p "$FAKE_DIR/claude.pids")
}
# a foreign process in its own process group, started before the reap
hsetup
( set -m; sleep 300 & echo $! > "$WORK/foreign.pid"; wait ) 2>/dev/null &
fbg=$!
sleep 0.3
hdirect hang 600
kill -9 "$RPID"
sleep 1
ps -o stat= -p "$RPID" 2>/dev/null | grep -q '^Z' && zomb=1 || zomb=0
check "zombie: the SIGKILLed runner is a zombie (parent does not reap)" [ "$zomb" = 1 ]
i=0; while [ $i -lt 60 ] && kill -0 "$CPID" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
check "zombie: claude reaped though kill -0 on the runner succeeds" not kill -0 "$CPID"
check "foreign: a process without the run identity survives the reap" kill -0 "$(cat "$WORK/foreign.pid")"
kill "$(cat "$WORK/foreign.pid")" 2>/dev/null; wait "$fbg" 2>/dev/null

hsetup
hdirect hangterm 600
check "term-proof: claude running" kill -0 "$CPID"
kill -9 "$RPID"
sleep 1.5
check "term-proof: still alive during the TERM grace" kill -0 "$CPID"
i=0; while [ $i -lt 80 ] && kill -0 "$CPID" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
check "term-proof: KILLed after the grace" not kill -0 "$CPID"

# 16d. the group reap guard: a live process group WITHOUT the run's identity is left alone
# (models a recycled pgid: the pipeline's group exists but none of its members is this run's)
hsetup
hdirect hang 600
PG=$(awk 'NR == 1 { print $3 }' .harness/asks/analyst.pid)
WD=""   # the watchdog subshell: a child of the runner that is not the pipeline and carries the run's argv
for c in $(pgrep -P "$RPID"); do
  [ "$c" != "$PG" ] && ps -o command= -p "$c" 2>/dev/null | grep -q "harness-run analyst $RID " && WD=$c
done
identity_members() { ps -ax -o pid= -o pgid= -o command= | awk -v g="$PG" -v a="harness-run analyst $RID " -v b="hrun-id=analyst:$RID" -v b2="hrid=analyst:$RID" '$2 == g && (index($0, a) || index($0, b2)) { print $1 }'; }
check "guard: premise, claude is in the run's group" [ "$(ps -o pgid= -p "$CPID" | tr -d ' ')" = "$PG" ]
check "guard: premise, the watchdog was found" [ -n "$WD" ]
kill -STOP "$WD"                                  # hold the watchdog while the premise is set up
kill -9 "$RPID"                                   # the runner dies (a zombie: its parent never reaps)
for p in $(identity_members); do kill -9 "$p" 2>/dev/null; done
sleep 0.3
check "guard: premise, no member carries the run identity" [ -z "$(identity_members)" ]
check "guard: premise, claude still alive" kill -0 "$CPID"
kill -CONT "$WD"
i=0; while [ $i -lt 80 ] && kill -0 "$WD" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
check "guard: the watchdog ran and finished" bash -c '! kill -0 "$0" 2>/dev/null' "$WD"
check "guard: a live process without the run identity was not killed" kill -0 "$CPID"
kill -KILL -- "-$PG" 2>/dev/null                  # test cleanup by group id, never by pattern

# 16e. set -m on a tty with tostop (the viewer pane): SIGTTOU must not stop the run
if [ "$(perl -e 'alarm 5; exec @ARGV' script -q /dev/null /bin/echo ttyok </dev/null 2>/dev/null | tr -d '\r\004\b^D')" = ttyok ]; then
  hsetup
  mkdir -p .harness/asks
  printf 'x\n' > .harness/asks/analyst.prompt; printf 'resume=\nmax_s=20\n' > .harness/asks/analyst.run
  cat > "$WORK/tty.sh" <<EOS
stty tostop
cd "$WORK"
HARNESS_ROLE=worker FAKE_CLAUDE_MODE=success PATH="$FAKE_CLAUDE:$HERE/../bin:$PATH" /bin/bash "$HERE/../bin/harness-run" analyst TTY-$$ "$WORK"
EOS
  perl -e 'alarm 15; exec @ARGV' script -q /dev/null /bin/bash "$WORK/tty.sh" </dev/null >/dev/null 2>&1
  check "tty tostop: the run finished normally (not stopped, not watchdog-killed)" jqt '.rc == 0 and .killed == null' .harness/asks/analyst.exit.json
else
  echo "skip: tty tostop (no script(1) with the BSD syntax)"
fi

# live-script safety: overwrite a copy of harness-run in place while it waits; it must still finish
hsetup
mkdir -p "$WORK/binc"
cp "$HERE/../bin/harness-run" "$WORK/binc/harness-run"
HR_BIN="$WORK/binc/harness-run"
hdirect slow20 600
i=0; while [ $i -lt 5 ]; do sleep 0.1; i=$((i + 1)); done
i=0; : > "$WORK/junk"; while [ $i -lt 300 ]; do echo 'echo CORRUPT >&2; exit 9' >> "$WORK/junk"; i=$((i + 1)); done
cat "$WORK/junk" > "$WORK/binc/harness-run"
i=0; while [ $i -lt 60 ] && [ ! -f .harness/asks/analyst.exit.json ]; do sleep 0.2; i=$((i + 1)); done
check "in-place rewrite: the running harness-run still writes exit.json" jqt '.rc == 0' .harness/asks/analyst.exit.json
unset HR_BIN

# 17. use_hl: only a live headless run (or config) selects the headless code
hsetup; export FAKE_CLAUDE_MODE=hang
( hrun ask analyst "q" --timeout 60000 ) &
bg=$!
i=0; while [ $i -lt 50 ] && ! grep -q . .harness/asks/analyst.pid 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
export HARNESS_RUNNER_ANALYST=pane
hrun status
check "use_hl: live headless run under runner=pane still shown as hl" grep -Eq 'analyst +running .* hl' <<<"$OUT"
hrun close analyst --force
check "use_hl: live run closed headless (force_kill)" grep -q force_kill .harness/progress.jsonl
wait "$bg"
export HARNESS_RUNNER_ANALYST=headless FAKE_CLAUDE_MODE=success
hrun ask analyst "again"
export HARNESS_RUNNER_ANALYST=pane
hrun status
check "use_hl: leftover .run, dead pid, runner=pane: not an hl line" not_grep " hl" <(printf '%s' "$OUT")
hrun close analyst
check "use_hl: leftover .run under runner=pane: close is pane behaviour (no viewer pane closed)" not_grep "closed analyst" <(printf '%s' "$OUT")
check "use_hl: leftover .run under runner=pane: viewer pane left registered" grep -q '^analyst ' .harness/panes
export HARNESS_RUNNER_ANALYST=headless

# status
hsetup
hrun ask analyst "q"
hrun status
check "status: headless idle line" grep -Eq 'analyst +idle +w1:p2 +hl' <<<"$OUT"

# metrics: runner split (old lines without runner count as pane)
setup
mkdir -p .harness
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\n' "{\"ts\":\"$now\",\"agent\":\"analyst\",\"exit\":0,\"dur_s\":5}" \
  "{\"ts\":\"$now\",\"agent\":\"analyst\",\"exit\":0,\"dur_s\":9,\"runner\":\"headless\",\"cost_usd\":0.5,\"startup_s\":2}" > .harness/progress.jsonl
hrun metrics --json
check "metrics: by_runner keys" jqt '.current.by_runner | keys == ["analyst/headless","analyst/pane"]' <<<"$OUT"
check "metrics: headless cost" jqt '.current.by_runner["analyst/headless"].cost_usd_sum == 0.5' <<<"$OUT"
hrun metrics
check "metrics text: runner split shown" grep -q "analyst/headless" <<<"$OUT"
printf '%s\n' "{\"ts\":\"$now\",\"agent\":\"analyst\",\"exit\":0,\"dur_s\":5}" > .harness/progress.jsonl
hrun metrics
check "metrics text: no split without headless rows" not_grep "runner split" <(printf '%s' "$OUT")

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
