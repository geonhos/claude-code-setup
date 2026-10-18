#!/bin/bash
# SessionStart hook for the conductor (matcher: startup|clear|compact).
# Injects .harness/progress.md as additionalContext so a /clear, compaction or
# crash recovery resumes from the durable progress log. Silent for workers
# (HARNESS_ROLE=worker), when the file is missing, or when jq is unavailable.
# Never fails: a SessionStart hook must not block a session.
[ "${HARNESS_ROLE:-}" = worker ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

dir=$PWD
if [ ! -t 0 ]; then
  c=$(cat 2>/dev/null | jq -r '.cwd // empty' 2>/dev/null)
  [ -z "$c" ] || [ ! -d "$c" ] || dir=$c
fi
f="$dir/.harness/progress.md"
[ -s "$f" ] || exit 0

{ printf 'Harness progress (resume from here; verify with harness status)\n'; cat "$f"; } \
  | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' 2>/dev/null
exit 0
