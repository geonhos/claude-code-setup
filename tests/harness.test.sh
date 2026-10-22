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
  export HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2 HARNESS_CLEAR_INTERVAL=0
  cd "$WORK" || exit 1
}

# run ARGS... -> sets OUT, RC  (killed by SIGALRM after 5s so a hang fails fast)
GUARD="perl -e alarm(5);exec(@ARGV)"
run() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}

not() { ! "$@"; }
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
# role-aware default timeout: implementer 1740000, reviewer 600000, explicit wins
: > "$FAKE_LOG"
run ask implementer "do it"
check "default timeout: implementer 1740000" logged "--wait --timeout 1740000"
: > "$FAKE_LOG"
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports && printf 'R\n' > $WORK/.harness/reports/reviewer.md"
run ask reviewer "review"
check "default timeout: reviewer 600000" logged "--wait --timeout 600000"
check "default timeout: reviewer not 1740000" not_logged "--timeout 1740000"
unset FAKE_PROMPT_HOOK

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

# --- report: ## Learned -> docs/wiki/inbox -------------------------------------------
setup
mkdir -p .harness/reports .harness/asks docs/wiki
printf '1700000000-123-456 1700000000\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Learned\n- stat -f is GNU-hostile (bin/harness:815)\n- vague claim with no proof\n- fixed in commit 79a1964\n## Open questions\n- none\n' > .harness/reports/analyst.md
run report analyst
check "learned rc" [ "$RC" -eq 0 ]
check "learned queue line" grep -q '^wiki: 2 lessons queued in docs/wiki/inbox/' <<<"$OUT"
Q=$(ls docs/wiki/inbox/*-analyst-1700000000-123-456.md 2>/dev/null | head -1)
check "learned file named by role+ask-id" [ -n "$Q" ]
check "learned header" grep -q '^role: analyst' "$Q"
check "learned header ask-id" grep -q '^ask-id: 1700000000-123-456' "$Q"
check "learned keeps evidence bullet" grep -q 'bin/harness:815' "$Q"
check "learned caps at 2 bullets" [ "$(grep -c '^- ' "$Q")" -eq 2 ]
check "learned drops bullet without evidence" not grep -q 'vague claim' "$Q"
run report analyst
check "learned warns on dropped bullet" grep -q 'dropped 1 Learned bullet' <<<"$OUT"
check "learned idempotent (one file)" [ "$(ls docs/wiki/inbox | wc -l | tr -d ' ')" -eq 1 ]
check "learned second run no queue line" not grep -q '^wiki:' <<<"$OUT"

setup
mkdir -p .harness/reports docs/wiki
printf '# analyst report\nstatus: done\n## Learned\n- none\n## Open questions\n- none\n' > .harness/reports/analyst.md
run report analyst
check "learned none: nothing queued" [ ! -d docs/wiki/inbox ]
check "learned none: no wiki line" not grep -q '^wiki:' <<<"$OUT"
printf '# analyst report\nstatus: done\n## Learned\n- no proof here at all\n' > .harness/reports/analyst.md
run report analyst
check "learned all dropped: nothing queued" [ ! -d docs/wiki/inbox ]
printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md
run report analyst
check "no Learned section: nothing queued" [ ! -d docs/wiki/inbox ]
mkdir -p .harness/reports .harness/asks
printf '1700000001-1-2 1700000001\n' > .harness/asks/reviewer.current
printf '# reviewer report\nstatus: done\n## Learned\n- race seen in .harness/progress.jsonl\nVERDICT: PASS\n' > .harness/reports/reviewer.md
run report reviewer
check "learned before VERDICT: rc 0" [ "$RC" -eq 0 ]
check "learned reviewer queued" [ "$(ls docs/wiki/inbox/*-reviewer-* 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
check "reviewer VERDICT still last line" [ "$(printf '%s\n' "$OUT" | tail -1)" = "VERDICT: PASS" ]

# learned: continuation lines, evidence strictness, idempotency, no ask-id, no docs/wiki
learned_case() { # learned_case BODY -> fresh wiki repo, report, sets OUT/RC and Q (count of queued files)
  setup
  mkdir -p .harness/reports .harness/asks docs/wiki
  printf '1700000002-9-9 1700000002\n' > .harness/asks/analyst.current
  printf '# analyst report\nstatus: done\n## Learned\n%b## Open questions\n- none\n' "$1" > .harness/reports/analyst.md
  run report analyst
  Q=$(ls docs/wiki/inbox/ 2>/dev/null | wc -l | tr -d ' ')
}
learned_case '- wrapped lesson that\n  cites tests/x.sh:42 on the next line\n'
check "learned continuation evidence kept" [ "$Q" -eq 1 ]
check "learned continuation joined" grep -q 'that cites tests/x.sh:42' docs/wiki/inbox/*.md
for ok in 'see 1700000000-123-456' 'bin/harness:815' 'foo.sh:12' 'commit 79a1964' 'commit deadbee1' 'in .harness/progress.jsonl' 'see run.log'; do
  learned_case "- $ok\n"
  check "evidence accepted: $ok" [ "$Q" -eq 1 ]
done
for bad in 'step:2' 'host:8080' 'about 12345678 items' 'deadbeef word' 'abcdefabc' 'v1.2 notes'; do
  learned_case "- $bad\n"
  check "evidence rejected: $bad" [ "$Q" -eq 0 ]
done
learned_case '- see bin/harness:1\n'
run report analyst
check "learned idempotent by ask-id (different date)" [ "$(ls docs/wiki/inbox | wc -l | tr -d ' ')" -eq 1 ]
mv docs/wiki/inbox/*.md docs/wiki/inbox/2020-01-01-analyst-1700000002-9-9.md
run report analyst
check "learned idempotent ignores date prefix" [ "$(ls docs/wiki/inbox | wc -l | tr -d ' ')" -eq 1 ]
learned_case '- see bin/harness:1\n'
rm -rf docs .harness/asks/analyst.current; mkdir -p docs/wiki
run report analyst
check "learned no ask-id: nothing queued" [ ! -d docs/wiki/inbox ]
check "learned no ask-id: warns" grep -q 'no ask-id' <<<"$OUT"
setup
mkdir -p .harness/reports .harness/asks
printf '1700000002-9-9 1700000002\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Learned\n- see bin/harness:1\n' > .harness/reports/analyst.md
run report analyst
check "learned without docs/wiki: nothing created" [ ! -d docs ]

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

# --- pane lifecycle: close guards, after-ask, TTL, legacy ------------------------------
# live_worker ROLE STATUS PANE — a live, harness-registered worker
live_worker() {
  echo "$2" > "$FAKE_DIR/live.$(WN "$1")"
  echo "$3" > "$FAKE_DIR/pane.$(WN "$1")"
  mkdir -p .harness; echo "$1 $3" >> .harness/panes
}
# stale ROLE MINUTES — collected-stamp of that age
stale() { mkdir -p .harness/asks; : > ".harness/asks/$1.finished"; touch -t "$(date -v-"$2"M +%Y%m%d%H%M 2>/dev/null || date -d "$2 minutes ago" +%Y%m%d%H%M)" ".harness/asks/$1.finished"; }

# refuses while working / blocked / uncollected report; --force overrides
setup
live_worker analyst working w1:p2
run close analyst
check "close working: rc 4" [ "$RC" -eq 4 ]
check "close working: message" grep -q "is working" <<<"$OUT"
check "close working: no pane close" not_logged "pane close"
run close analyst --force
check "close working --force: rc 0" [ "$RC" -eq 0 ]
check "close working --force: closed" logged "pane close w1:p2"
check "close --force: unregistered" not_grep "^analyst " "$WORK/.harness/panes"
setup
live_worker analyst blocked w1:p2
run close analyst
check "close blocked: rc 4" [ "$RC" -eq 4 ]
setup
live_worker analyst idle w1:p2
mkdir -p .harness/reports; echo "# r" > .harness/reports/analyst.md
run close analyst
check "close uncollected report: rc 4" [ "$RC" -eq 4 ]
check "close uncollected report: message" grep -q "not collected" <<<"$OUT"
run close analyst --force
check "close uncollected --force: rc 0" [ "$RC" -eq 0 ]
setup
live_worker implementer idle w1:p2
mkdir -p .harness/reports; echo x > .harness/reports/implementer.md.pending
run close implementer
check "close .pending: rc 4" [ "$RC" -eq 4 ]
# collected report (stamp newer than report) closes
setup
live_worker analyst idle w1:p2
mkdir -p .harness/reports .harness/asks; echo "# r" > .harness/reports/analyst.md
sleep 1; : > .harness/asks/analyst.finished
run close analyst
check "close collected report: rc 0" [ "$RC" -eq 0 ]
check "close logs event" grep -q '"event":"close","role":"analyst","pane":"w1:p2","reason":"manual"' .harness/progress.jsonl
check "close shows in progress.md" grep -q "^Recent closes (max 5): .* analyst (manual)" .harness/progress.md

# --all: closes idle ones, rc 4 when one is refused; other-repo -> 6
setup
live_worker analyst idle w1:p2; live_worker implementer working w1:p3
run close --all
check "close --all: refused rc 4" [ "$RC" -eq 4 ]
check "close --all: idle closed" logged "pane close w1:p2"
check "close --all: working kept" not_logged "pane close w1:p3"
setup
live_worker analyst idle w1:p2
echo "/nonexistent-elsewhere" > "$FAKE_DIR/cwd.$(WN analyst)"
run close --all
check "close --all other repo: rc 6" [ "$RC" -eq 6 ]
check "close --all other repo: not closed" not_logged "pane close"
run close --bogus
check "close bad flag: usage rc 1" [ "$RC" -eq 1 ]

# idle TTL
setup
live_worker analyst idle w1:p2; live_worker reviewer idle w1:p3; live_worker implementer idle w1:p4
stale analyst 90
: > .harness/asks/reviewer.finished           # fresh
echo "/nonexistent-elsewhere" > "$FAKE_DIR/cwd.$(WN implementer)"; stale implementer 90   # other repo
run status
check "ttl: stale analyst reaped" logged "pane close w1:p2"
check "ttl: fresh reviewer kept" not_logged "pane close w1:p3"
check "ttl: other-repo implementer kept" not_logged "pane close w1:p4"
check "ttl: logged with reason" grep -q '"role":"analyst".*"reason":"ttl"' .harness/progress.jsonl
check "ttl: config created" [ -s .harness/config.json ]
setup
live_worker analyst idle w1:p2; stale analyst 90
mkdir -p .harness/reports; echo "# r" > .harness/reports/analyst.md      # newer than stamp: uncollected
run status
check "ttl: uncollected report kept" not_logged "pane close"
rm .harness/reports/analyst.md; echo x > .harness/reports/analyst.md.pending
run status
check "ttl: .pending kept" not_logged "pane close"
rm .harness/reports/analyst.md.pending; echo working > "$FAKE_DIR/live.$(WN analyst)"
run status
check "ttl: working kept" not_logged "pane close"
echo idle > "$FAKE_DIR/live.$(WN analyst)"
HARNESS_NO_AUTOCLOSE=1 run status
check "ttl: HARNESS_NO_AUTOCLOSE=1 disables" not_logged "pane close"
HARNESS_IDLE_TTL_MINUTES=0 run status
check "ttl: 0 disables" not_logged "pane close"
HARNESS_IDLE_TTL_MINUTES=200 run status
check "ttl: env raises ttl" not_logged "pane close"
echo '{"idle_ttl_minutes": 120}' > .harness/config.json
run status
check "ttl: config raises ttl" not_logged "pane close"
echo '{"idle_ttl_minutes": 60}' > .harness/config.json
run status
check "ttl: config lowers ttl" logged "pane close w1:p2"

# default: implementer pane is kept (ADR 0006); config/env on_success closes after ask 0, not after 5
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK implementer)"
run ask implementer "do it"
check "default: ask rc 0" [ "$RC" -eq 0 ]
check "default: implementer pane kept" not_logged "pane close"
check "default: config template says never" jq -e '.close_after_ask.implementer=="never"' .harness/config.json
# config migration: untouched pre-ADR-0006 template is rewritten; edited / new files are not
OLDCFG=$(jq -n '.' >/dev/null; sed 's/"implementer": "never"/"implementer": "on_success"/' <<'EOC'
{
  "_doc": "close_after_ask.<role>: never | on_success (close the worker after `harness ask` exits 0; reviewer: 0 or 5). idle_ttl_minutes: close this repo's workers idle longer than N minutes after their last collected report (0 = off). HARNESS_NO_AUTOCLOSE=1 disables both. Env overrides: HARNESS_CLOSE_AFTER_ASK_<ROLE>, HARNESS_IDLE_TTL_MINUTES.",
  "close_after_ask": { "analyst": "never", "implementer": "never", "reviewer": "never" },
  "idle_ttl_minutes": 30
}
EOC
)
setup; mkdir -p .harness; printf '%s\n' "$OLDCFG" > .harness/config.json
run status
check "migrate: old template -> implementer never" jq -e '.close_after_ask.implementer=="never"' .harness/config.json
cp .harness/config.json "$WORK/new.json"; run status
check "migrate: new template untouched" cmp -s .harness/config.json "$WORK/new.json"
setup; mkdir -p .harness; printf '%s\n' "$OLDCFG" | sed 's/"idle_ttl_minutes": 30/"idle_ttl_minutes": 31/' > .harness/config.json
cp .harness/config.json "$WORK/edited.json"; run status
check "migrate: edited old file untouched" cmp -s .harness/config.json "$WORK/edited.json"
setup; mkdir -p .harness; printf '%s\n' "$OLDCFG" > .harness/config.json
OUT=$(HERDR_ENV=1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" HARNESS_ROLE=worker /bin/bash "$HARNESS" status 2>&1)
check "migrate: worker session does not rewrite" jq -e '.close_after_ask.implementer=="on_success"' .harness/config.json
export HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER=on_success
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it"
check "after_ask: ask rc 0" [ "$RC" -eq 0 ]
check "after_ask: implementer closed" logged "pane close w1:p2"
check "after_ask: logged" grep -q '"role":"implementer".*"reason":"after_ask"' .harness/progress.jsonl
check "after_ask: stdout is only the report" grep -qx "# implementer report" <<<"$OUT"
# ask after close respawns the worker
: > "$FAKE_LOG"
run ask implementer "again"
check "respawn after close: rc 0" [ "$RC" -eq 0 ]
check "respawn after close: pane split + start" logged "agent start $(WN implementer) --kind claude"
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '# implementer report\nstatus: partial\n' > $WORK/.harness/reports/implementer.md; printf '{\"status\":\"fail\",\"attempts\":3,\"step\":\"test\",\"tail\":\"x\"}' > $WORK/.harness/verify/implementer.json"
run ask implementer "do it"
check "after_ask: exit 5 not closed" [ "$RC" -eq 5 ]
check "after_ask 5: no pane close" not_logged "pane close"
setup
live_worker analyst idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q"
check "after_ask: analyst never closed" not_logged "pane close"
HARNESS_CLOSE_AFTER_ASK_ANALYST=on_success run ask analyst "q"
check "after_ask: env override closes analyst" logged "pane close w1:p2"
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK implementer)"
HARNESS_NO_AUTOCLOSE=1 run ask implementer "do it"
check "after_ask: HARNESS_NO_AUTOCLOSE=1 keeps worker" not_logged "pane close"
unset FAKE_PROMPT_HOOK HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER

# --legacy: only same-repo unscoped workers
setup
echo idle > "$FAKE_DIR/live.analyst"; echo w1:p5 > "$FAKE_DIR/pane.analyst"
echo idle > "$FAKE_DIR/live.reviewer"; echo w1:p6 > "$FAKE_DIR/pane.reviewer"; echo "/nonexistent-elsewhere" > "$FAKE_DIR/cwd.reviewer"
live_worker implementer idle w1:p7
run close --legacy
check "legacy: rc 0" [ "$RC" -eq 0 ]
check "legacy: same-repo unscoped closed" logged "pane close w1:p5"
check "legacy: other-repo unscoped kept" not_logged "pane close w1:p6"
check "legacy: scoped worker kept" not_logged "pane close w1:p7"
check "legacy: logged" grep -q '"role":"analyst".*"reason":"legacy"' .harness/progress.jsonl
echo working > "$FAKE_DIR/live.analyst"
run close --legacy
check "legacy working: rc 4" [ "$RC" -eq 4 ]
run spawn analyst
check "migration hint mentions --legacy" grep -q "harness close --legacy" <<<"$OUT"

# --- review fixes: --keep note, stamps, race, pane gone, progress.md ------------------
# 1: --keep after an auto-close prints the note; no note without --keep; exit 5 keeps the worker
export HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER=on_success
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK implementer)"
run ask implementer "one"
check "keep note: first ask closes" [ "$RC" -eq 0 ]
run ask implementer "two" --keep
check "keep note: rc 0" [ "$RC" -eq 0 ]
check "keep note: printed" grep -q "harness: note: implementer was closed (after_ask) — previous context is gone; running on a fresh worker" <<<"$OUT"
setup
live_worker implementer idle w1:p2
run ask implementer "one"
run ask implementer "two"
check "no note without --keep" not_grep "previous context is gone" <(echo "$OUT")
setup
live_worker analyst idle w1:p2; stale analyst 90
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q" --keep
check "keep note after ttl reap" grep -q "analyst was closed (ttl)" <<<"$OUT"
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '# implementer report\nstatus: partial\n' > $WORK/.harness/reports/implementer.md; printf '{\"status\":\"fail\",\"attempts\":3,\"step\":\"test\",\"tail\":\"x\"}' > $WORK/.harness/verify/implementer.json"
run ask implementer "one"
check "exit 5: worker stays" bash -c '[ "$1" -eq 5 ] && ! grep -qF "pane close" "$2"' _ "$RC" "$FAKE_LOG"
run ask implementer "one-b" --fresh >/dev/null; : > "$FAKE_LOG"
run ask implementer "fix" --keep
check "exit 5 then --keep: context kept, no note" not_grep "previous context is gone" <(echo "$OUT")
check "exit 5 then --keep: no /clear" not_logged "/clear"
unset FAKE_PROMPT_HOOK HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER

# 2: harness report on an interrupted verify stamps .finished
setup
live_worker implementer idle w1:p2
mkdir -p .harness/reports; echo "# r" > .harness/reports/implementer.md.pending
run report implementer
check "report interrupted: rc 5" [ "$RC" -eq 5 ]
check "report interrupted: stamped" [ -f .harness/asks/implementer.finished ]

# 3: starting an ask removes the collected stamp
setup
live_worker analyst idle w1:p2; mkdir -p .harness/asks; : > .harness/asks/analyst.finished
export FAKE_PROMPT_HOOK="test ! -e $WORK/.harness/asks/analyst.finished && touch $WORK/no-stamp-in-flight"
run ask analyst "q" --timeout 1000
check "ask in flight: no .finished" [ -e "$WORK/no-stamp-in-flight" ]
unset FAKE_PROMPT_HOOK

# 4: pane still present after close -> failure, registry kept
setup
live_worker analyst idle w1:p2
touch "$FAKE_DIR/close_noop"
HARNESS_CLOSE_POLLS=2 HARNESS_CLOSE_INTERVAL=0.1 run close analyst
check "pane survives: rc 1" [ "$RC" -eq 1 ]
check "pane survives: message" grep -q "still present" <<<"$OUT"
check "pane survives: registry kept" grep -q "^analyst w1:p2$" .harness/panes
check "pane survives: no close event" not_grep '"event":"close"' .harness/progress.jsonl

# 4b: a transient `pane get` error is not proof the pane is gone
setup
live_worker analyst idle w1:p2
touch "$FAKE_DIR/get_error"
HARNESS_CLOSE_POLLS=2 HARNESS_CLOSE_INTERVAL=0.1 run close analyst
check "pane get transient error: rc 1" [ "$RC" -eq 1 ]
check "pane get transient error: registry kept" grep -q "^analyst w1:p2$" .harness/panes

# 5: progress.md separates closes; ask-window lookups ignore them
setup
mkdir -p .harness
i=0; while [ $i -lt 20 ]; do echo '{"ts":"t","event":"close","role":"implementer","pane":"p","reason":"after_ask"}' >> .harness/progress.jsonl; i=$((i + 1)); done
echo '{"ts":"t0","agent":"analyst","exit":0,"summary":"S"}' | cat - .harness/progress.jsonl > .harness/j && mv .harness/j .harness/progress.jsonl
live_worker analyst idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q"
check "progress.md: asks listed" grep -q "analyst exit 0" .harness/progress.md
check "progress.md: no close line in asks" not_grep "^- .* close " .harness/progress.md
check "progress.md: closes line capped at 5" [ "$(grep '^Recent closes' .harness/progress.md | tr ';' '\n' | wc -l | tr -d ' ')" -le 5 ]
unset FAKE_PROMPT_HOOK

# stray .harness: workers and read-only status never create it; a conductor ask does
setup
OUT=$(HERDR_ENV=1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" HARNESS_ROLE=worker /bin/bash "$HARNESS" status 2>&1); RC=$?
check "stray: worker status creates no .harness" [ ! -e .harness ]
setup
run status
check "stray: status without .harness creates none" [ ! -e .harness ]
setup
live_worker analyst idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env HARNESS_ROLE=worker /bin/bash "$HARNESS" ask analyst "q" 2>&1)
check "stray: worker ask creates no config.json" [ ! -e .harness/config.json ]
unset FAKE_PROMPT_HOOK
setup
live_worker analyst idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q"
check "stray: conductor ask creates config" [ -s .harness/config.json ]
unset FAKE_PROMPT_HOOK
setup
OUT=$(env -u HERDR_ENV HARNESS_ROLE=worker /bin/bash "$HARNESS" route-log '{"event":"x"}' 2>&1)
check "stray: worker route-log creates none" [ ! -e .harness ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
