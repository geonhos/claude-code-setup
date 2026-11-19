#!/bin/bash
# install.sh — symlink agents, skills and the harness CLI into ~/.claude and ~/.local/bin and merge
# the hooks and env into settings.json. Idempotent. `--test` runs the suites in parallel and exits.
# Overridable for tests: CLAUDE_DIR, BIN_DIR
set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
CLAUDE_DIR=${CLAUDE_DIR:-$HOME/.claude}
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}
SETTINGS="$CLAUDE_DIR/settings.json"
GATE="$REPO/claude/hooks/conductor-gate.sh"
RESUME="$REPO/claude/hooks/conductor-resume.sh"
NOTIFY="$REPO/claude/hooks/notify-decision.sh"
MATCHER="Edit|Write|Read|Grep|Glob|Bash"

die() { echo "install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not on PATH"; }

if [ "${1:-}" = "--test" ]; then
  # parallel by default; HARNESS_TEST_SERIAL=1 one by one; HARNESS_TEST_TIMEOUT=N seconds per suite (default 300);
  # HARNESS_TESTS_DIR points at another directory of *.test.sh files (skips the wiki-lint step)
  tests_dir=${HARNESS_TESTS_DIR:-$REPO/tests}
  limit=${HARNESS_TEST_TIMEOUT:-300}
  case "$limit" in ''|*[!0-9]*) limit=300 ;; esac
  # suites are discovered by glob: every <tests_dir>/*.test.sh (helper files such as
  # harness-lib.sh do not match); the real wiki check runs as the extra `wikilint`
  names=""
  for f in "$tests_dir"/*.test.sh; do
    [ -e "$f" ] || continue
    b=$(basename "$f"); names="$names ${b%.test.sh}"
  done
  names=${names# }
  if [ -n "${HARNESS_TESTS_DIR:-}" ]; then
    echo "install: HARNESS_TESTS_DIR set: running suites from $tests_dir; wiki-lint skipped" >&2
  else
    names="$names wikilint"
  fi
  # guard (#92): a suite must not register a worktree of the repo under test in a temp dir
  tmp_worktrees() { git -C "$REPO" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | grep -E '^(/private)?(/var/folders/|/tmp/|/var/tmp/)' || true; }
  wt_before=$(tmp_worktrees)
  tdir=$(mktemp -d "${TMPDIR:-/tmp}/harness-tests.XXXXXX")
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
  trap 'kill_all; exit 129' HUP
  run_one() {  # run_one NAME — output to $tdir/NAME.out, exit code to $tdir/NAME.rc (always written)
    set +e  # a failing suite must still record its exit code
    case "$1" in
      wikilint) /bin/bash "$REPO/bin/harness" wiki-lint "$REPO/docs/wiki" ;;  # the real wiki: a bad page fails CI
      *) /bin/bash "$tests_dir/$1.test.sh" ;;
    esac > "$tdir/$1.out" 2>&1
    local r=$?
    echo "$r" > "$tdir/$1.rc.tmp"
    mv "$tdir/$1.rc.tmp" "$tdir/$1.rc"
    rm -f "$tdir/$1.pid"  # finished: bash reaps us, so the pid may be reused; kill_all must not see it
  }
  rc=0; failed=""
  report() {  # report NAME — print its block, record failure
    local r
    r=$(cat "$tdir/$1.rc")
    rm -f "$tdir/$1.pid"  # backstop: run_one may finish before the parent wrote the pid file
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
      pid=$(cat "$tdir/$n.pid" 2>/dev/null || true)  # gone once run_one has finished
      if [ -f "$tdir/$n.rc" ]; then
        report "$n"
      elif [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
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
  wt_leak=$(tmp_worktrees | WT_BEFORE="$wt_before" awk 'BEGIN { n = split(ENVIRON["WT_BEFORE"], a, "\n"); for (i = 1; i <= n; i++) seen[a[i]] = 1 } !($0 in seen)')
  if [ -n "$wt_leak" ]; then
    echo "FAILED: the test run registered temp worktrees of $REPO (use a temp repo):"; echo "$wt_leak"
    rc=1; failed="$failed worktree-guard"
  fi
  [ -z "$failed" ] || echo "FAILED suites:$failed"
  exit $rc
fi

need jq

# 0. validate before modifying anything
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq -e . "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS is not valid JSON; fix it before installing"
jq -se 'length == 1 and (.[0] | type == "object")' "$SETTINGS" >/dev/null 2>&1 \
  || die "$SETTINGS is not a JSON object (or holds more than one value); fix it before installing"

# 2. agents + skills + harness symlinks
# link_item <src> <dest> <backup-prefix>: symlink; an existing different dest moves to <prefix>.<timestamp>
link_item() {
  local bak
  if { [ -e "$2" ] || [ -L "$2" ]; } && [ "$(readlink "$2" || true)" != "$1" ]; then
    mkdir -p "${3%/*}"; bak="$3.$(date +%Y%m%d%H%M%S)"
    mv "$2" "$bak"
    echo "warning: $2 existed and was backed up to $bak" >&2
  fi
  ln -sfn "$1" "$2"
}
mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/skills" "$BIN_DIR"
for f in "$REPO"/claude/agents/*.md; do
  [ -e "$f" ] && link_item "$f" "$CLAUDE_DIR/agents/$(basename "$f")" "$CLAUDE_DIR/agents/$(basename "$f").bak"
done
for d in "$REPO"/claude/skills/*/; do
  d=${d%/}
  [ -f "$d/SKILL.md" ] && link_item "$d" "$CLAUDE_DIR/skills/$(basename "$d")" "$CLAUDE_DIR/skills.bak/$(basename "$d")"
done
# bin/* by glob; lib/ needs no link: the scripts resolve their symlink back into the repo
for f in "$REPO"/bin/*; do
  [ -f "$f" ] && ln -sfn "$f" "$BIN_DIR/$(basename "$f")"
done
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "warning: $BIN_DIR is not on PATH; add it so the conductor can run 'harness'" >&2 ;;
esac

# 3. settings.json: cache TTLs + exactly one entry each for the gate, resume and notify hooks
bak="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$bak"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq --arg gate "$GATE" --arg matcher "$MATCHER" --arg resume "$RESUME" --arg notify "$NOTIFY" '
  .promptCacheTtl = "1h"
  | .subagentPromptCacheTtl = "1h"
  | .env //= {}
  | .env.BASH_DEFAULT_TIMEOUT_MS = "600000"
  | .env.BASH_MAX_TIMEOUT_MS = "7200000"
  # strip our command from every entry of an event; drop entries left empty; re-append one canonical entry
  | def hook($ev; $cmd; $m):
      .hooks[$ev] = ((.hooks[$ev] // [])
        | map(if any(.hooks[]?; .command == $cmd) then (.hooks |= map(select(.command != $cmd))) | select((.hooks | length) > 0) else . end)
        + [{matcher: $m, hooks: [{type: "command", command: $cmd}]}]);
  .hooks //= {}
  | hook("PreToolUse"; $gate; $matcher)
  | hook("SessionStart"; $resume; "startup|clear|compact")
  | hook("Notification"; $notify; "permission_prompt|idle_prompt|elicitation_dialog|elicitation_url_dialog|agent_needs_input")
' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS" || die "failed to write $SETTINGS; restore from $bak"

cat <<EOF
installed:
  hooks    gate, resume, notify -> $SETTINGS (backup: $bak)
  agents   $CLAUDE_DIR/agents/ ($(cd "$REPO/claude/agents" && ls *.md | tr '\n' ' '))
  skills   $CLAUDE_DIR/skills/ ($(cd "$REPO/claude/skills" && ls -d */ | tr -d / | tr '\n' ' '))
  harness  $BIN_DIR/{harness,harness-verify,harness-run,harness-view}
next: run "harness init" in a repo to opt it in, then start Claude there.
EOF
