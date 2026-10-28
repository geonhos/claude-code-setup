#!/bin/bash
# Tests for the progress log, rotation, ctx reading and worker context reset in
# bin/harness (against tests/fake-herdr). Run: /bin/bash tests/progress.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
FAKE_BIN="$HERE/fake-herdr"
# WN <role> — scoped herdr name for the current directory (the repo under test)
WN() { env -u HARNESS_ROLE /bin/bash "$HARNESS" _wname "$1"; }
pass=0
fail=0

WORKS=""
trap 'cd / && for d in $WORKS; do rm -rf "$d"; done' EXIT
setup() {
  WORK=$(mktemp -d)
  WORKS="$WORKS $WORK"
  export FAKE_DIR="$WORK/fake" FAKE_LOG="$WORK/herdr.log"
  export HARNESS_PROJECTS_DIR="$WORK/projects"
  export HARNESS_CLEAR_INTERVAL=0 HARNESS_CLEAR_POLLS=3
  export HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2
  mkdir -p "$FAKE_DIR"
  : > "$FAKE_LOG"
  unset FAKE_PROMPT_HOOK FAKE_CLEAR HARNESS_CTX_RESET HARNESS_LOG_KEEP HARNESS_LOG_DAYS HARNESS_JSONL_MAX HARNESS_ROUTE_LOG
  cd "$WORK" || exit 1
  printf 'fake/\nherdr.log\nprojects/\n' > .gitignore
}

GUARD="perl -e alarm(10);exec(@ARGV)"
run() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>/dev/null)
  RC=$?
}
# runerr: same, stdout+stderr merged
runerr() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi; }
logged() { grep -qF -- "$1" "$FAKE_LOG"; }
not_grep() { ! grep "$@"; }
not_logged() { ! grep -qF -- "$1" "$FAKE_LOG"; }
gitwork() { git init -q . && git config user.email t@t && git config user.name t && echo s > s.txt && git add s.txt .gitignore && git -c core.hooksPath=/dev/null commit -q -m s; }
hook_report() { # hook_report AGENT BODY -> FAKE_PROMPT_HOOK writing a report
  export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '$2' > $WORK/.harness/reports/$1.md"
}
jl() { jq -r "$1" "$WORK/.harness/progress.jsonl" 2>/dev/null | tail -n 1; }
nlines() { wc -l < "$1" | tr -d ' '; }
logfiles() { ls "$WORK"/.harness/log/*.md 2>/dev/null; }
# the encoding rule lives in bin/harness (project_dir_name), reached via _projdir
projdir() { echo "$HARNESS_PROJECTS_DIR/$(HERDR_ENV=1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" env -u HARNESS_ROLE /bin/bash "$HARNESS" _projdir)"; }
lastjson() { printf '%s\n' "$1" >> .harness/progress.jsonl; }
# transcript SESSION CACHE_READ [CREATE] [INPUT]
transcript() {
  mkdir -p "$(projdir)"
  { printf '{"type":"user","message":{"content":"hi"}}\n'
    printf '{"type":"assistant","isSidechain":false,"message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' "${4:-2}" "${3:-0}" "$2"
    printf '{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":999999}}}\n'
    printf 'not json\n'
  } > "$(projdir)/$1.jsonl"
}

# --- log + jsonl per ask: exit 0 ----------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook_report analyst '# analyst report — find things\nstatus: done\n## Open questions\n- should we X?\n'
run ask analyst "Describe the repo"
check "log: ask rc unchanged" [ "$RC" -eq 0 ]
check "log: ask stdout is the report" [ "$OUT" = "$(printf '# analyst report — find things\nstatus: done\n## Open questions\n- should we X?')" ]
check "log: one log file" [ "$(logfiles | wc -l | tr -d ' ')" -eq 1 ]
check "log: file name" logfiles | grep -Eq '/[0-9]{8}-[0-9]{6}-analyst\.md$'
check "log: has instruction" grep -q "Describe the repo" "$(logfiles | head -1)"
check "log: has report" grep -q "status: done" "$(logfiles | head -1)"
check "jsonl: one line" [ "$(nlines .harness/progress.jsonl)" -eq 1 ]
check "jsonl: agent" [ "$(jl .agent)" = analyst ]
check "jsonl: exit" [ "$(jl .exit)" = 0 ]
check "jsonl: status" [ "$(jl .status)" = done ]
check "jsonl: summary" [ "$(jl .summary)" = "analyst report — find things" ]
check "jsonl: instr" [ "$(jl .instr)" = "Describe the repo" ]
check "jsonl: session" [ "$(jl .session)" = "sess-analyst-0" ]
check "jsonl: dur_s number" [ "$(jl '.dur_s|type')" = number ]
check "jsonl: ts" jq -e '.ts|test("^[0-9]{4}-")' .harness/progress.jsonl >/dev/null
check "jsonl: verify null for analyst" [ "$(jl '.verify')" = null ]
long=$(printf 'x%.0s' $(seq 1 300))
run ask analyst "$long"
check "jsonl: instr 160 chars" [ "$(jl '.instr|length')" -eq 160 ]

# --- routing.jsonl delegate line per ask --------------------------------------------
rj() { jq -r "$1" "$WORK/.harness/routing.jsonl" 2>/dev/null | tail -n 1; }
unset CLAUDE_CODE_SESSION_ID  # the host session must not leak into the null-session case
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook_report analyst '# analyst report — r\nstatus: done\n'
run ask analyst "look" --via skill
check "route: ask rc" [ "$RC" -eq 0 ]
check "route: one delegate line" [ "$(nlines .harness/routing.jsonl)" -eq 1 ]
check "route: event" [ "$(rj .event)" = delegate ]
check "route: worker" [ "$(rj .worker)" = analyst ]
check "route: source skill" [ "$(rj .source)" = skill ]
check "route: exit 0" [ "$(rj .exit)" = 0 ]
check "route: session null without env" [ "$(rj .session)" = null ]
OUT=$(CLAUDE_CODE_SESSION_ID=cond-42 HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "again" 2>/dev/null); RC=$?
check "route: default source conductor" [ "$(rj .source)" = conductor ]
check "route: session from env" [ "$(rj .session)" = cond-42 ]
check "route: two lines" [ "$(nlines .harness/routing.jsonl)" -eq 2 ]
run ask analyst "x" --via skill --fresh
check "route: --via combines with --fresh" [ "$RC" -eq 0 ]
check "route: three lines" [ "$(nlines .harness/routing.jsonl)" -eq 3 ]
runerr ask analyst "x" --via bogus
check "route: bogus via rc 1" [ "$RC" -eq 1 ]
check "route: bogus via message" grep -q -- '--via' <<<"$OUT"
check "route: bogus via not logged" [ "$(nlines .harness/routing.jsonl)" -eq 3 ]
check "route: bogus via no progress line" [ "$(nlines .harness/progress.jsonl)" -eq 3 ]
runerr ask analyst "x" --via
check "route: --via without value rc 1" [ "$RC" -eq 1 ]
check "route: --via without value not logged" [ "$(nlines .harness/routing.jsonl)" -eq 3 ]
check "route: --via without value no progress line" [ "$(nlines .harness/progress.jsonl)" -eq 3 ]
hook_report analyst '# analyst report — r\nstatus: done\n'
run ask analyst "--via" --via skill
check "route: text --via is not an option" [ "$RC" -eq 0 ]
check "route: text --via source skill" [ "$(rj .source)" = skill ]
# exit code of a failing ask is still recorded
rm -f "$FAKE_DIR/live.$(WN analyst)"; echo idle > "$FAKE_DIR/live.$(WN analyst)"
unset FAKE_PROMPT_HOOK
touch "$FAKE_DIR/no_stop_hook"
run ask analyst "no report please" --via skill
rm -f "$FAKE_DIR/no_stop_hook"
check "route: exit 3 recorded" [ "$(rj .exit)" = 3 ]
check "route: rc still 3" [ "$RC" -eq 3 ]
# routing log failure does not change the ask result
chmod 000 .harness/routing.jsonl
hook_report analyst '# analyst report — r\nstatus: done\n'
runerr ask analyst "y"
check "route: unwritable log keeps rc 0" [ "$RC" -eq 0 ]
check "route: unwritable log warns" grep -q 'route-log' <<<"$OUT"
check "route: unwritable log only our warning" [ "$(grep -c 'Permission denied' <<<"$OUT")" -eq 0 ]
chmod 644 .harness/routing.jsonl

# --- exit 3 (no report): screen tail in log ----------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
touch "$FAKE_DIR/no_stop_hook"
run ask analyst "q"
check "exit3: rc" [ "$RC" -eq 3 ]
check "exit3: jsonl exit" [ "$(jl .exit)" = 3 ]
check "exit3: log has screen" grep -q "fake screen line" "$(logfiles | head -1)"

# --- exit 2 (blocked), exit 4 (busy) ---------------------------------------------------------
setup
echo blocked > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "q"
check "exit2: rc" [ "$RC" -eq 2 ]
check "exit2: jsonl exit" [ "$(jl .exit)" = 2 ]
setup
echo working > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "q"
check "exit4: rc" [ "$RC" -eq 4 ]
check "exit4: jsonl exit" [ "$(jl .exit)" = 4 ]

# --- implementer: verify field, heads, brief ------------------------------------------------
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"
mkdir -p .harness; printf '# Task: brief title\nBRIEF-BODY-LINE\n' > .harness/task-implementer.md
export FAKE_PROMPT_HOOK="cd $WORK && echo c > c.txt && git add c.txt && git -c core.hooksPath=/dev/null commit -q -m c; mkdir -p .harness/reports .harness/verify; printf '# r — did it\nstatus: partial\n' > .harness/reports/implementer.md; printf '{\"status\":\"fail\",\"attempts\":3,\"step\":\"test\",\"tail\":\"\"}' > .harness/verify/implementer.json"
run ask implementer "Read .harness/task-implementer.md and do it."
check "impl: exit 5" [ "$RC" -eq 5 ]
check "impl: jsonl exit 5" [ "$(jl .exit)" = 5 ]
check "impl: jsonl verify fail" [ "$(jl .verify)" = fail ]
check "impl: jsonl status partial" [ "$(jl .status)" = partial ]
check "impl: head_before differs from head_after" [ "$(jl .head_before)" != "$(jl .head_after)" ]
check "impl: head_after is HEAD" [ "$(jl .head_after)" = "$(git rev-parse --short HEAD)" ]
check "impl: log has brief contents" grep -q BRIEF-BODY-LINE "$(logfiles | head -1)"

# --- logging never breaks an ask ------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness; echo notadir > .harness/log
runerr ask analyst "q"
check "logfail: rc still 0" [ "$RC" -eq 0 ]
check "logfail: warning on stderr" grep -qi "progress" <<<"$OUT"
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness; mkdir .harness/progress.jsonl
run ask analyst "q"
check "logfail2: rc still 0" [ "$RC" -eq 0 ]

# --- progress.md ------------------------------------------------------------------------------------------
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook_report analyst '# analyst report — first thing\nstatus: done\n## Open questions\n- should we X?\n- none\n'
run ask analyst "one"
check "md: exists" [ -f .harness/progress.md ]
check "md: title" head -1 .harness/progress.md | grep -q "^# Progress — $(basename "$WORK")"
check "md: goal unset" grep -qx 'Goal: (unset)' .harness/progress.md
check "md: ask line" grep -q "analyst exit 0 .* — analyst report — first thing" .harness/progress.md
check "md: open questions" grep -q -- "- should we X?" .harness/progress.md
check "md: open questions skip none" not_grep -qx -- "- none" .harness/progress.md
check "md: workers line" grep -q "analyst idle" .harness/progress.md
printf 'Ship the thing.\nSecond line.\n' > .harness/goal.md
hook_report analyst '# analyst report — second thing\nstatus: done\n'
run ask analyst "two"
check "md: goal shown" grep -qx 'Goal: Ship the thing. Second line.' .harness/progress.md
check "md: newest first" [ "$(grep -n 'second thing' .harness/progress.md | head -1 | cut -d: -f1)" -lt "$(grep -n 'first thing' .harness/progress.md | head -1 | cut -d: -f1)" ]
# cap: 40 prior lines -> 15 recent, <= 60 lines
i=0; while [ $i -lt 40 ]; do
  echo '{"ts":"2026-10-18T00:00:00Z","agent":"analyst","exit":0,"verify":null,"head_before":"a","head_after":"b","summary":"old","status":"done"}' >> .harness/progress.jsonl; i=$((i+1)); done
run ask analyst "three"
check "md: <= 60 lines" [ "$(nlines .harness/progress.md)" -le 60 ]
check "md: max 15 recent asks" [ "$(grep -c '^- 20' .harness/progress.md)" -eq 15 ]

# --- rotation -----------------------------------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness/log
i=1; while [ $i -le 205 ]; do : > ".harness/log/20261001-000000-analyst-$i.md"; i=$((i+1)); done
run ask analyst "q"
check "rotate: newest 200 kept" [ "$(logfiles | wc -l | tr -d ' ')" -eq 200 ]
check "rotate: new log kept" [ "$(ls .harness/log | grep -c -- '-analyst.md$')" -ge 1 ]
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook_report analyst '# r\nstatus: done\n'
mkdir -p .harness/log
: > .harness/log/20200101-000000-analyst.md; touch -t 202001010000 .harness/log/20200101-000000-analyst.md
: > .harness/log/20261001-000000-analyst.md
run ask analyst "q"
check "rotate: old by mtime deleted" [ ! -e .harness/log/20200101-000000-analyst.md ]
check "rotate: recent kept" [ -e .harness/log/20261001-000000-analyst.md ]
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook_report analyst '# r\nstatus: done\n'
export HARNESS_JSONL_MAX=300
mkdir -p .harness
i=0; while [ $i -lt 10 ]; do echo '{"ts":"2026-10-18T00:00:00Z","agent":"analyst","exit":0,"summary":"padding padding padding"}' >> .harness/progress.jsonl; i=$((i+1)); done
run ask analyst "q"
check "rotate: jsonl gz exists" [ "$(ls .harness/progress.jsonl.*.gz 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
check "rotate: gz has old lines" [ "$(gzip -dc .harness/progress.jsonl.*.gz | wc -l | tr -d ' ')" -eq 10 ]
check "rotate: new jsonl has only new line" [ "$(nlines .harness/progress.jsonl)" -eq 1 ]

# --- ctx reading / status column ---------------------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
echo "sess-rev" > "$FAKE_DIR/session.$(WN reviewer)"
transcript sess-analyst-0 134572 2750 2
run status
check "ctx: analyst 137k" grep -Eq "^analyst +idle +w1:p2 +137k$" <<<"$OUT"
check "ctx: missing transcript -" grep -Eq "^reviewer +idle +w1:p2 +-$" <<<"$OUT"
check "ctx: dead agent line" grep -Eq "^implementer +-$" <<<"$OUT"
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q"
check "ctx: ctx_before in jsonl" [ "$(jl .ctx_before)" = 137324 ]
check "ctx: ctx_after null after the reset (new session)" [ "$(jl .ctx_after)" = null ]
setup
echo idle > "$FAKE_DIR/live.$(WN reviewer)"
hook_report reviewer '# r\nVERDICT: PASS\n'
run ask reviewer "q"
check "ctx: unknown -> null" [ "$(jl .ctx_before)" = null ]

# --- context reset: implementer ---------------------------------------------------------------------------------------------------------
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset impl: rc 0" [ "$RC" -eq 0 ]
check "reset impl: /clear sent" logged "agent prompt $(WN implementer) /clear"
check "reset impl: no --wait on /clear" not_logged "/clear --wait"
check "reset impl: no respawn" not_logged "pane close"
check "reset impl: progress clear ok" [ "$(jl .clear)" = ok ]
check "reset impl: real prompt after clear" [ "$(grep -n "agent prompt $(WN implementer) /clear" "$FAKE_LOG" | cut -d: -f1)" -lt "$(grep -n "agent prompt $(WN implementer) do" "$FAKE_LOG" | cut -d: -f1)" ]

setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"; echo w1:p5 > "$FAKE_DIR/pane.$(WN implementer)"
mkdir -p .harness; echo "implementer w1:p5" > .harness/panes
export FAKE_CLEAR=stuck
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset stuck: rc 0" [ "$RC" -eq 0 ]
check "reset stuck: pane closed" logged "pane close w1:p5"
check "reset stuck: respawned" logged "agent start $(WN implementer)"
check "reset stuck: ask output is the report" [ "$OUT" = "$(printf '# r\nstatus: done')" ]
check "reset stuck: /clear sent twice (one retry)" [ "$(grep -c "agent prompt $(WN implementer) /clear" "$FAKE_LOG")" -eq 2 ]
check "reset stuck: progress clear respawn" [ "$(jl .clear)" = respawn ]
unset FAKE_CLEAR

# sid never changes and the pane is busy (working) after the first /clear: no second /clear, respawn
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"; echo w1:p5 > "$FAKE_DIR/pane.$(WN implementer)"
mkdir -p .harness; echo "implementer w1:p5" > .harness/panes
export FAKE_CLEAR=stuckbusy
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset busy: rc 0" [ "$RC" -eq 0 ]
check "reset busy: exactly one /clear (no retry while busy)" [ "$(grep -c "agent prompt $(WN implementer) /clear" "$FAKE_LOG")" -eq 1 ]
check "reset busy: pane closed" logged "pane close w1:p5"
check "reset busy: progress clear respawn" [ "$(jl .clear)" = respawn ]
unset FAKE_CLEAR

# sid changes late (30 polls ~ 15 s at the default 0.5 s interval): still ok, no retry, no respawn
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"; echo w1:p5 > "$FAKE_DIR/pane.$(WN implementer)"
mkdir -p .harness; echo "implementer w1:p5" > .harness/panes
export FAKE_CLEAR=late30; unset HARNESS_CLEAR_POLLS   # default poll count (60)
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset late: rc 0" [ "$RC" -eq 0 ]
check "reset late: one /clear" [ "$(grep -c "agent prompt $(WN implementer) /clear" "$FAKE_LOG")" -eq 1 ]
check "reset late: no respawn" not_logged "pane close"
check "reset late: progress clear ok" [ "$(jl .clear)" = ok ]
unset FAKE_CLEAR

# session id changes but the status stays working: still a successful clear (no retry, no respawn)
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"; echo w1:p5 > "$FAKE_DIR/pane.$(WN implementer)"
mkdir -p .harness; echo "implementer w1:p5" > .harness/panes
export FAKE_CLEAR=sidonly
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset sid-only: rc 0" [ "$RC" -eq 0 ]
check "reset sid-only: one /clear" [ "$(grep -c "agent prompt $(WN implementer) /clear" "$FAKE_LOG")" -eq 1 ]
check "reset sid-only: no respawn" not_logged "pane close"
check "reset sid-only: progress clear ok" [ "$(jl .clear)" = ok ]
unset FAKE_CLEAR

# only the second /clear takes effect: retry, no respawn
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"; echo w1:p5 > "$FAKE_DIR/pane.$(WN implementer)"
mkdir -p .harness; echo "implementer w1:p5" > .harness/panes
export FAKE_CLEAR=second
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset retry: rc 0" [ "$RC" -eq 0 ]
check "reset retry: /clear sent twice" [ "$(grep -c "agent prompt $(WN implementer) /clear" "$FAKE_LOG")" -eq 2 ]
check "reset retry: no respawn" not_logged "pane close"
check "reset retry: progress clear retry" [ "$(jl .clear)" = retry ]
unset FAKE_CLEAR

setup; gitwork
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "reset: fresh spawn needs no clear" not_logged "/clear"
check "reset: fresh spawn progress clear none" [ "$(jl .clear)" = none ]

setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it" --keep
check "keep: rc 0" [ "$RC" -eq 0 ]
check "keep: no clear" not_logged "/clear"

# --- context reset: analyst/reviewer threshold, --fresh ---------------------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
transcript sess-analyst-0 50000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q"
check "analyst low ctx: no clear" not_logged "/clear"
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
transcript sess-analyst-0 130000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q"
check "analyst high ctx: clear" logged "agent prompt $(WN analyst) /clear"
check "analyst high ctx: ctx_before logged" [ "$(jl .ctx_before)" = 130002 ]
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
transcript sess-analyst-0 130000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q" --keep
check "analyst high ctx --keep: no clear" not_logged "/clear"
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
transcript sess-analyst-0 50000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q" --fresh
check "analyst --fresh: clear" logged "agent prompt $(WN analyst) /clear"
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
transcript sess-analyst-0 50000
export HARNESS_CTX_RESET=40000
hook_report analyst '# r\nstatus: done\n'
run ask analyst "q"
check "HARNESS_CTX_RESET honoured" logged "agent prompt $(WN analyst) /clear"
setup
run ask analyst "q" --fresh --keep
check "fresh+keep is a usage error" [ "$RC" -eq 1 ]

# --- reset skipped after an unclean ask ----------------------------------------------------------------------------------------------------
reset_after() { # reset_after AGENT EXIT [flag] — a logged ask with EXIT, then a new ask
  setup; gitwork
  echo idle > "$FAKE_DIR/live.$(WN $1)"
  [ "$1" = implementer ] || transcript "sess-$1-0" 130000
  mkdir -p .harness
  lastjson "{\"ts\":\"2026-10-18T00:00:00Z\",\"agent\":\"$1\",\"exit\":$2}"
  hook_report "$1" '# r\nstatus: done\n'
  runerr ask "$1" "do it" ${3:-}
}
reset_after implementer 0
check "after exit 0: reset" logged "agent prompt $(WN implementer) /clear"
for e in 1 2 3 4 5 129 130 143; do
  reset_after implementer $e
  check "after exit $e: no clear" not_logged "/clear"
  check "after exit $e: stderr notice" grep -qx "keeping context (last ask exit $e)" <<<"$OUT"
done
reset_after reviewer 5 --fresh
check "reviewer exit 5 --fresh: reset" logged "agent prompt $(WN reviewer) /clear"
reset_after reviewer 0
check "reviewer exit 0: reset" logged "agent prompt $(WN reviewer) /clear"
reset_after reviewer 5
check "reviewer exit 5 (FAIL verdict): reset" logged "agent prompt $(WN reviewer) /clear"
reset_after reviewer 4
check "reviewer exit 4: no clear" not_logged "/clear"
reset_after implementer 5 --fresh
check "after exit 5 --fresh: reset" logged "agent prompt $(WN implementer) /clear"
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"; mkdir -p .harness
lastjson '{"ts":"t","agent":"implementer","exit":5}'
lastjson '{"ts":"t","agent":"analyst","exit":0}'
lastjson '{"ts":"t","agent":"implementer","exit":null,"late":true}'
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "other agents/late lines do not hide the last exit" not_logged "/clear"

# --- a worktree ask's line (agent: <role>, ask_id set) is not a plain ask's history -------------------------------------------------
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"; mkdir -p .harness
lastjson '{"ts":"2026-10-18T00:00:00Z","agent":"implementer","exit":0}'
lastjson '{"ts":"2026-10-18T00:00:01Z","agent":"implementer","exit":4,"ask_id":"1-2-3","wt":"/x/wt","base":"b"}'
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "leak: worktree exit 4 does not keep the plain ask's context" logged "/clear"
setup; gitwork
echo idle > "$FAKE_DIR/live.$(WN implementer)"; mkdir -p .harness
lastjson '{"ts":"2026-10-18T00:00:00Z","agent":"implementer","exit":4}'
lastjson '{"ts":"2026-10-18T00:00:01Z","agent":"implementer","exit":0,"ask_id":"1-2-3","wt":"/x/wt","base":"b"}'
hook_report implementer '# r\nstatus: done\n'
run ask implementer "do it"
check "leak: worktree exit 0 does not hide the plain ask's exit 4" not_logged "/clear"

# --- usage errors inside the ask are logged (exit 1); option errors that die first are not ---------------------------------------
for bad in "--fresh --keep" "--timeout abc" "--timeout 0" "--bogus"; do
  setup
  runerr ask analyst "q" $bad
  check "usage ($bad): rc 1" [ "$RC" -eq 1 ]
  check "usage ($bad): progress line exit 1" [ "$(jl .exit)" = 1 ]
  check "usage ($bad): routing line exit 1" [ "$(rj .exit)" = 1 ]
  check "usage ($bad): nothing sent" not_logged "agent prompt"
done
for bad in "--via nope" "--via" "--base x" "--worktree --base"; do
  setup
  runerr ask analyst "q" $bad
  check "early refusal ($bad): rc 1" [ "$RC" -eq 1 ]
  check "early refusal ($bad): nothing logged" [ ! -e .harness/progress.jsonl ] && [ ! -e .harness/routing.jsonl ]
done

# --- late report archived, never deleted unlogged --------------------------------------------------------------------------------
setup
echo working > "$FAKE_DIR/live.$(WN analyst)"
run ask analyst "first"
check "late: first ask exit 4" [ "$RC" -eq 4 ]
echo idle > "$FAKE_DIR/live.$(WN analyst)"
mkdir -p .harness/reports
printf '# LATE REPORT title\nstatus: partial\n' > .harness/reports/analyst.md
hook_report analyst '# r\nstatus: done\n'
run ask analyst "second"
check "late: archive file" [ "$(ls .harness/log/*-analyst-late.md 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
check "late: archive has the report" grep -q "LATE REPORT title" .harness/log/*-analyst-late.md
check "late: jsonl line" [ "$(jq -c 'select(.late == true) | [.exit, .status, .summary]' .harness/progress.jsonl)" = '[null,"partial","LATE REPORT title"]' ]
check "late: in progress.md" grep -q "analyst late report .* — LATE REPORT title" .harness/progress.md
# an already logged report is not archived again
run ask analyst "third"
check "logged report not archived twice" [ "$(ls .harness/log/*-analyst-late.md | wc -l | tr -d ' ')" -eq 1 ]
check "logged report: sha stored" [ -n "$(jl .report_sha | grep -v null)" ]
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
hook_report analyst '# r\nstatus: done\n'
run ask analyst "a"
run ask analyst "b"
check "normal flow: no late archive" [ "$(ls .harness/log/*-late*.md 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]

# --- transcript dir encoding ----------------------------------------------------------------------------------------------------------------------
setup
mkdir -p "$WORK/a_b c é한.d" && cd "$WORK/a_b c é한.d" || exit 1
check "encode: every non-alnum char (not byte) is -" [ "$(projdir | sed 's#.*/##')" = "$(printf %s "$(pwd -P)" | perl -CS -pe 's/[^A-Za-z0-9]/-/g')" ]
check "encode: tail is a-b-c----d" [ "$(projdir | sed 's#.*/##' | sed 's#.*\(a-b-c-*d\)$#\1#')" = "a-b-c----d" ]
echo idle > "$FAKE_DIR/live.$(WN analyst)"
transcript sess-analyst-0 134572 2750 2
run status
check "encode: ctx read in an odd cwd" grep -Eq "^analyst +idle +w1:p2 +137k$" <<<"$OUT"
cd "$WORK"

# --- ctx: whole-file scan -------------------------------------------------------------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
transcript sess-analyst-0 134572 2750 2
i=0; while [ $i -lt 400 ]; do echo '{"type":"progress","data":{}}' >> "$(projdir)/sess-analyst-0.jsonl"; i=$((i+1)); done
run status
check "ctx: assistant line beyond 200 lines back" grep -Eq "^analyst +idle +w1:p2 +137k$" <<<"$OUT"

# --- ask wrapper killed mid-wait ------------------------------------------------------------------------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.$(WN analyst)"
mkdir -p "$WORK/tmp"
export FAKE_PROMPT_HOOK="echo REPLAYED >> $WORK/tmp/harness-ask.*; sleep 3"
TMPDIR="$WORK/tmp" HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "long" > "$WORK/killed.out" 2>/dev/null &
KP=$!
i=0; while [ $i -lt 50 ] && ! grep -q REPLAYED "$WORK"/tmp/harness-ask.* 2>/dev/null; do sleep 0.1; i=$((i+1)); done
kill -TERM "$KP"; wait "$KP"; KRC=$?
unset FAKE_PROMPT_HOOK
OUT=$(cat "$WORK/killed.out")
check "kill: exit 143" [ "$KRC" -eq 143 ]
check "kill: stdout replayed" [ "$OUT" = REPLAYED ]
check "kill: temp file gone" [ -z "$(ls "$WORK/tmp" 2>/dev/null)" ]
check "kill: jsonl exit 143" [ "$(jl .exit)" = 143 ]
check "kill: log written" [ "$(logfiles | wc -l | tr -d ' ')" -eq 1 ]

# --- real exit for any signal, HUP trapped, whole tree killed ---------------------------------------------------------------
sigtest() { # sigtest SIGNAL EXPECTED_RC
  setup
  echo idle > "$FAKE_DIR/live.$(WN analyst)"
  mkdir -p "$WORK/tmp"; rm -f "$WORK/gc.pid"
  export FAKE_PROMPT_HOOK="echo REPLAYED >> $WORK/tmp/harness-ask.*; (sleep 30 & echo \$! > $WORK/gc.pid; wait); sleep 30"
  TMPDIR="$WORK/tmp" HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" env -u HARNESS_ROLE /bin/bash "$HARNESS" ask analyst "long" > "$WORK/sig.out" 2>/dev/null &
  KP=$!
  i=0; while [ $i -lt 50 ] && [ ! -s "$WORK/gc.pid" ]; do sleep 0.1; i=$((i+1)); done
  GC=$(cat "$WORK/gc.pid" 2>/dev/null)
  kill -"$1" "$KP"; wait "$KP"; KRC=$?
  unset FAKE_PROMPT_HOOK
  sleep 0.3
}
sigtest HUP 129
check "HUP: rc 129" [ "$KRC" -eq 129 ]
check "HUP: jsonl exit 129" [ "$(jl .exit)" = 129 ]
check "HUP: temp file gone" [ -z "$(ls "$WORK/tmp" 2>/dev/null)" ]
check "HUP: grandchild gone" [ -n "$GC" ] && ! kill -0 "$GC" 2>/dev/null
sigtest TERM 143
check "TERM: grandchild gone" [ -n "$GC" ] && ! kill -0 "$GC" 2>/dev/null
check "TERM: jsonl exit 143" [ "$(jl .exit)" = 143 ]
check "route: delegate on TERM" [ "$(rj .exit)" = 143 ]

# --- spawn env ----------------------------------------------------------------------------------------------------------------------------------------------
setup
run spawn analyst
check "spawn: auto-compact window env" logged "--env CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000"
check "spawn: role env kept" logged "--env HARNESS_ROLE=worker"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
