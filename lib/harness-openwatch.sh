# harness-openwatch.sh — `harness open-watch <role>`: open the live dashboard in a new pane (issue #102).
# Sourced eagerly by bin/harness: definitions only. Uses die/role_in from it; runs in the -C folder.
# Backends: herdr, tmux; else the command is printed (Ghostty and Terminal.app removed in #305: 0 of 13 real calls used them).
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
  else echo "no pane backend; run in another terminal: $c"; fi
}
