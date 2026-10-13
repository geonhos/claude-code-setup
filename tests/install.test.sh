#!/bin/bash
# Tests for install.sh. Run: /bin/bash tests/install.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
pass=0
fail=0
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]" >&2; fi; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
newdir() { mkdir -p "$ROOT/$1" && echo "$ROOT/$1"; }

# install_in DIR: run install.sh with every target under DIR; sets RC, output in DIR/out.txt
install_in() {
  local d=$1
  CLAUDE_DIR="$d/claude" BIN_DIR="$d/bin" GIT_IGNORE="$d/gitignore" /bin/bash "$REPO/install.sh" >"$d/out.txt" 2>&1
  RC=$?
  if [ "$RC" -ne 0 ]; then cat "$d/out.txt"; fi
  return 0
}

T=$(newdir main)
export CLAUDE_DIR="$T/claude" BIN_DIR="$T/bin" GIT_IGNORE="$T/gitignore" SKIP_HERDR_INTEGRATION=1
mkdir -p "$CLAUDE_DIR"
# pre-existing settings that must survive
cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "model": "fable",
  "agent": "something",
  "env": { "FOO": "bar" },
  "permissions": { "defaultMode": "auto" },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "/opt/other-hook.sh" } ] }
    ],
    "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "/opt/stop.sh" } ] } ]
  }
}
EOF
printf 'node_modules/\n' > "$GIT_IGNORE"

run_install() { install_in "$T"; }

run_install
check "first run rc" [ "$RC" -eq 0 ]

S="$CLAUDE_DIR/settings.json"
GATE="$REPO/claude/hooks/conductor-gate.sh"
check "settings valid json" jq -e . "$S" >/dev/null
check "model preserved" [ "$(jq -r .model "$S")" = fable ]
check "defaultMode preserved" [ "$(jq -r .permissions.defaultMode "$S")" = auto ]
check "other PreToolUse hook preserved" jq -e '.hooks.PreToolUse[] | select(.hooks[0].command=="/opt/other-hook.sh")' "$S" >/dev/null
check "Stop hook preserved" jq -e '.hooks.Stop[0].hooks[0].command=="/opt/stop.sh"' "$S" >/dev/null
check "gate hook added once" [ "$(jq --arg g "$GATE" '[.hooks.PreToolUse[] | select(.hooks[] | .command==$g)] | length' "$S")" -eq 1 ]
check "gate matcher" jq -e --arg g "$GATE" '.hooks.PreToolUse[] | select(.hooks[] | .command==$g) | .matcher=="Edit|Write|NotebookEdit|Read|Grep|Glob|Bash|Agent|Workflow|Monitor|mcp__filesystem__.*"' "$S" >/dev/null
check "promptCacheTtl" [ "$(jq -r .promptCacheTtl "$S")" = 1h ]
check "subagentPromptCacheTtl" [ "$(jq -r .subagentPromptCacheTtl "$S")" = 1h ]
check "BASH_DEFAULT_TIMEOUT_MS" [ "$(jq -r .env.BASH_DEFAULT_TIMEOUT_MS "$S")" = 600000 ]
check "BASH_MAX_TIMEOUT_MS" [ "$(jq -r .env.BASH_MAX_TIMEOUT_MS "$S")" = 1800000 ]
check "env.FOO preserved" [ "$(jq -r .env.FOO "$S")" = bar ]
check "backup created" ls "$CLAUDE_DIR"/settings.json.bak.* >/dev/null 2>&1

check "agent set to conductor" [ "$(jq -r .agent "$S")" = conductor ]

for a in analyst implementer reviewer conductor solo; do
  check "agent symlink $a" [ "$(readlink "$CLAUDE_DIR/agents/$a.md")" = "$REPO/claude/agents/$a.md" ]
done
check "harness symlink" [ "$(readlink "$BIN_DIR/harness")" = "$REPO/bin/harness" ]
check "CLAUDE.md not created" [ ! -e "$CLAUDE_DIR/CLAUDE.md" ]
check "global gitignore has .harness/" grep -qx '.harness/' "$GIT_IGNORE"
check "global gitignore keeps old lines" grep -qx 'node_modules/' "$GIT_IGNORE"

# second run: idempotent
run_install
check "second run rc" [ "$RC" -eq 0 ]
check "env still preserved after rerun" [ "$(jq -c '.env' "$S")" = '{"FOO":"bar","BASH_DEFAULT_TIMEOUT_MS":"600000","BASH_MAX_TIMEOUT_MS":"1800000"}' ]
check "gate hook still once" [ "$(jq --arg g "$GATE" '[.hooks.PreToolUse[] | select(.hooks[] | .command==$g)] | length' "$S")" -eq 1 ]
check "other hook still once" [ "$(jq '[.hooks.PreToolUse[] | select(.hooks[] | .command=="/opt/other-hook.sh")] | length' "$S")" -eq 1 ]
check "agent still conductor after rerun" [ "$(jq -r .agent "$S")" = conductor ]
check "CLAUDE.md still absent after rerun" [ ! -e "$CLAUDE_DIR/CLAUDE.md" ]
check "gitignore line once" [ "$(grep -cx '.harness/' "$GIT_IGNORE")" -eq 1 ]
# fresh HOME with no settings.json at all
T2=$(newdir fresh)
install_in "$T2"
check "fresh install rc" [ "$RC" -eq 0 ]
check "fresh settings created" jq -e '.hooks.PreToolUse | length == 1' "$T2/claude/settings.json" >/dev/null

# invalid settings must abort without side effects
assert_untouched() { # DIR ORIGINAL_CONTENT
  check "$1 settings untouched" [ "$(cat "$2/claude/settings.json")" = "$3" ]
  check "$1 no bin dir" [ ! -e "$2/bin" ]
  check "$1 no backup" [ -z "$(ls "$2"/claude/settings.json.bak.* 2>/dev/null)" ]
  check "$1 no gitignore" [ ! -e "$2/gitignore" ]
  check "$1 no CLAUDE.md" [ ! -e "$2/claude/CLAUDE.md" ]
  check "$1 no agents dir" [ ! -e "$2/claude/agents" ]
}
for case in 'badjson|{not json|not valid JSON' 'array|[]|not a JSON object' 'concat|{"a":1}{"b":2}|not a JSON object'; do
  name=${case%%|*}; rest=${case#*|}; content=${rest%|*}; msg=${rest##*|}
  D=$(newdir "$name"); mkdir -p "$D/claude"; printf '%s' "$content" > "$D/claude/settings.json"
  install_in "$D" >/dev/null
  check "$name rc" [ "$RC" -ne 0 ]
  check "$name message" grep -q "$msg" "$D/out.txt"
  assert_untouched "$name" "$D" "$content"
done

# co-located hook: gate and another command in one entry
T4=$(newdir coloc); mkdir -p "$T4/claude"
jq -n --arg g "$GATE" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$g},{type:"command",command:"/opt/keep.sh"}]}]}}' > "$T4/claude/settings.json"
install_in "$T4"
check "colocated rc" [ "$RC" -eq 0 ]
check "colocated other hook kept" [ "$(jq '[.hooks.PreToolUse[].hooks[] | select(.command=="/opt/keep.sh")] | length' "$T4/claude/settings.json")" -eq 1 ]
check "colocated gate once" [ "$(jq --arg g "$GATE" '[.hooks.PreToolUse[].hooks[] | select(.command==$g)] | length' "$T4/claude/settings.json")" -eq 1 ]

# unrelated empty-hooks entry survives; stale gate entry with other matcher is replaced
T9=$(newdir stale); mkdir -p "$T9/claude"
jq -n --arg g "$GATE" '{hooks:{PreToolUse:[{matcher:"X",hooks:[]},{matcher:"Old",hooks:[{type:"command",command:$g}]}]}}' > "$T9/claude/settings.json"
install_in "$T9"
check "stale rc" [ "$RC" -eq 0 ]
check "empty-hooks entry survives" jq -e '.hooks.PreToolUse[] | select(.matcher=="X" and (.hooks|length)==0)' "$T9/claude/settings.json" >/dev/null
check "stale gate replaced once" [ "$(jq --arg g "$GATE" '[.hooks.PreToolUse[] | select(any(.hooks[]?; .command==$g))] | length' "$T9/claude/settings.json")" -eq 1 ]
check "stale matcher updated" jq -e '[.hooks.PreToolUse[] | select(.matcher=="Old")] | length == 0' "$T9/claude/settings.json" >/dev/null

# gitignore without trailing newline
T5=$(newdir nonl); printf 'node_modules/' > "$T5/gitignore"
install_in "$T5"
check "no-newline gitignore lines" [ "$(cat "$T5/gitignore")" = "$(printf 'node_modules/\n.harness/')" ]

# symlinked settings.json stays a symlink
T6=$(newdir symlink); mkdir -p "$T6/claude" "$T6/real"; echo '{"model":"x"}' > "$T6/real/settings.json"
ln -s "$T6/real/settings.json" "$T6/claude/settings.json"
install_in "$T6"
check "settings still symlink" [ -L "$T6/claude/settings.json" ]
check "symlink target updated" jq -e --arg g "$GATE" '.model=="x" and (.hooks.PreToolUse[0].hooks[0].command==$g)' "$T6/real/settings.json" >/dev/null

# user's own agent file is backed up, not clobbered
T7=$(newdir agentfile); mkdir -p "$T7/claude/agents"; printf 'mine' > "$T7/claude/agents/analyst.md"
install_in "$T7"
check "agent now symlink" [ -L "$T7/claude/agents/analyst.md" ]
check "agent backup content" [ "$(cat "$T7"/claude/agents/analyst.md.bak.* 2>/dev/null)" = mine ]
check "agent backup message" grep -q "backed up" "$T7/out.txt"

# a symlink pointing elsewhere is also backed up and relinked
T10=$(newdir agentlink); mkdir -p "$T10/claude/agents"; ln -s /nonexistent/elsewhere.md "$T10/claude/agents/reviewer.md"
install_in "$T10"
check "foreign symlink relinked" [ "$(readlink "$T10/claude/agents/reviewer.md")" = "$REPO/claude/agents/reviewer.md" ]
check "foreign symlink backed up" [ -L "$(ls "$T10"/claude/agents/reviewer.md.bak.* 2>/dev/null | head -1)" ]

# a failed write must fail loudly
T11=$(newdir rofile); mkdir -p "$T11/claude"; echo '{}' > "$T11/claude/settings.json"; chmod 444 "$T11/claude/settings.json"
install_in "$T11" >/dev/null
check "write failure rc" [ "$RC" -ne 0 ]
check "write failure message" grep -q "failed to write" "$T11/out.txt"
check "write failure no success banner" [ -z "$(grep '^installed:' "$T11/out.txt")" ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
