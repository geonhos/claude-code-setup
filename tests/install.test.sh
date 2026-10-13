#!/bin/bash
# Tests for install.sh. Run: /bin/bash tests/install.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
pass=0
fail=0
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]"; fi; }

T=$(mktemp -d)
export CLAUDE_DIR="$T/claude" BIN_DIR="$T/bin" GIT_IGNORE="$T/gitignore" SKIP_HERDR_INTEGRATION=1
mkdir -p "$CLAUDE_DIR"
# pre-existing settings that must survive
cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "model": "fable",
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

run_install() { /bin/bash "$REPO/install.sh" >"$T/out.txt" 2>&1; RC=$?; }

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
check "gate matcher" jq -e --arg g "$GATE" '.hooks.PreToolUse[] | select(.hooks[] | .command==$g) | .matcher=="Edit|Write|NotebookEdit|Read|Grep|Glob|Bash|Agent|Workflow"' "$S" >/dev/null
check "promptCacheTtl" [ "$(jq -r .promptCacheTtl "$S")" = 1h ]
check "subagentPromptCacheTtl" [ "$(jq -r .subagentPromptCacheTtl "$S")" = 1h ]
check "backup created" ls "$CLAUDE_DIR"/settings.json.bak.* >/dev/null 2>&1

for a in analyst implementer reviewer; do
  check "agent symlink $a" [ "$(readlink "$CLAUDE_DIR/agents/$a.md")" = "$REPO/claude/agents/$a.md" ]
done
check "harness symlink" [ "$(readlink "$BIN_DIR/harness")" = "$REPO/bin/harness" ]
check "CLAUDE.md import line" grep -qxF "@$REPO/claude/CLAUDE.conductor.md" "$CLAUDE_DIR/CLAUDE.md"
check "global gitignore has .harness/" grep -qx '.harness/' "$GIT_IGNORE"
check "global gitignore keeps old lines" grep -qx 'node_modules/' "$GIT_IGNORE"

# second run: idempotent
run_install
check "second run rc" [ "$RC" -eq 0 ]
check "gate hook still once" [ "$(jq --arg g "$GATE" '[.hooks.PreToolUse[] | select(.hooks[] | .command==$g)] | length' "$S")" -eq 1 ]
check "other hook still once" [ "$(jq '[.hooks.PreToolUse[] | select(.hooks[] | .command=="/opt/other-hook.sh")] | length' "$S")" -eq 1 ]
check "import line once" [ "$(grep -cxF "@$REPO/claude/CLAUDE.conductor.md" "$CLAUDE_DIR/CLAUDE.md")" -eq 1 ]
check "gitignore line once" [ "$(grep -cx '.harness/' "$GIT_IGNORE")" -eq 1 ]

# fresh HOME with no settings.json at all
T2=$(mktemp -d)
CLAUDE_DIR="$T2/claude" BIN_DIR="$T2/bin" GIT_IGNORE="$T2/gitignore" /bin/bash "$REPO/install.sh" >/dev/null 2>&1
check "fresh install rc" [ $? -eq 0 ]
check "fresh settings created" jq -e '.hooks.PreToolUse | length == 1' "$T2/claude/settings.json" >/dev/null

# invalid settings.json must abort without touching it
T3=$(mktemp -d); mkdir -p "$T3/claude"; printf '{not json' > "$T3/claude/settings.json"
CLAUDE_DIR="$T3/claude" BIN_DIR="$T3/bin" GIT_IGNORE="$T3/gitignore" /bin/bash "$REPO/install.sh" >"$T3/out.txt" 2>&1
check "invalid settings rc" [ $? -ne 0 ]
check "invalid settings untouched" [ "$(cat "$T3/claude/settings.json")" = '{not json' ]
check "invalid settings message" grep -q "not valid JSON" "$T3/out.txt"

# co-located hook: gate and another command in one entry
T4=$(mktemp -d); mkdir -p "$T4/claude"
jq -n --arg g "$GATE" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$g},{type:"command",command:"/opt/keep.sh"}]}]}}' > "$T4/claude/settings.json"
CLAUDE_DIR="$T4/claude" BIN_DIR="$T4/bin" GIT_IGNORE="$T4/gitignore" /bin/bash "$REPO/install.sh" >/dev/null 2>&1
check "colocated rc" [ $? -eq 0 ]
check "colocated other hook kept" [ "$(jq '[.hooks.PreToolUse[].hooks[] | select(.command=="/opt/keep.sh")] | length' "$T4/claude/settings.json")" -eq 1 ]
check "colocated gate once" [ "$(jq --arg g "$GATE" '[.hooks.PreToolUse[].hooks[] | select(.command==$g)] | length' "$T4/claude/settings.json")" -eq 1 ]

# gitignore without trailing newline
T5=$(mktemp -d); printf 'node_modules/' > "$T5/gitignore"
CLAUDE_DIR="$T5/claude" BIN_DIR="$T5/bin" GIT_IGNORE="$T5/gitignore" /bin/bash "$REPO/install.sh" >/dev/null 2>&1
check "no-newline gitignore lines" [ "$(cat "$T5/gitignore")" = "$(printf 'node_modules/\n.harness/')" ]

# symlinked settings.json stays a symlink
T6=$(mktemp -d); mkdir -p "$T6/claude" "$T6/real"; echo '{"model":"x"}' > "$T6/real/settings.json"
ln -s "$T6/real/settings.json" "$T6/claude/settings.json"
CLAUDE_DIR="$T6/claude" BIN_DIR="$T6/bin" GIT_IGNORE="$T6/gitignore" /bin/bash "$REPO/install.sh" >/dev/null 2>&1
check "settings still symlink" [ -L "$T6/claude/settings.json" ]
check "symlink target updated" jq -e --arg g "$GATE" '.model=="x" and (.hooks.PreToolUse[0].hooks[0].command==$g)' "$T6/real/settings.json" >/dev/null

# user's own agent file is backed up, not clobbered
T7=$(mktemp -d); mkdir -p "$T7/claude/agents"; printf 'mine' > "$T7/claude/agents/analyst.md"
CLAUDE_DIR="$T7/claude" BIN_DIR="$T7/bin" GIT_IGNORE="$T7/gitignore" /bin/bash "$REPO/install.sh" >"$T7/out.txt" 2>&1
check "agent now symlink" [ -L "$T7/claude/agents/analyst.md" ]
check "agent backup content" [ "$(cat "$T7"/claude/agents/analyst.md.bak.* 2>/dev/null)" = mine ]
check "agent backup message" grep -q "backed up" "$T7/out.txt"

# top-level non-object settings
T8=$(mktemp -d); mkdir -p "$T8/claude"; printf '[]' > "$T8/claude/settings.json"
CLAUDE_DIR="$T8/claude" BIN_DIR="$T8/bin" GIT_IGNORE="$T8/gitignore" /bin/bash "$REPO/install.sh" >"$T8/out.txt" 2>&1
check "array settings rc" [ $? -ne 0 ]
check "array settings untouched" [ "$(cat "$T8/claude/settings.json")" = '[]' ]
check "array settings message" grep -q "not a JSON object" "$T8/out.txt"
check "array settings no agents dir" [ ! -e "$T8/claude/agents" ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
