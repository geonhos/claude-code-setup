# harness-openwatch.sh — `harness open-watch <role>`: open the live dashboard in a new pane/tab (issue #102).
# Sourced eagerly by bin/harness: definitions only. Uses die/role_in from it; runs in the -C folder.
cmd_open_watch() {
  local role=${1:-} c id
  role_in "$role" || die "usage: harness open-watch <${HARNESS_ROLES// /|}>"
  c="harness -C $(printf '%q' "$PWD") watch $role"   # absolute folder, shell-quoted
  if [ -n "${HERDR_ENV:-}" ] && command -v herdr >/dev/null 2>&1 \
    && id=$(herdr pane split --current --direction right --no-focus 2>/dev/null | jq -r '.result.pane.pane_id // empty') \
    && [ -n "$id" ] && herdr pane run "$id" "$c" >/dev/null 2>&1; then echo "opened in a herdr pane: $c"
  elif [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1 && tmux split-window -h "$c"; then echo "opened in a tmux pane: $c"
  elif command -v osascript >/dev/null 2>&1 \
    && osascript -e "tell application \"Terminal\" to do script \"$(printf '%s' "$c" | sed 's/[\\"]/\\&/g')\"" >/dev/null 2>&1; then
    echo "opened in a Terminal window: $c"
  else echo "no pane backend; run in another terminal: $c"; fi
}
