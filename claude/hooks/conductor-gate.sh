#!/bin/bash
# conductor-gate.sh — PreToolUse hook for the Fable conductor.
# Spec: docs/superpowers/specs/2026-10-12-herdr-conductor-setup-design.md
#
# Role:   HARNESS_ROLE=worker  -> allow everything (herdr workers, manual escape hatch)
#         anything else        -> conductor rules below
# Output: nothing (allow) or a PreToolUse deny JSON on stdout. Always exit 0.
set -u

if [ "${HARNESS_ROLE:-conductor}" = "worker" ]; then
  exit 0
fi

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "conductor-gate: jq not found, allowing" >&2
  exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$TOOL" ]; then
  echo "conductor-gate: unparseable hook input, allowing" >&2
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD=$PWD

# Fixed strings: never interpolate per-call data (keeps the prompt cache stable).
MSG_WRITE="Conductor cannot edit source. Delegate: harness ask implementer '<instruction>'. Direct writes are allowed only under docs/**/*.md and .harness/."
MSG_READ="Conductor does not read source. Delegate: harness ask analyst '<question>' and read its report. Direct reads are allowed only under .harness/, docs/, and *.md files."
MSG_AGENT="Native subagents inherit the Fable model. Use harness ask <analyst|implementer|reviewer> '<instruction>' instead."
MSG_BASH="Conductor shell is limited to: harness, herdr, gh, read-only git (status / log / diff --stat / branch / show --stat), cat or ls under .harness/ and docs/. Delegate command execution: harness ask implementer '<command and goal>'."

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

field() { printf '%s' "$INPUT" | jq -r ".tool_input.$1 // empty" 2>/dev/null; }

# rel PATH -> prints the path relative to CWD, or returns 1 when the path is
# empty, outside CWD, or contains a '..' segment.
rel() {
  local p=$1
  [ -n "$p" ] || return 1
  case "$p" in
    ..|../*|*/..|*/../*) return 1 ;;
  esac
  case "$p" in
    "$CWD")   p="." ;;
    "$CWD"/*) p=${p#"$CWD"/} ;;
    /*)       return 1 ;;
    ./*)      p=${p#./} ;;
  esac
  printf '%s' "$p"
}

# readable PATH -> 0 when the conductor may read it
readable() {
  local p
  p=$(rel "$1") || return 1
  case "$p" in
    .harness|.harness/*|docs|docs/*|*.md) return 0 ;;
  esac
  return 1
}

# writable PATH -> 0 when the conductor may write it
writable() {
  local p
  p=$(rel "$1") || return 1
  case "$p" in
    .harness/*) return 0 ;;
    docs/*.md)  return 0 ;;
  esac
  return 1
}

# bash_ok COMMAND -> 0 when every segment of the command is on the allowlist
bash_ok() {
  local cmd=$1 stripped segs seg
  [ -n "$cmd" ] || return 1
  case "$cmd" in
    *'$('*|*'`'*) return 1 ;;
  esac
  # tolerate stderr->stdout redirects, reject any other redirect
  stripped=$(printf '%s' "$cmd" | sed 's/2>&1//g')
  case "$stripped" in
    *'>'*|*'<'*) return 1 ;;
  esac
  # split on ; && || |  (one segment per line). Done outside the heredoc
  # below: an unquoted heredoc would eat the sed backslash-newlines.
  segs=$(printf '%s' "$stripped" | sed 's/&&/\
/g; s/||/\
/g; s/;/\
/g; s/|/\
/g')
  while IFS= read -r seg; do
    seg=$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$seg" ] || continue
    printf '%s' "$seg" | grep -Eq \
      '^(harness( .*)?|herdr( .*)?|gh( .*)?|jq( .*)?|git status( .*)?|git log( .*)?|git diff --stat( .*)?|git branch( .*)?|git show --stat( .*)?|cat \.harness/[^ ]*|ls( -[A-Za-z]+)*( (\.harness|docs)[^ ]*)?)$' \
      || return 1
  done <<EOF
$segs
EOF
  return 0
}

case "$TOOL" in
  Edit|Write)
    writable "$(field file_path)" || deny "$MSG_WRITE" ;;
  NotebookEdit)
    writable "$(field notebook_path)" || deny "$MSG_WRITE" ;;
  Read)
    readable "$(field file_path)" || deny "$MSG_READ" ;;
  Grep|Glob)
    readable "$(field path)" || deny "$MSG_READ" ;;
  Agent|Workflow)
    deny "$MSG_AGENT" ;;
  Bash)
    bash_ok "$(field command)" || deny "$MSG_BASH" ;;
esac

exit 0
