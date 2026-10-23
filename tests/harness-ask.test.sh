#!/bin/bash
# bin/harness against tests/fake-herdr: ask completion by Stop-hook marker. Run: /bin/bash tests/harness-ask.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"

# --- ask: completion = Stop-hook marker for this ask + fresh report ------------------

# marker + fresh report -> 0; ask-id and start epoch recorded for the hook
setup
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q"
check "marker+report: rc 0" [ "$RC" -eq 0 ]
check "marker: current ask file" grep -Eq '^[0-9]+-[0-9]+-[0-9]+ [0-9]+$' .harness/asks/analyst.current
check "marker: file named after ask-id" [ -f ".harness/done/analyst.$(cut -d' ' -f1 .harness/asks/analyst.current)" ]

# idle without marker (hook never fires) -> waits the grace period, then 3
setup
touch "$FAKE_DIR/no_stop_hook"
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
t0=$(date +%s)
run ask analyst "q"
check "idle w/o marker: rc 3" [ "$RC" -eq 3 ]
check "idle w/o marker: waited for grace" [ $(( $(date +%s) - t0 )) -ge 1 ]
check "idle w/o marker: hint to harness report" grep -q "harness report analyst" <<<"$OUT"

# marker for a different ask-id is ignored
setup
touch "$FAKE_DIR/no_stop_hook"
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst); mkdir -p $WORK/.harness/done; echo s > $WORK/.harness/done/analyst.other-id"
run ask analyst "q"
check "other ask-id marker ignored: rc 3" [ "$RC" -eq 3 ]

# marker but the report is older than the ask (stale) -> not accepted
setup
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf 'OLD\n' > $WORK/.harness/reports/analyst.md; touch -t 200001010000 $WORK/.harness/reports/analyst.md"
run ask analyst "q" --timeout 2000
check "stale report mtime: rc 4" [ "$RC" -eq 4 ]
check "stale report mtime: not printed" not_grep "OLD" <(printf '%s' "$OUT" | grep -v '^harness:')

# marker arrives while the worker is idle-looking only after a delay
# (Stop hook fires later than herdr's idle): still accepted within the grace
setup
export FAKE_PROMPT_HOOK="touch $FAKE_DIR/no_stop_hook; $(REPORT_HOOK analyst); ( sleep 0.4; id=\$(cut -d' ' -f1 $WORK/.harness/asks/analyst.current); echo \"s \$(date +%s)\" > $WORK/.harness/done/analyst.\$id ) >/dev/null 2>&1 &"
# grace is compared in whole seconds (date +%s), so a 1s grace is effectively (0,1]s and a
# 0.4s marker sometimes loses; 3s makes it >= 2s
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_IDLE_GRACE=3 HARNESS_POLL_SEC=0.2 PATH="$FAKE_BIN:$HERE/../bin:$PATH" perl -e 'alarm(12);exec(@ARGV)' env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "q" 2>&1); RC=$?
check "late marker within grace: rc 0" [ "$RC" -eq 0 ]

# real background-wait scenario: turn ended (Stop -> marker), herdr idle, no report.
# No exit 3 within the grace; then report written + a later Stop marker -> exit 0
setup
export FAKE_PROMPT_HOOK="( sleep 2.2; $(REPORT_HOOK analyst); sleep 1; id=\$(cut -d' ' -f1 $WORK/.harness/asks/analyst.current); echo \"s \$(date +%s)\" > $WORK/.harness/done/analyst.\$id ) >/dev/null 2>&1 &"
t0=$(date +%s)
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2 PATH="$FAKE_BIN:$HERE/../bin:$PATH" perl -e 'alarm(12);exec(@ARGV)' env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "q" --timeout 10000 2>&1); RC=$?
check "bg wait (marker, idle, no report): rc 0 not 3" [ "$RC" -eq 0 ]
check "bg wait: waited past grace" [ $(( $(date +%s) - t0 )) -ge 2 ]

# marker, idle, never a report -> keeps polling to the deadline, then 4 (not 3)
setup
export FAKE_PROMPT_HOOK="true"
run ask analyst "q" --timeout 2000
check "marker w/o report: rc 4" [ "$RC" -eq 4 ]
check "marker w/o report: message" grep -q "turn ended without a report" <<<"$OUT"

# marker from an earlier turn + report written later (before its Stop) -> not complete
setup
export FAKE_PROMPT_HOOK="touch $FAKE_DIR/no_stop_hook; id=\$(cut -d' ' -f1 $WORK/.harness/asks/analyst.current); mkdir -p $WORK/.harness/done; echo \"s \$(( \$(date +%s) - 5 ))\" > $WORK/.harness/done/analyst.\$id; $(REPORT_HOOK analyst)"
run ask analyst "q" --timeout 2500
check "earlier-turn marker, later report: not complete (rc 4)" [ "$RC" -eq 4 ]
check "earlier-turn marker: report not printed" not_grep "analyst report" <(printf '%s' "$OUT" | grep -v '^harness:')

# implementer verification in progress (.pending) -> idle grace never applies
setup
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf 'x\n' > $WORK/.harness/reports/implementer.md.pending; touch $FAKE_DIR/no_stop_hook"
run ask implementer "q" --timeout 2500
check "pending: waits to deadline, exit 5 INTERRUPTED" [ "$RC" -eq 5 ]

# earlier-turn marker + .pending + idle (bg-wait resume, verify running): no grace
# exit; waits to the deadline (5)
setup
export FAKE_PROMPT_HOOK="touch $FAKE_DIR/no_stop_hook; id=\$(cut -d' ' -f1 $WORK/.harness/asks/implementer.current); mkdir -p $WORK/.harness/done $WORK/.harness/reports; echo \"s \$(date +%s)\" > $WORK/.harness/done/implementer.\$id; printf 'x\\n' > $WORK/.harness/reports/implementer.md.pending"
t0=$(date +%s)
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2 PATH="$FAKE_BIN:$HERE/../bin:$PATH" perl -e 'alarm(12);exec(@ARGV)' env -u HARNESS_ROLE /bin/bash "$HARNESS" ask implementer "q" --timeout 3000 2>&1); RC=$?
check "marker+pending+idle: no grace exit, rc 5 at deadline" [ "$RC" -eq 5 ]
check "marker+pending+idle: waited to deadline" [ $(( $(date +%s) - t0 )) -ge 3 ]

# .pending + worker still working at the deadline (Stop hook verifying): rc 4, .pending
# untouched, nothing restored; later idle + verify done -> harness report exits 0
setup
echo idle > "$FAKE_DIR/live.$(WN implementer)"
export FAKE_PROMPT_HOOK="echo working > $FAKE_DIR/live.$(WN implementer); mkdir -p $WORK/.harness/reports; printf '# r\\nstatus: done\\n' > $WORK/.harness/reports/implementer.md.pending"
run ask implementer "q" --timeout 2000
check "pending+working at deadline: rc 4" [ "$RC" -eq 4 ]
check "pending+working: still verifying message" grep -q "still verifying" <<<"$OUT"
check "pending+working: .pending intact" [ -f "$WORK/.harness/reports/implementer.md.pending" ]
check "pending+working: not restored" [ ! -e "$WORK/.harness/reports/implementer.md" ]
run report implementer
check "report while still working: rc 4" [ "$RC" -eq 4 ]
check "report while working: .pending intact" [ -f "$WORK/.harness/reports/implementer.md.pending" ]
echo idle > "$FAKE_DIR/live.$(WN implementer)"
mv "$WORK/.harness/reports/implementer.md.pending" "$WORK/.harness/reports/implementer.md"
mkdir -p .harness/verify; printf '{"status":"pass","attempts":1,"step":"","tail":""}' > .harness/verify/implementer.json
run report implementer
check "verify done, idle: report rc 0" [ "$RC" -eq 0 ]

# exit-3 message (old worker without the hook) is on stdout and names close
setup
touch "$FAKE_DIR/no_stop_hook"
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2 PATH="$FAKE_BIN:$HERE/../bin:$PATH" perl -e 'alarm(5);exec(@ARGV)' env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "q" 2>/dev/null); RC=$?
check "exit 3: hint on stdout" grep -q "harness close analyst" <<<"$OUT"
check "exit 3: collect hint on stdout" grep -q "harness report analyst" <<<"$OUT"

# file_mtime: GNU-like stat (-f is filesystem mode: junk) and BSD-like stat
setup
echo x > f
mkdir -p gnu bsd
cat > gnu/stat <<'EOS'
#!/bin/sh
case "$1" in
  -c) echo 1700000000 ;;
  -f) printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: ext2/ext3\n1700000001\n' "$3" ;;
esac
EOS
cat > bsd/stat <<'EOS'
#!/bin/sh
case "$1" in
  -f) echo 1700000002 ;;
  *) echo "stat: illegal option" >&2; exit 1 ;;
esac
EOS
chmod +x gnu/stat bsd/stat
OUT=$(PATH="$WORK/gnu:$PATH" /bin/bash "$HARNESS" _mtime f 2>&1)
check "file_mtime GNU stat: epoch only" [ "$OUT" = 1700000000 ]
OUT=$(PATH="$WORK/bsd:$PATH" /bin/bash "$HARNESS" _mtime f 2>&1)
check "file_mtime BSD stat: epoch" [ "$OUT" = 1700000002 ]
OUT=$(/bin/bash "$HARNESS" _mtime f 2>&1)
check "file_mtime real stat: digits" grep -Eq '^[0-9]+$' <<<"$OUT"

# old markers are cleaned on the next ask
setup
mkdir -p .harness/done && echo s > .harness/done/analyst.old-1
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q"
check "old marker removed" [ ! -e .harness/done/analyst.old-1 ]
unset FAKE_PROMPT_HOOK


echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
