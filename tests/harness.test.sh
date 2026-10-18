#!/bin/bash
# Tests for bin/harness against tests/fake-herdr. Run: /bin/bash tests/harness.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
FAKE_BIN="$HERE/fake-herdr"
pass=0
fail=0

# fresh WORK FAKE_DIR per case; all of them removed on exit
WORKS=""
trap 'cd / && for d in $WORKS; do rm -rf "$d"; done' EXIT
setup() {
  WORK=$(mktemp -d)
  WORKS="$WORKS $WORK"
  export FAKE_DIR="$WORK/fake"
  export FAKE_LOG="$WORK/herdr.log"
  mkdir -p "$FAKE_DIR"
  : > "$FAKE_LOG"
  unset FAKE_PROMPT_HOOK
  cd "$WORK" || exit 1
}

# run ARGS... -> sets OUT, RC  (killed by SIGALRM after 5s so a hang fails fast)
GUARD="perl -e alarm(5);exec(@ARGV)"
run() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" $GUARD /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}

check() { # check LABEL CONDITION...
  local label=$1; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi
}
# FAKE_LOG holds `printf %q` of each argv: match literally (spaces inside an
# argument appear as "\ ").
logged() { grep -qF -- "$1" "$FAKE_LOG"; }
not_grep() { ! grep -q -- "$1" "$2" 2>/dev/null; }
not_logged() { ! grep -qF -- "$1" "$FAKE_LOG"; }

# --- preconditions -----------------------------------------------------------
setup
OUT=$(env -u HERDR_ENV PATH="$FAKE_BIN:$PATH" /bin/bash "$HARNESS" status 2>&1); RC=$?
check "refuses outside herdr" [ "$RC" -eq 1 ]
check "refuses outside herdr: message" grep -q "herdr pane" <<<"$OUT"

setup
run spawn bogus
check "unknown agent rc" [ "$RC" -eq 1 ]
check "unknown agent message" grep -q "unknown agent" <<<"$OUT"

run
check "no args shows usage" [ "$RC" -eq 1 ]
check "usage text" grep -q "harness ask" <<<"$OUT"

# --- spawn ---------------------------------------------------------------------
setup
run spawn analyst
check "spawn rc" [ "$RC" -eq 0 ]
check "spawn prints pane" [ "$OUT" = "w1:p2" ]
check "spawn splits with env" logged "pane split --current --direction right --cwd $WORK --env HARNESS_ROLE=worker --no-focus"
check "spawn starts agent" logged "agent start analyst --kind claude --pane w1:p2 -- --agent analyst"
check "spawn records pane" grep -q "^analyst w1:p2$" "$WORK/.harness/panes"

run spawn analyst
check "respawn rc" [ "$RC" -eq 0 ]
check "respawn reuses" [ "$(grep -c 'pane split' "$FAKE_LOG")" -eq 1 ]

setup
run spawn analyst --direction down
check "spawn direction flag" logged "pane split --current --direction down"

setup
touch "$FAKE_DIR/split_fail"
run spawn implementer
check "split failure rc" [ "$RC" -eq 1 ]
check "split failure message" grep -q "pane split failed" <<<"$OUT"

setup
touch "$FAKE_DIR/start_fail"
run spawn implementer
check "start failure rc" [ "$RC" -eq 1 ]
check "start failure shows screen" grep -q "fake screen line" <<<"$OUT"
check "start failure reads pane screen" logged "pane read w1:p2 --source recent-unwrapped --lines 60"
check "start failure closes orphan pane" logged "pane close w1:p2"
check "start failure unregisters pane" not_grep "^implementer w1:p2$" "$WORK/.harness/panes"

# --- option parsing ----------------------------------------------------------------
setup
run ask analyst "x" --timeout
check "ask --timeout without value rc" [ "$RC" -eq 1 ]

setup
run spawn analyst --direction
check "spawn --direction without value rc" [ "$RC" -eq 1 ]

setup
run spawn analyst --direction left
check "spawn --direction left rc" [ "$RC" -eq 1 ]
check "spawn --direction left: no split" not_logged "pane split"

# --- auto direction ------------------------------------------------------------------
setup
run spawn analyst
check "auto direction wide -> right" logged "pane split --current --direction right"

setup
echo "80 45" > "$FAKE_DIR/layout"
run spawn analyst
check "auto direction tall -> down" logged "pane split --current --direction down"

setup
echo "80 45" > "$FAKE_DIR/layout"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID= PATH="$FAKE_BIN:$PATH" $GUARD /bin/bash "$HARNESS" spawn analyst 2>&1); RC=$?
check "no HERDR_PANE_ID -> right" logged "pane split --current --direction right"
check "no HERDR_PANE_ID: no layout call" not_logged "pane layout"

# --- ask: success ----------------------------------------------------------------
setup
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports && printf '# analyst report\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
run ask analyst "Describe the repo"
check "ask rc" [ "$RC" -eq 0 ]
check "ask spawns first" logged "agent start analyst"
check "ask prompts with wait" logged "agent prompt analyst Describe\\ the\\ repo --wait --timeout 600000"
check "ask prints report" grep -q "status: done" <<<"$OUT"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" $GUARD /bin/bash "$HARNESS" ask analyst "again" 2>/dev/null); RC=$?
check "ask stdout is exactly the report" [ "$OUT" = "$(printf '# analyst report\nstatus: done')" ]

# --- ask: dash-leading instruction stays positional ------------------------------
setup
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports && echo ok > $WORK/.harness/reports/analyst.md"
run ask analyst "--not-a-flag text"
check "dash text rc" [ "$RC" -eq 0 ]
check "dash text is prompt's third arg" logged "agent prompt analyst --not-a-flag\\ text --wait"

# --- ask: --timeout validation ----------------------------------------------------
setup
run ask analyst "x" --timeout abc
check "ask --timeout abc rc" [ "$RC" -eq 1 ]
check "ask --timeout abc: no prompt" not_logged "agent prompt"

setup
run ask analyst "x" --timeout 0
check "ask --timeout 0 rc" [ "$RC" -eq 1 ]

# --- ask: prompt rejected outright -------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
touch "$FAKE_DIR/prompt_fail"
run ask analyst "x"
check "prompt rejected rc" [ "$RC" -eq 4 ]
check "prompt rejected message" grep -q "not accepted" <<<"$OUT"
check "prompt rejected: herdr error shown" grep -q "socket_unavailable" <<<"$OUT"

# --- ask: reuse + custom timeout + stale report removed --------------------------
setup
echo idle > "$FAKE_DIR/live.implementer"
mkdir -p .harness/reports && echo "OLD" > .harness/reports/implementer.md
export FAKE_PROMPT_HOOK="printf 'NEW\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it" --timeout 1000
check "ask reuse: no spawn" not_logged "agent start"
check "ask custom timeout" logged "--wait --timeout 1000"
check "ask stale report replaced" [ "$OUT" = "NEW" ]

# --- ask: blocked before prompt --------------------------------------------------
setup
echo blocked > "$FAKE_DIR/live.analyst"
run ask analyst "x"
check "blocked before rc" [ "$RC" -eq 2 ]
check "blocked before: no prompt sent" not_logged "agent prompt"
check "blocked before: screen" grep -q "fake screen line" <<<"$OUT"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" $GUARD /bin/bash "$HARNESS" ask analyst "x" 2>/dev/null); RC=$?
check "blocked: screen on stdout" grep -q "fake screen line" <<<"$OUT"

# --- ask: blocked after prompt ----------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
export FAKE_PROMPT_HOOK="echo blocked > $FAKE_DIR/live.analyst"
run ask analyst "x"
check "blocked after rc" [ "$RC" -eq 2 ]
check "blocked after: screen" grep -q "fake screen line" <<<"$OUT"

# --- ask: finished without report ------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.reviewer"
run ask reviewer "review"
check "no report rc" [ "$RC" -eq 3 ]
check "no report message" grep -q "no report" <<<"$OUT"
check "no report: screen" grep -q "fake screen line" <<<"$OUT"

# --- ask: still working (stalled/timeout) -----------------------------------------
setup
echo idle > "$FAKE_DIR/live.reviewer"
export FAKE_PROMPT_HOOK="echo working > $FAKE_DIR/live.reviewer"
run ask reviewer "review"
check "working rc" [ "$RC" -eq 4 ]
check "working message" grep -q "still working" <<<"$OUT"

# --- ask: agent vanished after prompt -> unknown ----------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
export FAKE_PROMPT_HOOK="rm -f $FAKE_DIR/live.analyst"
run ask analyst "x"
check "vanished rc" [ "$RC" -eq 4 ]
check "vanished reports unknown status" grep -q "status is 'unknown'" <<<"$OUT"
check "vanished: agent get diagnostic" grep -q "agent not found" <<<"$OUT"
check "vanished: pane screen still shown" grep -q "fake screen line" <<<"$OUT"

# --- ask: worker still busy with a previous instruction ---------------------------
setup
echo working > "$FAKE_DIR/live.analyst"
mkdir -p .harness/reports && echo "PENDING" > .harness/reports/analyst.md
run ask analyst "second"
check "busy rc" [ "$RC" -eq 4 ]
check "busy: no prompt sent" not_logged "agent prompt"
check "busy: report untouched" [ "$(cat "$WORK/.harness/reports/analyst.md")" = "PENDING" ]
check "busy: points to harness report" grep -q "harness report analyst" <<<"$OUT"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" $GUARD /bin/bash "$HARNESS" ask analyst "second" 2>/dev/null); RC=$?
check "busy: screen on stdout" grep -q "fake screen line" <<<"$OUT"

# --- report ------------------------------------------------------------------------
setup
mkdir -p .harness/reports && printf 'R1\nVERDICT: PASS\n' > .harness/reports/reviewer.md
run report reviewer
check "report rc" [ "$RC" -eq 0 ]
check "report prints file" [ "$OUT" = "$(printf 'R1\nVERDICT: PASS')" ]
check "report: no prompt sent" not_logged "agent prompt"

setup
run report reviewer
check "report missing rc" [ "$RC" -eq 3 ]
check "report missing message" grep -q "no report for reviewer" <<<"$OUT"

run report bogus
check "report unknown agent rc" [ "$RC" -eq 1 ]

run
check "usage lists report" grep -q "harness report" <<<"$OUT"

# --- ask: missing instruction ------------------------------------------------------
setup
run ask analyst
check "ask without text rc" [ "$RC" -eq 1 ]

# --- status ----------------------------------------------------------------------------
setup
echo working > "$FAKE_DIR/live.implementer"
run status
check "status rc" [ "$RC" -eq 0 ]
check "status live line" grep -Eq "^implementer +working +w1:p2$" <<<"$OUT"
check "status dead line" grep -Eq "^analyst +-$" <<<"$OUT"

# --- close ------------------------------------------------------------------------------
setup
run spawn analyst
run close analyst
check "close rc" [ "$RC" -eq 0 ]
check "close calls pane close" logged "pane close w1:p2"
check "close unregisters" [ ! -s "$WORK/.harness/panes" ]

setup
for a in analyst implementer reviewer; do echo idle > "$FAKE_DIR/live.$a"; done
echo w1:p2 > "$FAKE_DIR/pane.analyst"
echo w1:p3 > "$FAKE_DIR/pane.implementer"
echo w1:p4 > "$FAKE_DIR/pane.reviewer"
mkdir -p .harness
printf 'analyst w1:p2\nimplementer w1:p3\nreviewer w1:p4\n' > .harness/panes
run close analyst
check "close multi rc" [ "$RC" -eq 0 ]
check "close multi: closes analyst pane" logged "pane close w1:p2"
check "close multi: analyst removed" not_grep "^analyst " "$WORK/.harness/panes"
check "close multi: implementer kept" grep -q "^implementer w1:p3$" "$WORK/.harness/panes"
check "close multi: reviewer kept" grep -q "^reviewer w1:p4$" "$WORK/.harness/panes"

setup
echo idle > "$FAKE_DIR/live.analyst"   # live but not created by harness
run close analyst
check "close foreign pane rc" [ "$RC" -eq 1 ]
check "close foreign pane message" grep -q "not created by harness" <<<"$OUT"
check "close foreign pane: no close call" not_logged "pane close"

setup
run close analyst
check "close dead rc" [ "$RC" -eq 1 ]
check "close dead message" grep -q "not running" <<<"$OUT"

# --- ask: verification loop (exit 5, VERDICT, baseline) ----------------------------
gitwork() { git init -q . && git config user.email t@t && git config user.name t && echo s > s.txt && git add s.txt && git -c core.hooksPath=/dev/null commit -q -m s; }

setup; gitwork
echo idle > "$FAKE_DIR/live.implementer"
export FAKE_PROMPT_HOOK="test -s $WORK/.harness/verify/implementer.base && touch $WORK/seen-base; mkdir -p $WORK/.harness/reports; printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it"
check "implementer baseline before prompt" [ -e "$WORK/seen-base" ]
check "implementer verify none: exit 0" [ "$RC" -eq 0 ]

setup; gitwork
echo idle > "$FAKE_DIR/live.implementer"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '# implementer report\nstatus: partial\n' > $WORK/.harness/reports/implementer.md; printf '{\"status\":\"fail\",\"attempts\":3,\"step\":\"test\",\"tail\":\"x\"}' > $WORK/.harness/verify/implementer.json"
run ask implementer "do it"
check "implementer verify fail: exit 5" [ "$RC" -eq 5 ]
check "implementer verify fail: report printed" grep -q "status: partial" <<<"$OUT"
check "implementer verify fail: verify line" grep -qx "verify: FAIL (test, 3 attempts)" <<<"$OUT"

setup; gitwork
echo idle > "$FAKE_DIR/live.implementer"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '# r\nstatus: done\n' > $WORK/.harness/reports/implementer.md; printf '{\"status\":\"pass\",\"attempts\":1,\"step\":\"\",\"tail\":\"\"}' > $WORK/.harness/verify/implementer.json"
run ask implementer "do it"
check "implementer verify pass: exit 0" [ "$RC" -eq 0 ]

setup; gitwork
echo idle > "$FAKE_DIR/live.implementer"
mkdir -p .harness/verify; echo '{"status":"fail","attempts":3,"step":"test","tail":""}' > .harness/verify/implementer.json
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it"
check "stale verify fail cleared by baseline" [ "$RC" -eq 0 ]

for v in "FAIL:5" "PASS:0"; do
  setup
  echo idle > "$FAKE_DIR/live.reviewer"
  export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# reviewer report\nstatus: done\n- [Minor] x\n\nVERDICT: ${v%%:*}\n\n' > $WORK/.harness/reports/reviewer.md"
  run ask reviewer "review"
  check "reviewer VERDICT ${v%%:*}: exit" [ "$RC" -eq "${v##*:}" ]
  check "reviewer VERDICT ${v%%:*}: report printed" grep -q "VERDICT: ${v%%:*}" <<<"$OUT"
done

setup
echo idle > "$FAKE_DIR/live.reviewer"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# reviewer report\nstatus: done\nno findings\n' > $WORK/.harness/reports/reviewer.md"
run ask reviewer "review"
check "reviewer missing VERDICT: exit 3" [ "$RC" -eq 3 ]
check "reviewer missing VERDICT: message" grep -q "VERDICT" <<<"$OUT"

setup
echo idle > "$FAKE_DIR/live.reviewer"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nVERDICT: PASS\nmore text after\n' > $WORK/.harness/reports/reviewer.md"
run ask reviewer "review"
check "reviewer VERDICT not last line: exit 3" [ "$RC" -eq 3 ]

setup
echo idle > "$FAKE_DIR/live.analyst"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nVERDICT: FAIL\n' > $WORK/.harness/reports/analyst.md"
run ask analyst "q"
check "analyst unaffected by VERDICT text" [ "$RC" -eq 0 ]

# --- report: same finish logic as ask ----------------------------------------------
setup; gitwork
mkdir -p .harness/reports .harness/verify
printf '# r\nstatus: partial\n' > .harness/reports/implementer.md
echo '{"status":"fail","attempts":3,"step":"test","tail":""}' > .harness/verify/implementer.json
run report implementer
check "report implementer verify fail: exit 5" [ "$RC" -eq 5 ]
check "report implementer verify fail: line" grep -qx "verify: FAIL (test, 3 attempts)" <<<"$OUT"
echo '{"status":"pass","attempts":1,"step":"","tail":""}' > .harness/verify/implementer.json
run report implementer
check "report implementer verify pass: exit 0" [ "$RC" -eq 0 ]

setup
mkdir -p .harness/reports
printf '# r\nVERDICT: FAIL\n' > .harness/reports/reviewer.md
run report reviewer
check "report reviewer FAIL: exit 5" [ "$RC" -eq 5 ]
printf '# r\nVERDICT: PASS\n' > .harness/reports/reviewer.md
run report reviewer
check "report reviewer PASS: exit 0" [ "$RC" -eq 0 ]
printf '# r\nno verdict\n' > .harness/reports/reviewer.md
run report reviewer
check "report reviewer no VERDICT: exit 3" [ "$RC" -eq 3 ]

setup
echo working > "$FAKE_DIR/live.implementer"
mkdir -p .harness/reports; echo unverified > .harness/reports/implementer.md
run report implementer
check "report while working: exit 4" [ "$RC" -eq 4 ]
check "report while working: not printed" not_grep "unverified" <(printf '%s' "$OUT")
check "report while working: message" grep -q "working" <<<"$OUT"

# ask with a failing baseline still clears a stale fail result
setup
echo idle > "$FAKE_DIR/live.implementer"
mkdir -p .harness/verify; echo '{"status":"fail","attempts":3,"step":"test","tail":""}' > .harness/verify/implementer.json
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it"
check "non-git: stale verify fail cleared" [ "$RC" -eq 0 ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
