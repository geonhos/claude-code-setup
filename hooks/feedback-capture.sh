#!/bin/bash
#
# Feedback Capture hook (UserPromptSubmit + PostToolUse).
#
# Writes implicit "bad" signals to logs/feedback-signals.jsonl for the
# learning loop. /retro aggregates these weekly; /retro-review is the
# human gate before anything becomes a memory.
#
# Env vars:
#   HARNESS_AUTO_FEEDBACK=0   — disable all signal capture
#
# Signal types:
#   frustration_keyword   — user prompt contains frustration words
#   post_ship_rework      — Edit/Write on a file shortly after /ship
#   strong_bad_git_undo   — git revert / git reset --hard executed

if [ "${HARNESS_AUTO_FEEDBACK:-1}" = "0" ]; then
    exit 0
fi

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

if command -v jq &>/dev/null; then
    EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null)
    CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
else
    extract() {
        echo "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
    }
    EVENT=$(extract hook_event_name)
    SESSION_ID=$(extract session_id)
    CWD=$(extract cwd)
fi

[ -z "$EVENT" ] && exit 0
[ -z "$CWD" ] && CWD="$PWD"
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"

LOGDIR="${CWD}/logs"
SIGNALS="${LOGDIR}/feedback-signals.jsonl"
mkdir -p "$LOGDIR" 2>/dev/null || exit 0
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S")

log_signal() {
    local signal="$1"
    local detail="$2"
    if command -v jq &>/dev/null; then
        jq -n -c \
            --arg type "implicit_bad" \
            --arg signal "$signal" \
            --arg detail "$detail" \
            --arg session "$SESSION_ID" \
            --arg time "$TIMESTAMP" \
            '{type:$type, signal:$signal, detail:$detail, session:$session, time:$time}' \
            >> "$SIGNALS"
    else
        SAFE=$(printf '%s' "$detail" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n' | cut -c1-240)
        echo "{\"type\":\"implicit_bad\",\"signal\":\"${signal}\",\"detail\":\"${SAFE}\",\"session\":\"${SESSION_ID}\",\"time\":\"${TIMESTAMP}\"}" >> "$SIGNALS"
    fi
}

case "$EVENT" in
    UserPromptSubmit)
        if command -v jq &>/dev/null; then
            PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
        else
            PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        fi
        if echo "$PROMPT" | grep -qiE "(다시|틀렸|이상해|왜 이래|아니야|undo|revert that|rollback|wrong|not what|doesn't work|broke|broken)"; then
            log_signal "frustration_keyword" "$(printf '%s' "$PROMPT" | head -c 160)"
        fi
        ;;
    PostToolUse)
        if command -v jq &>/dev/null; then
            TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
            FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
            CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
        else
            TOOL=$(extract tool_name)
            FILE=$(extract file_path)
            CMD=$(extract command)
        fi

        # Post-ship rework: Edit/Write within 1h of last /ship progress update
        if [ "$TOOL" = "Edit" ] || [ "$TOOL" = "Write" ]; then
            PROGRESS="${CWD}/harness/progress.md"
            if [ -f "$PROGRESS" ]; then
                NOW=$(date +%s)
                MTIME=$(stat -f %m "$PROGRESS" 2>/dev/null || stat -c %Y "$PROGRESS" 2>/dev/null || echo 0)
                if [ "$MTIME" -gt 0 ]; then
                    DIFF=$((NOW - MTIME))
                    if [ "$DIFF" -ge 0 ] && [ "$DIFF" -lt 3600 ]; then
                        log_signal "post_ship_rework" "${TOOL} on ${FILE} (${DIFF}s after last ship progress)"
                    fi
                fi
            fi
        fi

        # Strong bad: git revert / git reset --hard
        if [ "$TOOL" = "Bash" ] && [ -n "$CMD" ]; then
            if echo "$CMD" | grep -qE "^\s*git\s+(revert\b|reset\s+--hard\b)"; then
                log_signal "strong_bad_git_undo" "$(printf '%s' "$CMD" | head -c 200)"
            fi
        fi
        ;;
esac

exit 0
