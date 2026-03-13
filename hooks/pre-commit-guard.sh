#!/bin/bash

# PreToolUse guard for Bash tool — intercepts "git commit" commands
# and runs build/test checks before allowing the commit.
# For non-commit commands, exits immediately with 0.

# TOOL_INPUT is JSON like: {"command":"git commit -m ...","description":"..."}
COMMAND=$(echo "$TOOL_INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')

# Only intercept git commit commands (not git log, git status, git diff, etc.)
if ! echo "$COMMAND" | grep -qE '^\s*git\s+commit\b'; then
    exit 0
fi

# Resolve and run the actual pre-commit checks
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRE_COMMIT="$SCRIPT_DIR/pre-commit.sh"

if [ -f "$PRE_COMMIT" ]; then
    bash "$PRE_COMMIT"
    exit $?
else
    echo "pre-commit.sh not found at $PRE_COMMIT, skipping checks"
    exit 0
fi
