# harness-openwatch.sh — `harness open-watch <role>`: open the live dashboard in a new pane/tab (issue #102).
# Sourced eagerly by bin/harness: definitions only. Uses die/role_in from it; runs in the -C folder.
# ow_osascript ARGS — osascript with a deadline (HARNESS_OSASCRIPT_TIMEOUT, default 10 s): the first
# macOS Automation prompt can block it. Fails on timeout. bash 3.2: background + poll.
ow_osascript() {
  local pid i=0 max=$(( ${HARNESS_OSASCRIPT_TIMEOUT:-10} * 10 ))
  osascript "$@" & pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    [ "$i" -lt "$max" ] || { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 1; }
    sleep 0.1; i=$((i + 1))
  done
  wait "$pid"
}
cmd_open_watch() {
  local role=${1:-} c id
  role_in "$role" || die "usage: harness open-watch <${HARNESS_ROLES// /|}>"
  # printf %q turns control characters into $'...', which fish and other non-POSIX shells cannot parse
  case "$PWD" in *[[:cntrl:]]*)
    echo "folder path has control characters; not opening a pane. Run in another terminal: harness -C <folder> watch $role"; return 0 ;;
  esac
  c="harness -C $(printf '%q' "$PWD") watch $role"   # absolute folder, shell-quoted
  if [ -n "${HERDR_ENV:-}" ] && command -v herdr >/dev/null 2>&1 \
    && id=$(herdr pane split --current --direction right --no-focus 2>/dev/null | jq -r '.result.pane.pane_id // empty'); then
    if [ -n "$id" ] && herdr pane run "$id" "$c" >/dev/null 2>&1; then echo "opened in a herdr pane: $c"; return 0; fi
    [ -z "$id" ] || herdr pane close "$id" >/dev/null 2>&1   # half-made pane: remove it, try the next backend
  fi
  if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1 && tmux split-window -h "$c" 2>/dev/null; then echo "opened in a tmux pane: $c"
  elif [ "${TERM_PROGRAM:-}" = ghostty ]; then   # Ghostty has no Terminal.app fallback: `open` launches a new instance window
    if command -v open >/dev/null 2>&1 && open -na Ghostty --args -e /bin/bash -c "$c" >/dev/null 2>&1; then echo "opened in a Ghostty window: $c"
    else echo "no pane backend; run in another terminal: $c"; fi
  elif command -v osascript >/dev/null 2>&1 \
    && ow_osascript -e "tell application \"Terminal\" to do script \"$(printf '%s' "$c" | sed 's/[\\"]/\\&/g')\"" >/dev/null 2>&1; then
    echo "opened in a Terminal window: $c"
  else echo "no pane backend; run in another terminal: $c"; fi
}
