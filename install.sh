#!/bin/bash
# install.sh — wire this repo into ~/.claude as the conductor setup:
# agent and skill symlinks, the harness CLI, and settings.json (gate hook,
# resume hook, routing-log hook, cache TTLs, Bash timeouts, and the `agent`
# key that makes `conductor` the default role).
# Idempotent. Re-run after pulling changes.
#
#   ./install.sh          install
#   ./install.sh --test   run the test suites (in parallel) and exit
#                         HARNESS_TEST_SERIAL=1 runs them one at a time;
#                         HARNESS_TEST_TIMEOUT=N caps each suite (default 300 s)
#
# Overridable for tests: CLAUDE_DIR, BIN_DIR, GIT_IGNORE, SKIP_HERDR_INTEGRATION=1
set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
CLAUDE_DIR=${CLAUDE_DIR:-$HOME/.claude}
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}
GIT_IGNORE=${GIT_IGNORE:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}
SETTINGS="$CLAUDE_DIR/settings.json"
GATE="$REPO/claude/hooks/conductor-gate.sh"
RESUME="$REPO/claude/hooks/conductor-resume.sh"
ROUTE="$REPO/claude/hooks/conductor-route.sh"
MATCHER="Edit|Write|NotebookEdit|Read|Grep|Glob|Bash|Agent|Workflow|Monitor|mcp__filesystem__.*"

die() { echo "install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not on PATH"; }

if [ "${1:-}" = "--test" ]; then
  # Suites run in parallel (each buffers to its own file; output is printed per
  # suite in finish order). HARNESS_TEST_SERIAL=1 runs them one by one, still
  # running every suite. Each suite has a wall-clock limit (HARNESS_TEST_TIMEOUT,
  # seconds, default 300); a suite over it has its process tree killed and is
  # reported as failed. HARNESS_TESTS_DIR points the runner at another directory
  # of *.test.sh files (used by the runner's own tests; skips the wiki-lint step).
  tests_dir=${HARNESS_TESTS_DIR:-$REPO/tests}
  limit=${HARNESS_TEST_TIMEOUT:-300}
  case "$limit" in ''|*[!0-9]*) limit=300 ;; esac
  if [ -n "${HARNESS_TESTS_DIR:-}" ]; then
    echo "install: HARNESS_TESTS_DIR set: running suites from $tests_dir; wiki-lint skipped" >&2
    names=""
    for f in "$tests_dir"/*.test.sh; do
      [ -e "$f" ] || continue
      b=$(basename "$f"); names="$names ${b%.test.sh}"
    done
    names=${names# }
  else
    names="gate harness verify progress route install wiki retro wikilint"
  fi
  tdir=$(mktemp -d)
  descendants() {  # descendants PID — every transitive child, one per line
    local c
    for c in $(pgrep -P "$1" 2>/dev/null || true); do echo "$c"; descendants "$c"; done
  }
  killtree() {  # killtree PID — stop PID first (so it cannot record a result), then its tree
    local rest
    rest=$(descendants "$1" | tr '\n' ' ')
    kill -TERM "$1" 2>/dev/null || true
    [ -z "$rest" ] || kill -TERM $rest 2>/dev/null || true
    sleep 0.3
    kill -KILL "$1" $rest 2>/dev/null || true
  }
  kill_all() {
    local f
    for f in "$tdir"/*.pid; do
      [ -e "$f" ] || continue
      killtree "$(cat "$f")"
    done
  }
  trap 'rm -rf "$tdir"' EXIT
  trap 'kill_all; exit 130' INT
  trap 'kill_all; exit 143' TERM
  run_one() {  # run_one NAME — output to $tdir/NAME.out, exit code to $tdir/NAME.rc (always written)
    set +e  # a failing suite must still record its exit code
    case "$1" in
      wikilint) /bin/bash "$REPO/bin/harness" wiki-lint "$REPO/docs/wiki" ;;  # the real wiki: a bad page fails CI
      *) /bin/bash "$tests_dir/$1.test.sh" ;;
    esac > "$tdir/$1.out" 2>&1
    local r=$?
    echo "$r" > "$tdir/$1.rc.tmp"
    mv "$tdir/$1.rc.tmp" "$tdir/$1.rc"
  }
  rc=0; failed=""
  report() {  # report NAME — print its block, record failure
    local r
    r=$(cat "$tdir/$1.rc")
    rm -f "$tdir/$1.pid"  # finished: its pid may be reused, kill_all must not touch it
    echo "=== $1 ==="; cat "$tdir/$1.out"
    if [ "$r" != 0 ]; then rc=1; failed="$failed $1"; echo "--- $1 FAILED (exit $r) ---"; fi
  }
  maxjobs=1000
  [ "${HARNESS_TEST_SERIAL:-0}" != 1 ] || maxjobs=1
  queue=$names; running=""; nrun=0
  while [ -n "$queue" ] || [ -n "$running" ]; do
    while [ -n "$queue" ] && [ "$nrun" -lt "$maxjobs" ]; do
      n=${queue%% *}
      case "$queue" in *" "*) queue=${queue#* } ;; *) queue="" ;; esac
      run_one "$n" &
      echo $! > "$tdir/$n.pid"
      date +%s > "$tdir/$n.start"
      running="$running $n"; nrun=$((nrun + 1))
    done
    still=""; nrun=0; now=$(date +%s)
    for n in $running; do
      pid=$(cat "$tdir/$n.pid")
      if [ -f "$tdir/$n.rc" ]; then
        report "$n"
      elif ! kill -0 "$pid" 2>/dev/null; then
        if [ ! -f "$tdir/$n.rc" ]; then  # died without recording (e.g. killed from outside)
          echo "suite process $pid vanished without an exit code" >> "$tdir/$n.out"
          echo 1 > "$tdir/$n.rc"
        fi
        report "$n"
      elif [ $((now - $(cat "$tdir/$n.start"))) -ge "$limit" ]; then
        killtree "$pid"
        echo "suite $n timed out after ${limit}s (killed)" >> "$tdir/$n.out"
        echo 124 > "$tdir/$n.rc"
        report "$n"
      else
        still="$still $n"; nrun=$((nrun + 1))
      fi
    done
    running=${still# }
    [ -z "$queue" ] && [ -z "$running" ] || sleep 0.2
  done
  wait
  [ -z "$failed" ] || echo "FAILED suites:$failed"
  exit $rc
fi

need jq
if [ "${SKIP_HERDR_INTEGRATION:-0}" != 1 ]; then
  need herdr
fi

# 0. validate before modifying anything
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq -e . "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS is not valid JSON; fix it before installing"
jq -se 'length == 1 and (.[0] | type == "object")' "$SETTINGS" >/dev/null 2>&1 \
  || die "$SETTINGS is not a JSON object (or holds more than one value); fix it before installing"

# 1. herdr's Claude integration first: it may rewrite settings.json itself,
#    and our merge below must see the result.
if [ "${SKIP_HERDR_INTEGRATION:-0}" != 1 ]; then
  if herdr_out=$(herdr integration install claude 2>&1); then
    echo "herdr: claude integration installed"
  else
    echo "warning: 'herdr integration install claude' failed; agent state detection falls back to heuristics" >&2
    echo "$herdr_out" >&2
  fi
fi

# 2. agents + skills + harness symlinks
mkdir -p "$CLAUDE_DIR/agents" "$BIN_DIR"
for f in "$REPO"/claude/agents/*.md; do
  [ -e "$f" ] || continue
  dest="$CLAUDE_DIR/agents/$(basename "$f")"
  if { [ -e "$dest" ] || [ -L "$dest" ]; } && [ "$(readlink "$dest" || true)" != "$f" ]; then
    abak="$dest.bak.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$abak"
    echo "warning: $dest existed and was backed up to $abak" >&2
  fi
  ln -sfn "$f" "$dest"
done
mkdir -p "$CLAUDE_DIR/skills"
for d in "$REPO"/claude/skills/*/; do
  d=${d%/}
  [ -f "$d/SKILL.md" ] || continue
  dest="$CLAUDE_DIR/skills/$(basename "$d")"
  if { [ -e "$dest" ] || [ -L "$dest" ]; } && [ "$(readlink "$dest" || true)" != "$d" ]; then
    mkdir -p "$CLAUDE_DIR/skills.bak"
    sbak="$CLAUDE_DIR/skills.bak/$(basename "$d").$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$sbak"
    echo "warning: $dest existed and was backed up to $sbak" >&2
  fi
  ln -sfn "$d" "$dest"
done
ln -sfn "$REPO/bin/harness" "$BIN_DIR/harness"
ln -sfn "$REPO/bin/harness-verify" "$BIN_DIR/harness-verify"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "warning: $BIN_DIR is not on PATH; add it so the conductor can run 'harness'" >&2 ;;
esac

# 3. settings.json: default agent + cache TTLs + exactly one entry each for the gate, resume and route hooks
bak="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$bak"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq --arg gate "$GATE" --arg matcher "$MATCHER" --arg resume "$RESUME" --arg route "$ROUTE" '
  .agent = "conductor"
  | .promptCacheTtl = "1h"
  | .subagentPromptCacheTtl = "1h"
  | .env //= {}
  | .env.BASH_DEFAULT_TIMEOUT_MS = "600000"
  | .env.BASH_MAX_TIMEOUT_MS = "1800000"
  | .hooks //= {}
  | .hooks.PreToolUse //= []
  # strip our gate from every entry; drop entries left empty; re-append one canonical entry
  | .hooks.PreToolUse |= map(if any(.hooks[]?; .command == $gate) then (.hooks |= map(select(.command != $gate))) | select((.hooks | length) > 0) else . end)
  | .hooks.PreToolUse += [{matcher: $matcher, hooks: [{type: "command", command: $gate}]}]
  # same for the SessionStart resume hook (other SessionStart hooks stay)
  | .hooks.SessionStart //= []
  | .hooks.SessionStart |= map(if any(.hooks[]?; .command == $resume) then (.hooks |= map(select(.command != $resume))) | select((.hooks | length) > 0) else . end)
  | .hooks.SessionStart += [{matcher: "startup|clear|compact", hooks: [{type: "command", command: $resume}]}]
  # same for the UserPromptSubmit routing-log hook (no matcher: every prompt)
  | .hooks.UserPromptSubmit //= []
  | .hooks.UserPromptSubmit |= map(if any(.hooks[]?; .command == $route) then (.hooks |= map(select(.command != $route))) | select((.hooks | length) > 0) else . end)
  | .hooks.UserPromptSubmit += [{hooks: [{type: "command", command: $route}]}]
' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS" || die "failed to write $SETTINGS; restore from $bak"

# 4. global gitignore
mkdir -p "$(dirname "$GIT_IGNORE")"
touch "$GIT_IGNORE"
if ! grep -qxF '.harness/' "$GIT_IGNORE"; then
  if [ -s "$GIT_IGNORE" ] && [ -n "$(tail -c1 "$GIT_IGNORE")" ]; then printf '\n' >> "$GIT_IGNORE"; fi
  printf '.harness/\n' >> "$GIT_IGNORE"
fi

cat <<EOF
installed:
  gate hook      $GATE  (matcher: $MATCHER)
  resume hook    $RESUME  (SessionStart: startup|clear|compact)
  route hook     $ROUTE  (UserPromptSubmit: logs prompts to .harness/routing.jsonl)
  agents         $CLAUDE_DIR/agents/ ($(cd "$REPO/claude/agents" && ls *.md | tr '\n' ' '))
  skills         $CLAUDE_DIR/skills/ ($(cd "$REPO/claude/skills" && ls -d */ | tr -d / | tr '\n' ' '))
  harness        $BIN_DIR/harness
  harness-verify $BIN_DIR/harness-verify
  settings       $SETTINGS (backup: $bak)
  agent          settings.agent = conductor (workers override with --agent <name>)
  cache TTL      promptCacheTtl=1h subagentPromptCacheTtl=1h
  bash timeouts  env.BASH_DEFAULT_TIMEOUT_MS=600000 env.BASH_MAX_TIMEOUT_MS=1800000
  gitignore      $GIT_IGNORE (+ .harness/)
next: start Claude inside a herdr pane and give it work. Escape hatch: HARNESS_ROLE=worker claude --agent solo
EOF
