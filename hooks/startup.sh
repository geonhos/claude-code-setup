#!/bin/bash

# Dynamically count agents, skills, and MCP servers
SCRIPT_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"

if [ -d "$SCRIPT_DIR/agents" ]; then
  AGENT_COUNT=$(find "$SCRIPT_DIR/agents" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
else
  AGENT_COUNT=15
fi

if [ -d "$SCRIPT_DIR/skills" ]; then
  SKILL_COUNT=$(find "$SCRIPT_DIR/skills" -name "SKILL.md" -type f 2>/dev/null | wc -l | tr -d ' ')
else
  SKILL_COUNT=32
fi

if [ -f "$SCRIPT_DIR/.mcp.json" ]; then
  MCP_COUNT=$(grep -c '"command"' "$SCRIPT_DIR/.mcp.json" 2>/dev/null || echo "3")
else
  MCP_COUNT=3
fi

# Read version from plugin.json
if [ -f "$SCRIPT_DIR/plugin.json" ]; then
  VERSION=$(grep '"version"' "$SCRIPT_DIR/plugin.json" 2>/dev/null | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
else
  VERSION="2.4.0"
fi

cat << EOF

══════════════════════════════════════════════════════════════════════
 ███╗   ███╗   █████╗   ███████╗
 ████╗ ████║  ██╔══██╗  ██╔════╝
 ██╔████╔██║  ███████║  ███████╗
 ██║╚██╔╝██║  ██╔══██║  ╚════██║
 ██║ ╚═╝ ██║  ██║  ██║  ███████║
 ╚═╝     ╚═╝  ╚═╝  ╚═╝  ╚══════╝  v${VERSION}
  :: Multi-Agent System ::          Powered by Claude Code
══════════════════════════════════════════════════════════════════════
  ${AGENT_COUNT} Agents  |  ${SKILL_COUNT} Skills  |  ${MCP_COUNT} MCP Servers

 [Workflow]
  Requirements → Plan → Validate(>=8) → Orchestrate → Execute → Verify

 [Agents]
  Pipeline:   requirements-analyst, plan-architect, orchestrator
  Execution:  frontend-dev, backend-dev, ai-expert, database-expert,
              devops-engineer, docs-writer, refactoring-expert
  Quality:    code-reviewer, qa-executor, security-analyst,
              performance-analyst, debug-specialist

 [Routing] Agent descriptions → automatic semantic dispatch

 [MCP] context7, filesystem, playwright
 [Skills] /git_commit /git_pr /brainstorm /test_runner
══════════════════════════════════════════════════════════════════════

<multi-agent-system version="${VERSION}">
<agents>
<pipeline>requirements-analyst, plan-architect, orchestrator</pipeline>
<execution>frontend-dev, backend-dev, ai-expert, database-expert, devops-engineer, docs-writer, refactoring-expert</execution>
<quality>code-reviewer, qa-executor, security-analyst, performance-analyst, debug-specialist</quality>
</agents>
<workflow>Requirements→Plan→Validate(≥8)→Orchestrate→Execute→Verify</workflow>
<routing>semantic — agent descriptions drive automatic dispatch</routing>
<mcp>context7, filesystem, playwright</mcp>
</multi-agent-system>
EOF
