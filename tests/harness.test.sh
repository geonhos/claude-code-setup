#!/bin/bash
# bin/harness against tests/fake-herdr: preconditions, spawn, ask, report, close, verify loop, worker names. Run: /bin/bash tests/harness.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"

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
check "learned warns on dropped bullet" grep -q 'dropped 1 Notes bullet' <<<"$OUT"
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
setup
mkdir -p docs/wiki
# the new `## Notes` heading is accepted (Learned above stays as the legacy form)
mkdir -p .harness/asks .harness/reports; printf '1700000003-7-7 1700000003\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Notes\n- seen in bin/harness:844\n' > .harness/reports/analyst.md
run report analyst
check "Notes section queued" grep -q '^wiki: 1 lesson' <<<"$OUT"

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


echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
