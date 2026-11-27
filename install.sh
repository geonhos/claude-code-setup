#!/bin/bash
# install.sh — symlink agents, skills and the harness CLI into ~/.claude and ~/.local/bin and merge
# the hooks and env into settings.json. Idempotent; prunes dangling links and hooks left by a moved
# checkout. `--test` runs the suites in parallel and exits.
# `--uninstall [--dry-run] [--force]` removes what this checkout installed (links, the three hooks, the
# four settings keys when still at their install value) and nothing else; --dry-run only lists, --force
# skips the live harness-run guard. Backups (*.bak.<ts>) are left in place.
# Overridable for tests: CLAUDE_DIR, BIN_DIR; HARNESS_UNINSTALL_PS (file used instead of `ps` output)
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

# --- ownership rules shared by install (prune) and --uninstall -----------------------------------
HOOK_BASES="conductor-gate.sh conductor-resume.sh notify-decision.sh"

# link_suffix <kind> <name>: the repo-relative path (with leading /) when <name> exists in this checkout
link_suffix() {
  case "$1" in
    agents) if [ -f "$REPO/claude/agents/$2" ]; then echo "/claude/agents/$2"; fi ;;
    skills) if [ -f "$REPO/claude/skills/$2/SKILL.md" ]; then echo "/claude/skills/$2"; fi ;;
    bin)    if [ -f "$REPO/bin/$2" ]; then echo "/bin/$2"; fi ;;
  esac
}

# dangling_shaped <dest> <suffix>: dest is a dangling symlink whose target ends in <suffix>
dangling_shaped() {
  [ -L "$1" ] && [ ! -e "$1" ] || return 1
  case "$(readlink "$1" || true)" in *"$2") return 0 ;; esac
  return 1
}

# classify_hook <command>: ours (this checkout's path) | stale (harness-shaped bare path that is gone)
# | foreign (harness-shaped path of another existing checkout) | other (never touched)
classify_hook() {
  local c=$1 b
  case "$c" in /*) ;; *) echo other; return 0 ;; esac
  # ours first: an exact match is ours whatever characters $REPO holds (non-ASCII, space, glob characters)
  for b in $HOOK_BASES; do
    [ "$c" = "$REPO/claude/hooks/$b" ] && { echo ours; return 0; }
  done
  # a command with whitespace or shell metacharacters is a wrapper or has arguments: never ours to judge
  case "$c" in *[[:space:]]*) echo other; return 0 ;; esac
  case "$c" in *[\;\&\|\<\>\(\)\$\`\\\"\'\*\?\[\]\{\}\!\#~]*) echo other; return 0 ;; esac
  for b in $HOOK_BASES; do
    case "$c" in
      */claude/hooks/"$b") if [ -e "$c" ]; then echo foreign; else echo stale; fi; return 0 ;;
    esac
  done
  echo other
}

# hook_commands <settings-file>: "<event><TAB><command>" for every hook item
hook_commands() {
  jq -r '(.hooks // {}) | objects | to_entries[] | .key as $e
    | (.value | arrays | .[] | objects | .hooks? | arrays | .[] | objects | .command? | strings)
    | [$e, .] | @tsv' "$1"
}

# jq filter: drops the hook items whose .command is in $rm; entries and event arrays it empties go too
HOOK_RM_JQ='
  def hit: type == "object" and ((.command // null) as $c | $c != null and ($rm | index($c)) != null);
  def touched: type == "object" and ((.hooks | type) == "array") and any(.hooks[]; hit);
  def clean: if touched then (.hooks |= map(select(hit | not))) | select((.hooks | length) > 0) else . end;
  if (.hooks | type) == "object" then
    .hooks |= (to_entries | map(
      if (.value | type) == "array" and (.value | any(.[]; touched))
      then (.value |= map(clean)) | select((.value | length) > 0) else . end) | from_entries)
  else . end'

# json_list: stdin lines -> JSON array of strings
json_list() { jq -R -s 'split("\n") | map(select(length > 0))'; }

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

if [ "${1:-}" = "--uninstall" ]; then
  need jq
  shift
  dry=0; force=0
  for a in "$@"; do
    case "$a" in
      --dry-run) dry=1 ;;
      --force) force=1 ;;
      *) die "usage: install.sh --uninstall [--dry-run] [--force]" ;;
    esac
  done
  # validate before modifying anything (same checks as install); a missing settings.json means links only
  if [ -f "$SETTINGS" ]; then
    jq -e . "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS is not valid JSON; fix it before uninstalling"
    jq -se 'length == 1 and (.[0] | type == "object")' "$SETTINGS" >/dev/null 2>&1 \
      || die "$SETTINGS is not a JSON object (or holds more than one value); fix it before uninstalling"
  fi
  # live-run guard: the links and harness-verify are global, so any harness-run on the machine counts
  if [ "$dry" -eq 0 ] && [ "$force" -eq 0 ]; then
    if [ -n "${HARNESS_UNINSTALL_PS:-}" ] && [ ! -r "$HARNESS_UNINSTALL_PS" ]; then
      die "HARNESS_UNINSTALL_PS=$HARNESS_UNINSTALL_PS is not a readable file"
    fi
    if { if [ -n "${HARNESS_UNINSTALL_PS:-}" ]; then cat "$HARNESS_UNINSTALL_PS"; else ps -axo pid=,command=; fi; } 2>/dev/null \
      | awk '{ for (i = 2; i <= 3 && i <= NF; i++) { n = split($i, p, "/"); if (p[n] == "harness-run") f = 1 } } END { exit !f }'; then
      die "a harness-run process is alive; its worker would lose harness-verify. Wait for it, or pass --force"
    fi
  fi
  verb="remove"
  nact=0

  # U1-U3: links
  for kind in agents skills bin; do
    dir="$CLAUDE_DIR/$kind"; [ "$kind" != bin ] || dir="$BIN_DIR"
    for l in "$dir"/*; do
      [ -L "$l" ] || continue
      n=$(basename "$l")
      case "$n" in *.bak.*) continue ;; esac
      t=$(readlink "$l" || true)
      suf=$(link_suffix "$kind" "$n")
      own=0
      case "$t" in "$REPO"/*) own=1 ;; esac
      if [ "$own" -eq 0 ] && [ -n "$suf" ]; then
        case "$t" in
          *"$suf")
            if [ -e "$l" ]; then
              echo "warning: $l installed from ${t%"$suf"}; run its install.sh --uninstall" >&2
            else
              own=1
            fi ;;
        esac
      fi
      [ "$own" -eq 1 ] || continue
      echo "$verb link $l -> $t"
      [ "$dry" -eq 1 ] || rm -f "$l"
      nact=$((nact + 1))
    done
  done

  # U4-U5: settings.json
  if [ -f "$SETTINGS" ]; then
    rm_cmds=""; nset=0
    while IFS="$(printf '\t')" read -r ev cmd; do
      [ -n "$cmd" ] || continue
      case "$(classify_hook "$cmd")" in
        ours|stale) echo "$verb hook $ev $cmd"; rm_cmds="$rm_cmds$cmd
"; nset=$((nset + 1)) ;;
        foreign) echo "warning: hook $cmd belongs to another checkout; run its install.sh --uninstall" >&2 ;;
      esac
    done <<EOF
$(hook_commands "$SETTINGS")
EOF
    dels="[]"; envdel=0
    for kv in 'promptCacheTtl|1h' 'subagentPromptCacheTtl|1h' 'env.BASH_DEFAULT_TIMEOUT_MS|600000' 'env.BASH_MAX_TIMEOUT_MS|7200000'; do
      key=${kv%%|*}; val=${kv#*|}
      path=$(printf '%s' "$key" | jq -R -c 'split(".")')
      st=$(jq -r --argjson p "$path" --arg v "$val" '(try getpath($p) catch null) as $x | if $x == null then "absent" elif $x == $v then "equal" else "diff" end' "$SETTINGS")
      case "$st" in
        equal)
          echo "$verb key $key"; nset=$((nset + 1))
          dels=$(printf '%s' "$dels" | jq -c --argjson p "$path" '. + [$p]')
          case "$key" in env.*) envdel=1 ;; esac ;;
        diff) echo "keep key $key (value differs from the install value $val)" ;;
      esac
    done
    if [ "$nset" -gt 0 ]; then
      nact=$((nact + nset))
      if [ "$dry" -eq 0 ]; then
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        printf '%s' "$rm_cmds" | json_list > "$tmp.rm"
        jq --slurpfile rmf "$tmp.rm" --argjson dels "$dels" --argjson envdel "$envdel" '
          ($rmf[0]) as $rm | delpaths($dels)
          | if $envdel == 1 and (.env | type) == "object" and (.env | length) == 0 then del(.env) else . end
          | '"$HOOK_RM_JQ" "$SETTINGS" > "$tmp"
        rm -f "$tmp.rm"
        bak="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
        cp "$SETTINGS" "$bak"
        cat "$tmp" > "$SETTINGS" || die "failed to write $SETTINGS; restore from $bak"
        echo "settings backup: $bak"
      fi
    fi
  fi

  if [ "$nact" -eq 0 ]; then echo "nothing to remove"; exit 0; fi
  baks=""
  for b in "$SETTINGS".bak.* "$CLAUDE_DIR"/agents/*.bak.* "$CLAUDE_DIR"/skills.bak/*; do
    { [ -e "$b" ] || [ -L "$b" ]; } && baks="$baks$b
"
  done
  if [ -n "$baks" ]; then
    echo "left in place: $(printf '%s' "$baks" | grep -c .) backup file(s):"
    printf '%s' "$baks" | sed 's/^/  /'
  fi
  echo "quit running conductor sessions before uninstalling or moving the checkout: their gate hook is gone or dangling afterwards."
  echo "per-repo 'harness init' state (.harness/, agent: conductor in settings) is untouched; see the README to revert it by hand."
  [ "$dry" -eq 0 ] || echo "dry run: nothing was changed"
  exit 0
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
  # a dangling link of this repo's shape (left by a moved checkout) is replaced without a backup
  if dangling_shaped "$2" "${1#"$REPO"}"; then rm -f "$2"; fi
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
trap 'rm -f "$tmp" "$tmp.rm" "$tmp.pre"' EXIT
# stale hook items (harness-shaped path that no longer exists) go first; another existing checkout's stay
rm_cmds=""
while IFS="$(printf '\t')" read -r ev cmd; do
  [ -n "$cmd" ] || continue
  case "$(classify_hook "$cmd")" in
    stale) rm_cmds="$rm_cmds$cmd
" ;;
    foreign) echo "warning: hook $cmd belongs to another checkout; two gates run until its install.sh --uninstall is run" >&2 ;;
  esac
done <<EOF
$(hook_commands "$SETTINGS")
EOF
printf '%s' "$rm_cmds" | json_list > "$tmp.rm"
jq --slurpfile rmf "$tmp.rm" '($rmf[0]) as $rm | '"$HOOK_RM_JQ" "$SETTINGS" > "$tmp.pre"
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
' "$tmp.pre" > "$tmp"
cat "$tmp" > "$SETTINGS" || die "failed to write $SETTINGS; restore from $bak"

cat <<EOF
installed:
  hooks    gate, resume, notify -> $SETTINGS (backup: $bak)
  agents   $CLAUDE_DIR/agents/ ($(cd "$REPO/claude/agents" && ls *.md | tr '\n' ' '))
  skills   $CLAUDE_DIR/skills/ ($(cd "$REPO/claude/skills" && ls -d */ | tr -d / | tr '\n' ' '))
  harness  $BIN_DIR/{harness,harness-verify,harness-run,harness-view}
next: run "harness init" in a repo to opt it in, then start Claude there.
EOF
