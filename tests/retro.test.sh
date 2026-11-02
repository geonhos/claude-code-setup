#!/bin/bash
# Tests for failure retro candidates and `harness retro` (bin/harness against tests/fake-claude).
# (bin/harness against tests/fake-claude). Run: /bin/bash tests/retro.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
FAKE_BIN="$HERE/fake-claude"
pass=0
fail=0
WORKS=""
trap 'cd / && for d in $WORKS; do rm -rf "$d"; done' EXIT
setup() {
  WORK=$(mktemp -d)
  WORKS="$WORKS $WORK"
  export FAKE_DIR="$WORK/fake" FAKE_LOG="$WORK/claude.log"
  export HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=5 FAKE_CLAUDE_MODE=success
  mkdir -p "$FAKE_DIR"
  : > "$FAKE_LOG"
  unset FAKE_REPORT_CMD HARNESS_LOG_KEEP HARNESS_LOG_DAYS HARNESS_NOW
  cd "$WORK" || exit 1
  env -u HERDR_ENV -u HARNESS_ROLE /bin/bash "$HARNESS" init --no-agent >/dev/null 2>&1
  git init -q . && git config user.email t@t && git config user.name t && echo s > s.txt && git add s.txt && git -c core.hooksPath=/dev/null commit -q -m s
}
GUARD="perl -e alarm(40);exec(@ARGV)"
run() {
  OUT=$(PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env -u HERDR_ENV -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi; }
not() { ! "$@"; }
ncand() { ls "$WORK"/.harness/retro/*.json 2>/dev/null | wc -l | tr -d ' '; }
cand() { jq -r "$1" "$WORK"/.harness/retro/*.json 2>/dev/null | head -n 1; }
# waitexit ROLE — until the (slow) fake run has written its exit file (15 s cap)
waitexit() { local i=0; while [ $i -lt 150 ] && [ ! -f ".harness/asks/$1.exit.json" ]; do sleep 0.1; i=$((i + 1)); done; }
# slowask ROLE ARGS... — an ask that times out (exit 4) while the fake run is still going; waits for the run to end
slowask() { local r=$1; FAKE_CLAUDE_MODE=slow30 run ask "$@" --timeout 1000; waitexit "$r"; }
hook() { # hook ROLE BODY [VERIFYJSON]
  export FAKE_CLAUDE_MODE=success FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '$2' > $WORK/.harness/reports/$1.md; ${3:+printf '$3' > $WORK/.harness/verify/implementer.json}"
}
QUEUED="retro: candidate queued"

# --- trigger / no-trigger matrix ---------------------------------------------------------
setup
hook analyst '# analyst report\nstatus: done\n'
run ask analyst "fine"
check "exit 0: rc" [ "$RC" -eq 0 ]
check "exit 0: no candidate" [ "$(ncand)" -eq 0 ]
check "exit 0: no notice" not grep -q "$QUEUED" <<<"$OUT"

setup   # exit 3: worker finished without a report
FAKE_CLAUDE_MODE=noreport run ask analyst "secret-prompt-text SECRET123"
check "exit 3: rc" [ "$RC" -eq 3 ]
check "exit 3: candidate" [ "$(ncand)" -eq 1 ]
check "exit 3: notice" grep -q "^retro: candidate queued (exit 3) — run 'harness retro' when the task is done" <<<"$OUT"
check "exit 3: role" [ "$(cand .role)" = analyst ]
check "exit 3: exit field" [ "$(cand .exit)" = 3 ]
check "exit 3: log path exists" [ -f "$WORK/$(cand .log)" ]
check "exit 3: ask-id from .current" [ "$(cand .ask_id)" = "$(awk 'NR==1{print $1}' .harness/asks/analyst.current)" ]
check "exit 3: file keyed by ask-id" [ -f ".harness/retro/$(cand .ask_id).json" ]
check "exit 3: no prompt text" not grep -rq 'SECRET123' .harness/retro
check "exit 3: only known keys" [ "$(jq -r 'keys|join(",")' .harness/retro/*.json)" = "ask_id,brief,duration_s,exit,late,log,reason,report,role,stream_log,ts,verify_attempts" ]

setup   # exit 4: still working
slowask analyst "x"
check "exit 4: rc" [ "$RC" -eq 4 ]
check "exit 4: candidate" [ "$(ncand)" -eq 1 ]

setup   # exit 5 implementer: verification gave up
hook implementer '# implementer report\nstatus: partial\n' '{"status":"fail","attempts":3,"step":"test","tail":"x"}'
run ask implementer "do it"
check "impl 5: rc" [ "$RC" -eq 5 ]
check "impl 5: candidate" [ "$(ncand)" -eq 1 ]
check "impl 5: notice after the verify line" [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "retro: candidate queued (exit 5) — run 'harness retro' when the task is done" ]
check "impl 5: attempts recorded" [ "$(cand .verify_attempts)" = 3 ]
check "impl 5: attempts in progress.jsonl" [ "$(jq -r .verify_attempts .harness/progress.jsonl | tail -n 1)" = 3 ]

setup   # exit 0 implementer with 2 verify attempts
hook implementer '# implementer report\nstatus: done\n' '{"status":"pass","attempts":2,"step":"","tail":""}'
run ask implementer "do it"
check "impl 2 attempts: rc 0" [ "$RC" -eq 0 ]
check "impl 2 attempts: candidate" [ "$(ncand)" -eq 1 ]
check "impl 2 attempts: reason" grep -q "(2 verify attempts)" <<<"$OUT"

setup   # exit 0 implementer with 1 attempt: no trigger
hook implementer '# implementer report\nstatus: done\n' '{"status":"pass","attempts":1,"step":"","tail":""}'
run ask implementer "do it"
check "impl 1 attempt: no candidate" [ "$(ncand)" -eq 0 ]

setup   # reviewer FAIL verdict (exit 5) is a normal outcome: no candidate
hook reviewer '# reviewer report\nVERDICT: FAIL\n'
run ask reviewer "review"
check "reviewer FAIL: rc 5" [ "$RC" -eq 5 ]
check "reviewer FAIL: no candidate" [ "$(ncand)" -eq 0 ]
check "reviewer FAIL: VERDICT stays last line" [ "$(printf '%s\n' "$OUT" | grep -v '^harness:' | tail -n 1)" = "VERDICT: FAIL" ]
setup   # reviewer without a VERDICT line (exit 3) still triggers
hook reviewer '# reviewer report\nno verdict\n'
run ask reviewer "review"
check "reviewer no verdict: rc 3" [ "$RC" -eq 3 ]
check "reviewer no verdict: candidate" [ "$(ncand)" -eq 1 ]

# a killed ask wrapper (143) is an interrupt, not a failure: no candidate, stdout untouched
setup
OUT=$(PATH="$FAKE_BIN:$HERE/../bin:$PATH" FAKE_CLAUDE_MODE=slow30 env -u HERDR_ENV -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "long" 2>&1 & KP=$!; sleep 1; kill -TERM $KP; wait $KP)
check "kill 143: no candidate" [ "$(ncand)" -eq 0 ]

# 129 (HUP) is the caller ending the wait too: no candidate (130/INT is ignored by background jobs; progress.test.sh covers its exit code)
{
  setup
  OUT=$(PATH="$FAKE_BIN:$HERE/../bin:$PATH" FAKE_CLAUDE_MODE=slow30 env -u HERDR_ENV -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "long" 2>&1 & KP=$!; sleep 1; kill -HUP $KP; wait $KP)
  check "kill HUP: no candidate" [ "$(ncand)" -eq 0 ]
}

# exit 1 after the ask passed its pre-flight (infrastructure failure) queues a candidate
setup
FAKE_CLAUDE_MODE=nostart run ask analyst "x"
check "start fail: rc 1" [ "$RC" -eq 1 ]
check "start fail: candidate" [ "$(ncand)" -eq 1 ]
check "start fail: reason" [ "$(cand .reason)" = "exit 1" ]
check "start fail: notice" grep -q "$QUEUED" <<<"$OUT"
setup   # harness-verify missing: the implementer ask dies after pre-flight
NOVERIFY_PATH="$FAKE_BIN:$(dirname "$(command -v jq)"):/usr/bin:/bin"
check "no harness-verify: PATH really lacks it" [ -z "$(PATH="$NOVERIFY_PATH" command -v harness-verify)" ]
OUT=$(PATH="$NOVERIFY_PATH" $GUARD env -u HERDR_ENV -u HARNESS_ROLE /bin/bash "$HARNESS" ask implementer "x" 2>&1); RC=$?
check "no harness-verify: rc 1" [ "$RC" -eq 1 ]
check "no harness-verify: candidate" [ "$(ncand)" -eq 1 ]
setup   # usage error before any side effect stays excluded
run ask analyst "x" --timeout abc
check "usage (bad timeout): rc 1" [ "$RC" -eq 1 ]
check "usage (bad timeout): no candidate" [ "$(ncand)" -eq 0 ]
run ask nosuchagent "x"
check "usage (bad agent): no candidate" [ "$(ncand)" -eq 0 ]

# report snapshots follow their candidate
setup
slowask analyst "x"
id=$(cand .ask_id)
mkdir -p .harness/retro/reports; echo r > ".harness/retro/reports/$id.md"
hook analyst '# analyst report\nstatus: done\n'
run retro
check "snapshot: retro ok" [ "$RC" -eq 0 ]
check "snapshot: candidate done" [ -f ".harness/retro/done/$id.json" ]
check "snapshot: pruned after retro" [ ! -e ".harness/retro/reports/$id.md" ]
# retro_done_from_brief also prunes
setup
mkdir -p .harness/retro/reports .harness/retro/done
echo '{}' > .harness/retro/x1.json; echo r > .harness/retro/reports/x1.md
printf '### x1 something\n' > .harness/task-retro.md
mkdir -p .harness/reports .harness/asks; printf '# a\nstatus: done\n' > .harness/reports/analyst.md; echo '{"exit":0}' > .harness/asks/analyst.exit.json
printf '%s\n' '{"agent":"analyst","exit":4,"instr":"Read .harness/task-retro.md and do it."}' > .harness/progress.jsonl
run report analyst
check "late retro: snapshot pruned" [ ! -e .harness/retro/reports/x1.md ]

# --- late report ----------------------------------------------------------------------------
setup
slowask analyst "slow"
check "late: ask exit 4" [ "$RC" -eq 4 ]
id=$(cand .ask_id)
mkdir -p .harness/reports; printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md
run report analyst
check "late: report rc 0" [ "$RC" -eq 0 ]
check "late: notice" grep -q "^retro: candidate queued (late report)" <<<"$OUT"
ok=0; [ "$(ncand)" -eq 1 ] && [ "$(cand .late)" = true ] && [ "$(cand .ask_id)" = "$id" ] && ok=1
check "late: same candidate extended" [ "$ok" = 1 ]
check "late: report snapshot path (stable)" [ "$(cand .report)" = ".harness/retro/reports/$id.md" ]
check "late: report snapshot exists" grep -q '^# analyst report' ".harness/retro/reports/$id.md"
run report analyst
check "late: second collect silent" not grep -q "$QUEUED" <<<"$OUT"
setup   # a worktree ask's newer line (agent: analyst, ask_id set) must not hide the plain ask's exit 4
slowask analyst "slow"
check "leak: plain ask exit 4" [ "$RC" -eq 4 ]
printf '%s\n' '{"ts":"2026-10-28T00:00:00Z","agent":"analyst","exit":0,"ask_id":"1-2-3","wt":"/x/wt","base":"b"}' >> .harness/progress.jsonl
mkdir -p .harness/reports; printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md
run report analyst
check "leak: late report still queues its candidate (worktree line ignored)" grep -q "^retro: candidate queued (late report)" <<<"$OUT"
setup   # report after a good ask is not late
hook analyst '# analyst report\nstatus: done\n'
run ask analyst "fine"
run report analyst
check "report after exit 0: no candidate" [ "$(ncand)" -eq 0 ]

# --- rotate_logs keeps logs of pending candidates -----------------------------------------
setup
slowask analyst "fails"
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
# leftover report snapshots: swept only when old AND no pending candidate points at them
mkdir -p .harness/retro/reports
echo r > .harness/retro/reports/orphan-old.md
echo r > .harness/retro/reports/pending-old.md
echo r > .harness/retro/reports/orphan-fresh.md
touch -t 202001010000 .harness/retro/reports/orphan-old.md .harness/retro/reports/pending-old.md
jq -n -c '{ask_id:"pending-old",role:"analyst"}' > .harness/retro/pending-old.json
run ask analyst "ok 5"
check "snapshot sweep: old orphan removed" [ ! -f .harness/retro/reports/orphan-old.md ]
check "snapshot sweep: old but pending kept" [ -f .harness/retro/reports/pending-old.md ]
check "snapshot sweep: fresh orphan kept" [ -f .harness/retro/reports/orphan-fresh.md ]
unset HARNESS_LOG_DAYS

# --- raw streams named by a pending candidate are never gzipped or deleted -------------------
setup; mkdir -p docs/wiki
hook analyst '# analyst report\nstatus: done\n'
mkdir -p .harness/log .harness/retro
echo '{}' > .harness/log/20200101-000000-analyst.jsonl      # pending, plain
echo '{}' > .harness/log/20200102-000000-analyst.jsonl      # not referenced
echo '{}' | gzip > .harness/log/20200103-000000-analyst.jsonl.gz   # pending, candidate says .jsonl
echo '{}' | gzip > .harness/log/20200104-000000-analyst.jsonl.gz   # not referenced
touch -t 202001010000 .harness/log/2020010*-analyst.jsonl* 
jq -n -c '{ask_id:"s1",role:"analyst",stream_log:".harness/log/20200101-000000-analyst.jsonl"}' > .harness/retro/s1.json
jq -n -c '{ask_id:"s3",role:"analyst",stream_log:".harness/log/20200103-000000-analyst.jsonl"}' > .harness/retro/s3.json
export HARNESS_LOG_DAYS=1
run ask analyst "ok"
check "stream rotate: pending plain stream not gzipped" [ -f .harness/log/20200101-000000-analyst.jsonl ]
check "stream rotate: pending stream (gz on disk) survives age delete" [ -f .harness/log/20200103-000000-analyst.jsonl.gz ]
check "stream rotate: unreferenced plain stream gone" [ ! -e .harness/log/20200102-000000-analyst.jsonl ]
check "stream rotate: unreferenced gz stream gone" [ ! -e .harness/log/20200104-000000-analyst.jsonl.gz ]
unset HARNESS_LOG_DAYS
# without age deletion, an unreferenced day-old stream is gzipped, a pending one is not
echo '{}' > .harness/log/20200105-000000-analyst.jsonl
perl -e 'utime(time - 2 * 86400, time - 2 * 86400, @ARGV)' .harness/log/20200105-000000-analyst.jsonl
run ask analyst "ok 2"
check "stream gzip: unreferenced day-old stream gzipped" [ -f .harness/log/20200105-000000-analyst.jsonl.gz ] 
check "stream gzip: pending stream stays plain" [ -f .harness/log/20200101-000000-analyst.jsonl ]
# the brief points a .jsonl candidate at the .gz that exists
run retro --dry-run
check "retro brief: plain stream path as is" grep -q 'stream: .harness/log/20200101-000000-analyst.jsonl ' <<<"$OUT"
check "retro brief: .jsonl resolved to .gz" grep -q 'stream: .harness/log/20200103-000000-analyst.jsonl.gz' <<<"$OUT"
check "retro brief: gz hint" grep -q 'gzip -dc' <<<"$OUT"

# --- no docs/wiki side effects ------------------------------------------------------------------
setup
slowask analyst "fails"
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
slowask analyst "PROMPT-TEXT-1"
slowask reviewer "PROMPT-TEXT-2"
check "retro setup: 2 candidates" [ "$(ncand)" -eq 2 ]
before=$(grep -c '^claude' "$FAKE_LOG")
run retro --dry-run
check "retro dry-run: rc 0" [ "$RC" -eq 0 ]
check "retro dry-run: lists both" [ "$(printf '%s\n' "$OUT" | grep -c 'exit 4')" -ge 2 ]
check "retro dry-run: says nothing written" grep -q 'dry run: no ask sent, nothing written' <<<"$OUT"
check "retro dry-run: no brief file written" [ ! -e .harness/task-retro.md ]
printf '%s\n' "$OUT" > "$WORK/dry-brief.md"
check "retro dry-run: no ask sent" [ "$(grep -c '^claude' "$FAKE_LOG")" -eq "$before" ]
check "retro dry-run: candidates kept" [ "$(ncand)" -eq 2 ]
B="$WORK/dry-brief.md"
check "brief: has both ask-ids" [ "$(grep -c '^### ' $B)" -eq 2 ]
check "brief: Symptom/Cause/Next time" grep -q 'Symptom.*Cause.*Next time' <<<"$(tr '\n' ' ' < $B)"
check "brief: mandatory Evidence" grep -q 'Evidence:' $B
check "brief: 120 words" grep -q '120 words' $B
check "brief: recurrence rule" grep -q 'recurrence of' $B
check "brief: inbox output name" grep -q 'docs/wiki/inbox/<YYYY-MM-DD>-retro-<ask-id>.md' $B
check "brief: no prompt text" not grep -q 'PROMPT-TEXT' $B
check "brief: log paths" grep -q '^- log: .harness/log/' $B
check "brief: inbox is committed / no secrets" grep -q 'committed to git: never copy prompt text, screen text, secrets, tokens' $B
check "brief: skip only ask-ids with a retro note" grep -qF 'already has a retro note in the inbox (a file named `*-retro-<ask-id>.md`' $B
check "brief: other inbox files do not skip" grep -q 'harvest.*do not count' $B
check "brief: no any-inbox-file skip rule" not grep -q 'already appears in a file' $B
check "brief: evidence not only rotating paths" grep -q 'rotate away' $B

# real path, analyst fails (no report -> exit 3): candidates stay
export FAKE_CLAUDE_MODE=noreport
run retro
check "retro fail: nonzero rc" [ "$RC" -ne 0 ]
check "retro fail: candidates kept" [ "$(ncand)" -eq 2 ]
check "retro fail: no candidate for the retro ask itself" [ "$(ncand)" -eq 2 ]
check "retro fail: ask used --via retro" grep -q '"source":"retro"' .harness/routing.jsonl
# real path, analyst ok: candidates move to done/
hook analyst '# analyst report\nstatus: done\n'
run retro
check "retro ok: rc 0" [ "$RC" -eq 0 ]
check "retro ok: brief instruction sent" grep -q 'task-retro.md' "$FAKE_LOG"
check "retro ok: pending emptied" [ "$(ncand)" -eq 0 ]
check "retro ok: moved to done/" [ "$(ls .harness/retro/done/*.json | wc -l | tr -d ' ')" -eq 2 ]
check "retro ok: processed line" grep -q 'retro: 2 candidates processed' <<<"$OUT"
check "retro ok: still no docs/wiki/inbox created by harness" [ ! -d docs/wiki/inbox ]

setup   # repo without docs/wiki: brief points to .harness/retro/inbox
slowask analyst "x"
run retro --dry-run
check "retro no wiki: brief output dir" grep -q '.harness/retro/inbox/' <<<"$OUT"
check "retro no wiki: says do not create docs/wiki" grep -q 'Do not create docs/wiki' <<<"$OUT"

setup; mkdir -p docs/wiki   # retro ask times out, its report arrives later: candidates move on collect
slowask reviewer "x"
check "late retro setup: 1 candidate" [ "$(ncand)" -eq 1 ]
run retro
check "late retro: candidate kept after a non-zero retro ask" [ "$(ncand)" -eq 1 ]
if [ "$(ncand)" -eq 1 ]; then
  mkdir -p .harness/reports; printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md
  run report analyst
  check "late retro: candidates moved on collect" [ "$(ncand)" -eq 0 ]
  check "late retro: processed notice" grep -q 'processed (late retro report)' <<<"$OUT"
  check "late retro: no candidate for the retro ask itself" [ "$(ls .harness/retro/done/*.json | wc -l | tr -d ' ')" -eq 1 ]
fi

setup   # brief points at the log snapshot, not the live task file
mkdir -p .harness; printf 'BRIEF-BODY\n' > .harness/task-analyst.md
slowask analyst 'Read .harness/task-analyst.md and do it.'
check "brief field: log#brief" [ "$(cand .brief)" = "$(cand .log)#brief" ]
check "brief field: log holds the brief" grep -q 'BRIEF-BODY' "$(cand .log)"
run retro --dry-run
check "brief field: rendered as log section" grep -q '^- brief: .harness/log/.*(its `## Brief` section' <<<"$OUT"

# --via validation
setup
hook analyst '# analyst report\nstatus: done\n'
run ask analyst "x" --via retro
check "--via retro accepted" [ "$RC" -eq 0 ]
run ask analyst "x" --via bogus
check "--via bogus still refused" [ "$RC" -eq 1 ]
check "exit 1 (usage error): no candidate" [ "$(ncand)" -eq 0 ]


echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
