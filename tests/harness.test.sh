#!/bin/bash
# Tests for bin/harness against tests/fake-herdr. Run: /bin/bash tests/harness.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
FAKE_BIN="$HERE/fake-herdr"
# WN <role> — scoped herdr name for the current directory (the repo under test)
WN() { env -u HARNESS_ROLE /bin/bash "$HARNESS" _wname "$1"; }
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
  export HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2
  cd "$WORK" || exit 1
}

# run ARGS... -> sets OUT, RC  (killed by SIGALRM after 5s so a hang fails fast)
GUARD="perl -e alarm(5);exec(@ARGV)"
run() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
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
OUT=$(env -u HERDR_ENV -u HARNESS_ROLE PATH="$FAKE_BIN:$PATH" /bin/bash "$HARNESS" status 2>&1); RC=$?
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
check "spawn splits with env" logged "pane split --current --direction right --cwd $WORK --env HARNESS_ROLE=worker --env CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000 --no-focus"
check "spawn starts agent" logged "agent start $(WN analyst) --kind claude --pane w1:p2 -- --agent analyst"
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
OUT=$(HERDR_ENV=1 HERDR_PANE_ID= PATH="$FAKE_BIN:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" spawn analyst 2>&1); RC=$?
check "no HERDR_PANE_ID -> right" logged "pane split --current --direction right"
check "no HERDR_PANE_ID: no layout call" not_logged "pane layout"

# --- worker guard: ask/spawn refused in worker sessions ----------------------------
setup
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" HARNESS_ROLE=worker $GUARD /bin/bash "$HARNESS" ask analyst x 2>&1); RC=$?
check "worker ask rc 1" [ "$RC" -eq 1 ]
check "worker ask message" grep -q conductor <<<"$OUT"
check "worker ask: no progress.jsonl" [ ! -e "$WORK/.harness/progress.jsonl" ]
check "worker ask: no routing.jsonl" [ ! -e "$WORK/.harness/routing.jsonl" ]
check "worker ask: nothing sent" not_logged "agent prompt"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" HARNESS_ROLE=worker $GUARD /bin/bash "$HARNESS" spawn analyst 2>&1); RC=$?
check "worker spawn rc 1" [ "$RC" -eq 1 ]
check "worker spawn: no pane split" not_logged "pane split"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" HARNESS_ROLE=worker $GUARD /bin/bash "$HARNESS" status 2>&1); RC=$?
check "worker status still works" [ "$RC" -eq 0 ]

# --- ask: success ----------------------------------------------------------------
setup
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports && printf '# analyst report\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
run ask analyst "Describe the repo"
check "ask rc" [ "$RC" -eq 0 ]
check "ask spawns first" logged "agent start $(WN analyst)"
check "ask prompts with wait" logged "agent prompt $(WN analyst) Describe\\ the\\ repo --wait --timeout 600000"
check "ask prints report" grep -q "status: done" <<<"$OUT"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "again" 2>/dev/null); RC=$?
check "ask stdout is exactly the report" [ "$OUT" = "$(printf '# analyst report\nstatus: done')" ]

# --- ask: dash-leading instruction stays positional ------------------------------
setup
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports && echo ok > $WORK/.harness/reports/analyst.md"
run ask analyst "--not-a-flag text"
check "dash text rc" [ "$RC" -eq 0 ]
check "dash text is prompt's third arg" logged "agent prompt $(WN analyst) --not-a-flag\\ text --wait"

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
echo idle > "$FAKE_DIR/live.$(WN analyst)"
touch "$FAKE_DIR/prompt_fail"
run ask analyst "x"
check "prompt rejected rc" [ "$RC" -eq 4 ]
check "prompt rejected message" grep -q "not accepted" <<<"$OUT"
check "prompt rejected: herdr error shown" grep -q "socket_unavailable" <<<"$OUT"

# --- ask: reuse + custom timeout + stale report removed --------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN implementer)"
mkdir -p .harness/reports && echo "OLD" > .harness/reports/implementer.md
export FAKE_PROMPT_HOOK="printf 'NEW\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it" --timeout 1000
check "ask reuse: no spawn" not_logged "agent start"
check "ask custom timeout" logged "--wait --timeout 1000"
check "ask stale report replaced" [ "$OUT" = "NEW" ]

# --- ask: blocked before prompt --------------------------------------------------
setup
echo blocked > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "x"
check "blocked before rc" [ "$RC" -eq 2 ]
check "blocked before: no prompt sent" not_logged "agent prompt"
check "blocked before: screen" grep -q "fake screen line" <<<"$OUT"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "x" 2>/dev/null); RC=$?
check "blocked: screen on stdout" grep -q "fake screen line" <<<"$OUT"

# --- ask: blocked after prompt ----------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
export FAKE_PROMPT_HOOK="echo blocked > $FAKE_DIR/live.$(WN analyst)"
run ask analyst "x"
check "blocked after rc" [ "$RC" -eq 2 ]
check "blocked after: screen" grep -q "fake screen line" <<<"$OUT"

# --- ask: finished without report ------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
run ask reviewer "review" --timeout 2000
check "no report rc" [ "$RC" -eq 4 ]
check "no report message" grep -q "without a report" <<<"$OUT"
check "no report: screen" grep -q "fake screen line" <<<"$OUT"

# --- ask: still working (stalled/timeout) -----------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
export FAKE_PROMPT_HOOK="echo working > $FAKE_DIR/live.$(WN reviewer)"
run ask reviewer "review" --timeout 1000
check "working rc" [ "$RC" -eq 4 ]
check "working message" grep -q "still working" <<<"$OUT"

# --- ask: agent vanished after prompt -> unknown ----------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
export FAKE_PROMPT_HOOK="rm -f $FAKE_DIR/live.$(WN analyst)"
run ask analyst "x"
check "vanished rc" [ "$RC" -eq 4 ]
check "vanished reports unknown status" grep -q "status is 'unknown'" <<<"$OUT"
check "vanished: agent get diagnostic" grep -q "agent not found" <<<"$OUT"
check "vanished: pane screen still shown" grep -q "fake screen line" <<<"$OUT"

# --- ask: worker still busy with a previous instruction ---------------------------
setup
echo working > "$FAKE_DIR/live.$(WN analyst)"
mkdir -p .harness/reports && echo "PENDING" > .harness/reports/analyst.md
run ask analyst "second"
check "busy rc" [ "$RC" -eq 4 ]
check "busy: no prompt sent" not_logged "agent prompt"
check "busy: report untouched" [ "$(cat "$WORK/.harness/reports/analyst.md")" = "PENDING" ]
check "busy: points to harness report" grep -q "harness report analyst" <<<"$OUT"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "second" 2>/dev/null); RC=$?
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
echo working > "$FAKE_DIR/live.$(WN implementer)"
run status
check "status rc" [ "$RC" -eq 0 ]
check "status live line" grep -Eq "^implementer +working +w1:p2 +-$" <<<"$OUT"
check "status dead line" grep -Eq "^analyst +-$" <<<"$OUT"

# --- close ------------------------------------------------------------------------------
setup
run spawn analyst
run close analyst
check "close rc" [ "$RC" -eq 0 ]
check "close calls pane close" logged "pane close w1:p2"
check "close unregisters" [ ! -s "$WORK/.harness/panes" ]

setup
for a in analyst implementer reviewer; do echo idle > "$FAKE_DIR/live.$(WN $a)"; done
echo w1:p2 > "$FAKE_DIR/pane.$(WN analyst)"
echo w1:p3 > "$FAKE_DIR/pane.$(WN implementer)"
echo w1:p4 > "$FAKE_DIR/pane.$(WN reviewer)"
mkdir -p .harness
printf 'analyst w1:p2\nimplementer w1:p3\nreviewer w1:p4\n' > .harness/panes
run close analyst
check "close multi rc" [ "$RC" -eq 0 ]
check "close multi: closes analyst pane" logged "pane close w1:p2"
check "close multi: analyst removed" not_grep "^analyst " "$WORK/.harness/panes"
check "close multi: implementer kept" grep -q "^implementer w1:p3$" "$WORK/.harness/panes"
check "close multi: reviewer kept" grep -q "^reviewer w1:p4$" "$WORK/.harness/panes"

setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"   # live but not created by harness
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
echo idle > "$FAKE_DIR/live.$(WN implementer)"
export FAKE_PROMPT_HOOK="test -s $WORK/.harness/verify/implementer.base && touch $WORK/seen-base; mkdir -p $WORK/.harness/reports; printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it"
check "implementer baseline before prompt" [ -e "$WORK/seen-base" ]
check "implementer verify none: exit 0" [ "$RC" -eq 0 ]

setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '# implementer report\nstatus: partial\n' > $WORK/.harness/reports/implementer.md; printf '{\"status\":\"fail\",\"attempts\":3,\"step\":\"test\",\"tail\":\"x\"}' > $WORK/.harness/verify/implementer.json"
run ask implementer "do it"
check "implementer verify fail: exit 5" [ "$RC" -eq 5 ]
check "implementer verify fail: report printed" grep -q "status: partial" <<<"$OUT"
check "implementer verify fail: verify line" grep -qx "verify: FAIL (test, 3 attempts)" <<<"$OUT"

setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '# r\nstatus: done\n' > $WORK/.harness/reports/implementer.md; printf '{\"status\":\"pass\",\"attempts\":1,\"step\":\"\",\"tail\":\"\"}' > $WORK/.harness/verify/implementer.json"
run ask implementer "do it"
check "implementer verify pass: exit 0" [ "$RC" -eq 0 ]

setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"
mkdir -p .harness/verify; echo '{"status":"fail","attempts":3,"step":"test","tail":""}' > .harness/verify/implementer.json
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it"
check "stale verify fail cleared by baseline" [ "$RC" -eq 0 ]

for v in "FAIL:5" "PASS:0"; do
  setup
  echo idle > "$FAKE_DIR/live.$(WN reviewer)"
  export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# reviewer report\nstatus: done\n- [Minor] x\n\nVERDICT: ${v%%:*}\n\n' > $WORK/.harness/reports/reviewer.md"
  run ask reviewer "review"
  check "reviewer VERDICT ${v%%:*}: exit" [ "$RC" -eq "${v##*:}" ]
  check "reviewer VERDICT ${v%%:*}: report printed" grep -q "VERDICT: ${v%%:*}" <<<"$OUT"
done

setup
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# reviewer report\nstatus: done\nno findings\n' > $WORK/.harness/reports/reviewer.md"
run ask reviewer "review"
check "reviewer missing VERDICT: exit 3" [ "$RC" -eq 3 ]
check "reviewer missing VERDICT: message" grep -q "VERDICT" <<<"$OUT"

setup
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nVERDICT: PASS\nmore text after\n' > $WORK/.harness/reports/reviewer.md"
run ask reviewer "review"
check "reviewer VERDICT not last line: exit 3" [ "$RC" -eq 3 ]

setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
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
echo working > "$FAKE_DIR/live.$(WN implementer)"
mkdir -p .harness/reports; echo unverified > .harness/reports/implementer.md
run report implementer
check "report while working: exit 4" [ "$RC" -eq 4 ]
check "report while working: not printed" not_grep "unverified" <(printf '%s' "$OUT")
check "report while working: message" grep -q "working" <<<"$OUT"

# ask with a failing baseline still clears a stale fail result
setup
echo idle > "$FAKE_DIR/live.$(WN implementer)"
mkdir -p .harness/verify; echo '{"status":"fail","attempts":3,"step":"test","tail":""}' > .harness/verify/implementer.json
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it"
check "non-git: stale verify fail cleared" [ "$RC" -eq 0 ]

# --- implementer: harness-verify missing is loud ------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN implementer)"
NB=$(mktemp -d); ln -s "$(command -v jq)" "$NB/jq"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$NB:/usr/bin:/bin" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" ask implementer "x" 2>&1); RC=$?
check "no harness-verify: exit 1" [ "$RC" -eq 1 ]
check "no harness-verify: names install.sh" grep -q "install.sh" <<<"$OUT"
check "no harness-verify: nothing prompted" not_logged "agent prompt"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$NB:/usr/bin:/bin" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "x" 2>&1); RC=$?
check "no harness-verify: analyst unaffected" not_grep "harness-verify not found" <(printf "%s" "$OUT")
rm -rf "$NB"

# --- implementer: hook killed mid-run leaves only .pending ----------------------------
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nstatus: done\n' > $WORK/.harness/reports/implementer.md.pending"
run ask implementer "do it" --timeout 2500
check "interrupted ask: exit 5" [ "$RC" -eq 5 ]
check "interrupted ask: INTERRUPTED line" grep -qx "verify: INTERRUPTED" <<<"$OUT"
check "interrupted ask: report restored" [ -f "$WORK/.harness/reports/implementer.md" ]
check "interrupted ask: pending gone" [ ! -e "$WORK/.harness/reports/implementer.md.pending" ]
unset FAKE_PROMPT_HOOK

setup
echo idle > "$FAKE_DIR/live.$(WN implementer)"
mkdir -p .harness/reports; echo '# r' > .harness/reports/implementer.md.pending
run report implementer
check "interrupted report: exit 5" [ "$RC" -eq 5 ]
check "interrupted report: INTERRUPTED line" grep -qx "verify: INTERRUPTED" <<<"$OUT"

setup
echo working > "$FAKE_DIR/live.$(WN implementer)"
mkdir -p .harness/reports; echo '# r' > .harness/reports/implementer.md.pending
run report implementer
check "pending while working: exit 4" [ "$RC" -eq 4 ]
check "pending while working: not restored" [ -e "$WORK/.harness/reports/implementer.md.pending" ]

# --- ask again after verify FAIL: no re-baseline, still exit 5 ------------------------
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"
mkdir -p .claude; echo '{"test":"exit 1","maxAttempts":1}' > .claude/harness.json
printf 'fake/\nherdr.log\n' > .gitignore   # harness noise must not count as changes
STOPJ="printf '{\"agent_type\":\"implementer\",\"cwd\":\"$WORK\"}' | harness-verify stop >/dev/null"
export FAKE_PROMPT_HOOK="echo c > $WORK/new.txt; $STOPJ; $STOPJ; mkdir -p $WORK/.harness/reports; printf '# r\nstatus: partial\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it"
check "refail: first ask exit 5" [ "$RC" -eq 5 ]
export FAKE_PROMPT_HOOK="$STOPJ; mkdir -p $WORK/.harness/reports; printf '# r\nstatus: partial\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "retry without changes"
check "refail: second ask (no new change) exit 5" [ "$RC" -eq 5 ]
check "refail: verify line" grep -q "verify: FAIL" <<<"$OUT"
unset FAKE_PROMPT_HOOK

# --- repo-scoped worker names + cwd check ------------------------------------------------
setup
n1=$(WN analyst); n1b=$(WN analyst)
check "scoped name: <role>-<8 hex>" grep -Eq '^analyst-[0-9a-f]{8}$' <<<"$n1"
check "scoped name: stable" [ "$n1" = "$n1b" ]
run spawn analyst
check "scoped name: used for agent start" logged "agent start $n1 --kind claude"
check "scoped name: role kept for --agent" logged "-- --agent analyst"
setup
n2=$(WN analyst)
check "scoped name: differs per repo" [ "$n1" != "$n2" ]
mkdir -p sub; ( cd sub && git init -q . ); n3=$(cd sub && WN analyst)
check "scoped name: git top-level, not PWD" [ "$n3" != "$n2" ]
n4=$(cd sub && mkdir -p deep && cd deep && WN analyst)
check "scoped name: subdir of repo shares the name" [ "$n3" = "$n4" ]

# worker in another directory -> exit 6, nothing sent
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
mkdir -p "$WORK/../other-repo-$$"; OTHER=$(cd "$WORK/../other-repo-$$" && pwd -P)
echo "$OTHER" > "$FAKE_DIR/cwd.$(WN analyst)"
run ask analyst "q"
check "foreign cwd: ask exit 6" [ "$RC" -eq 6 ]
check "foreign cwd: message" grep -q "outside this repo" <<<"$OUT"
check "foreign cwd: nothing prompted" not_logged "agent prompt"
run spawn analyst
check "foreign cwd: spawn exit 6" [ "$RC" -eq 6 ]
run report analyst
check "foreign cwd: report exit 6" [ "$RC" -eq 6 ]
rmdir "$OTHER"

# worker in a subdirectory of the repo is accepted
setup
mkdir -p sub/dir
echo idle > "$FAKE_DIR/live.$(WN analyst)"
echo "$WORK/sub/dir" > "$FAKE_DIR/cwd.$(WN analyst)"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
run ask analyst "q"
check "subdir cwd: ask accepted" [ "$RC" -eq 0 ]
unset FAKE_PROMPT_HOOK

# same-prefix sibling dir is not "inside" the repo
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
mkdir -p "$WORK-other"; echo "$(cd "$WORK-other" && pwd -P)" > "$FAKE_DIR/cwd.$(WN analyst)"
run ask analyst "q"
check "sibling prefix cwd: ask exit 6" [ "$RC" -eq 6 ]
rmdir "$WORK-other"

# worker cwd given via a symlink to the repo is accepted
setup
LINK="$WORK-link"; ln -s "$WORK" "$LINK"
echo idle > "$FAKE_DIR/live.$(WN analyst)"
echo "$LINK" > "$FAKE_DIR/cwd.$(WN analyst)"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
run ask analyst "q"
check "symlink cwd: ask accepted" [ "$RC" -eq 0 ]
echo "$LINK/gone" > "$FAKE_DIR/cwd.$(WN analyst)"
run ask analyst "q"
check "symlink vanished cwd: ask accepted" [ "$RC" -eq 0 ]
unset FAKE_PROMPT_HOOK
rm -f "$LINK"

# close on an out-of-repo worker -> exit 6
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
echo "/nonexistent-elsewhere" > "$FAKE_DIR/cwd.$(WN analyst)"
run close analyst
check "foreign cwd: close exit 6" [ "$RC" -eq 6 ]

# herdr reports no cwd -> accepted with a warning
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
: > "$FAKE_DIR/cwd.$(WN analyst)"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# r\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
run ask analyst "q"
check "missing cwd: ask accepted" [ "$RC" -eq 0 ]
check "missing cwd: warning" grep -q "did not report cwd" <<<"$OUT"
unset FAKE_PROMPT_HOOK

# old unscoped worker of this repo -> one-line hint, no kill
setup
echo idle > "$FAKE_DIR/live.analyst"
run spawn analyst
check "migration hint printed" grep -q "old unscoped worker 'analyst'" <<<"$OUT"
check "migration: old worker not closed" [ -f "$FAKE_DIR/live.analyst" ]

# --- ask: completion = Stop-hook marker for this ask + fresh report ------------------
REPORT_HOOK() { echo "mkdir -p $WORK/.harness/reports && printf '# $1 report\nstatus: done\n' > $WORK/.harness/reports/$1.md"; }

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
run ask analyst "q"
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
