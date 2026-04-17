#!/bin/bash
#
# PreToolUse guard — intercepts `git commit` Bash invocations and runs
# build/test checks before allowing the commit to proceed.
#
# Claude Code hooks receive event JSON on stdin (NOT a $TOOL_INPUT env var).
# Non-commit Bash invocations exit 0 immediately.
#
# Env vars:
#   HARNESS_SKIP_PRECOMMIT=1  — skip all checks
#   HARNESS_RUN_TESTS=1       — run full test suite (default: compile only)

if [ "${HARNESS_SKIP_PRECOMMIT:-0}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)

if command -v jq &>/dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
else
    COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit\b'; then
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRE_COMMIT="$SCRIPT_DIR/pre-commit.sh"

if [ -f "$PRE_COMMIT" ]; then
    bash "$PRE_COMMIT"
    exit $?
fi

exit 0
