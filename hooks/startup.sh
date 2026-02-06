#!/bin/bash

cat << 'EOF'
┌────────────────────────────────────────────────────────────┐
│  Multi-Agent System v2.1.0                                 │
│  15 agents | 32 skills | 3 MCP servers                     │
└────────────────────────────────────────────────────────────┘

[Workflow]
  1.Requirements → 2.Plan → 3.Validate(≥8) → 4.Orchestrate → 5.Execute → 6.Verify

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

<multi-agent-system version="2.1.0">
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
