#!/bin/bash
# Tests for install.sh --uninstall (#291). Run: /bin/bash tests/uninstall.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
# wiki tests-inherit-worker-env: a worker's env must not leak into the cases; the live-run guard is
# off (HARNESS_UNINSTALL_PS=/dev/null) in every case but the guard case, because the Stop hook runs
# this suite with a real harness-run alive
unset HARNESS_ROLE
OUT=""
REPO=$(cd "$HERE/.." && pwd)
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
newdir() { mkdir -p "$ROOT/$1" && echo "$ROOT/$1"; }

# inst_from SRC DIR: install SRC's install.sh into the sandbox DIR
inst_from() { CLAUDE_DIR="$2/claude" BIN_DIR="$2/bin" /bin/bash "$1/install.sh" >"$2/inst.txt" 2>&1 || { cat "$2/inst.txt"; return 1; }; }
# uninst_from SRC DIR [args]: sets RC; output in DIR/out.txt (stdout and stderr)
uninst_from() {
  local src=$1 d=$2; shift 2
  CLAUDE_DIR="$d/claude" BIN_DIR="$d/bin" HARNESS_UNINSTALL_PS=${PS_FILE:-/dev/null} /bin/bash "$src/install.sh" --uninstall "$@" >"$d/out.txt" 2>&1
  RC=$?
}
tree_sum() { (cd "$1" && find . -print | LC_ALL=C sort | while read -r f; do printf '%s %s\n' "$f" "$(readlink "$f" 2>/dev/null || { [ -f "$f" ] && shasum < "$f"; })"; done | shasum); }
# links_into DIR PREFIX: symlinks under DIR/claude and DIR/bin whose target begins with PREFIX/
links_into() { find "$1/claude" "$1/bin" -type l 2>/dev/null | while read -r l; do case "$(readlink "$l")" in "$2"/*) echo "$l" ;; esac; done | wc -l | tr -d ' '; }
# the pre-existing settings of install.test.sh, plus a user skill dir and /opt hooks
seed() {
  mkdir -p "$1/claude/skills/mine"; echo mine > "$1/claude/skills/mine/SKILL.md"
  cat > "$1/claude/settings.json" <<'EOF'
{
  "model": "fable",
  "agent": "something",
  "env": { "FOO": "bar" },
  "permissions": { "defaultMode": "auto" },
  "hooks": {
    "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "/opt/other-hook.sh" } ] } ],
    "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "/opt/stop.sh" } ] } ],
    "SessionStart": [ { "matcher": "startup", "hooks": [ { "type": "command", "command": "/opt/session.sh" } ] } ],
    "Notification": [ { "hooks": [ { "type": "command", "command": "/opt/notify.sh" } ] } ]
  }
}
EOF
}
GATE="$REPO/claude/hooks/conductor-gate.sh"; RESUME="$REPO/claude/hooks/conductor-resume.sh"; NOTIFY="$REPO/claude/hooks/notify-decision.sh"

# --- 1. install -> uninstall ---------------------------------------------------------------------
T=$(newdir t1); seed "$T"; ORIG=$(jq -S . "$T/claude/settings.json")
inst_from "$REPO" "$T"
check "1 installed 14 links into the repo" [ "$(links_into "$T" "$REPO")" -eq 14 ]
uninst_from "$REPO" "$T"
S="$T/claude/settings.json"
check "1 rc 0" [ "$RC" -eq 0 ]
check "1 no link into the repo left" [ "$(links_into "$T" "$REPO")" -eq 0 ]
check "1 output has 14 remove link lines" [ "$(grep -c '^remove link ' "$T/out.txt")" -eq 14 ]
check "1 three hooks gone" [ "$(jq --arg a "$GATE" --arg b "$RESUME" --arg c "$NOTIFY" '[.. | .command? | strings | select(. == $a or . == $b or . == $c)] | length' "$S")" -eq 0 ]
check "1 six keys gone" jq -e '(has("promptCacheTtl") or has("subagentPromptCacheTtl") or (.env | has("BASH_DEFAULT_TIMEOUT_MS")) or (.env | has("BASH_MAX_TIMEOUT_MS"))) | not' "$S" >/dev/null
check "1 attribution gone" jq -e 'has("attribution") | not' "$S" >/dev/null
check "1 settings equal to the pre-install file" [ "$(jq -S . "$S")" = "$ORIG" ]
check "1 user skill dir kept" [ -f "$T/claude/skills/mine/SKILL.md" ]
check "1 /opt hooks kept" [ "$(jq '[.. | .command? | strings | select(startswith("/opt/"))] | length' "$S")" -eq 4 ]
check "1 settings backup made" ls "$T"/claude/settings.json.bak.* >/dev/null 2>&1
check "1 prints the backup count" grep -q 'left in place: .* backup file' "$T/out.txt"
check "1 prints the quit-sessions line" grep -q '^quit running conductor sessions' "$T/out.txt"
check "1 prints the harness init hint" grep -q "harness init' state" "$T/out.txt"

# --- 2. second run: nothing to remove ------------------------------------------------------------
rm -f "$T/out.txt"; BAKS=$(ls "$T/claude" | sort | tr '\n' ' '); SUM=$(tree_sum "$T"); touch -t 202001010000 "$S"
uninst_from "$REPO" "$T"
check "2 second run rc 0" [ "$RC" -eq 0 ]
check "2 says nothing to remove" grep -qx 'nothing to remove' "$T/out.txt"
check "2 no new file" [ "$(ls "$T/claude" | sort | tr '\n' ' ')" = "$BAKS" ]
check "2 settings mtime unchanged" [ -z "$(find "$S" -newermt 2021-01-01)" ]
rm -f "$T/out.txt"
check "2 tree unchanged" [ "$(tree_sum "$T")" = "$SUM" ]

# --- 3. --dry-run --------------------------------------------------------------------------------
T=$(newdir t3); seed "$T"; inst_from "$REPO" "$T"
SUM=$(tree_sum "$T")
uninst_from "$REPO" "$T" --dry-run
check "3 dry-run rc 0" [ "$RC" -eq 0 ]
check "3 lists 14 links" [ "$(grep -c '^remove link ' "$T/out.txt")" -eq 14 ]
check "3 lists 3 hooks" [ "$(grep -c '^remove hook ' "$T/out.txt")" -eq 3 ]
check "3 lists 6 keys" [ "$(grep -c '^remove key ' "$T/out.txt")" -eq 6 ]
rm -f "$T/out.txt"
check "3 tree checksum equal before and after" [ "$(tree_sum "$T")" = "$SUM" ]

# --- 4. moved checkout ---------------------------------------------------------------------------
T=$(newdir t4); seed "$T"; OLD="$T/old"; mkdir -p "$OLD"
(cd "$REPO" && tar --exclude=./.git --exclude=./.harness -cf - .) | (cd "$OLD" && tar -xf -)
inst_from "$OLD" "$T"; rm -rf "$OLD"
check "4 premise: 14 dangling links" [ "$(find "$T/claude" "$T/bin" -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')" -eq 14 ]
uninst_from "$REPO" "$T"
check "4 rc 0" [ "$RC" -eq 0 ]
check "4 stale links removed" [ "$(find "$T/claude" "$T/bin" -type l | wc -l | tr -d ' ')" -eq 0 ]
check "4 stale hooks removed" [ "$(jq '[.. | .command? | strings | select(contains("/claude/hooks/"))] | length' "$T/claude/settings.json")" -eq 0 ]
check "4 /opt hooks kept" [ "$(jq '[.. | .command? | strings | select(startswith("/opt/"))] | length' "$T/claude/settings.json")" -eq 4 ]

# --- 5. live foreign checkout --------------------------------------------------------------------
T=$(newdir t5); seed "$T"; OTH="$T/other"; mkdir -p "$OTH"
(cd "$REPO" && tar --exclude=./.git --exclude=./.harness -cf - .) | (cd "$OTH" && tar -xf -)
inst_from "$OTH" "$T"
uninst_from "$REPO" "$T"
check "5 rc 0" [ "$RC" -eq 0 ]
check "5 its 14 links kept" [ "$(links_into "$T" "$OTH")" -eq 14 ]
check "5 its 3 hooks kept" [ "$(jq --arg o "$OTH" '[.. | .command? | strings | select(startswith($o + "/claude/hooks/"))] | length' "$T/claude/settings.json")" -eq 3 ]
check "5 warns about the other checkout" grep -q "installed from $OTH; run its install.sh --uninstall" "$T/out.txt"
check "5 warns about its hooks" grep -q "hook $OTH/claude/hooks/conductor-gate.sh belongs to another checkout" "$T/out.txt"

# --- 6. lookalikes of the user ---------------------------------------------------------------------
T=$(newdir t6); mkdir -p "$T/claude/agents" "$T/bin" "$T/x/claude/hooks"
printf '#!/bin/sh\n' > "$T/x/claude/hooks/conductor-gate.sh"
printf 'mine' > "$T/claude/agents/analyst.md"
ln -s /x/claude/agents/mine.md "$T/claude/agents/mine.md"
jq -n --arg live "$T/x/claude/hooks/conductor-gate.sh" '{hooks:{
  PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"/gone/claude/hooks/notify-decision.sh --flag"},
                                    {type:"command",command:"bash /x/claude/hooks/conductor-gate.sh"},
                                    {type:"command",command:$live}]}],
  Notification:[{hooks:[{type:"command",command:"/gone/claude/hooks/notify-decision.sh extra"}]}]}}' > "$T/claude/settings.json"
BEFORE=$(jq -S . "$T/claude/settings.json")
uninst_from "$REPO" "$T"
check "6 rc 0" [ "$RC" -eq 0 ]
check "6 regular file agents/analyst.md kept" [ "$(cat "$T/claude/agents/analyst.md")" = mine ]
check "6b dangling link to a name not in this checkout kept" [ "$(readlink "$T/claude/agents/mine.md")" = /x/claude/agents/mine.md ]
check "6 hook with args kept" jq -e '[.. | .command? | strings | select(. == "/gone/claude/hooks/notify-decision.sh extra")] | length == 1' "$T/claude/settings.json" >/dev/null
check "6 hook with a flag kept" jq -e '[.. | .command? | strings | select(. == "/gone/claude/hooks/notify-decision.sh --flag")] | length == 1' "$T/claude/settings.json" >/dev/null
check "6 bash-prefixed hook kept" jq -e '[.. | .command? | strings | select(. == "bash /x/claude/hooks/conductor-gate.sh")] | length == 1' "$T/claude/settings.json" >/dev/null
check "6 existing foreign gate path kept" jq -e --arg l "$T/x/claude/hooks/conductor-gate.sh" '[.. | .command? | strings | select(. == $l)] | length == 1' "$T/claude/settings.json" >/dev/null
check "6 settings unchanged" [ "$(jq -S . "$T/claude/settings.json")" = "$BEFORE" ]
check "6 no settings backup (file did not change)" [ -z "$(ls "$T"/claude/settings.json.bak.* 2>/dev/null)" ]
# a stale bare path IS removed (this is what the existence test decides; mutant target)
jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"/gone/claude/hooks/conductor-gate.sh"}]}]}}' > "$T/claude/settings.json"
uninst_from "$REPO" "$T"
check "6 stale bare gate path removed" jq -e '[.. | .command? | strings] | length == 0' "$T/claude/settings.json" >/dev/null
check "6 emptied PreToolUse array dropped" jq -e '.hooks | has("PreToolUse") | not' "$T/claude/settings.json" >/dev/null

# --- 7. different values kept --------------------------------------------------------------------
T=$(newdir t7); mkdir -p "$T/claude"
echo '{"promptCacheTtl":"5m","subagentPromptCacheTtl":"1h","env":{"FOO":"bar","BASH_DEFAULT_TIMEOUT_MS":"1","BASH_MAX_TIMEOUT_MS":"7200000"}}' > "$T/claude/settings.json"
uninst_from "$REPO" "$T"
S="$T/claude/settings.json"
check "7 rc 0" [ "$RC" -eq 0 ]
check "7 promptCacheTtl 5m kept" [ "$(jq -r .promptCacheTtl "$S")" = 5m ]
check "7 equal subagentPromptCacheTtl removed" jq -e 'has("subagentPromptCacheTtl") | not' "$S" >/dev/null
check "7 differing BASH_DEFAULT_TIMEOUT_MS kept" [ "$(jq -r .env.BASH_DEFAULT_TIMEOUT_MS "$S")" = 1 ]
check "7 equal BASH_MAX_TIMEOUT_MS removed" jq -e '.env | has("BASH_MAX_TIMEOUT_MS") | not' "$S" >/dev/null
check "7 non-empty env kept with FOO" [ "$(jq -r .env.FOO "$S")" = bar ]
check "7 reports the kept keys" grep -q '^keep key promptCacheTtl' "$T/out.txt"
# attribution: custom value kept, install value removed, empty object dropped
echo '{"attribution":{"commit":"Co-Authored-By: me","pr":""},"model":"m"}' > "$S"
uninst_from "$REPO" "$T"
check "7 custom attribution.commit kept" [ "$(jq -r .attribution.commit "$S")" = "Co-Authored-By: me" ]
check "7 empty attribution.pr removed" jq -e '.attribution | has("pr") | not' "$S" >/dev/null
check "7 reports kept attribution.commit" grep -q '^keep key attribution.commit' "$T/out.txt"
echo '{"attribution":{"commit":"","pr":""},"model":"m"}' > "$S"
uninst_from "$REPO" "$T"
check "7 empty attribution object dropped" jq -e 'has("attribution") | not' "$S" >/dev/null
# env left {} is dropped
echo '{"env":{"BASH_DEFAULT_TIMEOUT_MS":"600000","BASH_MAX_TIMEOUT_MS":"7200000"},"model":"m"}' > "$S"
uninst_from "$REPO" "$T"
check "7 empty env dropped" jq -e 'has("env") | not' "$S" >/dev/null
check "7 model kept" [ "$(jq -r .model "$S")" = m ]

# --- 8. co-located hook item ---------------------------------------------------------------------
T=$(newdir t8); mkdir -p "$T/claude"
jq -n --arg g "$GATE" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$g},{type:"command",command:"/opt/keep.sh"}]}]}}' > "$T/claude/settings.json"
uninst_from "$REPO" "$T"
check "8 entry keeps the other command" [ "$(jq -c '.hooks.PreToolUse' "$T/claude/settings.json")" = '[{"matcher":"Bash","hooks":[{"type":"command","command":"/opt/keep.sh"}]}]' ]

# --- 9. no settings.json / no .hooks / invalid JSON --------------------------------------------------
T=$(newdir t9a); mkdir -p "$T/claude/agents"; ln -s "$REPO/claude/agents/analyst.md" "$T/claude/agents/analyst.md"
uninst_from "$REPO" "$T"
check "9 no settings.json: rc 0" [ "$RC" -eq 0 ]
check "9 no settings.json: link removed" [ ! -L "$T/claude/agents/analyst.md" ]
check "9 no settings.json: none created" [ ! -e "$T/claude/settings.json" ]
T=$(newdir t9b); mkdir -p "$T/claude"; echo '{"promptCacheTtl":"1h"}' > "$T/claude/settings.json"
uninst_from "$REPO" "$T"
check "9 no .hooks: rc 0" [ "$RC" -eq 0 ]
check "9 no .hooks: key removed" [ "$(jq -c . "$T/claude/settings.json")" = '{}' ]
T=$(newdir t9c); mkdir -p "$T/claude/agents" "$T/bin"; ln -s "$REPO/claude/agents/analyst.md" "$T/claude/agents/analyst.md"; printf '{not json' > "$T/claude/settings.json"
uninst_from "$REPO" "$T"
check "9 invalid JSON: rc 1" [ "$RC" -eq 1 ]
check "9 invalid JSON: message" grep -q 'not valid JSON' "$T/out.txt"
check "9 invalid JSON: link untouched" [ -L "$T/claude/agents/analyst.md" ]
check "9 invalid JSON: file untouched" [ "$(cat "$T/claude/settings.json")" = '{not json' ]
check "9 invalid JSON: no backup" [ -z "$(ls "$T"/claude/settings.json.bak.* 2>/dev/null)" ]
# uninstall creates no directory: an empty sandbox stays empty
T=$(newdir t9d)
CLAUDE_DIR="$T/c" BIN_DIR="$T/b" HARNESS_UNINSTALL_PS=/dev/null /bin/bash "$REPO/install.sh" --uninstall >"$T/out.txt" 2>&1; RC=$?
check "9 empty sandbox: rc 0" [ "$RC" -eq 0 ]
check "9 empty sandbox: nothing to remove" grep -qx 'nothing to remove' "$T/out.txt"
check "9 empty sandbox: no CLAUDE_DIR created" [ ! -e "$T/c" ]
check "9 empty sandbox: no BIN_DIR created" [ ! -e "$T/b" ]

# --- 10. live-run guard ----------------------------------------------------------------------------
T=$(newdir t10); seed "$T"; inst_from "$REPO" "$T"
printf '  101 /bin/bash %s/bin/harness-run analyst\n  102 grep -c harness-run notes\n' "$REPO" > "$T/ps.txt"
SUM=$(tree_sum "$T")
PS_FILE="$T/ps.txt" uninst_from "$REPO" "$T"
check "10 live run: rc 1" [ "$RC" -eq 1 ]
check "10 live run: message" grep -q 'harness-run process is alive' "$T/out.txt"
rm -f "$T/out.txt"
check "10 live run: nothing changed" [ "$(tree_sum "$T")" = "$SUM" ]
printf '  102 grep -c harness-run notes\n  103 /bin/bash /x/bin/harness-view\n' > "$T/ps2.txt"
T2=$(newdir t10b); seed "$T2"; inst_from "$REPO" "$T2"
PS_FILE="$T/ps2.txt" uninst_from "$REPO" "$T2"
check "10 harness-run only inside an argument or another tool does not block" [ "$RC" -eq 0 ]
check "10 ... and the uninstall ran" [ "$(links_into "$T2" "$REPO")" -eq 0 ]
PS_FILE="$T/ps.txt" uninst_from "$REPO" "$T" --force
check "10 --force rc 0" [ "$RC" -eq 0 ]
check "10 --force removed the links" [ "$(links_into "$T" "$REPO")" -eq 0 ]

# unreadable HARNESS_UNINSTALL_PS must not turn the guard off silently
T=$(newdir t10c); seed "$T"; inst_from "$REPO" "$T"; SUM=$(tree_sum "$T")
PS_FILE="$T/missing-ps.txt" uninst_from "$REPO" "$T"
check "10 missing ps file: rc 1" [ "$RC" -eq 1 ]
check "10 missing ps file: message" grep -q 'HARNESS_UNINSTALL_PS=.* is not a readable file' "$T/out.txt"
rm -f "$T/out.txt"
check "10 missing ps file: nothing changed" [ "$(tree_sum "$T")" = "$SUM" ]
uninst_from "$REPO" "$T"   # /dev/null still works
check "10 /dev/null ps file works" [ "$RC" -eq 0 ]

# --- 12. unusual checkout paths (Major 1): own hooks are matched before any character filter ----------
# copy_to SRC DEST: copy the tree without .git/.harness
copy_to() { mkdir -p "$2"; (cd "$1" && tar --exclude=./.git --exclude=./.harness -cf - .) | (cd "$2" && tar -xf -); }
# hook_count FILE: hooks of any checkout in settings
hook_count() { jq '[.. | .command? | strings | select(contains("/claude/hooks/"))] | length' "$1"; }
for variant in "ko:작업/ccs" "sp:sp ace/ccs" "gl:gl[a]b*/ccs"; do
  tag=${variant%%:*}; sub=${variant#*:}
  T=$(newdir t12$tag); seed "$T"; copy_to "$REPO" "$T/$sub"
  inst_from "$T/$sub" "$T"
  check "12$tag premise: 14 links installed" [ "$(links_into "$T" "$T/$sub")" -eq 14 ]
  check "12$tag premise: 3 hooks installed next to the 4 user hooks" [ "$(hook_count "$T/claude/settings.json")" -eq 3 ]
  uninst_from "$T/$sub" "$T"
  check "12$tag rc 0" [ "$RC" -eq 0 ]
  check "12$tag 14 remove link lines" [ "$(grep -c '^remove link ' "$T/out.txt")" -eq 14 ]
  check "12$tag no link left" [ "$(links_into "$T" "$T/$sub")" -eq 0 ]
  check "12$tag 3 hooks removed" [ "$(grep -c '^remove hook ' "$T/out.txt")" -eq 3 ]
  check "12$tag no hook of the checkout left" [ "$(jq --arg r "$T/$sub" '[.. | .command? | strings | select(startswith($r + "/claude/hooks/"))] | length' "$T/claude/settings.json")" -eq 0 ]
done
# moved checkout whose old path was Korean-named: the stale bare paths are removed
T=$(newdir t12mv); seed "$T"; copy_to "$REPO" "$T/old/작업"
inst_from "$T/old/작업" "$T"; rm -rf "$T/old"
uninst_from "$REPO" "$T"
check "12mv Korean old path: rc 0" [ "$RC" -eq 0 ]
check "12mv Korean old path: stale hooks removed" [ "$(jq '[.. | .command? | strings | select(contains("/claude/hooks/"))] | length' "$T/claude/settings.json")" -eq 0 ]
check "12mv Korean old path: /opt hooks kept" [ "$(jq '[.. | .command? | strings | select(startswith("/opt/"))] | length' "$T/claude/settings.json")" -eq 4 ]
# wrapper-form hook of the user: kept (mutant target: the whitespace filter)
T=$(newdir t12w); mkdir -p "$T/claude"
jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"/opt/wrap.sh /gone/claude/hooks/conductor-gate.sh"}]}]}}' > "$T/claude/settings.json"
BEFORE=$(jq -S . "$T/claude/settings.json")
uninst_from "$REPO" "$T" --dry-run
check "12w wrapper hook: not listed for removal" [ "$(grep -c '^remove hook ' "$T/out.txt")" -eq 0 ]
uninst_from "$REPO" "$T"
check "12w wrapper hook kept" [ "$(jq -S . "$T/claude/settings.json")" = "$BEFORE" ]
# no-space metacharacter forms are kept too (mutant target: the metacharacter filter)
jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"/opt/run.sh;/gone/claude/hooks/conductor-gate.sh"},{type:"command",command:"/x/$(id)/claude/hooks/conductor-gate.sh"}]}]}}' > "$T/claude/settings.json"
BEFORE=$(jq -S . "$T/claude/settings.json")
uninst_from "$REPO" "$T" --dry-run
check "12w metacharacter hooks: not listed for removal" [ "$(grep -c '^remove hook ' "$T/out.txt")" -eq 0 ]
uninst_from "$REPO" "$T"
check "12w metacharacter hooks kept" [ "$(jq -S . "$T/claude/settings.json")" = "$BEFORE" ]
# a stale bare path with a space (old checkout path had a space) is kept: documented fail-safe
jq -n '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"/gone/sp ace/claude/hooks/conductor-gate.sh"}]}]}}' > "$T/claude/settings.json"
BEFORE=$(jq -S . "$T/claude/settings.json")
uninst_from "$REPO" "$T"
check "12w stale path containing a space kept (fail-safe)" [ "$(jq -S . "$T/claude/settings.json")" = "$BEFORE" ]

# --- 13. *.bak.* links and a user's own env {} --------------------------------------------------------
T=$(newdir t13a); mkdir -p "$T/claude/agents" "$T/bin"
ln -s "$REPO/claude/agents/analyst.md" "$T/claude/agents/analyst.md.bak.20250101000000"
ln -s "$REPO/claude/agents/solo.md" "$T/claude/agents/solo.md"
uninst_from "$REPO" "$T"
check "13 link named *.bak.* kept" [ -L "$T/claude/agents/analyst.md.bak.20250101000000" ]
check "13 the ordinary link next to it removed" [ ! -L "$T/claude/agents/solo.md" ]
# a pre-existing "env": {} stays when only a non-env key is removed (U6)
T=$(newdir t13b); mkdir -p "$T/claude"
echo '{"promptCacheTtl":"1h","env":{},"model":"m"}' > "$T/claude/settings.json"
uninst_from "$REPO" "$T"
check "13 promptCacheTtl removed" jq -e 'has("promptCacheTtl") | not' "$T/claude/settings.json" >/dev/null
check "13 user's empty env kept" [ "$(jq -c .env "$T/claude/settings.json")" = '{}' ]

# --- symlinked settings.json stays a symlink -----------------------------------------------------
T=$(newdir t11); mkdir -p "$T/claude" "$T/real"; echo '{"promptCacheTtl":"1h","model":"x"}' > "$T/real/settings.json"
ln -s "$T/real/settings.json" "$T/claude/settings.json"
uninst_from "$REPO" "$T"
check "settings symlink kept" [ -L "$T/claude/settings.json" ]
check "settings symlink target updated" [ "$(jq -c . "$T/real/settings.json")" = '{"model":"x"}' ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
