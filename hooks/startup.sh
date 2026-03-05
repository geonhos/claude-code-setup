#!/bin/bash

cat << 'EOF'

══════════════════════════════════════════════════════════════════════
 ███╗   ███╗   █████╗   ███████╗
 ████╗ ████║  ██╔══██╗  ██╔════╝
 ██╔████╔██║  ███████║  ███████╗
 ██║╚██╔╝██║  ██╔══██║  ╚════██║
 ██║ ╚═╝ ██║  ██║  ██║  ███████║
 ╚═╝     ╚═╝  ╚═╝  ╚═╝  ╚══════╝  v2.3.1
  :: Multi-Agent System ::          Powered by Claude Code
══════════════════════════════════════════════════════════════════════
  15 Agents  |  32 Skills  |  3 MCP Servers

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

<multi-agent-system version="2.3.1">
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
