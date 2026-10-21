#!/bin/bash
# Tests for failure retro candidates, `harness retro` and `harness metrics`
# (bin/harness against tests/fake-herdr). Run: /bin/bash tests/retro.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
FAKE_BIN="$HERE/fake-herdr"
WN() { env -u HARNESS_ROLE /bin/bash "$HARNESS" _wname "$1"; }
pass=0
fail=0
WORKS=""
trap 'cd / && for d in $WORKS; do rm -rf "$d"; done' EXIT
setup() {
  WORK=$(mktemp -d)
  WORKS="$WORKS $WORK"
  export FAKE_DIR="$WORK/fake" FAKE_LOG="$WORK/herdr.log"
  export HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2
  mkdir -p "$FAKE_DIR"
  : > "$FAKE_LOG"
  unset FAKE_PROMPT_HOOK HARNESS_LOG_KEEP HARNESS_LOG_DAYS HARNESS_NOW
  cd "$WORK" || exit 1
  git init -q . && git config user.email t@t && git config user.name t && echo s > s.txt && git add s.txt && git -c core.hooksPath=/dev/null commit -q -m s
}
GUARD="perl -e alarm(10);exec(@ARGV)"
run() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi; }
not() { ! "$@"; }
ncand() { ls "$WORK"/.harness/retro/*.json 2>/dev/null | wc -l | tr -d ' '; }
cand() { jq -r "$1" "$WORK"/.harness/retro/*.json 2>/dev/null | head -n 1; }
hook() { # hook ROLE BODY [VERIFYJSON]
  export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '$2' > $WORK/.harness/reports/$1.md; ${3:+printf '$3' > $WORK/.harness/verify/implementer.json}"
}
QUEUED="retro: candidate queued"

# --- trigger / no-trigger matrix ---------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook analyst '# analyst report\nstatus: done\n'
run ask analyst "fine"
check "exit 0: rc" [ "$RC" -eq 0 ]
check "exit 0: no candidate" [ "$(ncand)" -eq 0 ]
check "exit 0: no notice" not grep -q "$QUEUED" <<<"$OUT"

setup   # exit 3: worker finished without a report
echo idle > "$FAKE_DIR/live.$(WN analyst)"
touch "$FAKE_DIR/no_stop_hook"
export FAKE_PROMPT_HOOK=true
run ask analyst "secret-prompt-text SECRET123"
check "exit 3: rc" [ "$RC" -eq 3 ]
check "exit 3: candidate" [ "$(ncand)" -eq 1 ]
check "exit 3: notice" grep -q "^retro: candidate queued (exit 3) — run 'harness retro' when the task is done" <<<"$OUT"
check "exit 3: role" [ "$(cand .role)" = analyst ]
check "exit 3: exit field" [ "$(cand .exit)" = 3 ]
check "exit 3: log path exists" [ -f "$WORK/$(cand .log)" ]
check "exit 3: ask-id from .current" [ "$(cand .ask_id)" = "$(awk 'NR==1{print $1}' .harness/asks/analyst.current)" ]
check "exit 3: file keyed by ask-id" [ -f ".harness/retro/$(cand .ask_id).json" ]
check "exit 3: no prompt text" not grep -rq 'SECRET123' .harness/retro
check "exit 3: no screen text" not grep -rq 'fake screen' .harness/retro
check "exit 3: only known keys" [ "$(jq -r 'keys|join(",")' .harness/retro/*.json)" = "ask_id,brief,duration_s,exit,late,log,reason,report,role,ts,verify_attempts" ]

setup   # exit 4: still working
echo idle > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "x" --timeout 2000
check "exit 4: rc" [ "$RC" -eq 4 ]
check "exit 4: candidate" [ "$(ncand)" -eq 1 ]

setup   # exit 5 implementer: verification gave up
echo idle > "$FAKE_DIR/live.$(WN implementer)"
hook implementer '# implementer report\nstatus: partial\n' '{"status":"fail","attempts":3,"step":"test","tail":"x"}'
run ask implementer "do it"
check "impl 5: rc" [ "$RC" -eq 5 ]
check "impl 5: candidate" [ "$(ncand)" -eq 1 ]
check "impl 5: notice after the verify line" [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "retro: candidate queued (exit 5) — run 'harness retro' when the task is done" ]
check "impl 5: attempts recorded" [ "$(cand .verify_attempts)" = 3 ]
check "impl 5: attempts in progress.jsonl" [ "$(jq -r .verify_attempts .harness/progress.jsonl | tail -n 1)" = 3 ]

setup   # exit 0 implementer with 2 verify attempts
echo idle > "$FAKE_DIR/live.$(WN implementer)"
hook implementer '# implementer report\nstatus: done\n' '{"status":"pass","attempts":2,"step":"","tail":""}'
run ask implementer "do it"
check "impl 2 attempts: rc 0" [ "$RC" -eq 0 ]
check "impl 2 attempts: candidate" [ "$(ncand)" -eq 1 ]
check "impl 2 attempts: reason" grep -q "(2 verify attempts)" <<<"$OUT"

setup   # exit 0 implementer with 1 attempt: no trigger
echo idle > "$FAKE_DIR/live.$(WN implementer)"
hook implementer '# implementer report\nstatus: done\n' '{"status":"pass","attempts":1,"step":"","tail":""}'
run ask implementer "do it"
check "impl 1 attempt: no candidate" [ "$(ncand)" -eq 0 ]

setup   # reviewer FAIL verdict (exit 5) is a normal outcome: no candidate
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
hook reviewer '# reviewer report\nVERDICT: FAIL\n'
run ask reviewer "review"
check "reviewer FAIL: rc 5" [ "$RC" -eq 5 ]
check "reviewer FAIL: no candidate" [ "$(ncand)" -eq 0 ]
check "reviewer FAIL: VERDICT stays last line" [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "VERDICT: FAIL" ]
setup   # reviewer without a VERDICT line (exit 3) still triggers
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
hook reviewer '# reviewer report\nno verdict\n'
run ask reviewer "review"
check "reviewer no verdict: rc 3" [ "$RC" -eq 3 ]
check "reviewer no verdict: candidate" [ "$(ncand)" -eq 1 ]

# a killed ask wrapper (143) is an interrupt, not a failure: no candidate, stdout untouched
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" FAKE_PROMPT_HOOK='sleep 3' env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "long" 2>&1 & KP=$!; sleep 1; kill -TERM $KP; wait $KP)
check "kill 143: no candidate" [ "$(ncand)" -eq 0 ]

# --- late report ----------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "slow" --timeout 2000
check "late: ask exit 4" [ "$RC" -eq 4 ]
id=$(cand .ask_id)
echo idle > "$FAKE_DIR/live.$(WN analyst)"
mkdir -p .harness/reports; printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md
run report analyst
check "late: report rc 0" [ "$RC" -eq 0 ]
check "late: notice" grep -q "^retro: candidate queued (late report)" <<<"$OUT"
check "late: same candidate extended" [ "$(ncand)" -eq 1 ] && [ "$(cand .late)" = true ] && [ "$(cand .ask_id)" = "$id" ]
check "late: report path added" [ "$(cand .report)" = ".harness/reports/analyst.md" ]
run report analyst
check "late: second collect silent" not grep -q "$QUEUED" <<<"$OUT"
setup   # report after a good ask is not late
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook analyst '# analyst report\nstatus: done\n'
run ask analyst "fine"
run report analyst
check "report after exit 0: no candidate" [ "$(ncand)" -eq 0 ]

# --- rotate_logs keeps logs of pending candidates -----------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "fails" --timeout 2000
keeplog=$(cand .log)
hook analyst '# analyst report\nstatus: done\n'
export HARNESS_LOG_KEEP=1
sleep 1
run ask analyst "ok 1"
run ask analyst "ok 2"
check "rotate: referenced log survives" [ -f "$keeplog" ]
check "rotate: unreferenced old log removed" [ "$(ls .harness/log/*.md | wc -l | tr -d ' ')" -le 3 ]
rm -f .harness/retro/*.json
touch -t 202001010000 "$keeplog"
export HARNESS_LOG_DAYS=1
mkdir -p .harness/retro; jq -n -c --arg l "$keeplog" '{ask_id:"x",role:"analyst",log:$l}' > .harness/retro/x.json
run ask analyst "ok 3"
check "rotate: age-based delete also spares referenced log" [ -f "$keeplog" ]
rm -f .harness/retro/x.json
run ask analyst "ok 4"
check "rotate: unreferenced old log goes" [ ! -f "$keeplog" ]
unset HARNESS_LOG_DAYS

# --- no docs/wiki side effects ------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "fails" --timeout 2000
run retro --dry-run
check "no docs dir created by candidates/dry-run" [ ! -d docs ]

# --- harness retro ------------------------------------------------------------------------------------
setup
run retro
check "retro: nothing pending rc 0" [ "$RC" -eq 0 ]
check "retro: nothing pending text" [ "$OUT" = "retro: nothing pending" ]
run retro --dry-run
check "retro dry-run: nothing pending" [ "$OUT" = "retro: nothing pending" ]
run retro --bogus
check "retro: bad flag rc 1" [ "$RC" -eq 1 ]

setup; mkdir -p docs/wiki
echo idle > "$FAKE_DIR/live.$(WN analyst)"
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
run ask analyst "PROMPT-TEXT-1" --timeout 2000
run ask reviewer "PROMPT-TEXT-2" --timeout 2000
check "retro setup: 2 candidates" [ "$(ncand)" -eq 2 ]
before=$(grep -c 'agent prompt' "$FAKE_LOG")
run retro --dry-run
check "retro dry-run: rc 0" [ "$RC" -eq 0 ]
check "retro dry-run: lists both" [ "$(printf '%s\n' "$OUT" | grep -c 'exit 4')" -ge 2 ]
check "retro dry-run: brief path" grep -q 'brief: .harness/task-retro.md' <<<"$OUT"
check "retro dry-run: no ask sent" [ "$(grep -c 'agent prompt' "$FAKE_LOG")" -eq "$before" ]
check "retro dry-run: candidates kept" [ "$(ncand)" -eq 2 ]
B=.harness/task-retro.md
check "brief: has both ask-ids" [ "$(grep -c '^### ' $B)" -eq 2 ]
check "brief: Symptom/Cause/Next time" grep -q 'Symptom.*Cause.*Next time' <<<"$(tr '\n' ' ' < $B)"
check "brief: mandatory Evidence" grep -q 'Evidence:' $B
check "brief: 120 words" grep -q '120 words' $B
check "brief: recurrence rule" grep -q 'recurrence of' $B
check "brief: inbox output name" grep -q 'docs/wiki/inbox/<YYYY-MM-DD>-retro-<ask-id>.md' $B
check "brief: no prompt text" not grep -q 'PROMPT-TEXT' $B
check "brief: no screen text" not grep -q 'fake screen' $B
check "brief: log paths" grep -q '^- log: .harness/log/' $B

# real path, analyst fails (blocked -> exit 2): candidates stay
echo blocked > "$FAKE_DIR/live.$(WN analyst)"
run retro
check "retro fail: nonzero rc" [ "$RC" -ne 0 ]
check "retro fail: candidates kept" [ "$(ncand)" -eq 2 ]
check "retro fail: no candidate for the retro ask itself" [ "$(ncand)" -eq 2 ]
check "retro fail: ask used --via retro" grep -q '"source":"retro"' .harness/routing.jsonl
# real path, analyst ok: candidates move to done/
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook analyst '# analyst report\nstatus: done\n'
run retro
check "retro ok: rc 0" [ "$RC" -eq 0 ]
check "retro ok: brief instruction sent" grep -q 'task-retro.md' "$FAKE_LOG"
check "retro ok: asked with --fresh" true
check "retro ok: pending emptied" [ "$(ncand)" -eq 0 ]
check "retro ok: moved to done/" [ "$(ls .harness/retro/done/*.json | wc -l | tr -d ' ')" -eq 2 ]
check "retro ok: processed line" grep -q 'retro: 2 candidates processed' <<<"$OUT"
check "retro ok: still no docs/wiki/inbox created by harness" [ ! -d docs/wiki/inbox ]

setup   # repo without docs/wiki: brief points to .harness/retro/inbox
echo idle > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "x" --timeout 2000
run retro --dry-run
check "retro no wiki: brief output dir" grep -q '.harness/retro/inbox/' .harness/task-retro.md
check "retro no wiki: says do not create docs/wiki" grep -q 'Do not create docs/wiki' .harness/task-retro.md

# --via validation
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook analyst '# analyst report\nstatus: done\n'
run ask analyst "x" --via retro
check "--via retro accepted" [ "$RC" -eq 0 ]
run ask analyst "x" --via bogus
check "--via bogus still refused" [ "$RC" -eq 1 ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
