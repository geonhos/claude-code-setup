#!/bin/bash
# run.sh <arm A|B> <round> — one fresh clone at 43fc5a7, one analyst run, stream saved
arm=$1; r=$2
REPO=$HOME/workspace/claude-code-setup
OUT=$REPO/.harness/code-mode-experiment
d=$(mktemp -d); echo "$arm$r $d" >> $OUT/clones.txt
git clone -q "$REPO" "$d/repo" && cd "$d/repo" && git checkout -q -B main 43fc5a7 || exit 9
mkdir -p .harness && cp "$OUT/brief.md" .harness/task-analyst.md
printf 'Read .harness/task-analyst.md and do it.\n' > "$d/prompt"
extra=()
[ "$arm" = B ] && extra=(--settings '{"env":{"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"1"}}')
s=$(date +%s)
env -u HERDR_PANE_ID HARNESS_ROLE=worker perl -e 'alarm 900; exec @ARGV' \
  claude -p --agent analyst --output-format stream-json --verbose --include-hook-events \
  --disallowedTools=AskUserQuestion --permission-mode auto --permission-prompts none \
  --no-session-persistence "${extra[@]}" < "$d/prompt" > "$OUT/$arm$r.jsonl" 2> "$OUT/$arm$r.err"
rc=$?
echo "$arm$r rc=$rc wall=$(( $(date +%s) - s ))" >> "$OUT/runs.txt"
mkdir -p "$OUT/$arm$r-harness"
cp -R .harness/. "$OUT/$arm$r-harness/" 2>/dev/null
git status --short > "$OUT/$arm$r-gitstatus.txt"
