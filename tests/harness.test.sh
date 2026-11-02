#!/bin/bash
# bin/harness (headless runner only): preconditions, worker guard, report, defaults, init. Run: /bin/bash tests/harness.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"

# --- preconditions -----------------------------------------------------------
setup
OUT=$(env -u HERDR_ENV -u HARNESS_ROLE PATH="$FAKE_BIN:$PATH" /bin/bash "$HARNESS" status 2>&1); RC=$?
check "status works without herdr" [ "$RC" -eq 0 ]
check "status without herdr lists the roles" grep -q "analyst" <<<"$OUT"
run spawn analyst
check "spawn is gone" [ "$RC" -eq 1 ]

run
check "no args shows usage" [ "$RC" -eq 1 ]
check "usage text" grep -q "harness ask" <<<"$OUT"
check "usage has no spawn" bash -c '! grep -q "harness spawn" <<<"$1"' _ "$OUT"

setup
run ask analyst "x" --timeout
check "ask --timeout without value rc" [ "$RC" -eq 1 ]
run ask analyst "x" --timeout abc
check "ask --timeout abc rc" [ "$RC" -eq 1 ]
run ask analyst "x" --timeout 0
check "ask --timeout 0 rc" [ "$RC" -eq 1 ]
run ask analyst
check "ask without instruction rc" [ "$RC" -eq 1 ]

# --- worker guard: ask refused in worker sessions ----------------------------
setup
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" HARNESS_ROLE=worker $GUARD /bin/bash "$HARNESS" ask analyst x 2>&1); RC=$?
check "worker ask rc 1" [ "$RC" -eq 1 ]
check "worker ask message" grep -q conductor <<<"$OUT"
check "worker ask: no progress.jsonl" [ ! -e "$WORK/.harness/progress.jsonl" ]
check "worker ask: no routing.jsonl" [ ! -e "$WORK/.harness/routing.jsonl" ]
check "worker ask: no viewer pane" not_logged "pane split"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" HARNESS_ROLE=worker $GUARD /bin/bash "$HARNESS" status 2>&1); RC=$?
check "worker status still works" [ "$RC" -eq 0 ]

# fin ROLE — a finished headless run for ROLE (report needs exit.json)
fin() { mkdir -p .harness/asks; [ -f ".harness/asks/$1.exit.json" ] || printf '{"ask_id":"t-1-1","exit":0}\n' > ".harness/asks/$1.exit.json"; }

# --- report ------------------------------------------------------------------------
setup
mkdir -p .harness/reports && printf 'R1\nVERDICT: PASS\n' > .harness/reports/reviewer.md
fin reviewer; run report reviewer
check "report rc" [ "$RC" -eq 0 ]
check "report prints file" [ "$OUT" = "$(printf 'R1\nVERDICT: PASS')" ]

setup
run report reviewer
check "report without a finished run rc" [ "$RC" -eq 3 ]
check "report without a finished run message" grep -q "no finished run for reviewer" <<<"$OUT"

run report bogus
check "report unknown agent rc" [ "$RC" -eq 1 ]

run

# --- report: ## Learned -> docs/wiki/inbox -------------------------------------------
setup
mkdir -p .harness/reports .harness/asks docs/wiki
printf '1700000000-123-456 1700000000\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Learned\n- stat -f is GNU-hostile (bin/harness:815)\n- vague claim with no proof\n- fixed in commit 79a1964\n## Open questions\n- none\n' > .harness/reports/analyst.md
fin analyst; run report analyst
check "learned rc" [ "$RC" -eq 0 ]
check "learned queue line" grep -q '^wiki: 2 lessons queued in docs/wiki/inbox/' <<<"$OUT"
Q=$(ls docs/wiki/inbox/*-analyst-1700000000-123-456.md 2>/dev/null | head -1)
check "learned file named by role+ask-id" [ -n "$Q" ]
check "learned header" grep -q '^role: analyst' "$Q"
check "learned header ask-id" grep -q '^ask-id: 1700000000-123-456' "$Q"
check "learned keeps evidence bullet" grep -q 'bin/harness:815' "$Q"
check "learned caps at 2 bullets" [ "$(grep -c '^- ' "$Q")" -eq 2 ]
check "learned drops bullet without evidence" not grep -q 'vague claim' "$Q"
fin analyst; run report analyst
check "learned warns on dropped bullet" grep -q 'dropped 1 Notes bullet' <<<"$OUT"
check "learned idempotent (one file)" [ "$(ls docs/wiki/inbox | wc -l | tr -d ' ')" -eq 1 ]
check "learned second run no queue line" not grep -q '^wiki:' <<<"$OUT"

setup
mkdir -p .harness/reports docs/wiki
printf '# analyst report\nstatus: done\n## Learned\n- none\n## Open questions\n- none\n' > .harness/reports/analyst.md
fin analyst; run report analyst
check "learned none: nothing queued" [ ! -d docs/wiki/inbox ]
check "learned none: no wiki line" not grep -q '^wiki:' <<<"$OUT"
printf '# analyst report\nstatus: done\n## Learned\n- no proof here at all\n' > .harness/reports/analyst.md
fin analyst; run report analyst
check "learned all dropped: nothing queued" [ ! -d docs/wiki/inbox ]
printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md
fin analyst; run report analyst
check "no Learned section: nothing queued" [ ! -d docs/wiki/inbox ]
mkdir -p .harness/reports .harness/asks
printf '1700000001-1-2 1700000001\n' > .harness/asks/reviewer.current
printf '# reviewer report\nstatus: done\n## Learned\n- race seen in .harness/progress.jsonl\nVERDICT: PASS\n' > .harness/reports/reviewer.md
fin reviewer; run report reviewer
check "learned before VERDICT: rc 0" [ "$RC" -eq 0 ]
check "learned reviewer queued" [ "$(ls docs/wiki/inbox/*-reviewer-* 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ]
check "reviewer VERDICT still last line" [ "$(printf '%s\n' "$OUT" | tail -1)" = "VERDICT: PASS" ]

# learned: continuation lines, evidence strictness, idempotency, no ask-id, no docs/wiki
learned_case() { # learned_case BODY -> fresh wiki repo, report, sets OUT/RC and Q (count of queued files)
  setup
  mkdir -p .harness/reports .harness/asks docs/wiki
  printf '1700000002-9-9 1700000002\n' > .harness/asks/analyst.current
  printf '# analyst report\nstatus: done\n## Learned\n%b## Open questions\n- none\n' "$1" > .harness/reports/analyst.md
  fin analyst; run report analyst
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
fin analyst; run report analyst
check "learned idempotent by ask-id (different date)" [ "$(ls docs/wiki/inbox | wc -l | tr -d ' ')" -eq 1 ]
mv docs/wiki/inbox/*.md docs/wiki/inbox/2020-01-01-analyst-1700000002-9-9.md
fin analyst; run report analyst
check "learned idempotent ignores date prefix" [ "$(ls docs/wiki/inbox | wc -l | tr -d ' ')" -eq 1 ]
learned_case '- see bin/harness:1\n'
rm -rf docs .harness/asks/analyst.current; mkdir -p docs/wiki
fin analyst; run report analyst
check "learned no ask-id: nothing queued" [ ! -d docs/wiki/inbox ]
check "learned no ask-id: warns" grep -q 'no ask-id' <<<"$OUT"
setup
mkdir -p .harness/reports .harness/asks
printf '1700000002-9-9 1700000002\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Learned\n- see bin/harness:1\n' > .harness/reports/analyst.md
fin analyst; run report analyst
check "learned without docs/wiki: nothing created" [ ! -d docs ]
setup
mkdir -p docs/wiki
# the new `## Notes` heading is accepted (Learned above stays as the legacy form)
mkdir -p .harness/asks .harness/reports; printf '1700000003-7-7 1700000003\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Notes\n- seen in bin/harness:844\n' > .harness/reports/analyst.md
fin analyst; run report analyst
check "Notes section queued" grep -q '^wiki: 1 lesson' <<<"$OUT"

# Learned + Notes together: bullets from both, one shared 2-bullet cap
setup
mkdir -p docs/wiki .harness/asks .harness/reports; printf '1700000004-8-8 1700000004\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Learned\n- first in bin/harness:10\n## Notes\n- second in bin/harness:20\n- third in bin/harness:30\n' > .harness/reports/analyst.md
fin analyst; run report analyst
check "Learned+Notes queue line" grep -q '^wiki: 2 lessons' <<<"$OUT"
Q=$(ls docs/wiki/inbox/*-analyst-1700000004-8-8.md 2>/dev/null | head -1)
check "Learned+Notes keeps Learned bullet" grep -q 'bin/harness:10' "$Q"
check "Learned+Notes keeps Notes bullet" grep -q 'bin/harness:20' "$Q"
check "Learned+Notes shared cap drops third" not grep -q 'bin/harness:30' "$Q"

# Notes bullets without evidence: dropped with a warning, nothing queued
setup
mkdir -p docs/wiki .harness/asks .harness/reports; printf '1700000005-6-6 1700000005\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Notes\n- no proof at all\n- also unproven\n' > .harness/reports/analyst.md
fin analyst; run report analyst
check "Notes without evidence: warns" grep -q 'dropped 2 Notes bullet' <<<"$OUT"
check "Notes without evidence: nothing queued" [ ! -d docs/wiki/inbox ]

# --- shared defaults: one source (lib/harness-defaults.sh), prose copies must not drift -------
setup
DEF=$(/bin/bash "$HARNESS" _defaults); dv() { printf '%s\n' "$DEF" | sed -n "s/^$1=//p"; }
check "_defaults lists the roles" [ "$(dv HARNESS_ROLES)" = "analyst implementer reviewer" ]
check "_defaults needs no herdr" [ -n "$DEF" ]
CDPATH=. /bin/bash "$HARNESS" _defaults >"$WORK/cdp.out" 2>&1; rc=$?
check "CDPATH=. harness _defaults exits 0" [ "$rc" = 0 ]
check "CDPATH=. harness _defaults prints no extra output" [ "$(cat "$WORK/cdp.out")" = "$DEF" ]
T_DEF=$(dv HARNESS_DEFAULT_TIMEOUT_MS); T_IMPL=$(dv HARNESS_IMPLEMENTER_TIMEOUT_MS)
for f in claude/agents/conductor.md claude/skills/implement/SKILL.md; do
  check "$f quotes the default timeouts" bash -c 'grep -q "$2" "$1" && grep -q "$3" "$1"' _ "$HERE/../$f" "$T_DEF" "$T_IMPL"
done
check "default ask timeouts equal the headless caps (ms)" bash -c '[ "$1" = $(($3 * 1000)) ] && [ "$2" = $(($4 * 1000)) ]' _ "$T_DEF" "$T_IMPL" "$(dv HARNESS_HL_MAX_S_DEFAULT)" "$(dv HARNESS_HL_MAX_S_IMPLEMENTER_DEFAULT)"
check "no stray 6-8 digit number in conductor.md/implement skill" bash -c '! grep -ohE "\b[0-9]{6,8}\b" "$1" "$2" | grep -vxE "$3|$4|7200000"' _ "$HERE/../claude/agents/conductor.md" "$HERE/../claude/skills/implement/SKILL.md" "$T_IMPL" "$T_DEF"
check "header comment quotes the default timeouts" bash -c 'sed -n 1,15p "$1" | grep -q "implementer $2" && sed -n 1,15p "$1" | grep -q "analyst/reviewer $3"' _ "$HARNESS" "$T_IMPL" "$T_DEF"
OUT=$(HERDR_ENV=1 PATH="$FAKE_BIN:$PATH" /bin/bash "$HARNESS" 2>&1)
check "usage text prints the default timeouts" bash -c 'grep -q "implementer $2" <<<"$1" && grep -q "others $3" <<<"$1"' _ "$OUT" "$T_IMPL" "$T_DEF"
TPL=$(sed -n "/^config_template() {/,/^EOC/p" "$HARNESS" | sed '1,2d;$d')
check "config template viewer = default" [ "$(printf '%s' "$TPL" | jq -r .viewer)" = "$(dv HARNESS_VIEWER_DEFAULT)" ]
check "config template has only _doc and viewer" [ "$(printf '%s' "$TPL" | jq -r 'keys | join(" ")')" = "_doc viewer" ]
check "metrics --json lists every role" bash -c 'cd "$1" && HERDR_ENV=1 "$2" metrics --json | jq -e ".current.roles | keys == [\"analyst\",\"implementer\",\"reviewer\"]" >/dev/null' _ "$WORK" "$HARNESS"

check "_defaults: headless cap implementer 90 min, others 60" bash -c '[ "$1" = 5400 ] && [ "$2" = 3600 ]' _ "$(dv HARNESS_HL_MAX_S_IMPLEMENTER_DEFAULT)" "$(dv HARNESS_HL_MAX_S_DEFAULT)"
check "README quotes the headless caps (60 / 90 min)" bash -c 'grep -q "headless_max_minutes" "$1" && grep -q "implementer 90" "$1"' _ "$HERE/../README.md"

# --- harness init / checkout marker (decision 0010) ---
setup; rm -rf .harness
run ask analyst "q"
check "ask without marker: exit 1" [ "$RC" = 1 ]
check "ask without marker: message" grep -q "not a harness checkout (no .harness/asks); run 'harness init' here first" <<<"$OUT"
check "ask without marker: no .harness created" [ ! -e .harness ]
run status
check "status without marker still works" [ "$RC" = 0 ]
check "status without marker creates nothing" [ ! -e .harness ]

setup; rm -rf .harness
run init
check "init: exit 0" [ "$RC" = 0 ]
check "init creates asks/" [ -d .harness/asks ]
check "init creates config.json" [ -s .harness/config.json ]
check "init writes settings.local.json agent conductor" [ "$(jq -r .agent .claude/settings.local.json)" = conductor ]
check "init (default) leaves the tracked settings.json alone" [ ! -e .claude/settings.json ]
check "init names the target file" grep -q "settings.local.json" <<<"$OUT"
run init
check "init is idempotent" bash -c '[ "$1" = 0 ] && [ "$(jq -r .agent .claude/settings.local.json)" = conductor ]' _ "$RC"
run init --bogus
check "init rejects unknown flag" [ "$RC" != 0 ]

setup; rm -rf .harness
run init
check "init: no herdr needed" grep -q "no herdr needed" <<<"$OUT"

setup; rm -rf .harness
run init --shared
check "init --shared: writes settings.json" [ "$(jq -r .agent .claude/settings.json)" = conductor ]
check "init --shared: no settings.local.json" [ ! -e .claude/settings.local.json ]

setup; rm -rf .harness; mkdir .claude; printf '{"model":"x","env":{"A":"1"}}\n' > .claude/settings.local.json
run init
check "init merges: agent set" [ "$(jq -r .agent .claude/settings.local.json)" = conductor ]
check "init merges: other keys kept" [ "$(jq -r '.model + .env.A' .claude/settings.local.json)" = x1 ]
check "init merge: .bak holds the original" [ "$(jq -c . .claude/settings.local.json.bak)" = '{"model":"x","env":{"A":"1"}}' ]
printf '{"model":"changed"}\n' > .claude/settings.local.json.bak
jq 'del(.agent)' .claude/settings.local.json > .claude/s.tmp && cat .claude/s.tmp > .claude/settings.local.json
run init
check "init: an existing .bak is never overwritten" [ "$(jq -r .model .claude/settings.local.json.bak)" = changed ]

setup; rm -rf .harness; mkdir .claude; printf '{"model":"x","env":{"A":"1"}}\n' > .claude/settings.json
run init --shared
check "init --shared merges into settings.json" [ "$(jq -r '.agent + .model' .claude/settings.json)" = conductorx ]

setup; rm -rf .harness .claude; mkdir real .claude; printf '{"model":"x"}\n' > real/s.json; ln -s ../real/s.json .claude/settings.local.json
run init
check "init: symlinked settings stays a symlink" [ -L .claude/settings.local.json ]
check "init: symlink target got the agent key" [ "$(jq -r '.agent + .model' real/s.json)" = conductorx ]

setup; rm -rf .harness; mkdir .claude; printf '{"agent":"solo","model":"x"}\n' > .claude/settings.local.json
run init
check "init keeps a different agent" [ "$(jq -r .agent .claude/settings.local.json)" = solo ]
check "init notes the kept agent" grep -q "kept" <<<"$OUT"
check "init keeps a different agent: no .bak needed" [ ! -e .claude/settings.local.json.bak ]

setup; rm -rf .harness
run init --no-agent
check "init --no-agent: no settings written" bash -c '[ ! -e .claude/settings.json ] && [ ! -e .claude/settings.local.json ]'
check "init --no-agent: asks created" [ -d .harness/asks ]

setup; rm -rf .harness; git init -q .; export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME=$WORK/xdg
run init --no-agent
check "init in git: .harness/ excluded" grep -qx '.harness/' .git/info/exclude
run init --no-agent
check "init in git: exclude not duplicated" [ "$(grep -cx '.harness/' .git/info/exclude)" = 1 ]
check "init in git: git status clean of .harness" bash -c '! git status --porcelain | grep -q harness'

setup; rm -rf .harness
run init --no-agent
run ask analyst "q"
check "after init, ask gets past the marker check" bash -c '! grep -q "not a harness checkout" <<<"$1"' _ "$OUT"
unset GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM XDG_CONFIG_HOME

# --- init from a subdir lands at the git toplevel (and from a git worktree) ---
setup; rm -rf .harness; git init -q .; mkdir -p deep/er
( cd deep/er && HERDR_ENV=1 env -u HARNESS_ROLE /bin/bash "$HARNESS" init --no-agent >/dev/null 2>&1 )
check "init from a subdir: .harness/asks at the toplevel" [ -d .harness/asks ]
check "init from a subdir: nothing created in the subdir" [ ! -e deep/er/.harness ]
git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -q --allow-empty -m s
git worktree add -q "$WORK/wt2" 2>/dev/null
mkdir -p "$WORK/wt2/sub"; ( cd "$WORK/wt2/sub" && env -u HARNESS_ROLE /bin/bash "$HARNESS" init --no-agent >/dev/null 2>&1 )
check "init from a worktree subdir: asks at the worktree root" [ -d "$WORK/wt2/.harness/asks" ]
OUT=$(cd "$WORK/wt2/sub" && env -u HARNESS_ROLE /bin/bash "$HARNESS" ask nosuchrole q 2>&1)
check "worktree subdir (.git is a file): ask passes the checkout check" bash -c '! grep -q "not a harness checkout" <<<"$1"' _ "$OUT"

# --- symlinked cwd: ask from L -> real/sub resolves the root physically ---
setup; rm -rf .harness; git init -q .; mkdir -p real/sub; ln -s "$WORK/real/sub" "$WORK/L"
env -u HARNESS_ROLE /bin/bash "$HARNESS" init --no-agent >/dev/null 2>&1
OUT=$(cd "$WORK/L" && env -u HARNESS_ROLE /bin/bash "$HARNESS" ask nosuchrole q 2>&1)
check "symlinked cwd: ask finds the checkout" bash -c '! grep -q "not a harness checkout" <<<"$1"' _ "$OUT"

# --- marker side effects: nothing creates .harness/ outside a checkout ---
setup; rm -rf .harness
run status
check "status outside a checkout: no .harness created" [ ! -e .harness ]
# a stray .harness/ (no asks/) in an un-init dir is never written to
setup; rm -rf .harness; mkdir -p .harness/log; echo x > .harness/log/a1.md
STRAY_BEFORE=$(find .harness | sort | tr '\n' ' ')
run status
check "status: stray .harness/ (no asks/) left unchanged" [ "$(find .harness | sort | tr '\n' ' ')" = "$STRAY_BEFORE" ]
echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
