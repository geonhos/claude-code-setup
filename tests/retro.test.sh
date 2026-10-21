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
check "late: report snapshot path (stable)" [ "$(cand .report)" = ".harness/retro/reports/$id.md" ]
check "late: report snapshot exists" grep -q '^# analyst report' ".harness/retro/reports/$id.md"
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
check "retro dry-run: says nothing written" grep -q 'dry run: no ask sent, nothing written' <<<"$OUT"
check "retro dry-run: no brief file written" [ ! -e .harness/task-retro.md ]
printf '%s\n' "$OUT" > "$WORK/dry-brief.md"
check "retro dry-run: no ask sent" [ "$(grep -c 'agent prompt' "$FAKE_LOG")" -eq "$before" ]
check "retro dry-run: candidates kept" [ "$(ncand)" -eq 2 ]
B="$WORK/dry-brief.md"
check "brief: has both ask-ids" [ "$(grep -c '^### ' $B)" -eq 2 ]
check "brief: Symptom/Cause/Next time" grep -q 'Symptom.*Cause.*Next time' <<<"$(tr '\n' ' ' < $B)"
check "brief: mandatory Evidence" grep -q 'Evidence:' $B
check "brief: 120 words" grep -q '120 words' $B
check "brief: recurrence rule" grep -q 'recurrence of' $B
check "brief: inbox output name" grep -q 'docs/wiki/inbox/<YYYY-MM-DD>-retro-<ask-id>.md' $B
check "brief: no prompt text" not grep -q 'PROMPT-TEXT' $B
check "brief: no screen text" not grep -q 'fake screen' $B
check "brief: log paths" grep -q '^- log: .harness/log/' $B
check "brief: inbox is committed / no secrets" grep -q 'committed to git: never copy prompt text, screen text, secrets, tokens' $B
check "brief: skip ask-ids already in inbox" grep -q 'Skip any ask-id that already appears' $B
check "brief: evidence not only rotating paths" grep -q 'rotate away' $B

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
clears=$(grep -c "agent prompt $(WN analyst) /clear" "$FAKE_LOG")
run retro
check "retro ok: rc 0" [ "$RC" -eq 0 ]
check "retro ok: brief instruction sent" grep -q 'task-retro.md' "$FAKE_LOG"
check "retro ok: asked with --fresh (/clear sent)" [ "$(grep -c "agent prompt $(WN analyst) /clear" "$FAKE_LOG")" -gt "$clears" ]
check "retro ok: pending emptied" [ "$(ncand)" -eq 0 ]
check "retro ok: moved to done/" [ "$(ls .harness/retro/done/*.json | wc -l | tr -d ' ')" -eq 2 ]
check "retro ok: processed line" grep -q 'retro: 2 candidates processed' <<<"$OUT"
check "retro ok: still no docs/wiki/inbox created by harness" [ ! -d docs/wiki/inbox ]

setup   # repo without docs/wiki: brief points to .harness/retro/inbox
echo idle > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "x" --timeout 2000
run retro --dry-run
check "retro no wiki: brief output dir" grep -q '.harness/retro/inbox/' <<<"$OUT"
check "retro no wiki: says do not create docs/wiki" grep -q 'Do not create docs/wiki' <<<"$OUT"

setup; mkdir -p docs/wiki   # retro ask times out, its report arrives later: candidates move on collect
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
run ask reviewer "x" --timeout 2000
check "late retro setup: 1 candidate" [ "$(ncand)" -eq 1 ]
echo blocked > "$FAKE_DIR/live.$(WN analyst)"
run retro
echo idle > "$FAKE_DIR/live.$(WN analyst)"
check "late retro: candidate kept after a non-zero retro ask" [ "$(ncand)" -eq 1 ]
if [ "$(ncand)" -eq 1 ]; then
  mkdir -p .harness/reports; printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md
  run report analyst
  check "late retro: candidates moved on collect" [ "$(ncand)" -eq 0 ]
  check "late retro: processed notice" grep -q 'processed (late retro report)' <<<"$OUT"
  check "late retro: no candidate for the retro ask itself" [ "$(ls .harness/retro/done/*.json | wc -l | tr -d ' ')" -eq 1 ]
fi

setup   # brief points at the log snapshot, not the live task file
echo idle > "$FAKE_DIR/live.$(WN analyst)"
mkdir -p .harness; printf 'BRIEF-BODY\n' > .harness/task-analyst.md
run ask analyst 'Read .harness/task-analyst.md and do it.' --timeout 2000
check "brief field: log#brief" [ "$(cand .brief)" = "$(cand .log)#brief" ]
check "brief field: log holds the brief" grep -q 'BRIEF-BODY' "$(cand .log)"
run retro --dry-run
check "brief field: rendered as log section" grep -q '^- brief: .harness/log/.*(its `## Brief` section' <<<"$OUT"

# --via validation
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook analyst '# analyst report\nstatus: done\n'
run ask analyst "x" --via retro
check "--via retro accepted" [ "$RC" -eq 0 ]
run ask analyst "x" --via bogus
check "--via bogus still refused" [ "$RC" -eq 1 ]
check "exit 1 (usage error): no candidate" [ "$(ncand)" -eq 0 ]

# --- harness metrics -------------------------------------------------------------------------------------
# fixed clock: NOW = 2026-10-29T00:00:00Z -> current window 2026-10-01..2026-10-29, previous 2026-09-03..2026-10-01
NOW=$(perl -MTime::Local -e 'print timegm(0,0,0,29,9,2026)')
setup
mkdir -p .harness
cat > .harness/progress.jsonl <<'EOF'
{"ts":"2026-10-02T10:00:00Z","agent":"analyst","exit":0,"dur_s":100,"status":"done"}
{"ts":"2026-10-03T10:00:00Z","agent":"analyst","exit":4,"dur_s":600}
{"ts":"2026-10-03T10:05:00Z","agent":"analyst","exit":null,"late":true,"status":"done"}
{"ts":"2026-10-04T10:00:00Z","agent":"implementer","exit":0,"dur_s":300,"verify":"pass","verify_attempts":1}
{"ts":"2026-10-05T10:00:00Z","agent":"implementer","exit":5,"dur_s":900,"verify":"fail","verify_attempts":3}
{"ts":"2026-10-06T10:00:00Z","agent":"implementer","exit":0,"dur_s":500,"verify":"pass","verify_attempts":2}
{"ts":"2026-10-07T10:00:00Z","agent":"implementer","exit":0,"dur_s":100}
{"ts":"2026-10-08T10:00:00Z","agent":"reviewer","exit":0,"dur_s":50}
{"ts":"2026-10-09T10:00:00Z","agent":"reviewer","exit":5,"dur_s":150}
{"ts":"2026-10-09T10:30:00Z","agent":"reviewer","exit":3,"dur_s":200}
{"ts":"2026-10-10T10:00:00Z","event":"close","role":"implementer","reason":"after_ask"}
this is not json
{"ts":"2026-09-10T10:00:00Z","agent":"analyst","exit":0,"dur_s":40}
{"ts":"2026-09-11T10:00:00Z","agent":"reviewer","exit":5,"dur_s":60}
{"ts":"2026-09-12T10:00:00Z","agent":"reviewer","exit":5,"dur_s":80}
{"ts":"2026-08-01T10:00:00Z","agent":"analyst","exit":0,"dur_s":1}
{"agent":"analyst","exit":0,"dur_s":1}
EOF
mkdir -p .harness/retro/done; echo '{}' > .harness/retro/a.json; echo '{}' > .harness/retro/done/b.json; echo '{}' > .harness/retro/done/c.json
export HARNESS_NOW=$NOW
run metrics --json
check "metrics json: rc 0" [ "$RC" -eq 0 ]
J=$OUT
jv() { printf '%s' "$J" | jq -r "$1"; }
check "json: valid" jq -e . <<<"$J" >/dev/null
check "json: window" [ "$(jv '.window.start + " " + .window.end + " " + (.window.days|tostring)')" = "2026-10-01 2026-10-29 28" ]
check "json: previous window" [ "$(jv '.previous.start + " " + .previous.end')" = "2026-09-03 2026-10-01" ]
check "json: asks total (late row excluded)" [ "$(jv .current.total.asks)" -eq 9 ]
check "json: late" [ "$(jv .current.total.late)" -eq 1 ]
check "json: asks per role" [ "$(jv '[.current.roles.analyst.asks,.current.roles.implementer.asks,.current.roles.reviewer.asks]|join(",")')" = "2,4,3" ]
check "json: exit distribution" [ "$(jv '.current.total.exit|to_entries|map("\(.key)=\(.value)")|join(",")')" = "0=5,3=1,4=1,5=2,late=1" ]
check "json: abnormal total" [ "$(jv .current.total.abnormal)" -eq 3 ]
check "json: abnormal rate total (3/10)" [ "$(jv .current.total.abnormal_rate)" = 30 ]
check "json: abnormal rate analyst (2/3)" [ "$(jv .current.roles.analyst.abnormal_rate)" = 66.7 ]
check "json: abnormal rate implementer" [ "$(jv .current.roles.implementer.abnormal_rate)" = 0 ]
check "json: abnormal rate reviewer (1/3)" [ "$(jv .current.roles.reviewer.abnormal_rate)" = 33.3 ]
check "json: implementer verify-failure rate (1/4)" [ "$(jv .current.roles.implementer.verify_failure_rate)" = 25 ]
check "json: mean verify attempts (old lines skipped)" [ "$(jv .current.roles.implementer.mean_verify_attempts)" = 2 ]
check "json: reviewer FAIL rate (1/3)" [ "$(jv .current.roles.reviewer.fail_rate)" = 33.3 ]
check "json: implementer median/p95" [ "$(jv '"\(.current.roles.implementer.duration_median_s)/\(.current.roles.implementer.duration_p95_s)"')" = "400/900" ]
check "json: analyst median/p95 (600,100)" [ "$(jv '"\(.current.roles.analyst.duration_median_s)/\(.current.roles.analyst.duration_p95_s)"')" = "350/600" ]
check "json: reviewer median/p95" [ "$(jv '"\(.current.roles.reviewer.duration_median_s)/\(.current.roles.reviewer.duration_p95_s)"')" = "150/200" ]
check "json: previous asks" [ "$(jv .prev.total.asks)" -eq 3 ]
check "json: previous reviewer FAIL rate (2/2)" [ "$(jv .prev.roles.reviewer.fail_rate)" = 100 ]
check "json: previous empty role is null" [ "$(jv .prev.roles.implementer.verify_failure_rate)" = null ]
check "json: retro counts" [ "$(jv '"\(.retro.pending)/\(.retro.processed)"')" = "1/2" ]
check "json: no wiki -> null" [ "$(jv .wiki)" = null ]

run metrics
check "text: rc 0" [ "$RC" -eq 0 ]
check "text: header" grep -q '^harness metrics  2026-10-01 .. 2026-10-29 (28d)  vs  2026-09-03 .. 2026-10-01' <<<"$OUT"
check "text: asks row" grep -Eq '^  asks +9 +3$' <<<"$OUT"
check "text: abnormal row" grep -Eq 'abnormal rate .* +30% +' <<<"$OUT"
check "text: exits line" grep -q 'exits current:  0:5 3:1 4:1 5:2 late:1' <<<"$OUT"
check "text: retro line" grep -q '^retro: 1 pending · 2 processed' <<<"$OUT"
check "text: no wiki" grep -q '^wiki: none' <<<"$OUT"

run metrics --since 2026-10-05
check "since: window start" grep -q '2026-10-05 .. 2026-10-29 (24d)  vs  2026-09-11 .. 2026-10-05' <<<"$OUT"
run metrics --since 2099-01-01
check "since: future rc 1" [ "$RC" -eq 1 ]
check "since: future message" grep -q 'in the future' <<<"$OUT"
run metrics --since 2026-02-31
check "since: impossible date rc 1" [ "$RC" -eq 1 ]
run metrics --since nope
check "since: bad date rc 1" [ "$RC" -eq 1 ]
run metrics --bogus
check "metrics: bad flag rc 1" [ "$RC" -eq 1 ]

# empty / missing progress.jsonl
setup
run metrics --json
check "metrics: no progress file rc 0" [ "$RC" -eq 0 ]
check "metrics: no progress file zero asks" [ "$(printf '%s' "$OUT" | jq -r .current.total.asks)" -eq 0 ]
run metrics
check "metrics: no data text rc 0" [ "$RC" -eq 0 ]

# wiki block
setup
unset HARNESS_NOW
mkdir -p docs/wiki/gotchas docs/wiki/inbox
printf -- '---\nstatus: active\n---\n# a\n' > docs/wiki/gotchas/a.md
printf -- '---\nstatus: active\n---\n# b\n' > docs/wiki/gotchas/b.md
printf -- '---\nstatus: stale\n---\n# c\n' > docs/wiki/gotchas/c.md
printf -- '---\nstatus: draft\n---\n# d\n' > docs/wiki/gotchas/d.md
printf '# Wiki index\n\n- [a](gotchas/a.md) — h (active, 2026-10-21)\n- [b](gotchas/b.md) — h (active, 2026-10-21)\n- [c](gotchas/c.md) — h (stale, 2026-10-21)\n' > docs/wiki/index.md
printf 'x\n' > docs/wiki/log.md
printf 'recurrence of gotchas/a.md\nEvidence: x\n' > docs/wiki/inbox/n1.md
printf -- '- lesson\n' > docs/wiki/inbox/n2.md
now=$(date +%s)
perl -e 'utime($ARGV[0],$ARGV[0],$ARGV[1])' $((now - 10 * 86400 - 100)) docs/wiki/inbox/n1.md
run metrics --json
J=$OUT
check "wiki: pages" [ "$(jv '.wiki.pages|"\(.active)/\(.stale)/\(.draft)/\(.superseded)/\(.other)"')" = "2/1/1/0/0" ]
check "wiki: inbox items" [ "$(jv .wiki.inbox_items)" -eq 2 ]
check "wiki: oldest inbox days" [ "$(jv .wiki.inbox_oldest_days)" -eq 10 ]
check "wiki: index lines" [ "$(jv .wiki.index_lines)" -eq 5 ]
check "wiki: SessionStart bytes = active lines only" [ "$(jv .wiki.session_start_bytes)" -eq "$(grep -F '(active,' docs/wiki/index.md | LC_ALL=C wc -c | tr -d ' ')" ]
check "wiki: recurrence notes" [ "$(jv .retro.recurrences_noted)" -eq 1 ]
run metrics
check "text: wiki pages line" grep -q '^wiki: pages active 2 · stale 1 · draft 1' <<<"$OUT"
check "text: wiki inbox line" grep -q '^wiki: inbox 2 item(s), oldest 10d · index 5 lines' <<<"$OUT"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
