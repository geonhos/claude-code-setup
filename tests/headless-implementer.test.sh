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

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
