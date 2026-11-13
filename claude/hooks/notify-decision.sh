#!/bin/bash
# Notification hook for the conductor: a macOS desktop notification when Claude Code
# waits for the user. Registered globally with the matcher permission_prompt|idle_prompt|
# elicitation_dialog|elicitation_url_dialog|agent_needs_input. Like the gate, it acts only
# when the hook input says agent_type == conductor (workers and plain sessions: no call;
# an inherited HARNESS_ROLE=worker does not matter). Title names the work folder (basename
# of the input's cwd), body is the input's message. Silent without osascript or jq.
# Never fails.
command -v osascript >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0
in=$(cat 2>/dev/null)
[ "$(printf '%s' "$in" | jq -r 'if type == "object" then (.agent_type // empty) else empty end' 2>/dev/null)" = conductor ] || exit 0
msg=$(printf '%s' "$in" | jq -r '.message // empty' 2>/dev/null)
cwd=$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
[ -n "$msg" ] || msg="Claude needs your attention"
# AppleScript string literal: escape backslash and double quote, flatten newlines
esc() { printf '%s' "$1" | tr '\n\r' '  ' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }
osascript -e "display notification \"$(esc "$msg")\" with title \"Claude: $(esc "${cwd##*/}")\"" >/dev/null 2>&1
exit 0
