#!/bin/bash
# Headless implementer (decision 0009): exit 2 on denials, verify exit map, auto-resume, viewer,
# lifecycle. bin/harness ask with runner.implementer=headless against tests/fake-herdr + fake-claude.
# Run: /bin/bash tests/headless-implementer.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
FAKE_CLAUDE="$HERE/fake-claude"

hrun() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=5 \
    PATH="$FAKE_BIN:$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm($ENV{HRUN_ALARM_S} || 60);exec(@ARGV)' \
    env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
jqt() { jq -e "$@" >/dev/null; }
lastprog() { tail -n 1 .harness/progress.jsonl 2>/dev/null; }
# isetup — implementer (and analyst) headless; the fake claude writes an implementer report
isetup() {
  setup
  export HARNESS_RUNNER_IMPLEMENTER=headless HARNESS_RUNNER_ANALYST=headless
  export FAKE_CLAUDE_MODE=success
  unset FAKE_CLAUDE_DENY
  export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
}

# 1. permission pin + denial parsing + exit 2
isetup
hrun ask implementer "q"
check "pin: rc 0" [ "$RC" -eq 0 ]
check "pin: implementer argv has --permission-mode auto" logged "--permission-mode auto"
check "pin: implementer argv has --permission-prompts none" logged "--permission-prompts none"
isetup
hrun ask analyst "q"
check "pin: analyst argv unchanged" not_logged "--permission-mode"

isetup; export FAKE_CLAUDE_MODE=noreport FAKE_CLAUDE_DENY=1
hrun ask implementer "q"
check "denied, no report: rc 2" [ "$RC" -eq 2 ]
check "denied, no report: names tool and first line" grep -q 'Bash: rm -rf /tmp/x (safetyCheck)' <<<"$OUT"
check "denied, no report: only first line of the input" not_grep "second line" <(printf '%s' "$OUT")
check "denied, no report: re-ask hint" grep -q 'Re-ask' <<<"$OUT"
check "denied, no report: exit.json denied[]" jqt '.denied[0].tool == "Bash" and .denied[0].reason == "safetyCheck" and .denials == 1' .harness/asks/implementer.exit.json
check "denied, no report: progress exit 2" jqt '.exit == 2' <<<"$(lastprog)"

isetup; export FAKE_CLAUDE_DENY=1
hrun ask implementer "q"
check "denied + report: rc 0" [ "$RC" -eq 0 ]
check "denied + report: report printed" grep -q "implementer report" <<<"$OUT"
check "denied + report: note about the denial" grep -q 'note: 1 denied tool call' <<<"$OUT"

isetup; export FAKE_CLAUDE_MODE=noreport FAKE_CLAUDE_DENY=1
hrun ask analyst "q"
check "denied, no report: analyst (all headless roles) rc 2" [ "$RC" -eq 2 ]

isetup; export FAKE_CLAUDE_MODE=noreport
hrun ask implementer "q"
check "no denial, no report: still rc 3" [ "$RC" -eq 3 ]

# 2. implementer exit map (the Stop hook is simulated by the fake claude's report command)
isetup
export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports $WORK/.harness/verify && printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md && printf '{\"status\":\"pass\",\"attempts\":1}' > $WORK/.harness/verify/implementer.json"
hrun ask implementer "q"
check "map: report + verify pass: rc 0" [ "$RC" -eq 0 ]
check "map: report + verify pass: report printed" grep -q "implementer report" <<<"$OUT"

isetup
export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports $WORK/.harness/verify && printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md && printf '{\"status\":\"fail\",\"step\":\"test\",\"attempts\":3}' > $WORK/.harness/verify/implementer.json"
hrun ask implementer "q"
check "map: verify FAIL at cap: rc 5" [ "$RC" -eq 5 ]
check "map: verify FAIL line" grep -q 'verify: FAIL (test, 3 attempts)' <<<"$OUT"
check "map: verify FAIL: report still printed" grep -q "implementer report" <<<"$OUT"

isetup
export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md.pending"
hrun ask implementer "q"
check "map: only .pending: rc 5" [ "$RC" -eq 5 ]
check "map: only .pending: INTERRUPTED" grep -q 'verify: INTERRUPTED' <<<"$OUT"
check "map: only .pending: report restored" test -f .harness/reports/implementer.md

# deadline while the Stop hook is verifying (.pending present): exit 4 "still verifying", run not killed
isetup; export FAKE_CLAUDE_MODE=hang
( hrun ask implementer "q" --timeout 3000; echo "$RC" > "$WORK/ask.rc"; echo "$OUT" > "$WORK/ask.out" ) &
bg=$!
i=0; while [ $i -lt 50 ] && ! grep -q . .harness/asks/implementer.pid 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
mkdir -p .harness/reports; printf '# implementer report\nstatus: done\n' > .harness/reports/implementer.md.pending
wait "$bg"
check "deadline+pending: rc 4" [ "$(cat "$WORK/ask.rc")" = 4 ]
check "deadline+pending: says still verifying" grep -q 'still verifying' "$WORK/ask.out"
check "deadline+pending: run still alive" grep -q . .harness/asks/implementer.pid
hrun close implementer
check "deadline+pending: close without --force refused (4)" [ "$RC" -eq 4 ]
hrun close implementer --force
hrun report implementer
check "killed mid-verify: report is INTERRUPTED rc 5" [ "$RC" -eq 5 ]
check "killed mid-verify: INTERRUPTED line" grep -q 'verify: INTERRUPTED' <<<"$OUT"

# 3. auto-resume after a non-zero implementer exit (decision 0009)
failcmd() { echo "mkdir -p $WORK/.harness/reports $WORK/.harness/verify && printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md && printf '{\"status\":\"fail\",\"step\":\"test\",\"attempts\":3}' > $WORK/.harness/verify/implementer.json"; }
isetup
export FAKE_REPORT_CMD=$(failcmd)
hrun ask implementer "first"
check "autoresume: first ask exits 5" [ "$RC" -eq 5 ]
check "autoresume: first ask runs fresh" not_logged "--resume"
export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
hrun ask implementer "second"
check "autoresume: second ask resumes the failed session" logged "--resume sess-1"
check "autoresume: says it keeps context" grep -q 'keeping context (last ask exit 5)' <<<"$OUT"
check "autoresume: progress resumed:true" jqt '.resumed == true and .resume == true and .exit == 0' <<<"$(lastprog)"
hrun ask implementer "third"
check "autoresume: after a clean exit the next ask is fresh" test "$(grep -c -- '--resume' "$FAKE_LOG")" = 1
check "autoresume: no resumed flag when fresh" jqt '(.resumed // false) == false and .resume == false' <<<"$(lastprog)"

isetup
export FAKE_REPORT_CMD=$(failcmd)
hrun ask implementer "first"
export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
hrun ask implementer "second" --fresh
check "autoresume: --fresh overrides" not_logged "--resume"
check "autoresume: --fresh progress not resumed" jqt '(.resumed // false) == false' <<<"$(lastprog)"

isetup
export FAKE_REPORT_CMD=$(failcmd)
hrun ask analyst "first"
hrun ask analyst "second"
check "autoresume: analyst is not auto-resumed" not_logged "--resume"

# 4. harness-view (design §7): verify blocks, Stop start/done, denials, failing-test tails
vw() { printf '%s\n' "$@" | NO_COLOR=1 PATH="$HERE/../bin:$PATH" /bin/bash "$HERE/../bin/harness-view" 2>&1; }
OUT=$(vw '{"type":"system","subtype":"hook_started","hook_event":"Stop","hook_name":"Stop"}' \
  '{"type":"system","subtype":"hook_response","hook_event":"Stop","hook_name":"Stop","exit_code":0,"stdout":"{\"decision\":\"block\",\"reason\":\"Verification failed at step test (attempt 1 of 3)\\nmore\"}"}' \
  '{"type":"system","subtype":"hook_response","hook_event":"Stop","hook_name":"Stop","exit_code":0,"stdout":""}' \
  '{"type":"system","subtype":"hook_response","hook_event":"PostToolUse","hook_name":"PostToolUse:Edit","exit_code":0,"stdout":"{\"decision\":\"block\",\"reason\":\"LINT: add END\"}"}' \
  '{"type":"system","subtype":"permission_denied","tool_name":"Bash","decision_reason":"safetyCheck","message":"m"}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"FAIL suite\nl2\nl3\nl4\nl5\nl6\nl7\nfinal line"}]}}' \
  '{"type":"user","message":{"content":[{"type":"tool_result","is_error":true,"content":"single"}]}}')
check "view: Stop hook start line" grep -q '⧗ verify (Stop hook)' <<<"$OUT"
check "view: Stop block reason (exit 0)" grep -q '⟲ Stop block: Verification failed at step test (attempt 1 of 3)' <<<"$OUT"
check "view: Stop block shows only the first reason line" not_grep "more" <(printf '%s' "$OUT")
check "view: Stop done line" grep -q '✓ verify done' <<<"$OUT"
check "view: PostToolUse block" grep -q '⟲ PostToolUse block: LINT: add END' <<<"$OUT"
check "view: permission_denied" grep -q '⛔ denied Bash: safetyCheck' <<<"$OUT"
check "view: failed result keeps the tail" grep -q '| final line' <<<"$OUT"
check "view: failed result drops the middle" not_grep "| l3" <(printf '%s' "$OUT")
check "view: failed result first line kept" grep -q '✗ FAIL suite' <<<"$OUT"
check "view: single-line failure unchanged" grep -qx '✗ single' <<<"$OUT"
OUT=$(vw 'not json' '{"type":"system","subtype":"hook_response","hook_event":"Stop","exit_code":0,"stdout":"not json"}' '{"type":"system","subtype":"hook_response","hook_event":"Stop","exit_code":2,"stderr":"boom"}')
check "view: odd hook stdout still never fails" grep -q 'hook .* exit 2: boom' <<<"$OUT"

# 5. lifecycle: the viewer pane stays (close_after_ask never), .pending blocks the TTL reap
isetup
hrun ask implementer "q"
check "lifecycle: default close_after_ask never keeps the viewer pane" grep -q '^implementer ' .harness/panes
check "lifecycle: ... and the session for --keep" test -s .harness/asks/implementer.session
touch -t 202001010000 .harness/asks/implementer.finished
printf '# implementer report\nstatus: done\n' > .harness/reports/implementer.md.pending
rm -f .harness/reports/implementer.md
HARNESS_IDLE_TTL_MINUTES=1 hrun status
check "lifecycle: TTL does not reap while .pending exists" grep -q '^implementer ' .harness/panes
rm -f .harness/reports/implementer.md.pending
HARNESS_IDLE_TTL_MINUTES=1 hrun status
check "lifecycle: TTL reaps the idle viewer once nothing is pending" not_grep '^implementer ' .harness/panes

isetup
HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER=on_success hrun ask implementer "q"
check "lifecycle: on_success still closes the viewer after exit 0" not_grep '^implementer ' .harness/panes

# 6. per-role headless cap: implementer 90 min, analyst 60, config headless_max_minutes wins
isetup
hrun ask implementer "q"
check "cap: implementer default 5400 s" grep -qx 'max_s=5400' .harness/asks/implementer.run
hrun ask analyst "q"
check "cap: analyst default 3600 s" grep -qx 'max_s=3600' .harness/asks/analyst.run
mkdir -p .harness; printf '{"headless_max_minutes": 7}\n' > .harness/config.json
hrun ask implementer "q"
check "cap: config headless_max_minutes wins for the implementer" grep -qx 'max_s=420' .harness/asks/implementer.run

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
