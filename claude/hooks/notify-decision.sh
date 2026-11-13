#!/bin/bash
# Notification hook for the conductor: a macOS desktop notification when Claude Code
# waits for the user (permission prompt, idle prompt, AskUserQuestion). Title names the
# work folder (basename of the hook input's cwd), body is the hook input's message.
# Silent for workers (HARNESS_ROLE=worker), without osascript or jq. Never fails.
[ "${HARNESS_ROLE:-}" = worker ] && exit 0
command -v osascript >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
in=$(cat 2>/dev/null)
msg=$(printf '%s' "$in" | jq -r '.message // empty' 2>/dev/null)
cwd=$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
[ -n "$msg" ] || msg="Claude needs your attention"
# AppleScript string literal: escape backslash and double quote, flatten newlines
esc() { printf '%s' "$1" | tr '\n\r' '  ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
osascript -e "display notification \"$(esc "$msg")\" with title \"Claude: $(esc "${cwd##*/}")\"" >/dev/null 2>&1
exit 0
