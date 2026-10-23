#!/bin/bash
# Worktree asks (ADR 0008, S1): bin/harness ask --worktree for headless analyst/reviewer against
# tests/fake-herdr + tests/fake-claude. Run: /bin/bash tests/worktree.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
FAKE_CLAUDE="$HERE/fake-claude"
GATE="$HERE/../claude/hooks/conductor-gate.sh"

hrun() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=5 \
    PATH="$FAKE_BIN:$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm(25);exec(@ARGV)' \
    env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
# wsetup — a git repo with one commit, headless roles, worktrees under $WORK/wtroot
wsetup() {
  setup
  git init -q . && git config user.email t@t && git config user.name t
  echo one > a.txt && git add a.txt && git commit -qm one
  export HARNESS_RUNNER_ANALYST=headless HARNESS_RUNNER_REVIEWER=headless
  export HARNESS_WT_ROOT="$WORK/wtroot" HARNESS_NO_AUTOCLOSE=1
  unset HARNESS_MAX_PARALLEL
  export FAKE_CLAUDE_MODE=success
  # the fake claude runs with cwd = the worktree: relative paths
  export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md"
}
ask_id() { sed -n 's/^harness: ask \([^ ]*\) .*/\1/p' <<<"$OUT" | head -n 1; }
jqt() { jq -e "$@" >/dev/null; }
wt_dirs() { ls -d "$WORK"/wtroot/*/* 2>/dev/null | wc -l | tr -d ' '; }
wait_reg() { # N — until N registry entries exist
  local i=0; while [ $i -lt 60 ] && [ "$(ls .harness/wt/*.json 2>/dev/null | wc -l | tr -d ' ')" -lt "$1" ]; do sleep 0.2; i=$((i + 1)); done
}
wait_pid() { # until the nth run announced itself
  local i=0; while [ $i -lt 60 ] && [ "$(ls "$WORK"/wtroot/*/*/.harness/asks/analyst.pid 2>/dev/null | wc -l | tr -d ' ')" -lt "$1" ]; do sleep 0.2; i=$((i + 1)); done
}

# 1. clean success: created, ran in the worktree, report printed, checkout removed
wsetup
hrun ask analyst "q1" --worktree
id=$(ask_id)
check "ok: rc 0" [ "$RC" -eq 0 ]
check "ok: ask-id printed on stderr" [ -n "$id" ]
check "ok: report printed" grep -q "analyst report" <<<"$OUT"
check "ok: checkout removed" [ "$(wt_dirs)" = 0 ]
check "ok: git forgot the worktree" [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ]
check "ok: registry collected" jqt '.state == "collected" and .branch == null and .role == "analyst"' "$WORK/.harness/wt/$id.json"
check "ok: report saved" grep -q "analyst report" ".harness/wt/$id.report.md"
check "ok: progress has wt/base" jqt --arg id "$id" '.exit == 0 and .ask_id == $id and (.wt | test("analyst-")) and (.base | length) == 40' <<<"$(tail -n 1 .harness/progress.jsonl)"
check "ok: log name has id8" bash -c "ls .harness/log | grep -q -- -analyst-$(jq -r .id8 ".harness/wt/$id.json")"
check "ok: nothing in main asks dir" not_grep . .harness/asks/analyst.current
check "ok: pane unregistered" not_grep "analyst@" .harness/panes
hrun report "$id"
check "ok: report by ask-id after removal" grep -q "analyst report" <<<"$OUT"

# 2. dirty tree is kept; close without --force refuses, with --force removes
wsetup
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo x > dirty.txt"
hrun ask analyst "q2" --worktree
id=$(ask_id)
check "dirty: rc 0" [ "$RC" -eq 0 ]
check "dirty: kept" [ "$(wt_dirs)" = 1 ]
check "dirty: registry kept" jqt '.state == "kept"' ".harness/wt/$id.json"
hrun status
check "dirty: status lists it" grep -qE "^analyst@[0-9a-f]{8} +kept" <<<"$OUT"
hrun close "$id"
check "dirty: close refuses (4)" [ "$RC" -eq 4 ]
check "dirty: still there" [ "$(wt_dirs)" = 1 ]
hrun close "$id" --force
check "dirty: close --force rc 0" [ "$RC" -eq 0 ]
check "dirty: removed" [ "$(wt_dirs)" = 0 ]
check "dirty: registry closed" jqt '.state == "closed"' ".harness/wt/$id.json"

# 3. failure (no report) keeps the checkout; a clean one closes without --force
wsetup; export FAKE_CLAUDE_MODE=noreport
hrun ask analyst "q3" --worktree
id=$(ask_id)
check "fail: rc 3" [ "$RC" -eq 3 ]
check "fail: kept" [ "$(wt_dirs)" = 1 ]
check "fail: collect hint names the ask-id" grep -q "harness report $id" <<<"$OUT"
hrun close "$id"
check "fail: clean close rc 0" [ "$RC" -eq 0 ]
check "fail: removed" [ "$(wt_dirs)" = 0 ]

# 4. usage errors: nothing created, exit 1
wsetup
hrun ask implementer "q" --worktree
check "impl: rc 1" [ "$RC" -eq 1 ]
check "impl: clear message" grep -q "analyst and reviewer only" <<<"$OUT"
unset HARNESS_RUNNER_ANALYST
hrun ask analyst "q" --worktree
check "pane runner: rc 1" [ "$RC" -eq 1 ]
check "pane runner: says headless" grep -q "headless" <<<"$OUT"
export HARNESS_RUNNER_ANALYST=headless
hrun ask analyst "q" --worktree --keep
check "keep: rc 1" [ "$RC" -eq 1 ]
hrun ask analyst "q" --base nosuchref
check "bad base: rc 1" [ "$RC" -eq 1 ]
check "usage: no worktree, no registry, no retro" bash -c "[ ! -e .harness/wt ] && [ '$(wt_dirs)' = 0 ] && [ ! -d .harness/retro ]"

# 5. --base, brief copy, memory link (kept via a dirty tree)
wsetup
echo two > a.txt && git commit -qam two
mkdir -p .harness && echo brief > .harness/task-analyst-x.md
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo x > dirty.txt"
hrun ask analyst "read .harness/task-analyst-x.md" --worktree --base HEAD~1
id=$(ask_id)
wt=$(jq -r .path ".harness/wt/$id.json")
check "base: worktree at the base commit" [ "$(git -C "$wt" rev-parse HEAD)" = "$(git rev-parse HEAD~1)" ]
check "base: registry base" [ "$(jq -r .base ".harness/wt/$id.json")" = "$(git rev-parse HEAD~1)" ]
check "base: detached" bash -c "! git -C '$wt' symbolic-ref -q HEAD"
check "brief: copied into the worktree" grep -q brief "$wt/.harness/task-analyst-x.md"
check "memory: agent-memory linked to main" [ "$(readlink "$wt/.claude/agent-memory")" = "$(cd "$WORK" && pwd -P)/.claude/agent-memory" ]
hrun close "$id" --force
check "base: closed" [ "$RC" -eq 0 ]
check "memory: main memory dir survives" [ -d "$WORK/.claude/agent-memory" ]

# 6. max_parallel and two same-role asks side by side
wsetup; export FAKE_CLAUDE_MODE=hang HARNESS_MAX_PARALLEL=2
( hrun ask analyst "qa" --worktree --timeout 60000; echo "$RC" > "$WORK/a.rc" ) &
wait_pid 1
( hrun ask analyst "qb" --worktree --timeout 60000; echo "$RC" > "$WORK/b.rc" ) &
wait_pid 2
check "parallel: two checkouts" [ "$(wt_dirs)" = 2 ]
check "parallel: distinct dirs" [ "$(ls -d "$WORK"/wtroot/*/* | sort -u | wc -l | tr -d ' ')" = 2 ]
check "parallel: two registry keys" [ "$(grep -c '^analyst@' .harness/panes)" = 2 ]
check "parallel: both running" [ "$(cat .harness/wt/*.json | jq -s '[.[] | select(.state == "running")] | length')" = 2 ]
hrun ask analyst "qc" --worktree
check "max_parallel: third refused (4)" [ "$RC" -eq 4 ]
check "max_parallel: says so" grep -q "max_parallel" <<<"$OUT"
check "max_parallel: nothing created for it" [ "$(wt_dirs)" = 2 ]
hrun status
check "parallel: status lists both" [ "$(grep -cE '^analyst@[0-9a-f]{8} +running' <<<"$OUT")" = 2 ]
hrun close "$(basename "$(ls .harness/wt/*.json | head -n 1)" .json)"
check "parallel: close without --force refuses a live run" [ "$RC" -eq 4 ]
for f in .harness/wt/*.json; do hrun close "$(basename "$f" .json)" --force; done
wait
OUT="a=$(cat "$WORK/a.rc") b=$(cat "$WORK/b.rc")"
check "parallel: both asks returned 3" [ "$(cat "$WORK/a.rc")$(cat "$WORK/b.rc")" = 33 ]
check "parallel: all removed" [ "$(wt_dirs)" = 0 ]

# 7. plain asks are untouched
wsetup
hrun ask analyst "plain"
check "plain: rc 0" [ "$RC" -eq 0 ]
check "plain: no worktree state" bash -c "[ ! -e .harness/wt ] && [ '$(wt_dirs)' = 0 ]"
check "plain: report in the main root" [ -f .harness/reports/analyst.md ]

# 8. the conductor gate denies reading source under the worktree home
payload=$(jq -n --arg p "$HOME/.cache/harness/wt/abcd1234/analyst-12345678/bin/harness" '{tool_name:"Read",cwd:"/repo",tool_input:{file_path:$p}}')
got=$(printf '%s' "$payload" | HERDR_ENV=1 HARNESS_ROLE=conductor /bin/bash "$GATE" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // empty')
OUT="gate said: $got"
check "gate: Read under wt home denied" [ "$got" = deny ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
