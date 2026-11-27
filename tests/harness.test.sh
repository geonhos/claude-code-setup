#!/bin/bash
# bin/harness (headless runner only): preconditions, worker guard, report, defaults, init. Run: /bin/bash tests/harness.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"

# --- preconditions -----------------------------------------------------------
setup
OUT=$(env -u HARNESS_ROLE /bin/bash "$HARNESS" status 2>&1); RC=$?
check "status works" [ "$RC" -eq 0 ]
check "status lists the roles" grep -q "analyst" <<<"$OUT"

run
check "no args shows usage" [ "$RC" -eq 1 ]
check "usage text" grep -q "harness ask" <<<"$OUT"

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
  [ -n "${NOWIKI:-}" ] || : > docs/wiki/index.md
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

# title cut at 70 chars
L=$(printf 'x%.0s' $(seq 1 90))
notes_case "- $L see bin/harness:1\n"
check "notes: unbroken word cut at 70 chars + ellipsis" grep -q -- "--title $(printf 'x%.0s' $(seq 1 70))… --body" "$FAKE_GH_LOG"

# title cut at a word/clause boundary, never mid-word (English and Korean)
notes_case '- Hooks run in a fresh shell, so exported variables from the parent session are lost (bin/harness:9)\n'
check "notes: english title cut at word boundary" grep -q -- '--title Hooks run in a fresh shell… --body' "$FAKE_GH_LOG"
notes_case '- 워커 세션은 부모 셸의 환경 변수를 물려받지 않으므로 헤드리스 실행기에서 명시적으로 넘겨야 하고 그렇지 않으면 값이 사라진다 (bin/harness:9)\n'
check "notes: korean title ends with ellipsis" grep -q -- '--title .*… --body' "$FAKE_GH_LOG"
check "notes: korean title cut at a space" grep -q -- '--title 워커 세션은 부모 셸의 환경 변수를 물려받지 않으므로 헤드리스 실행기에서 명시적으로 넘겨야 하고 그렇지 않으면 값이 사라진다… --body' "$FAKE_GH_LOG"

# status-only bullets are dropped, lessons kept
notes_case '- Commit 34f73c6, 7 files, +79/-14, pushed; PR not opened.\n- seen in bin/harness:1\n'
check "notes status: only the lesson filed" [ "$(creates)" -eq 1 ]
check "notes status: status bullet not filed" not grep -q '34f73c6' "$FAKE_GH_LOG"
check "notes status: warns on dropped bullet" grep -q 'dropped 1 Notes bullet' <<<"$OUT"
notes_case '- Commit 34f73c6, 7 files, +79/-14, pushed; PR not opened.\n'
check "notes status only: gh not called" [ ! -s "$FAKE_GH_LOG" ]

# same title twice in one report -> one issue
notes_case '- seen in bin/harness:1\n- seen in bin/harness:1\n'
check "notes same title twice: one issue" [ "$(creates)" -eq 1 ]
check "notes same title twice: counts skip" grep -q '^wiki: 1 issue filed with label wiki (1 duplicate skipped)' <<<"$OUT"

# closed duplicate -> skipped; list asks for all states
setup; : > "$FAKE_GH_LOG"
mkdir -p .harness/reports .harness/asks docs/wiki; : > docs/wiki/index.md; printf '1700000000-1-1 1700000000\n' > .harness/asks/analyst.current
printf '# analyst report\nstatus: done\n## Notes\n- seen in bin/harness:1\n' > .harness/reports/analyst.md
fin analyst; FAKE_GH_CLOSED='seen in bin/harness:1' ghrun report analyst
check "notes closed dup: not filed" [ "$(creates)" -eq 0 ]
check "notes closed dup: list covers all states" grep -q '^issue list --label wiki --state all' "$FAKE_GH_LOG"

# duplicate: same title already open with label wiki
setup; : > "$FAKE_GH_LOG"
mkdir -p .harness/reports .harness/asks docs/wiki; : > docs/wiki/index.md; printf '1700000000-1-1 1700000000\n' > .harness/asks/analyst.current
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
# no docs/wiki/index.md: no gh call, one line, Notes stay in the archived report
NOWIKI=1 notes_case '- seen in bin/harness:1\n- also in bin/harness:2\n- vague claim\n'
check "notes no wiki: rc 0" [ "$RC" -eq 0 ]
check "notes no wiki: gh not called" [ ! -s "$FAKE_GH_LOG" ]
check "notes no wiki: prints the line" grep -qx 'wiki: no docs/wiki here; 2 Notes bullet(s) left in the report' <<<"$OUT"
check "notes no wiki: report still printed" grep -q '^# analyst report' <<<"$OUT"
# docs/wiki/index.md, gh failing: the warning names the count, rc unchanged
notes_case '- seen in bin/harness:1\n- also in bin/harness:2\n'; : > "$FAKE_GH_LOG"
fin analyst; FAKE_GH_FAIL=1 ghrun report analyst
check "notes wiki gh fail: warning names the count" grep -q 'harness: wiki: .*2 Notes bullet(s) not filed.*remain in the report' <<<"$OUT"
check "notes wiki gh fail: rc 0" [ "$RC" -eq 0 ]
# create fails after one success: K = n - made - skipped (4 bullets, 1 made, 1 duplicate -> 2 left); the loop stops
FAKE_GH_CREATE_OK=1 notes_case '- seen in bin/harness:1\n- seen in bin/harness:1\n- second in bin/harness:2\n- third in bin/harness:3\n'
check "notes create fails: warning counts the bullets left (2)" grep -q 'gh issue create failed; 2 Notes bullet(s) not filed' <<<"$OUT"
check "notes create fails: no create after the failed one (2 attempts)" [ "$(creates)" -eq 2 ]
check "notes create fails: rc 0" [ "$RC" -eq 0 ]
# docs/wiki/index.md, working gh: filed as before
notes_case '- seen in bin/harness:1\n- also in bin/harness:2\n'
check "notes wiki: two issues filed" [ "$(creates)" -eq 2 ]
check "notes wiki: no-wiki line absent" not grep -q 'no docs/wiki here' <<<"$OUT"

# gh missing: PATH holds only the tools harness needs, no gh
setup; mkdir -p nogh
for t in bash sh awk sed cut grep date git jq mkdir cat printf ls wc tr head tail sort rm find stat perl env dirname basename uname mktemp; do
  p=$(command -v "$t" 2>/dev/null) && [ -x "$p" ] && ln -sf "$p" "nogh/$t"
done
mkdir -p .harness/reports .harness/asks docs/wiki; : > docs/wiki/index.md; printf '1700000000-1-1 1700000000\n' > .harness/asks/analyst.current
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
mkdir -p .harness/reports .harness/asks docs/wiki; : > docs/wiki/index.md
printf '1700000001-1-2 1700000001\n' > .harness/asks/reviewer.current
printf '# reviewer report\nstatus: done\n## Notes\n- race seen in .harness/progress.jsonl\nVERDICT: PASS\n' > .harness/reports/reviewer.md
fin reviewer; ghrun report reviewer
check "notes before VERDICT: rc 0" [ "$RC" -eq 0 ]
check "notes reviewer filed" [ "$(creates)" -eq 1 ]
check "reviewer VERDICT still last line" [ "$(printf '%s\n' "$OUT" | tail -1)" = "VERDICT: PASS" ]

# continuation lines, evidence strictness, no ask-id
notes_case '- wrapped lesson that\n  cites tests/x.sh:42 on the next line\n'
check "notes continuation joined" grep -q 'that cites tests/x.sh:42' "$FAKE_GH_LOG"
for ok in 'see 1700000000-123-456' 'bin/harness:815' 'foo.sh:12' 'stale cache, commit 79a1964' 'stale cache, commit deadbee1' 'in .harness/progress.jsonl' 'see run.log'; do
  notes_case "- $ok\n"
  check "evidence accepted: $ok" [ "$(creates)" -eq 1 ]
done
for bad in 'step:2' 'host:8080' 'about 12345678 items' 'deadbeef word' 'abcdefabc' 'v1.2 notes'; do
  notes_case "- $bad\n"
  check "evidence rejected: $bad" [ "$(creates)" -eq 0 ]
done
notes_case '- x\n'; : > "$FAKE_GH_LOG"
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
OUT=$(/bin/bash "$HARNESS" 2>&1)
check "usage text prints the default timeouts" bash -c 'grep -q "implementer $2" <<<"$1" && grep -q "others $3" <<<"$1"' _ "$OUT" "$T_IMPL" "$T_DEF"
check "no config template left in bin/harness (#257)" bash -c '! grep -q "config_template\|ensure_config" "$1"' _ "$HARNESS"
check "metrics --json lists every role" bash -c 'cd "$1" && "$2" metrics --json | jq -e ".current.roles | keys == [\"analyst\",\"implementer\",\"reviewer\"]" >/dev/null' _ "$WORK" "$HARNESS"

check "_defaults: headless cap implementer 90 min, others 60" bash -c '[ "$1" = 5400 ] && [ "$2" = 3600 ]' _ "$(dv HARNESS_HL_MAX_S_IMPLEMENTER_DEFAULT)" "$(dv HARNESS_HL_MAX_S_DEFAULT)"
check "README quotes the headless caps (60 / 90 min)" bash -c 'grep -q "headless_max_minutes" "$1" && grep -q "implementer 90" "$1"' _ "$HERE/../README.md"

# --- harness init / checkout marker (decision 0010) ---
DENY_JSON='["Bash(git reset *--hard*)","Bash(git clean *)","Bash(git push *--force*)","Bash(git push -f*)","Bash(git push * -f*)","Read(.env)","Read(.env.*)","Read(~/.ssh/**)","Read(~/.aws/**)"]'
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
check "init creates no config.json (#257)" [ ! -e .harness/config.json ]
check "init output does not mention config.json" bash -c '! grep -q config.json <<<"$1"' _ "$OUT"
check "init writes settings.local.json agent conductor" [ "$(jq -r .agent .claude/settings.local.json)" = conductor ]
check "init (default) leaves the tracked settings.json alone" [ ! -e .claude/settings.json ]
check "init names the target file" grep -q "settings.local.json" <<<"$OUT"
run status
check "status creates no config.json (#257)" [ ! -e .harness/config.json ]
run init
check "init is idempotent" bash -c '[ "$1" = 0 ] && [ "$(jq -r .agent .claude/settings.local.json)" = conductor ]' _ "$RC"
run init --bogus
check "init rejects unknown flag" [ "$RC" != 0 ]

# #257: the test-only _mtime subcommand is gone: an unknown command prints usage
setup
run _mtime .
check "_mtime is an unknown command (usage, rc 1)" bash -c '[ "$1" = 1 ] && grep -q "^usage:" <<<"$2"' _ "$RC" "$OUT"

# worker deny rules (#165): the nine rules, written by every init into settings.local.json
eval "$(sed -n '/^digits_only() {/,/^}/p;/^file_mtime() {/,/^}/p' "$HARNESS")"
mtime() { file_mtime "$1"; }
setup; rm -rf .harness .claude
run init
check "init deny: settings.local.json has exactly the nine rules in order" [ "$(jq -c .permissions.deny .claude/settings.local.json)" = "$DENY_JSON" ]
check "init deny: output lists the added rules" grep -qF 'Bash(git clean *)' <<<"$OUT"
M1=$(mtime .claude/settings.local.json)
sleep 1.1
run init
check "init deny re-run: still nine rules" [ "$(jq '.permissions.deny | length' .claude/settings.local.json)" = 9 ]
check "init deny re-run: file not rewritten" [ "$(mtime .claude/settings.local.json)" = "$M1" ]
check "init deny re-run: says the rules are present" grep -q "deny rules present" <<<"$OUT"
check "init deny re-run: no .bak (nothing changed)" [ ! -e .claude/settings.local.json.bak ]

setup; rm -rf .harness; mkdir -p .claude; SEED='{"permissions":{"deny":["Bash(curl *)"],"allow":["Bash(ls *)"]}}'; printf '%s\n' "$SEED" > .claude/settings.local.json
run init
check "init deny merge: existing deny entry first, nine rules after" [ "$(jq -c .permissions.deny .claude/settings.local.json)" = "$(jq -c '["Bash(curl *)"] + .' <<<"$DENY_JSON")" ]
check "init deny merge: allow kept" [ "$(jq -c .permissions.allow .claude/settings.local.json)" = '["Bash(ls *)"]' ]
check "init deny merge: .bak equals the seed" [ "$(jq -c . .claude/settings.local.json.bak)" = "$(jq -c . <<<"$SEED")" ]
check "init deny merge: agent set too" [ "$(jq -r .agent .claude/settings.local.json)" = conductor ]

setup; rm -rf .harness; mkdir -p .claude; printf '{"agent":"conductor","permissions":{"deny":["Bash(git clean *)","Read(.env)"]}}\n' > .claude/settings.local.json
run init
check "init deny partial: only missing rules appended, no duplicates" [ "$(jq -c '.permissions.deny | length' .claude/settings.local.json)" = 9 ]
check "init deny partial: existing order kept" [ "$(jq -c '.permissions.deny[0:2]' .claude/settings.local.json)" = '["Bash(git clean *)","Read(.env)"]' ]

# an unmergeable settings file fails init before anything is created (#165, user decision 2026-11-19)
# odd_case LABEL CONTENT MSG — init exits non-zero, file byte-identical, no .bak, message names the file + MSG, nothing created
# nothing_created LABEL — init left no trace: no .harness/asks, no config.json, no ignore line in .git/info/exclude
nothing_created() {
  check "init odd ($1): nothing created" bash -c '[ ! -e .harness/asks ] && [ ! -e .harness/config.json ] && ! grep -qs . .git/info/exclude && [ ! -e AGENTS.md ]' _
}
odd_case() {
  setup; git init -q; rm -rf .harness AGENTS.md; mkdir -p .claude; printf "$2" > .claude/settings.local.json; cp .claude/settings.local.json "$WORK/before.json"
  run init
  check "init odd ($1): exits non-zero" [ "$RC" != 0 ]
  check "init odd ($1): file byte-identical" cmp -s "$WORK/before.json" .claude/settings.local.json
  check "init odd ($1): no .bak" [ ! -e .claude/settings.local.json.bak ]
  check "init odd ($1): message names the file and the problem" grep -qF -- ".claude/settings.local.json $3" <<<"$OUT"
  nothing_created "$1"
}
odd_case "invalid JSON" '{"a":' "is not valid JSON"
odd_case "empty" '' "is empty"
odd_case "whitespace only" ' \n\n' "is empty"
odd_case "top level array" '[1]\n' "has a top level that is not an object"
odd_case "permissions not object" '{"permissions":"x"}\n' "has a permissions that is not an object"
odd_case "deny not array" '{"permissions":{"deny":"nope"},"model":"x"}\n' "has a permissions.deny that is not an array"
check "init odd: deny message is not the permissions one" bash -c '! grep -qF "permissions that is not an object" <<<"$1"' _ "$OUT"
ERR=$(PATH="$HERE/../bin:$PATH" env -u HARNESS_ROLE /bin/bash "$HARNESS" init 2>&1 >/dev/null)
check "init odd: message on stderr" grep -q "permissions.deny" <<<"$ERR"
# a settings path that is a directory or an unreadable file: its own message, no raw error leaked, nothing changed
setup; git init -q; rm -rf .harness .claude AGENTS.md; mkdir -p .claude/settings.local.json
run init
check "init odd (directory): exits non-zero" [ "$RC" != 0 ]
check "init odd (directory): own message" grep -qF ".claude/settings.local.json is not a regular file" <<<"$OUT"
check "init odd (directory): not reported as empty or invalid JSON" bash -c '! grep -qE "empty|not valid JSON" <<<"$1"' _ "$OUT"
nothing_created "directory"
if [ "$(id -u)" = 0 ]; then echo "skip: init odd (unreadable file) — root reads mode 000 files"
else
  setup; git init -q; rm -rf .harness AGENTS.md; mkdir -p .claude; printf '{"a":1}\n' > .claude/settings.local.json; chmod 000 .claude/settings.local.json
  run init
  chmod 644 .claude/settings.local.json
  check "init odd (unreadable): exits non-zero" [ "$RC" != 0 ]
  check "init odd (unreadable): own message" grep -qF ".claude/settings.local.json is not readable" <<<"$OUT"
  check "init odd (unreadable): no raw error leaked, not called empty" bash -c '! grep -qiE "permission denied|empty|not valid JSON" <<<"$1"' _ "$OUT"
  chmod 000 .claude/settings.local.json
  nothing_created "unreadable"
  chmod 644 .claude/settings.local.json
fi
# null counts as absent: the deny rules are merged in, other keys kept
setup; rm -rf .harness; mkdir -p .claude; printf '{"permissions":null,"model":"x"}\n' > .claude/settings.local.json
run init
check "init null permissions: rc 0, nine rules merged, model kept" bash -c '[ "$1" = 0 ] && [ "$(jq -c .permissions.deny .claude/settings.local.json)" = "$2" ] && [ "$(jq -r .model .claude/settings.local.json)" = x ]' _ "$RC" "$DENY_JSON"
setup; rm -rf .harness; mkdir -p .claude; printf '{"permissions":{"deny":null,"allow":["Bash(ls *)"]}}\n' > .claude/settings.local.json
run init
check "init null deny: rc 0, nine rules merged, allow kept" bash -c '[ "$1" = 0 ] && [ "$(jq -c .permissions.deny .claude/settings.local.json)" = "$2" ] && [ "$(jq -c .permissions.allow .claude/settings.local.json)" = "[\"Bash(ls *)\"]" ]' _ "$RC" "$DENY_JSON"

setup; rm -rf .harness .claude; mkdir -p .claude; printf '[1]\n' > .claude/settings.json; cp .claude/settings.json "$WORK/before.json"
run init --shared
check "init --shared odd settings.json: exits non-zero" [ "$RC" != 0 ]
check "init --shared odd settings.json: names settings.json" grep -qF ".claude/settings.json has a top level" <<<"$OUT"
check "init --shared odd settings.json: file unchanged" cmp -s "$WORK/before.json" .claude/settings.json
check "init --shared odd settings.json: settings.local.json not created, nothing else" bash -c '[ ! -e .claude/settings.local.json ] && [ ! -e .harness ]'
setup; rm -rf .harness .claude; mkdir -p .claude; printf '{"a":1}\n' > .claude/settings.json; printf '{"permissions":[]}\n' > .claude/settings.local.json; cp .claude/settings.json "$WORK/b1"; cp .claude/settings.local.json "$WORK/b2"
run init --shared
check "init --shared odd local, good shared: fails, neither file changed" bash -c '[ "$1" != 0 ] && cmp -s "$2" .claude/settings.json && cmp -s "$3" .claude/settings.local.json && [ ! -e .harness ]' _ "$RC" "$WORK/b1" "$WORK/b2"
setup; rm -rf .harness .claude; mkdir -p .claude; printf '[1]\n' > .claude/settings.json
run init --shared --no-agent
check "init --shared --no-agent: odd settings.json is not touched, so init works" [ "$RC" = 0 ]
setup; rm -rf .harness .claude; mkdir -p .claude; printf '{"agent":"solo","permissions":{"deny":[]}}\n' > .claude/settings.local.json
run init
check "init: a different agent value is still not an error" [ "$RC" = 0 ]

# symlinked settings.local.json: rules added, symlink survives, .bak written once
setup; rm -rf .harness .claude; mkdir real .claude; printf '{"model":"x"}\n' > real/s.json; ln -s ../real/s.json .claude/settings.local.json
run init
check "init symlink: rules added through the link" [ "$(jq -c .permissions.deny real/s.json)" = "$DENY_JSON" ]
check "init symlink: still a symlink" [ -L .claude/settings.local.json ]
check "init symlink: .bak written" [ "$(jq -r .model .claude/settings.local.json.bak)" = x ]
jq 'del(.permissions.deny[0])' real/s.json > real/t && cat real/t > real/s.json
run init
check "init symlink: second change adds the rule again" [ "$(jq '.permissions.deny | length' real/s.json)" = 9 ]
check "init symlink: .bak not overwritten by the second change" [ "$(jq -c . .claude/settings.local.json.bak)" = '{"model":"x"}' ]

# harness ask warns (never refuses) when the checkout lacks the deny rules (#165, D5)
setup; export FAKE_CLAUDE_MODE=success; unset FAKE_CLAUDE_DENY; export FAKE_REPORT_CMD="$(REPORT_HOOK analyst)"
rm -f .claude/settings.local.json
hrun ask analyst "q"
check "ask warns: settings.local.json missing" grep -q "lacks the worker deny rules; run 'harness init' again" <<<"$OUT"
check "ask warns (missing): the ask still ran" [ -s "$FAKE_LOG" ]
setup; export FAKE_REPORT_CMD="$(REPORT_HOOK analyst)"
mkdir -p .claude; jq -n '{permissions:{deny:["Bash(git clean *)"]}}' > .claude/settings.local.json
hrun ask analyst "q"
check "ask warns: partial deny set" grep -q "lacks the worker deny rules" <<<"$OUT"
check "ask warns (partial): the ask still ran" [ -s "$FAKE_LOG" ]
setup; export FAKE_REPORT_CMD="$(REPORT_HOOK analyst)"
hrun ask analyst "q"
check "ask: no warning when the set is complete" not_grep "deny rules" <<<"$OUT"
check "ask (complete): the ask ran" [ -s "$FAKE_LOG" ]
# the warning names the checkout; under -C it is that checkout's own file that is checked
setup; export FAKE_CLAUDE_MODE=success; export FAKE_REPORT_CMD="$(REPORT_HOOK analyst)"
LANE="$WORK/lane1"; mkdir -p "$LANE/.harness/asks" "$LANE/.claude"
hrun -C "$LANE" ask analyst "q"
check "ask warns under -C: names the lane path" grep -qF "$(cd "$LANE" && pwd -P)" <<<"$(grep 'lacks the worker deny rules' <<<"$OUT")"
check "ask warns under -C: still says run harness init" grep -q "harness init" <<<"$OUT"
jq -n --argjson d "$DENY_JSON" '{permissions:{deny:$d}}' > "$LANE/.claude/settings.local.json"
hrun -C "$LANE" ask analyst "q"
check "ask under -C: lane file complete, no warning (the primary's file is not consulted)" not_grep "deny rules" <<<"$OUT"
# (the no-mirror guard for a nested non-worktree -C dir is tested inside git in tests/lane.test.sh, #252)
check "ask under -C: its own row is in the folder" [ "$(jq -s 'length' "$LANE/.harness/progress.jsonl")" -ge 1 ]
unset FAKE_CLAUDE_MODE FAKE_REPORT_CMD

# --- init writes the harness rules block into AGENTS.md (#243, decision 0016) ---
# Expected text is built from the template file and literal markers, not from init's code.
RB='<!-- harness:rules begin -->'; RE='<!-- harness:rules end -->'
RTPL="$HERE/../claude/templates/agents-rules.md"
rules_expected() { printf '%s\n' "$RB"; cat "$RTPL"; printf '%s\n' "$RE"; }
# irun ARGS... -> OUT (stdout), ERR (stderr), RC; no alarm needed, init is file work
irun() { OUT=$(PATH="$HERE/../bin:$PATH" env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>"$WORK/err"); RC=$?; ERR=$(cat "$WORK/err"); }
# rsetup — fresh git checkout with no harness state and no AGENTS.md
rsetup() { setup; git init -q; rm -rf .harness .claude AGENTS.md; }
excl_count() { grep -cxF AGENTS.md .git/info/exclude; }

rsetup
irun init
rules_expected > "$WORK/want"
check "rules 1: AGENTS.md is begin + template + end" cmp -s "$WORK/want" AGENTS.md
check "rules 1: rc 0" [ "$RC" = 0 ]
check "rules 1: AGENTS.md excluded once" [ "$(excl_count)" = 1 ]
check "rules 1: output says created and excluded" bash -c 'grep -qF "created AGENTS.md (harness rules)" <<<"$1" && grep -qF "added AGENTS.md to" <<<"$1"' _ "$OUT"
check "rules 1: git does not list AGENTS.md" [ -z "$(git status --porcelain AGENTS.md)" ]

M1=$(mtime AGENTS.md); sleep 1.1
irun init
check "rules 2: rerun leaves the file byte-identical" cmp -s "$WORK/want" AGENTS.md
check "rules 2: rerun does not rewrite (mtime)" [ "$(mtime AGENTS.md)" = "$M1" ]
check "rules 2: rerun says up to date" grep -qF "AGENTS.md: harness rules up to date" <<<"$OUT"
check "rules 2: exclude line still once" [ "$(excl_count)" = 1 ]

rsetup; printf '# Mine\ntext' > AGENTS.md
irun init
printf '# Mine\ntext\n\n' > "$WORK/want"; rules_expected >> "$WORK/want"
check "rules 3: no trailing newline: text kept, blank line, block" cmp -s "$WORK/want" AGENTS.md
check "rules 3: output says appended" grep -qF "AGENTS.md: appended the harness rules block" <<<"$OUT"
check "rules 3: a file init did not create is not excluded" [ "$(excl_count)" = 0 ]
rsetup; printf '# Mine\n\ntext\n\n' > AGENTS.md
irun init
printf '# Mine\n\ntext\n\n' > "$WORK/want"; rules_expected >> "$WORK/want"
check "rules 3: blank last line: no extra blank line" cmp -s "$WORK/want" AGENTS.md

rsetup; printf 'before\r\n  keep  \n%s\nSTALE\n%s\nafter no newline' "$RB" "$RE" > AGENTS.md
irun init
printf 'before\r\n  keep  \n' > "$WORK/want"; rules_expected >> "$WORK/want"; printf 'after no newline' >> "$WORK/want"
check "rules 4: stale block replaced, prefix and suffix byte-identical" cmp -s "$WORK/want" AGENTS.md
check "rules 4: output says updated" grep -qF "AGENTS.md: updated the harness rules block" <<<"$OUT"

for kind in "begin only" "end before begin" "two begins"; do
  rsetup
  case "$kind" in
    "begin only") printf 'a\n%s\nb\n' "$RB" ;;
    "end before begin") printf 'a\n%s\nb\n%s\nc\n' "$RE" "$RB" ;;
    "two begins") printf '%s\nx\n%s\ny\n%s\n' "$RB" "$RB" "$RE" ;;
  esac > AGENTS.md
  cp AGENTS.md "$WORK/before.md"
  irun init
  check "rules 5 ($kind): exits 1" [ "$RC" = 1 ]
  check "rules 5 ($kind): file byte-identical" cmp -s "$WORK/before.md" AGENTS.md
  check "rules 5 ($kind): nothing else created" bash -c '[ ! -e .harness/asks ] && [ ! -e .claude ]'
  check "rules 5 ($kind): stderr says what to do" grep -qF "AGENTS.md has a broken harness:rules block; fix or remove the markers, then run 'harness init' again" <<<"$ERR"
done

rsetup; printf '# Tracked\n' > AGENTS.md; git add AGENTS.md; git -c user.name=t -c user.email=t@t commit -q -m a
irun init
printf '# Tracked\n\n' > "$WORK/want"; rules_expected >> "$WORK/want"
check "rules 6: tracked file gets the block" cmp -s "$WORK/want" AGENTS.md
check "rules 6: prints the uncommitted note" grep -qF "note: AGENTS.md is tracked; the rules change is uncommitted" <<<"$OUT"
check "rules 6: tracked file is never excluded" [ "$(excl_count)" = 0 ]

for f in CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md; do
  rsetup; mkdir -p .claude; printf 'mine\n' > "$f"; cp "$f" "$WORK/before.md"
  irun init
  check "rules 7 ($f): AGENTS.md written" grep -qF "$RB" AGENTS.md
  check "rules 7 ($f): stderr names the file and @AGENTS.md" bash -c 'grep -qF "warning: $1 exists, so Claude Code does not read AGENTS.md here; add this line to $1: @AGENTS.md" <<<"$2"' _ "$f" "$ERR"
  check "rules 7 ($f): the file is not touched" cmp -s "$WORK/before.md" "$f"
  printf '@AGENTS.md\n' >> "$f"
  irun init
  check "rules 7 ($f): with an @AGENTS.md line there is no warning" not_grep "does not read AGENTS.md" <<<"$ERR"
done

WORK=$(mktemp -d); WORKS="$WORKS $WORK"; cd "$WORK" || exit 1
irun init
check "rules 8: no git: rc 0" [ "$RC" = 0 ]
check "rules 8: no git: AGENTS.md created in the cwd" cmp -s <(rules_expected) AGENTS.md
check "rules 8: no git: stderr empty" [ -z "$ERR" ]

rsetup
irun init --shared
check "rules 9: --shared creates the file" cmp -s <(rules_expected) AGENTS.md
check "rules 9: --shared does not exclude it" [ "$(excl_count)" = 0 ]
check "rules 9: --shared says commit it" grep -qF "created AGENTS.md (harness rules); commit it to share it" <<<"$OUT"

rsetup
irun init --no-agent
check "rules 10: --no-agent still creates it" cmp -s <(rules_expected) AGENTS.md

# 11: template missing (broken install): note on stderr, the rest of init runs
SCR=$(mktemp -d); WORKS="$WORKS $SCR"; cp -R "$HERE/../bin" "$HERE/../lib" "$SCR/"
rsetup
OUT=$(PATH="$SCR/bin:$PATH" env -u HARNESS_ROLE /bin/bash "$SCR/bin/harness" init 2>"$WORK/err"); RC=$?; ERR=$(cat "$WORK/err")
check "rules 11: template missing: rc 0" [ "$RC" = 0 ]
check "rules 11: template missing: note on stderr" grep -qF "note: harness rules template not found ($(cd "$SCR/lib" && pwd -P)/../claude/templates/agents-rules.md); AGENTS.md skipped" <<<"$ERR"
check "rules 11: template missing: no AGENTS.md, rest of init ran" bash -c '[ ! -e AGENTS.md ] && [ -d .harness/asks ]'

# 12 (#247): CRLF marker lines are recognised; the file stays CRLF outside the block; marker lines keep
# their CR, the template text between them is written with LF; a second init is a no-op
rsetup; printf 'a\r\nb\r\n<!-- harness:rules begin -->\r\nold\r\n<!-- harness:rules end -->\r\ntail\r\n' > AGENTS.md
irun init
{ printf 'a\r\nb\r\n<!-- harness:rules begin -->\r\n'; cat "$RTPL"; printf '<!-- harness:rules end -->\r\ntail\r\n'; } > "$WORK/want"
check "rules 12: CRLF block replaced, outside bytes and marker CRs kept" cmp -s "$WORK/want" AGENTS.md
check "rules 12: CRLF: says updated" grep -qF "AGENTS.md: updated the harness rules block" <<<"$OUT"
irun init
check "rules 12: CRLF rerun: up to date, file unchanged" bash -c 'grep -qF "AGENTS.md: harness rules up to date" <<<"$1" && cmp -s "$2" AGENTS.md' _ "$OUT" "$WORK/want"
check "rules 12: CRLF rerun: exactly one block" [ "$(grep -c 'harness:rules begin' AGENTS.md)" = 1 ]
rsetup; printf 'a\r\n<!-- harness:rules begin -->\r\n' > AGENTS.md; cp AGENTS.md "$WORK/before.md"
irun init
check "rules 12: CRLF begin without end: still a broken block" bash -c '[ "$1" = 1 ] && cmp -s "$2" AGENTS.md' _ "$RC" "$WORK/before.md"

# 13 (#247): a dangling AGENTS.md symlink is skipped like any non-regular file: nothing written through it
rsetup; ln -s nowhere.md AGENTS.md
irun init
check "rules 13: dangling symlink: rc 0, note, nothing created" bash -c '[ "$1" = 0 ] && grep -qF "note: AGENTS.md is not a regular file; rules block skipped" <<<"$2" && [ ! -e nowhere.md ] && [ -L AGENTS.md ] && ! grep -qxF AGENTS.md .git/info/exclude' _ "$RC" "$ERR"

# 14 (#247): a read-only AGENTS.md gives the note only, no raw bash error
rsetup; printf '# Mine\n' > AGENTS.md; chmod 444 AGENTS.md
irun init
check "rules 14: read-only: rc 0, one note line on stderr, no raw error" bash -c '[ "$1" = 0 ] && [ "$2" = "note: could not write AGENTS.md" ]' _ "$RC" "$ERR"
chmod 644 AGENTS.md


setup; rm -rf .harness
INIT_OUT=$(PATH="$HERE/../bin:$PATH" env -u HARNESS_ROLE /bin/bash "$HARNESS" init 2>"$WORK/init.err")
check "init: full watch hint" grep -qF "workers run as detached headless Claude sessions: watch a run with 'harness watch <role>'" <<<"$INIT_OUT"
check "init: stderr is empty" [ ! -s "$WORK/init.err" ]

setup; rm -rf .harness .claude
run init --shared
check "init --shared: writes settings.json" [ "$(jq -r .agent .claude/settings.json)" = conductor ]
check "init --shared: deny rules are not committed to settings.json" jq -e 'has("permissions") | not' .claude/settings.json
check "init --shared: deny rules go to settings.local.json" [ "$(jq -c .permissions.deny .claude/settings.local.json)" = "$DENY_JSON" ]
check "init --shared: settings.local.json has no agent key" jq -e 'has("agent") | not' .claude/settings.local.json

setup; rm -rf .harness; mkdir -p .claude; printf '{"model":"x","env":{"A":"1"}}\n' > .claude/settings.local.json
run init
check "init merges: agent set" [ "$(jq -r .agent .claude/settings.local.json)" = conductor ]
check "init merges: other keys kept" [ "$(jq -r '.model + .env.A' .claude/settings.local.json)" = x1 ]
check "init merge: .bak holds the original" [ "$(jq -c . .claude/settings.local.json.bak)" = '{"model":"x","env":{"A":"1"}}' ]
printf '{"model":"changed"}\n' > .claude/settings.local.json.bak
jq 'del(.agent)' .claude/settings.local.json > .claude/s.tmp && cat .claude/s.tmp > .claude/settings.local.json
run init
check "init: an existing .bak is never overwritten" [ "$(jq -r .model .claude/settings.local.json.bak)" = changed ]

setup; rm -rf .harness; mkdir -p .claude; printf '{"model":"x","env":{"A":"1"}}\n' > .claude/settings.json
run init --shared
check "init --shared merges into settings.json" [ "$(jq -r '.agent + .model' .claude/settings.json)" = conductorx ]

setup; rm -rf .harness .claude; mkdir real .claude; printf '{"model":"x"}\n' > real/s.json; ln -s ../real/s.json .claude/settings.local.json
run init
check "init: symlinked settings stays a symlink" [ -L .claude/settings.local.json ]
check "init: symlink target got the agent key" [ "$(jq -r '.agent + .model' real/s.json)" = conductorx ]

setup; rm -rf .harness; mkdir -p .claude; printf '{"agent":"solo","model":"x"}\n' > .claude/settings.local.json
run init
check "init keeps a different agent" [ "$(jq -r .agent .claude/settings.local.json)" = solo ]
check "init notes the kept agent" grep -q "kept" <<<"$OUT"
check "init keeps a different agent: deny rules still added" [ "$(jq -c .permissions.deny .claude/settings.local.json)" = "$DENY_JSON" ]
check "init keeps a different agent: .bak is the seed" [ "$(jq -c . .claude/settings.local.json.bak)" = '{"agent":"solo","model":"x"}' ]

setup; rm -rf .harness .claude
run init --no-agent
check "init --no-agent: no agent key anywhere, no settings.json" bash -c '[ ! -e .claude/settings.json ] && jq -e "has(\"agent\") | not" .claude/settings.local.json >/dev/null'
check "init --no-agent: deny rules still written" [ "$(jq -c .permissions.deny .claude/settings.local.json)" = "$DENY_JSON" ]
check "init --no-agent: asks created" [ -d .harness/asks ]

setup; rm -rf .harness; git init -q .; export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME=$WORK/xdg
run init --no-agent
check "init in git: .harness/ excluded" grep -qx '.harness/' .git/info/exclude
run init --no-agent
check "init in git: exclude not duplicated" [ "$(grep -cx '.harness/' .git/info/exclude)" = 1 ]
check "init in git: git status clean of .harness" bash -c '! git status --porcelain | grep -q harness'

# every harness-made path stays out of git (#63); the user's excludesFile is neutralised
touch_all() { mkdir -p .harness/asks .claude/agent-memory/implementer docs/superpowers/plans
  echo x > .claude/settings.local.json; echo x > .claude/settings.local.json.bak
  echo x > .claude/agent-memory/implementer/m.md; echo x > docs/superpowers/plans/p.md; }
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0=/dev/null
setup; rm -rf .harness .claude; git init -q .
run init --no-agent
touch_all
check "init in git: no harness-made path shows in git status" bash -c '! git status --porcelain -uall | grep -E "harness|settings.local|agent-memory|superpowers"'
run init --no-agent
check "init twice: no duplicate exclude lines" [ -z "$(grep -v '^#' .git/info/exclude | sort | uniq -d)" ]
check "init: all five patterns present" [ "$(grep -cE '^(\.harness/|\.claude/settings\.local\.json|\.claude/settings\.local\.json\.bak|\.claude/agent-memory/|docs/superpowers/)$' .git/info/exclude)" = 5 ]
setup; rm -rf .harness .claude; git init -q .
run init --shared
check "init --shared: settings.json not excluded" bash -c '! git check-ignore -q .claude/settings.json'
check "init --shared: settings.json visible to git" bash -c 'git status --porcelain -uall | grep -q "claude/settings.json"'
setup; rm -rf .harness .claude; git init -q .
git -C "$WORK" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -q --allow-empty -m s
git -C "$WORK" worktree add -q "$WORK/wt3" 2>/dev/null
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
git -C "$WORK" -c user.email=t@t -c user.name=t -c core.hooksPath=/dev/null commit -q --allow-empty -m s
git -C "$WORK" worktree add -q "$WORK/wt2" 2>/dev/null
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
# /watch skill: runs open-watch in both folder forms, never runs harness watch
W="$HERE/../claude/skills/watch/SKILL.md"
check "watch skill names the primary-folder form" grep -q 'harness open-watch <role>' "$W"
check "watch skill names the work-folder form" grep -q 'harness -C <absolute work-folder path> open-watch <role>' "$W"
check "watch skill never runs the command itself" grep -q 'Never runs .harness watch. itself\|never run' "$W"
check "watch skill points at harness lane ls" grep -q 'harness lane ls' "$W"
# guard: docs/superpowers is gitignored; no file under it may be tracked (#133)
if git -C "$HERE/.." rev-parse --git-dir >/dev/null 2>&1; then
  check "docs/superpowers has no tracked files" [ -z "$(git -C "$HERE/.." ls-files docs/superpowers)" ]
fi
echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
