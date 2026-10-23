#!/bin/bash
# Headless runner (ADR 0007): bin/harness ask/report/close with runner=headless against
# tests/fake-herdr + tests/fake-claude. Run: /bin/bash tests/headless.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
FAKE_CLAUDE="$HERE/fake-claude"

# hrun ARGS... -> OUT, RC. Like run(), with the fake claude on PATH and a longer alarm.
hrun() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=5 \
    PATH="$FAKE_BIN:$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm(20);exec(@ARGV)' \
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
check "close --force: no leftover fake claude" not pgrep -f "fake-claude/claude"
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
