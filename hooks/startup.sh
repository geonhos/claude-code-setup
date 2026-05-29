#!/bin/bash
#
# SessionStart hook — slim banner + pending-draft notification.
#
# Philosophy: Claude already sees skill descriptions and agent frontmatter
# via the tool/skill registries. Don't duplicate them here — only emit
# information that is NOT derivable from tool metadata.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"

if [ -f "$SCRIPT_DIR/plugin.json" ]; then
  VERSION=$(grep '"version"' "$SCRIPT_DIR/plugin.json" 2>/dev/null | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
else
  VERSION="6.0.0"
fi

DRAFT_COUNT=0
if [ -d "$PWD/memory/_draft" ]; then
  DRAFT_COUNT=$(find "$PWD/memory/_draft" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
fi

FEEDBACK_STATUS="on"
if [ "${HARNESS_AUTO_FEEDBACK:-1}" = "0" ]; then
  FEEDBACK_STATUS="off"
fi

cat << EOF

══════════════════════════════════════════════════════════════════════
 ███╗   ███╗   █████╗   ███████╗
 ████╗ ████║  ██╔══██╗  ██╔════╝
 ██╔████╔██║  ███████║  ███████╗
 ██║╚██╔╝██║  ██╔══██║  ╚════██║
 ██║ ╚═╝ ██║  ██║  ██║  ███████║
 ╚═╝     ╚═╝  ╚═╝  ╚═╝  ╚══════╝  v${VERSION}
  :: Harness Conductor ::    Gated pipeline + learning loop
══════════════════════════════════════════════════════════════════════

<multi-agent-system version="${VERSION}">
/ship: thin conductor — drives native Claude Code through enforced gates
(plan score ≥8 → branch → implement → /review Critical=0 → tests green → PR).
Implementation & verification are delegated to native CC + companion plugins
(wshobson/agents, anthropics/claude-plugins-official); the harness only gates.
Granular skills: /plan (scored), /retro, /retro-review, best_practices (context7).
Learning loop: /retro (weekly) analyzes signals → /retro-review approves drafts.
Signal capture: ${FEEDBACK_STATUS} (HARNESS_AUTO_FEEDBACK=0 to disable).
EOF

if [ "$DRAFT_COUNT" -gt 0 ]; then
  echo "⚠  ${DRAFT_COUNT} retro draft(s) pending approval — run /retro-review"
fi

echo "</multi-agent-system>"
