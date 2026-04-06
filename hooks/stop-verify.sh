#!/bin/bash
#
# Stop Hook — Verification nudge at end of turn
# Reminds Claude to verify work completeness before finishing.
#
# Inspired by: disler/claude-code-hooks-mastery (Stop hook pattern)

# Check if harness progress file exists and has active work
CWD="${CWD:-.}"
PROGRESS="${CWD}/harness/progress.md"

if [ -f "$PROGRESS" ]; then
  # Check for incomplete pipeline stages
  if grep -q "Status: In Progress" "$PROGRESS" 2>/dev/null; then
    echo "<stop-verification>"
    echo "Active /ship pipeline detected. Verify:"
    echo "- All pipeline stages completed"
    echo "- No skipped stages"
    echo "- Tests are green"
    echo "- PR is created"
    echo "</stop-verification>"
    exit 0
  fi
fi

# General verification nudge
echo "<stop-verification>"
echo "Before finishing, verify:"
echo "- Code changes are complete and correct"
echo "- Tests pass for modified code"
echo "- No TODO/FIXME left unresolved"
echo "- Documentation updated if needed"
echo "</stop-verification>"
