#!/bin/bash

cat << 'EOF'

══════════════════════════════════════════════════════════════════════
 ███╗   ███╗   █████╗   ███████╗
 ████╗ ████║  ██╔══██╗  ██╔════╝
 ██╔████╔██║  ███████║  ███████╗
 ██║╚██╔╝██║  ██╔══██║  ╚════██║
 ██║ ╚═╝ ██║  ██║  ██║  ███████║
 ╚═╝     ╚═╝  ╚═╝  ╚═╝  ╚══════╝  v2.1.1
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

 [Auto Triggers]
  requirements|요구사항  → requirements-analyst
  plan|계획|설계        → plan-architect
  test|테스트|QA        → qa-executor
  review|리뷰           → code-reviewer
  security|보안         → security-analyst
  debug|버그|error      → debug-specialist
  React|UI|컴포넌트     → frontend-dev
  API|Spring|백엔드     → backend-dev
  ML|AI|LLM            → ai-expert
  DB|스키마             → database-expert
  Docker|K8s|배포       → devops-engineer

 [MCP] context7, filesystem, memory
 [Skills] /git_commit /git_pr /brainstorm /test_runner
══════════════════════════════════════════════════════════════════════

<multi-agent-system version="2.1.1">
<agents>
<pipeline>requirements-analyst, plan-architect, orchestrator</pipeline>
<execution>frontend-dev, backend-dev, ai-expert, database-expert, devops-engineer, docs-writer, refactoring-expert</execution>
<quality>code-reviewer, qa-executor, security-analyst, performance-analyst, debug-specialist</quality>
</agents>
<workflow>Requirements→Plan→Validate(≥8)→Orchestrate→Execute→Verify</workflow>
<triggers>
requirements|요구사항→requirements-analyst
plan|계획|설계→plan-architect
test|테스트|QA→qa-executor
review|리뷰→code-reviewer
security|보안→security-analyst
debug|버그|error→debug-specialist
React|UI|컴포넌트→frontend-dev
API|Spring|백엔드→backend-dev
ML|AI|LLM→ai-expert
DB|스키마→database-expert
Docker|K8s|배포→devops-engineer
refactor|정리→refactoring-expert
performance|성능→performance-analyst
</triggers>
<mcp>context7, filesystem, memory</mcp>
</multi-agent-system>
EOF
