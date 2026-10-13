#!/bin/bash
# install.sh — wire this repo into ~/.claude as the conductor setup.
# Idempotent. Re-run after pulling changes.
#
#   ./install.sh          install
#   ./install.sh --test   run the test suites and exit
#
# Overridable for tests: CLAUDE_DIR, BIN_DIR, GIT_IGNORE, SKIP_HERDR_INTEGRATION=1
set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
CLAUDE_DIR=${CLAUDE_DIR:-$HOME/.claude}
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}
GIT_IGNORE=${GIT_IGNORE:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}
SETTINGS="$CLAUDE_DIR/settings.json"
GATE="$REPO/claude/hooks/conductor-gate.sh"
IMPORT_LINE="@$REPO/claude/CLAUDE.conductor.md"
MATCHER="Edit|Write|NotebookEdit|Read|Grep|Glob|Bash|Agent|Workflow"

die() { echo "install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not on PATH"; }

if [ "${1:-}" = "--test" ]; then
  rc=0
  /bin/bash "$REPO/tests/gate.test.sh"    || rc=1
  /bin/bash "$REPO/tests/harness.test.sh" || rc=1
  /bin/bash "$REPO/tests/install.test.sh" || rc=1
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

# 2. agents + harness symlinks
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
ln -sfn "$REPO/bin/harness" "$BIN_DIR/harness"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "warning: $BIN_DIR is not on PATH; add it so the conductor can run 'harness'" >&2 ;;
esac

# 3. settings.json: cache TTLs + exactly one gate hook entry
bak="$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
cp "$SETTINGS" "$bak"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq --arg gate "$GATE" --arg matcher "$MATCHER" '
  .promptCacheTtl = "1h"
  | .subagentPromptCacheTtl = "1h"
  | .hooks //= {}
  | .hooks.PreToolUse //= []
  # strip our gate from every entry; drop entries left empty; re-append one canonical entry
  | .hooks.PreToolUse |= map(if any(.hooks[]?; .command == $gate) then (.hooks |= map(select(.command != $gate))) | select((.hooks | length) > 0) else . end)
  | .hooks.PreToolUse += [{matcher: $matcher, hooks: [{type: "command", command: $gate}]}]
' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS" || die "failed to write $SETTINGS; restore from $bak"

# 4. CLAUDE.md import
touch "$CLAUDE_DIR/CLAUDE.md"
grep -qxF "$IMPORT_LINE" "$CLAUDE_DIR/CLAUDE.md" || printf '\n%s\n' "$IMPORT_LINE" >> "$CLAUDE_DIR/CLAUDE.md"

# 5. global gitignore
mkdir -p "$(dirname "$GIT_IGNORE")"
touch "$GIT_IGNORE"
if ! grep -qxF '.harness/' "$GIT_IGNORE"; then
  if [ -s "$GIT_IGNORE" ] && [ -n "$(tail -c1 "$GIT_IGNORE")" ]; then printf '\n' >> "$GIT_IGNORE"; fi
  printf '.harness/\n' >> "$GIT_IGNORE"
fi

cat <<EOF
installed:
  gate hook      $GATE  (matcher: $MATCHER)
  agents         $CLAUDE_DIR/agents/ ($(cd "$REPO/claude/agents" && ls *.md | tr '\n' ' '))
  harness        $BIN_DIR/harness
  settings       $SETTINGS (backup: $bak)
  CLAUDE.md      $IMPORT_LINE
  cache TTL      promptCacheTtl=1h subagentPromptCacheTtl=1h
  gitignore      $GIT_IGNORE (+ .harness/)
next: start Claude inside a herdr pane and give it work. Escape hatch: HARNESS_ROLE=worker claude
EOF
