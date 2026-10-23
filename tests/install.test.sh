#!/bin/bash
# Tests for install.sh. Run: /bin/bash tests/install.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
pass=0
fail=0
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]" >&2; fi; }
not_grep() { ! grep "$@"; }

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
    "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "/opt/stop.sh" } ] } ],
    "SessionStart": [ { "matcher": "startup", "hooks": [ { "type": "command", "command": "/opt/session.sh" } ] } ],
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "/opt/prompt.sh" } ] } ]
  }
}
EOF
printf 'node_modules/\n' > "$GIT_IGNORE"

run_install() { install_in "$T"; }

mkdir -p "$CLAUDE_DIR/skills/analyze"; echo old > "$CLAUDE_DIR/skills/analyze/SKILL.md"
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
for s in analyze implement review; do
  check "skill symlink $s" [ "$(readlink "$CLAUDE_DIR/skills/$s")" = "$REPO/claude/skills/$s" ]
  check "skill symlink $s resolves" [ -f "$CLAUDE_DIR/skills/$s/SKILL.md" ]
done
check "foreign skill dir backed up" ls -d "$CLAUDE_DIR"/skills.bak/analyze.* >/dev/null 2>&1
check "no backup left inside skills/" [ -z "$(ls -d "$CLAUDE_DIR"/skills/*.bak.* 2>/dev/null)" ]
check "foreign skill dir warning" grep -q 'skills/analyze existed and was backed up' "$T/out.txt"
ROUTE="$REPO/claude/hooks/conductor-route.sh"
check "route hook executable" [ -x "$ROUTE" ]
check "route hook added once" [ "$(jq --arg r "$ROUTE" '[.hooks.UserPromptSubmit[]? | select(any(.hooks[]?; .command==$r))] | length' "$S")" -eq 1 ]
check "route hook has no matcher" jq -e --arg r "$ROUTE" '.hooks.UserPromptSubmit[] | select(any(.hooks[]?; .command==$r)) | has("matcher") | not' "$S" >/dev/null
check "route hook type command" jq -e --arg r "$ROUTE" '.hooks.UserPromptSubmit[] | select(any(.hooks[]?; .command==$r)) | .hooks[0].type=="command"' "$S" >/dev/null
check "other UserPromptSubmit hook preserved" [ "$(jq '[.hooks.UserPromptSubmit[]? | select(any(.hooks[]?; .command=="/opt/prompt.sh"))] | length' "$S")" -eq 1 ]
check "installed output lists route hook" grep -q 'route hook' "$T/out.txt"
check "installed output lists skills" grep -q '^  skills  ' "$T/out.txt"
check "harness symlink" [ "$(readlink "$BIN_DIR/harness")" = "$REPO/bin/harness" ]
check "harness-verify symlink" [ "$(readlink "$BIN_DIR/harness-verify")" = "$REPO/bin/harness-verify" ]
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
check "route hook still once after rerun" [ "$(jq --arg r "$REPO/claude/hooks/conductor-route.sh" '[.hooks.UserPromptSubmit[]? | select(any(.hooks[]?; .command==$r))] | length' "$S")" -eq 1 ]
check "other UserPromptSubmit still once" [ "$(jq '[.hooks.UserPromptSubmit[]? | select(any(.hooks[]?; .command=="/opt/prompt.sh"))] | length' "$S")" -eq 1 ]
check "skill symlink survives rerun" [ "$(readlink "$CLAUDE_DIR/skills/implement")" = "$REPO/claude/skills/implement" ]
check "no skill backup warning on rerun" not_grep -q 'skills/.*backed up' "$T/out.txt"
# fresh HOME with no settings.json at all
T2=$(newdir fresh)
mkdir -p "$T2/claude/skills"; ln -s /tmp/elsewhere "$T2/claude/skills/review"
install_in "$T2"
check "fresh install rc" [ "$RC" -eq 0 ]
check "fresh settings created" jq -e '.hooks.PreToolUse | length == 1' "$T2/claude/settings.json" >/dev/null

check "fresh install has route hook" jq -e '.hooks.UserPromptSubmit | length == 1' "$T2/claude/settings.json" >/dev/null
check "fresh install has skills" [ -L "$T2/claude/skills/review" ]
check "misdirected skill symlink replaced" [ "$(readlink "$T2/claude/skills/review")" = "$REPO/claude/skills/review" ]
check "misdirected skill symlink backed up" ls -d "$T2"/claude/skills.bak/review.* >/dev/null 2>&1

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

# --- skills: static checks -----------------------------------------------------------------
for s in analyze implement review; do
  SK="$REPO/claude/skills/$s/SKILL.md"
  check "skill $s exists" [ -f "$SK" ]
  check "skill $s name matches dir" [ "$(sed -n 's/^name: *//p' "$SK" | head -1)" = "$s" ]
  check "skill $s says conductor only" grep -qi 'conductor only' "$SK"
  check "skill $s uses --via skill" grep -q -- '--via skill' "$SK"
  check "skill $s no context fork" not_grep -q '^context: *fork' "$SK"
  check "skill $s has worker opt-out" grep -q 'HARNESS_ROLE=worker' "$SK"
done
check "skill analyze targets analyst" grep -q 'harness ask analyst' "$REPO/claude/skills/analyze/SKILL.md"
check "skill implement targets implementer" grep -q 'harness ask implementer' "$REPO/claude/skills/implement/SKILL.md"
check "skill review targets reviewer" grep -q 'harness ask reviewer' "$REPO/claude/skills/review/SKILL.md"
check "skill review demands VERDICT" grep -q 'VERDICT' "$REPO/claude/skills/review/SKILL.md"

# --- SessionStart resume hook ----------------------------------------------------------------
RESUME="$REPO/claude/hooks/conductor-resume.sh"
check "resume hook executable" [ -x "$RESUME" ]
check "resume hook added once" [ "$(jq --arg r "$RESUME" '[.hooks.SessionStart[]? | select(any(.hooks[]?; .command==$r))] | length' "$S")" -eq 1 ]
check "resume hook matcher" jq -e --arg r "$RESUME" '.hooks.SessionStart[] | select(any(.hooks[]?; .command==$r)) | .matcher=="startup|clear|compact"' "$S" >/dev/null
check "resume hook type command" jq -e --arg r "$RESUME" '.hooks.SessionStart[] | select(any(.hooks[]?; .command==$r)) | .hooks[0].type=="command"' "$S" >/dev/null
check "other SessionStart hooks preserved" jq -e '[.hooks.SessionStart[]? | select(any(.hooks[]?; .command=="/opt/session.sh"))] | length == 1' "$S" >/dev/null

HW=$(newdir hookwork); mkdir -p "$HW/.harness"
printf '# Progress — x (main)\nGoal: g\n' > "$HW/.harness/progress.md"
OUT=$(cd "$HW" && HARNESS_ROLE=worker /bin/bash "$RESUME" </dev/null 2>&1); RC=$?
check "resume hook silent for workers" [ -z "$OUT" ]
check "resume hook worker rc" [ "$RC" -eq 0 ]
HE=$(newdir hookempty)
OUT=$(cd "$HE" && env -u HARNESS_ROLE /bin/bash "$RESUME" </dev/null 2>&1); RC=$?
check "resume hook silent without progress.md" [ -z "$OUT" ]
check "resume hook missing-file rc" [ "$RC" -eq 0 ]
OUT=$(cd "$HW" && env -u HARNESS_ROLE /bin/bash "$RESUME" </dev/null 2>/dev/null); RC=$?
check "resume hook rc" [ "$RC" -eq 0 ]
check "resume hook event name" [ "$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.hookEventName)" = SessionStart ]
check "resume hook prefix line" printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext | head -1 | grep -qx 'Harness progress (resume from here; verify with harness status)'
check "resume hook has file content" printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext | grep -qx 'Goal: g'
OUT=$(cd "$HE" && printf '{"cwd":"%s","source":"clear"}' "$HW" | env -u HARNESS_ROLE /bin/bash "$RESUME" 2>/dev/null)
check "resume hook uses stdin cwd" printf '%s' "$OUT" | jq -e .hookSpecificOutput.additionalContext >/dev/null
OUT=$(cd "$HW" && env -u HARNESS_ROLE PATH=/usr/bin:/bin /bin/bash "$RESUME" </dev/null 2>&1); RC=$?
check "resume hook works with no jq on PATH (rc 0)" [ "$RC" -eq 0 ]

# wiki index injection
WK=$(newdir hookwiki); mkdir -p "$WK/docs/wiki"
printf '# Wiki index\n- [a](gotchas/a.md) — one (active, 2026-10-21)\n- [b](gotchas/b.md) — two (draft, 2026-10-21)\n- [c](decisions/c.md) — three (stale, 2026-10-21)\n' > "$WK/docs/wiki/index.md"
OUT=$(cd "$WK" && env -u HARNESS_ROLE /bin/bash "$RESUME" </dev/null 2>/dev/null); RC=$?
CTX=$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext)
check "wiki only (no progress.md) injects" [ "$RC" -eq 0 ] 
check "wiki active line present" printf '%s' "$CTX" | grep -q 'gotchas/a.md'
check "wiki draft line absent" sh -c '! printf "%s" "$1" | grep -q gotchas/b.md' _ "$CTX"
check "wiki stale line absent" sh -c '! printf "%s" "$1" | grep -q decisions/c.md' _ "$CTX"
check "wiki heading line absent" sh -c '! printf "%s" "$1" | grep -q "^# Wiki index"' _ "$CTX"
mkdir -p "$WK/.harness"; printf 'Goal: g\n' > "$WK/.harness/progress.md"
OUT=$(cd "$WK" && env -u HARNESS_ROLE /bin/bash "$RESUME" </dev/null 2>/dev/null)
CTX=$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext)
check "progress and wiki both injected" sh -c 'printf "%s" "$1" | grep -qx "Goal: g" && printf "%s" "$1" | grep -q gotchas/a.md' _ "$CTX"
check "progress comes before wiki" [ "$(printf '%s' "$CTX" | grep -n 'Goal: g\|gotchas/a.md' | head -1 | cut -d: -f2-)" = "Goal: g" ]
OUT=$(cd "$WK" && HARNESS_ROLE=worker /bin/bash "$RESUME" </dev/null 2>&1)
check "wiki injection silent for workers" [ -z "$OUT" ]
# cap: many active lines -> wiki part <= 2048 bytes, truncation note
i=0; while [ $i -lt 60 ]; do printf -- '- [p%s](gotchas/p%s.md) — hook text to fill space here (active, 2026-10-21)\n' $i $i; i=$((i+1)); done > "$WK/docs/wiki/index.md"
OUT=$(cd "$WK" && env -u HARNESS_ROLE /bin/bash "$RESUME" </dev/null 2>/dev/null)
CTX=$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext)
WB=$(printf '%s\n' "$CTX" | awk '/^Wiki \(active/ || /^- \[p/ || /^… see/' | LC_ALL=C wc -c | tr -d ' ')
check "wiki part (header included) capped at 2048 bytes" [ "$WB" -le 2048 ] 
check "wiki truncation note" printf '%s' "$CTX" | grep -qx '… see docs/wiki/index.md'
check "wiki truncation drops late lines" sh -c '! printf "%s" "$1" | grep -q "p59.md"' _ "$CTX"

# second run: idempotent resume hook
install_in "$T"
check "resume hook still once after rerun" [ "$(jq --arg r "$RESUME" '[.hooks.SessionStart[]? | select(any(.hooks[]?; .command==$r))] | length' "$S")" -eq 1 ]
check "other SessionStart still once" [ "$(jq '[.hooks.SessionStart[]? | select(any(.hooks[]?; .command=="/opt/session.sh"))] | length' "$S")" -eq 1 ]

# --- test runner (install.sh --test) against scratch suites -----------------
# INSTALL_SH can point at another copy of the script (used to show the tests red).
RUNNER=${INSTALL_SH:-$REPO/install.sh}
# guard BODY...: run with a hard 40 s bound (a hang fails the check instead of the suite)
guard() {
  "$@" & local p=$!
  ( sleep 40; kill -KILL "$p" 2>/dev/null ) & local w=$!
  wait "$p" 2>/dev/null; local r=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  return $r
}
mk_suites() {  # mk_suites DIR [failing|hanging]
  local d=$1; mkdir -p "$d"
  printf '#!/bin/bash\necho ok-a\n' > "$d/a.test.sh"
  printf '#!/bin/bash\necho ok-c\n' > "$d/c.test.sh"
  case "${2:-}" in
    failing) printf '#!/bin/bash\necho boom-b\nexit 1\n' > "$d/b.test.sh" ;;
    hanging) printf '#!/bin/bash\necho start-b\nsleep 60 &\necho $! > "%s/bg.pid"\nsleep 60 &\necho $! > "%s/fg.pid"\nwait\n' "$d" "$d" > "$d/b.test.sh" ;;
    *)       printf '#!/bin/bash\necho ok-b\n' > "$d/b.test.sh" ;;
  esac
}
run_runner() {  # run_runner DIR [ENV=VAL...] — sets RRC, output in DIR.out
  local d=$1; shift
  env HARNESS_TESTS_DIR="$d" "$@" /bin/bash "$RUNNER" --test > "$d.out" 2>&1
  echo $? > "$d.rc"
}
for mode in parallel serial; do
  ser=0; [ "$mode" = serial ] && ser=1
  D=$ROOT/rn-ok-$mode; mk_suites "$D" ok
  guard run_runner "$D" HARNESS_TEST_SERIAL=$ser; RRC=$(cat "$D.rc" 2>/dev/null || echo 137)
  check "runner $mode: all pass exits 0" [ "$RRC" -eq 0 ]
  check "runner $mode: all blocks printed" sh -c 'grep -q ok-a "$1" && grep -q ok-b "$1" && grep -q ok-c "$1"' _ "$D.out"
  check "runner $mode: no FAILED line when green" not_grep -q FAILED "$D.out"

  D=$ROOT/rn-fail-$mode; mk_suites "$D" failing
  start=$(date +%s)
  guard run_runner "$D" HARNESS_TEST_SERIAL=$ser; RRC=$(cat "$D.rc" 2>/dev/null || echo 137)
  check "runner $mode: failing suite exits non-zero" [ "$RRC" -ne 0 ] && [ "$RRC" -lt 128 ]
  check "runner $mode: FAILED line names the suite" grep -qx 'FAILED suites: b' "$D.out"
  check "runner $mode: failing suite block printed" sh -c 'grep -q "boom-b" "$1" && grep -q "b FAILED (exit 1)" "$1"' _ "$D.out"
  check "runner $mode: other suites still printed" sh -c 'grep -q ok-a "$1" && grep -q ok-c "$1"' _ "$D.out"
  check "runner $mode: failing run finishes quickly" [ $(( $(date +%s) - start )) -lt 20 ]

  D=$ROOT/rn-hang-$mode; mk_suites "$D" hanging
  start=$(date +%s)
  guard run_runner "$D" HARNESS_TEST_SERIAL=$ser HARNESS_TEST_TIMEOUT=2; RRC=$(cat "$D.rc" 2>/dev/null || echo 137)
  check "runner $mode: hung suite exits non-zero" [ "$RRC" -ne 0 ] && [ "$RRC" -lt 128 ]
  check "runner $mode: hung suite reported timed out" grep -q 'b timed out after 2s' "$D.out"
  check "runner $mode: timeout run ends quickly" [ $(( $(date +%s) - start )) -lt 15 ]
  check "runner $mode: timeout names FAILED suite" grep -qx 'FAILED suites: b' "$D.out"
  check "runner $mode: other suites ran despite hang" sh -c 'grep -q ok-a "$1" && grep -q ok-c "$1"' _ "$D.out"
  sleep 0.5
  check "runner $mode: hung suite's descendants killed" sh -c '! kill -0 "$(cat "$1/bg.pid")" 2>/dev/null && ! kill -0 "$(cat "$1/fg.pid")" 2>/dev/null' _ "$D"
  kill "$(cat "$D/bg.pid" 2>/dev/null)" "$(cat "$D/fg.pid" 2>/dev/null)" 2>/dev/null || true
done

# TERM to the runner kills the running suites and exits 143
D=$ROOT/rn-term; mk_suites "$D" hanging
printf '#!/bin/bash\nsleep 61 &\necho $! > "%s/b.pid"\nwait\n' "$D" > "$D/b.test.sh"
HARNESS_TESTS_DIR="$D" /bin/bash "$RUNNER" --test > "$D.out" 2>&1 &
RP=$!
i=0; while [ ! -s "$D/b.pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
kill -TERM "$RP"
( sleep 40; kill -KILL "$RP" 2>/dev/null ) & WD=$!
wait "$RP"; TRC=$?
kill "$WD" 2>/dev/null; wait "$WD" 2>/dev/null
check "runner: TERM exits 143" [ "$TRC" -eq 143 ]
sleep 0.5
check "runner: TERM kills suite children" sh -c '! kill -0 "$(cat "$1/b.pid")" 2>/dev/null' _ "$D"
kill "$(cat "$D/b.pid")" 2>/dev/null || true
check "runner: HARNESS_TESTS_DIR notice names dir and wiki-lint skip" sh -c 'grep -q "HARNESS_TESTS_DIR set: running suites from $1; wiki-lint skipped" "$2"' _ "$D" "$D.out"

# HUP to the runner behaves like TERM: suites killed, exit 129
D=$ROOT/rn-hup; mk_suites "$D" hanging
printf '#!/bin/bash\nsleep 61 &\necho $! > "%s/b.pid"\nwait\n' "$D" > "$D/b.test.sh"
HARNESS_TESTS_DIR="$D" /bin/bash "$RUNNER" --test > "$D.out" 2>&1 &
RP=$!
i=0; while [ ! -s "$D/b.pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
kill -HUP "$RP"
( sleep 40; kill -KILL "$RP" 2>/dev/null ) & WD=$!
wait "$RP"; HRC=$?
kill "$WD" 2>/dev/null; wait "$WD" 2>/dev/null
check "runner: HUP exits 129" [ "$HRC" -eq 129 ]
sleep 0.5
check "runner: HUP kills suite children" sh -c '! kill -0 "$(cat "$1/b.pid")" 2>/dev/null' _ "$D"
kill "$(cat "$D/b.pid")" 2>/dev/null || true

# a finished suite's .pid file is removed, so kill_all cannot hit a reused pid.
# Suite b polls the runner's tdir (under TMPDIR=$D/tmp) while a is done and b still runs.
D=$ROOT/rn-pid; mkdir -p "$D/tmp"
printf '#!/bin/bash\nexit 0\n' > "$D/a.test.sh"
cat > "$D/b.test.sh" <<EOS
#!/bin/bash
i=0
while [ \$i -lt 100 ]; do
  for t in "$D"/tmp/harness-tests.*; do
    if [ -f "\$t/a.rc" ] && [ ! -e "\$t/a.pid" ]; then echo gone > "$D/result"; exit 0; fi
  done
  sleep 0.1; i=\$((i+1))
done
echo stuck > "$D/result"
EOS
guard run_runner "$D" TMPDIR="$D/tmp"
check "runner: finished suite's pid file removed while others run" grep -qx gone "$D/result"

# runner discovers suites by glob: hyphenated names run, helper files (no .test.sh) do not
D=$ROOT/rn-glob; mk_suites "$D"
printf '#!/bin/bash\necho ok-hy\n' > "$D/x-y.test.sh"
printf 'echo helper-ran\n' > "$D/x-lib.sh"
HARNESS_TESTS_DIR="$D" /bin/bash "$RUNNER" --test > "$D.out" 2>&1
check "runner glob: hyphenated suite runs" grep -qx '=== x-y ===' "$D.out"
check "runner glob: helper not run" not_grep helper-ran "$D.out"
check "runner: no hardcoded suite list" not_grep 'names="gate' "$RUNNER"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
