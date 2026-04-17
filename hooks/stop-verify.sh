#!/bin/bash
#
# Stop Hook — verification nudge at end of turn.
#
# Policy: only emit the nudge when this turn actually modified something.
# Read-only / exploratory turns should not get the "verify tests pass" spam.
#
# Active /ship pipeline is a separate case and always emits.

CWD="${CWD:-$PWD}"
cd "$CWD" 2>/dev/null || exit 0

# Active /ship pipeline — always nudge completion
PROGRESS="${CWD}/harness/progress.md"
if [ -f "$PROGRESS" ] && grep -q "Status: In Progress" "$PROGRESS" 2>/dev/null; then
    echo "<stop-verification>"
    echo "Active /ship pipeline detected. Verify: stages done, tests green, PR created."
    echo "</stop-verification>"
    exit 0
fi

# Otherwise, only nudge if something was actually changed this session
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

if git diff --quiet HEAD 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
    exit 0
fi

echo "<stop-verification>"
echo "Uncommitted changes present. Before finishing: tests pass, docs updated, no stray TODO/FIXME."
echo "</stop-verification>"
