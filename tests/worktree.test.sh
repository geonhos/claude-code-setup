#!/bin/bash
# Worktree asks (decision 0008, S1): bin/harness ask --worktree for headless analyst/reviewer against
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
  # the worktree home must be outside the repo (harness refuses otherwise); .harness/ is never committed
  WTROOT="$WORK.wt"; WORKS="$WORKS $WTROOT"
  mkdir -p .git/info && echo '.harness/' >> .git/info/exclude
  export HARNESS_WT_ROOT="$WTROOT" HARNESS_NO_AUTOCLOSE=1 MAINROOT="$WORK"
  unset HARNESS_MAX_PARALLEL
  export FAKE_CLAUDE_MODE=success
  # the fake claude runs with cwd = the worktree: relative paths
  export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md"
}
ask_id() { sed -n 's/^harness: ask \([^ ]*\) .*/\1/p' <<<"$OUT" | head -n 1; }
jqt() { jq -e "$@" >/dev/null; }
wt_dirs() { ls -d "$WTROOT"/*/* 2>/dev/null | wc -l | tr -d ' '; }
wait_reg() { # N — until N registry entries exist
  local i=0; while [ $i -lt 60 ] && [ "$(ls .harness/wt/*.json 2>/dev/null | wc -l | tr -d ' ')" -lt "$1" ]; do sleep 0.2; i=$((i + 1)); done
}
wait_panes() { # N — until N worktree asks registered their viewer pane (the barrier for registry assertions)
  local i=0 n=0
  while [ $i -lt 150 ]; do
    n=$(grep -c '^analyst@' .harness/panes 2>/dev/null)   # empty while the registry file does not exist yet
    [ "${n:-0}" -lt "$1" ] || break
    sleep 0.2; i=$((i + 1))
  done
}
wait_pid() { # until the nth run announced itself (30 s cap: a loaded machine starts them slowly)
  local i=0; while [ $i -lt 150 ] && [ "$(ls "$WTROOT"/*/*/.harness/asks/analyst.pid 2>/dev/null | wc -l | tr -d ' ')" -lt "$1" ]; do sleep 0.2; i=$((i + 1)); done
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
echo beyond > "$(jq -r .path ".harness/wt/$id.json")/beyond.txt"   # more than the saved patch holds
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
hrun ask analyst "q" --worktree --base nosuchref
check "bad base: rc 1" [ "$RC" -eq 1 ]
hrun ask analyst "q" --base HEAD
check "base without worktree: rc 1" [ "$RC" -eq 1 ]
check "base without worktree: says so" grep -q "only with --worktree" <<<"$OUT"
HARNESS_WT_ROOT="$WORK/inrepo" hrun ask analyst "q" --worktree
check "wt root inside the repo: rc 1" [ "$RC" -eq 1 ]
check "wt root inside the repo: says so" grep -q "HARNESS_WT_ROOT" <<<"$OUT"
HARNESS_WT_ROOT="relative/wt" hrun ask analyst "q" --worktree
check "wt root relative: rc 1" [ "$RC" -eq 1 ]
HARNESS_WT_ROOT="$WTROOT/.harness/x" hrun ask analyst "q" --worktree
check "wt root in a .harness dir: rc 1" [ "$RC" -eq 1 ]
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
check "parallel: distinct dirs" [ "$(ls -d "$WTROOT"/*/* | sort -u | wc -l | tr -d ' ')" = 2 ]
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


# 9. brief copy follows .harness/ paths named inside the copied brief (one level)
wsetup
mkdir -p .harness && echo "design is in .harness/spec-x.md" > .harness/task-analyst-y.md && echo specbody > .harness/spec-x.md
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\nspec=%s\n' \"\$(cat .harness/spec-x.md)\" > .harness/reports/analyst.md"
hrun ask analyst "read .harness/task-analyst-y.md" --worktree
check "nested brief: rc 0" [ "$RC" -eq 0 ]
check "nested brief: the spec named in the brief is in the worktree" grep -q "spec=specbody" <<<"$OUT"

# 10. .harness/*.md results written in the worktree come back to the main .harness/
wsetup
mkdir -p .harness && echo "a v1" > .harness/design-a.md && echo "b v1" > .harness/design-b.md && echo brief > .harness/task-analyst-z.md
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo detail > .harness/out-detail.md && echo 'a v2' > .harness/design-a.md && echo 'b v2' > .harness/design-b.md && echo 'b main' > \$MAINROOT/.harness/design-b.md && echo changed > .harness/task-analyst-z.md"
hrun ask analyst "read .harness/task-analyst-z.md, .harness/design-a.md and .harness/design-b.md" --worktree
id=$(ask_id); id8=$(jq -r .id8 ".harness/wt/$id.json")
check "copy-back: rc 0" [ "$RC" -eq 0 ]
check "copy-back: new file comes back" grep -q detail .harness/out-detail.md
check "copy-back: changed file (main untouched) overwritten" grep -q "a v2" .harness/design-a.md
check "copy-back: main-changed file kept" grep -q "b main" .harness/design-b.md
check "copy-back: worker version beside it" grep -q "b v2" ".harness/design-b.$id8.md"
check "copy-back: says so" grep -q "design-b.$id8.md" <<<"$OUT"
check "copy-back: task files are not copied back" grep -q brief .harness/task-analyst-z.md
check "copy-back: checkout removed after" [ "$(wt_dirs)" = 0 ]

# 11. other edits in the worktree come back as a patch; the checkout is kept
wsetup
export FAKE_REPORT_CMD="mkdir -p .harness/reports docs && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo plan > docs/plan.md && echo two >> a.txt && printf '\\000\\001bin' > bin.dat"
hrun ask analyst "q11" --worktree
id=$(ask_id)
check "patch: rc 0" [ "$RC" -eq 0 ]
check "patch: file in main .harness/wt" [ -s ".harness/wt/$id.patch" ]
check "patch: names the untracked file" grep -q "docs/plan.md" ".harness/wt/$id.patch"
check "patch: names the tracked change" grep -q "a.txt" ".harness/wt/$id.patch"
check "patch: applies to the main tree" git apply --check ".harness/wt/$id.patch"
check "patch: warning with its path in the output" grep -q "wt/$id.patch" <<<"$OUT"
check "patch: worktree kept" jqt '.state == "kept"' ".harness/wt/$id.json"
check "patch: worktree still there" [ "$(wt_dirs)" = 1 ]
hrun close "$id" --force

# 12. registry hygiene: old terminal entries and their reports are deleted; stale running reaped
wsetup
mkdir -p .harness/wt
echo '{"id":"old1","id8":"aaaaaaaa","role":"analyst","path":"/nonexistent","state":"closed"}' > .harness/wt/old1.json
echo r > .harness/wt/old1.report.md
echo '{"id":"new1","id8":"bbbbbbbb","role":"analyst","path":"/nonexistent","state":"closed"}' > .harness/wt/new1.json
touch -t 202001010000 .harness/wt/old1.json .harness/wt/old1.report.md
HARNESS_NO_AUTOCLOSE=0 hrun status
check "reap: old closed registry entry deleted" [ ! -e .harness/wt/old1.json ]
check "reap: its saved report deleted" [ ! -e .harness/wt/old1.report.md ]
check "reap: recent closed entry kept" [ -e .harness/wt/new1.json ]
# a `running` entry whose owner is dead (reboot) is reaped like a kept one
git worktree add -q --detach "$WTROOT/r8/analyst-dead0001" HEAD
printf '{"id":"dead1","id8":"dead0001","role":"analyst","path":"%s","pid":999999,"state":"running","created_s":1}\n' "$WTROOT/r8/analyst-dead0001" > .harness/wt/dead1.json
touch -t 202001010000 .harness/wt/dead1.json
HARNESS_NO_AUTOCLOSE=0 hrun status
check "stale running: checkout removed" [ ! -d "$WTROOT/r8/analyst-dead0001" ]
check "stale running: state reaped" jqt '.state == "reaped"' .harness/wt/dead1.json

# 13. a close --force result is not overwritten by the late post-ask handling
wsetup
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo x > dirty.txt"
hrun ask analyst "q13" --worktree
id=$(ask_id)
jq '.state = "closed"' ".harness/wt/$id.json" > "$WORK/reg.tmp" && mv "$WORK/reg.tmp" ".harness/wt/$id.json"
hrun report "$id"
check "closed stays closed after a late report" jqt '.state == "closed"' ".harness/wt/$id.json"
git worktree remove --force "$(jq -r .path ".harness/wt/$id.json")"

# 14. a failure after `git worktree add` leaves no worktree behind
wsetup
blob=$(echo x | git hash-object -w --stdin)
tree=$(printf '100644 blob %s\t.harness\n' "$blob" | git mktree)
bad=$(git commit-tree "$tree" -m filebase)
hrun ask analyst "q14" --worktree --base "$bad"
check "create failure: rc 1" [ "$RC" -eq 1 ]
check "create failure: no checkout left" [ "$(wt_dirs)" = 0 ]
check "create failure: git forgot it" [ "$(git worktree list | wc -l | tr -d ' ')" = 1 ]

# 15. close --all handles worktree asks (live refused without --force)
wsetup; export FAKE_CLAUDE_MODE=hang
( hrun ask analyst "q15" --worktree --timeout 60000; echo "$RC" > "$WORK/a.rc" ) &
wait_pid 1
hrun close --all
check "close --all: live worktree ask refused (4)" [ "$RC" -eq 4 ]
check "close --all: still there" [ "$(wt_dirs)" = 1 ]
hrun close --all --force
check "close --all --force: rc 0" [ "$RC" -eq 0 ]
check "close --all --force: removed" [ "$(wt_dirs)" = 0 ]
wait

# 16. a worktree ask beside a plain ask of the same role
wsetup; export FAKE_CLAUDE_MODE=hang
( hrun ask analyst "q16" --worktree --timeout 60000; echo "$RC" > "$WORK/a.rc" ) &
wait_pid 1
FAKE_CLAUDE_MODE=success hrun ask analyst "plain16"
check "mixed: plain ask rc 0" [ "$RC" -eq 0 ]
check "mixed: plain report in the main root" [ -f .harness/reports/analyst.md ]
check "mixed: worktree ask still running" [ "$(wt_dirs)" = 1 ]
check "mixed: panes hold both keys" bash -c "grep -q '^analyst@' .harness/panes"
for f in .harness/wt/*.json; do hrun close "$(basename "$f" .json)" --force; done
check "mixed: worktree ask closed" [ "$(wt_dirs)" = 0 ]
wait

# 17. five asks started at once register five panes (locked registry)
wsetup; export FAKE_CLAUDE_MODE=hang HARNESS_MAX_PARALLEL=6
for i in 1 2 3 4 5; do ( hrun ask analyst "q17-$i" --worktree --timeout 60000 >/dev/null ) & done
wait_panes 5
wait_pid 5
check "panes: five registered" [ "$(grep -c '^analyst@' .harness/panes)" = 5 ]
for f in .harness/wt/*.json; do hrun close "$(basename "$f" .json)" --force; done
wait

# 18. a late report of a worktree ask is archived under its own key and log name
wsetup
hrun ask analyst "plain18"
export FAKE_CLAUDE_MODE=noreport
hrun ask analyst "q18" --worktree
id=$(ask_id); id8=$(jq -r .id8 ".harness/wt/$id.json")
mkdir -p "$(jq -r .path ".harness/wt/$id.json")/.harness/reports"
cp .harness/reports/analyst.md "$(jq -r .path ".harness/wt/$id.json")/.harness/reports/analyst.md"
hrun report "$id"
check "late: log named with the id8" bash -c "ls .harness/log | grep -q -- -analyst-$id8-late"
check "late: jsonl line carries the ask id" bash -c "grep '\"late\":true' .harness/progress.jsonl | grep -q '$id'"
hrun close "$id" --force

# 19. kept worktree with a saved patch is never auto-reaped; close removes it, the patch survives
wsetup
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo plan > plan19.txt"
hrun ask analyst "q19" --worktree
id=$(ask_id); path=$(jq -r .path ".harness/wt/$id.json")
check "kept+patch: patch saved" [ -s ".harness/wt/$id.patch" ]
touch -t 202001010000 ".harness/wt/$id.json" ".harness/wt/$id.patch"
HARNESS_NO_AUTOCLOSE=0 HARNESS_IDLE_TTL_MIN=1 HARNESS_LOG_DAYS=1 hrun status
HARNESS_NO_AUTOCLOSE=0 HARNESS_IDLE_TTL_MIN=1 HARNESS_LOG_DAYS=1 hrun status
check "kept+patch: survives reap passes (checkout)" [ -d "$path" ]
check "kept+patch: survives reap passes (state)" jqt '.state == "kept"' ".harness/wt/$id.json"
check "kept+patch: survives LOG_DAYS (patch)" [ -s ".harness/wt/$id.patch" ]
check "kept+patch: status shows the patch path" grep -q "patch .*wt/$id.patch" <<<"$OUT"
hrun close "$id"
check "kept+patch: close without --force when nothing beyond the patch" [ "$RC" -eq 0 ]
check "kept+patch: checkout removed" [ ! -d "$path" ]
check "kept+patch: patch survives close" [ -s ".harness/wt/$id.patch" ]
# changes beyond the saved patch: close refuses without --force
hrun ask analyst "q19b" --worktree
id=$(ask_id); path=$(jq -r .path ".harness/wt/$id.json")
echo more > "$path/extra19.txt"
hrun close "$id"
check "kept+patch: more than the patch -> refused (4)" [ "$RC" -eq 4 ]
check "kept+patch: refused -> checkout stays" [ -d "$path" ]
hrun close "$id" --force
check "kept+patch: --force removes it" [ ! -d "$path" ]
# a clean kept entry without a patch is still reaped by the idle TTL
wsetup
git worktree add -q --detach "$WTROOT/r19/analyst-clean001" HEAD
mkdir -p .harness/wt
printf '{"id":"clean1","id8":"clean001","role":"analyst","path":"%s","pid":999999,"state":"kept","created_s":1}\n' "$WTROOT/r19/analyst-clean001" > .harness/wt/clean1.json
touch -t 202001010000 .harness/wt/clean1.json
HARNESS_NO_AUTOCLOSE=0 HARNESS_IDLE_TTL_MIN=1 hrun status
check "kept clean: reaped by TTL" [ ! -d "$WTROOT/r19/analyst-clean001" ]

# 20. copy-back allowlist: reserved names and symlinks stay in the worktree
wsetup
mkdir -p .harness && echo mine > .harness/goal.md && echo prog > .harness/progress.md && echo secret > "$WORK/outside20.txt"
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo hijack > .harness/goal.md && echo hijack > .harness/progress.md && echo hijack > .harness/task-new.md && ln -s $WORK/outside20.txt .harness/link20.md && echo ok > .harness/notes20.md"
hrun ask analyst "q20" --worktree
check "allowlist: rc 0" [ "$RC" -eq 0 ]
check "allowlist: goal.md untouched" grep -q '^mine$' .harness/goal.md
check "allowlist: progress.md not overwritten by the worker" not_grep hijack .harness/progress.md
check "allowlist: task-*.md not copied" [ ! -e .harness/task-new.md ]
check "allowlist: symlink not copied" [ ! -e .harness/link20.md ] && [ ! -L .harness/link20.md ]
check "allowlist: plain .md still copied" grep -q '^ok$' .harness/notes20.md

# 21. lock takeover: a dead owner, or an old ownerless lock, is taken over; no hang
wsetup
mkdir -p .harness/panes.lock && echo 999999 > .harness/panes.lock/owner
hrun ask analyst "q21a" --worktree
check "lock: dead owner taken over (rc 0)" [ "$RC" -eq 0 ]
mkdir -p .harness/panes.lock && touch -t 202001010000 .harness/panes.lock
hrun ask analyst "q21b" --worktree
check "lock: old ownerless lock taken over (rc 0)" [ "$RC" -eq 0 ]
check "lock: no stale dir left" bash -c "! ls .harness | grep -q 'panes.lock'"

# 22. HARNESS_WT_ROOT with a '..' component is rejected
wsetup
HARNESS_WT_ROOT="$WORK.wt/sub/../../escape22" hrun ask analyst "q22" --worktree
check "wt root with ..: rc 1" [ "$RC" -eq 1 ]
check "wt root with ..: says so" grep -q "'\.\.'" <<<"$OUT"

# 23. a saved patch survives a tree that was cleaned in place afterwards (close, late report)
wsetup
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo plan > plan23.txt"
hrun ask analyst "q23" --worktree
id=$(ask_id); path=$(jq -r .path ".harness/wt/$id.json")
check "patch kept: patch saved" [ -s ".harness/wt/$id.patch" ]
sum23=$(cksum < ".harness/wt/$id.patch")
rm -f "$path/plan23.txt"                      # cleaned in place: the patch is now the only copy
hrun report "$id"
check "patch kept: late report keeps the patch" [ "$(cksum < ".harness/wt/$id.patch")" = "$sum23" ]
if [ -d "$path" ]; then hrun close "$id"; else RC=0; fi
check "patch kept: close rc 0" [ "$RC" -eq 0 ]
check "patch kept: patch survives close" [ "$(cksum < ".harness/wt/$id.patch")" = "$sum23" ]
check "patch kept: checkout gone" [ ! -d "$path" ]

# 24. a commit the worker made in the detached checkout is saved in the patch; the tree is kept
wsetup
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo committed > c24.txt && printf '\\000\\001bin' > c24.dat && git add c24.txt c24.dat && git commit -qm worker"
hrun ask analyst "q24" --worktree
id=$(ask_id); path=$(jq -r .path ".harness/wt/$id.json")
check "commit: rc 0" [ "$RC" -eq 0 ]
check "commit: tree kept" [ -d "$path" ]
check "commit: registry kept" jqt '.state == "kept"' ".harness/wt/$id.json"
check "commit: patch names the committed file" grep -q "c24.txt" ".harness/wt/$id.patch"
check "commit: patch is binary-safe" grep -q "GIT binary patch" ".harness/wt/$id.patch"
check "commit: patch applies to the main tree" git apply --check ".harness/wt/$id.patch"
hrun close "$id"
check "commit: close without --force refuses nothing new (patch equals saved)" [ "$RC" -eq 0 ]
check "commit: patch survives close" grep -q "c24.txt" ".harness/wt/$id.patch"

# 25. lock owner pid reused by an unrelated live process: taken over, no hang
wsetup
sleep 300 & spid=$!
mkdir -p .harness/panes.lock && echo "$spid" > .harness/panes.lock/owner
hrun ask analyst "q25" --worktree
kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
check "lock reuse: rc 0" [ "$RC" -eq 0 ]
# a live harness-looking owner is honoured until HARNESS_LOCK_MAX_S, then taken over with a warning
cat > "$WORK/harness-owner.sh" <<'EOS'
#!/bin/bash
while :; do sleep 1; done
EOS
/bin/bash "$WORK/harness-owner.sh" & opid=$!
sleep 0.3
mkdir -p .harness/panes.lock && echo "$opid" > .harness/panes.lock/owner
HARNESS_LOCK_MAX_S=2 hrun ask analyst "q25b" --worktree
kill "$opid" 2>/dev/null; wait "$opid" 2>/dev/null
check "lock ceiling: rc 0" [ "$RC" -eq 0 ]
check "lock ceiling: warned" grep -q "taking it over" <<<"$OUT"

# 26. takeover with several contenders: mutual exclusion holds, nothing nests, nothing is left.
# Deterministic: mv and rm are shadowed by functions that sleep (rank-staggered), widening the gap
# between "judged stale" and "removed/renamed". main's lock_take (rename the stale dir, put it back
# when it was not the judged one) then moves a FRESH lock away and leaves a window with no lock, so
# a second contender enters the critical section while the first is still inside ("bad").
# Start barrier: the race needs >=2 contenders to judge the dead lock within ~0.2 s of each other, which
# a loaded machine's staggered forks defeat; each contender signals ready and waits for "go".
# The script name must contain "harness" (the real lock_stale checks the owner's command line).
wsetup
fn() { awk -v n="$1" '$0 ~ "^" n "\\(\\) \\{" { p = 1 } p { print } p && /^}$/ { p = 0 }' "$2"; }
cat > "$WORK/harness-contend.sh" <<'EOS'
#!/bin/bash
. "$1"; d=$2; w=$3; n=$4
: > "$w/r.$n"; while [ ! -e "$w/go" ]; do sleep 0.02; done   # start barrier: no start-up skew
mv() { sleep "0.$n"; command mv "$@"; }
rm() { sleep "0.$n"; command rm "$@"; }
lock_take "$d"
if mkdir "$w/in" 2>/dev/null; then sleep 0.7; rmdir "$w/in"; echo ok >> "$w/ok"; else echo bad >> "$w/bad"; fi
lock_drop "$d"
EOS
contend() { # contend <harness-file> <dir> — five contenders over a dead-owner lock
  { for f in digits_only file_mtime lock_stale lock_take; do fn "$f" "$1"; done; grep '^lock_drop()' "$1"; } > "$2/lockfns.sh"
  mkdir -p "$2/l" && mkdir "$2/l/lock" && echo 999999 > "$2/l/lock/owner"
  local i
  for i in 1 2 3 4 5; do /bin/bash "$WORK/harness-contend.sh" "$2/lockfns.sh" "$2/l/lock" "$2/l" "$i" 2>/dev/null & done
  barrier_go "$2/l"
  wait
}
barrier_go() { # barrier_go <dir> — release the contenders once all five are ready
  local k=0
  while [ "$(ls "$1" | grep -c '^r\.')" -lt 5 ] && [ $k -lt 200 ]; do sleep 0.05; k=$((k + 1)); done
  : > "$1/go"
}
mkdir -p "$WORK/new"; contend "$HARNESS" "$WORK/new"
check "contenders: all five got the lock" [ "$(wc -l < "$WORK/new/l/ok" | tr -d ' ')" = 5 ]
check "contenders: never two at once" [ ! -e "$WORK/new/l/bad" ]
check "contenders: no lock or takeover dir left" bash -c "[ -z \"\$(ls '$WORK/new/l' | grep -E '^lock')\" ]"
# the same scenario must FAIL on the pre-v19 lock_take (kept in the test as a fixture)
cat > "$WORK/oldlock.sh" <<'EOS'
digits_only() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
lock_stale() { :; }
lock_take() {
  local d=$1 i=0 own age mt stale
  while ! mkdir "$d" 2>/dev/null; do
    i=$((i + 1))
    if [ $((i % 10)) -eq 0 ]; then
      stale=0
      own=$(cat "$d/owner" 2>/dev/null)
      if digits_only "$own"; then
        kill -0 "$own" 2>/dev/null || stale=1
      elif mt=$(file_mtime "$d"); then
        age=$(( $(date +%s) - mt ))
        [ "$age" -le "${HARNESS_LOCK_STALE_S:-10}" ] || stale=1
      fi
      if [ "$stale" = 1 ] && mv "$d" "$d.stale.$$" 2>/dev/null; then
        if [ "$(cat "$d.stale.$$/owner" 2>/dev/null)" = "$own" ]; then
          rm -rf "$d.stale.$$"
        else
          mv "$d.stale.$$" "$d" 2>/dev/null || rm -rf "$d.stale.$$"
        fi
      fi
    fi
    sleep 0.05
  done
  echo $$ > "$d/owner" 2>/dev/null
  return 0
}
lock_drop() { rmdir "$1" 2>/dev/null || rm -rf "$1"; }
EOS
# one catch proves the scenario detects the bug, so only the OLD-code control is retried
caught=0
for k in 1 2 3; do
  mkdir -p "$WORK/old$k/l" && mkdir "$WORK/old$k/l/lock" && echo 999999 > "$WORK/old$k/l/lock/owner"
  for i in 1 2 3 4 5; do /bin/bash "$WORK/harness-contend.sh" "$WORK/oldlock.sh" "$WORK/old$k/l/lock" "$WORK/old$k/l" "$i" 2>/dev/null & done
  barrier_go "$WORK/old$k/l"
  wait
  if [ -e "$WORK/old$k/l/bad" ] || [ "$(wc -l < "$WORK/old$k/l/ok" 2>/dev/null | tr -d ' ')" != 5 ]; then caught=1; break; fi
done
check "contenders: the old rename/put-back takeover is caught (two at once or a lost holder)" [ "$caught" = 1 ]

# 27. lock ceiling counts the LOCK's age, not the waiter's wait: a lock just acquired is never stolen
wsetup
cat > "$WORK/harness-owner27.sh" <<'EOS'
#!/bin/bash
while :; do sleep 1; done
EOS
/bin/bash "$WORK/harness-owner27.sh" & o27=$!
sleep 0.3
{ for f in digits_only file_mtime lock_stale; do fn "$f" "$HARNESS"; done; } > "$WORK/stalefns.sh"
. "$WORK/stalefns.sh"
mkdir -p "$WORK/l27" && echo "$o27" > "$WORK/l27/owner"
# 5 is what an old waiter would pass as "waited"; the argument is ignored now
check "ceiling: fresh lock, live harness owner, long-waiting contender: not stale" bash -c ". '$WORK/stalefns.sh'; ! HARNESS_LOCK_MAX_S=3 lock_stale '$WORK/l27' 5 2>/dev/null"
perl -e 'utime(time - 5, time - 5, $ARGV[0])' "$WORK/l27/owner"
check "ceiling: the same lock held past the ceiling is stale" bash -c ". '$WORK/stalefns.sh'; HARNESS_LOCK_MAX_S=3 lock_stale '$WORK/l27' 0 2>/dev/null"
kill "$o27" 2>/dev/null; wait "$o27" 2>/dev/null

# 28. a worker commit that leaves the tree equal to the base has nothing to lose: removed
wsetup
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && git commit -q --allow-empty -m empty"
hrun ask analyst "q28" --worktree
id=$(ask_id); path=$(jq -r .path ".harness/wt/$id.json")
check "empty commit: rc 0" [ "$RC" -eq 0 ]
check "empty commit: checkout removed" [ ! -d "$path" ]
check "empty commit: registry collected" jqt '.state == "collected"' ".harness/wt/$id.json"
check "empty commit: no patch" [ ! -e ".harness/wt/$id.patch" ]
# ... and a commit that changes the tree is still kept
wsetup
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# analyst report\nstatus: done\n' > .harness/reports/analyst.md && echo x > c28.txt && git add c28.txt && git commit -qm real"
hrun ask analyst "q28b" --worktree
id=$(ask_id); path=$(jq -r .path ".harness/wt/$id.json")
check "real commit: still kept" [ -d "$path" ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
