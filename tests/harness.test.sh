#!/bin/bash
# bin/harness (headless runner only): preconditions, worker guard, report, defaults, init. Run: /bin/bash tests/harness.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"

# --- preconditions -----------------------------------------------------------
setup
OUT=$(env -u HARNESS_ROLE /bin/bash "$HARNESS" status 2>&1); RC=$?
check "status works" [ "$RC" -eq 0 ]
check "status lists the roles" grep -q "analyst" <<<"$OUT"
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
OUT=$(HARNESS_ROLE=worker $GUARD /bin/bash "$HARNESS" ask analyst x 2>&1); RC=$?
check "worker ask rc 1" [ "$RC" -eq 1 ]
check "worker ask message" grep -q conductor <<<"$OUT"
check "worker ask: no progress.jsonl" [ ! -e "$WORK/.harness/progress.jsonl" ]
OUT=$(HARNESS_ROLE=worker $GUARD /bin/bash "$HARNESS" status 2>&1); RC=$?
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

# --- report: ## Notes -> `wiki` GitHub issues -------------------------------------------
export FAKE_GH_LOG=$(mktemp); GH_LOGS="$FAKE_GH_LOG"
trap 'cd / && for d in $WORKS; do rm -rf "$d"; done; rm -f $GH_LOGS' EXIT
GH_PATH="$HERE/fake-gh:$PATH"
ghrun() { PATH="$GH_PATH" run "$@"; }
creates() { grep -c '^issue create --label wiki ' "$FAKE_GH_LOG"; }
# notes_case BODY — fresh checkout with a report whose Notes section is BODY, then `report analyst`
notes_case() {
  setup
  : > "$FAKE_GH_LOG"; unset FAKE_GH_OPEN FAKE_GH_FAIL
  mkdir -p .harness/reports .harness/asks docs/wiki
  printf '1700000000-123-456 1700000000\n' > .harness/asks/analyst.current
  printf '# analyst report\nstatus: done\n## Notes\n%b## Open questions\n- none\n' "$1" > .harness/reports/analyst.md
  fin analyst; ghrun report analyst
}
notes_case '- stat -f is GNU-hostile (bin/harness:815)\n- vague claim with no proof\n- fixed in commit 79a1964\n'
check "notes rc" [ "$RC" -eq 0 ]
check "notes: one issue per evidence bullet" [ "$(creates)" -eq 2 ]
check "notes: summary line" grep -q '^wiki: 2 issues filed with label wiki' <<<"$OUT"
check "notes: title is the bullet" grep -q -- '--title stat -f is GNU-hostile (bin/harness:815)' "$FAKE_GH_LOG"
check "notes: no-evidence bullet not filed" not grep -q 'vague claim' "$FAKE_GH_LOG"
check "notes: warns on dropped bullet" grep -q 'dropped 1 Notes bullet' <<<"$OUT"
check "notes: body has source line" grep -q 'Source: analyst ask 1700000000-123-456, ' "$FAKE_GH_LOG"
check "notes: nothing written under docs/wiki/inbox" [ ! -e docs/wiki/inbox ]

# title cut at 70 chars
L=$(printf 'x%.0s' $(seq 1 90))
notes_case "- $L see bin/harness:1\n"
check "notes: title cut to 70 chars" grep -q -- "--title $(printf 'x%.0s' $(seq 1 70)) --body" "$FAKE_GH_LOG"

# duplicate: same title already open with label wiki
setup; : > "$FAKE_GH_LOG"
mkdir -p .harness/reports .harness/asks docs/wiki; printf '1700000000-1-1 1700000000\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Notes\n- seen in bin/harness:1\n- other in bin/harness:2\n' > .harness/reports/analyst.md
fin analyst; FAKE_GH_OPEN='seen in bin/harness:1' ghrun report analyst
check "notes dup: only the new bullet filed" [ "$(creates)" -eq 1 ]
check "notes dup: list asked for wiki label" grep -q '^issue list --label wiki' "$FAKE_GH_LOG"
check "notes dup: summary counts skip" grep -q '^wiki: 1 issue filed with label wiki (1 duplicate skipped)' <<<"$OUT"

# gh failing: one warning, ask output and rc intact
notes_case '- seen in bin/harness:1\n'; : > "$FAKE_GH_LOG"
fin analyst; FAKE_GH_FAIL=1 ghrun report analyst
check "notes gh fail: rc 0" [ "$RC" -eq 0 ]
check "notes gh fail: warns once" [ "$(grep -c 'harness: wiki: gh' <<<"$OUT")" -eq 1 ]
check "notes gh fail: report still printed" grep -q '^# analyst report' <<<"$OUT"
# gh missing: PATH holds only the tools harness needs, no gh
setup; mkdir -p nogh
for t in bash sh awk sed cut grep date git jq mkdir cat printf ls wc tr head tail sort rm find stat perl env dirname basename uname mktemp; do
  p=$(command -v "$t" 2>/dev/null) && [ -x "$p" ] && ln -sf "$p" "nogh/$t"
done
mkdir -p .harness/reports .harness/asks docs/wiki; printf '1700000000-1-1 1700000000\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Notes\n- seen in bin/harness:1\n' > .harness/reports/analyst.md
fin analyst; OUT=$(PATH="$WORK/nogh" /bin/bash "$HARNESS" report analyst 2>&1); RC=$?
check "notes gh missing: rc 0" [ "$RC" -eq 0 ]
check "notes gh missing: warns" grep -q 'harness: wiki: gh not found' <<<"$OUT"

# no-evidence-only, none, no Notes: gh never called
notes_case '- none\n'
check "notes none: gh not called" [ ! -s "$FAKE_GH_LOG" ]
notes_case '- no proof here at all\n- also unproven\n'
check "notes without evidence: warns" grep -q 'dropped 2 Notes bullet' <<<"$OUT"
check "notes without evidence: gh not called" [ ! -s "$FAKE_GH_LOG" ]
notes_case ''
check "empty Notes: gh not called" [ ! -s "$FAKE_GH_LOG" ]

# reviewer: Notes before VERDICT
setup; : > "$FAKE_GH_LOG"
mkdir -p .harness/reports .harness/asks
printf '1700000001-1-2 1700000001\n' > .harness/asks/reviewer.current
printf '# reviewer report\nstatus: done\n## Notes\n- race seen in .harness/progress.jsonl\nVERDICT: PASS\n' > .harness/reports/reviewer.md
fin reviewer; ghrun report reviewer
check "notes before VERDICT: rc 0" [ "$RC" -eq 0 ]
check "notes reviewer filed" [ "$(creates)" -eq 1 ]
check "reviewer VERDICT still last line" [ "$(printf '%s\n' "$OUT" | tail -1)" = "VERDICT: PASS" ]

# continuation lines, evidence strictness, legacy ## Learned heading, no ask-id
notes_case '- wrapped lesson that\n  cites tests/x.sh:42 on the next line\n'
check "notes continuation joined" grep -q 'that cites tests/x.sh:42' "$FAKE_GH_LOG"
for ok in 'see 1700000000-123-456' 'bin/harness:815' 'foo.sh:12' 'commit 79a1964' 'commit deadbee1' 'in .harness/progress.jsonl' 'see run.log'; do
  notes_case "- $ok\n"
  check "evidence accepted: $ok" [ "$(creates)" -eq 1 ]
done
for bad in 'step:2' 'host:8080' 'about 12345678 items' 'deadbeef word' 'abcdefabc' 'v1.2 notes'; do
  notes_case "- $bad\n"
  check "evidence rejected: $bad" [ "$(creates)" -eq 0 ]
done
notes_case '- x\n'; : > "$FAKE_GH_LOG"
printf '# analyst report\nstatus: done\n## Learned\n- legacy in bin/harness:1\n' > .harness/reports/analyst.md
fin analyst; ghrun report analyst
check "legacy Learned heading filed" [ "$(creates)" -eq 1 ]
notes_case '- see bin/harness:1\n'; : > "$FAKE_GH_LOG"
rm -f .harness/asks/analyst.current
fin analyst; ghrun report analyst
check "notes no ask-id: gh not called" [ ! -s "$FAKE_GH_LOG" ]
check "notes no ask-id: warns" grep -q 'no ask-id' <<<"$OUT"

# --- shared defaults: one source (lib/harness-defaults.sh), prose copies must not drift -------
setup
DEF=$(/bin/bash "$HARNESS" _defaults); dv() { printf '%s\n' "$DEF" | sed -n "s/^$1=//p"; }
check "_defaults lists the roles" [ "$(dv HARNESS_ROLES)" = "analyst implementer reviewer" ]
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
OUT=$(/bin/bash "$HARNESS" 2>&1)
check "usage text prints the default timeouts" bash -c 'grep -q "implementer $2" <<<"$1" && grep -q "others $3" <<<"$1"' _ "$OUT" "$T_IMPL" "$T_DEF"
TPL=$(sed -n "/^config_template() {/,/^EOC/p" "$HARNESS" | sed '1,2d;$d')
check "config template has only _doc" [ "$(printf '%s' "$TPL" | jq -r 'keys | join(" ")')" = "_doc" ]
check "metrics --json lists every role" bash -c 'cd "$1" && "$2" metrics --json | jq -e ".current.roles | keys == [\"analyst\",\"implementer\",\"reviewer\"]" >/dev/null' _ "$WORK" "$HARNESS"

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
INIT_OUT=$(PATH="$HERE/../bin:$PATH" env -u HARNESS_ROLE /bin/bash "$HARNESS" init 2>"$WORK/init.err")
check "init: full watch hint" grep -qF "workers run as detached headless Claude sessions: watch a run with 'harness watch <role>'" <<<"$INIT_OUT"
check "init: stderr is empty" [ ! -s "$WORK/init.err" ]

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

# every harness-made path stays out of git (#63); the user's excludesFile is neutralised
touch_all() { mkdir -p .harness/asks .claude/agent-memory/implementer docs/wiki/inbox docs/superpowers/plans
  echo x > .claude/settings.local.json; echo x > .claude/settings.local.json.bak
  echo x > .claude/agent-memory/implementer/m.md; echo x > docs/wiki/inbox/l.md; echo x > docs/superpowers/plans/p.md; }
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0=/dev/null
setup; rm -rf .harness .claude; git init -q .
run init --no-agent
touch_all
check "init in git: no harness-made path shows in git status" bash -c '! git status --porcelain -uall | grep -E "harness|settings.local|agent-memory|inbox|superpowers"'
run init --no-agent
check "init twice: no duplicate exclude lines" [ -z "$(grep -v '^#' .git/info/exclude | sort | uniq -d)" ]
check "init: all six patterns present" [ "$(grep -cE '^(\.harness/|\.claude/settings\.local\.json|\.claude/settings\.local\.json\.bak|\.claude/agent-memory/|docs/wiki/inbox/|docs/superpowers/)$' .git/info/exclude)" = 6 ]
setup; rm -rf .harness .claude; git init -q .
run init --shared
check "init --shared: settings.json not excluded" bash -c '! git check-ignore -q .claude/settings.json'
check "init --shared: settings.json visible to git" bash -c 'git status --porcelain -uall | grep -q "claude/settings.json"'
setup; rm -rf .harness .claude; git init -q .
git -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -q --allow-empty -m s
git worktree add -q "$WORK/wt3" 2>/dev/null
( cd "$WORK/wt3" && env -u HARNESS_ROLE /bin/bash "$HARNESS" init --no-agent >/dev/null 2>&1 )
( cd "$WORK/wt3" && mkdir -p docs/superpowers && echo x > docs/superpowers/p.md && echo x > .harness/a )
check "worktree init: patterns excluded, worktree status clean" bash -c '! (cd "$1" && git status --porcelain -uall | grep -E "harness|superpowers")' _ "$WORK/wt3"
unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

setup; rm -rf .harness
run init --no-agent
run ask analyst "q"
check "after init, ask gets past the marker check" bash -c '! grep -q "not a harness checkout" <<<"$1"' _ "$OUT"
unset GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM XDG_CONFIG_HOME

# --- init from a subdir lands at the git toplevel (and from a git worktree) ---
setup; rm -rf .harness; git init -q .; mkdir -p deep/er
( cd deep/er && env -u HARNESS_ROLE /bin/bash "$HARNESS" init --no-agent >/dev/null 2>&1 )
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
# /watch skill: prints both command forms, never runs harness watch
W="$HERE/../claude/skills/watch/SKILL.md"
check "watch skill names the primary-folder form" grep -q 'harness watch <role>' "$W"
check "watch skill names the work-folder form" grep -q 'harness -C <absolute work-folder path> watch <role>' "$W"
check "watch skill never runs the command itself" grep -q 'never run it' "$W"
check "watch skill points at harness lane ls" grep -q 'harness lane ls' "$W"
echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
