#!/bin/bash

# Dynamically count agents, skills, and MCP servers
SCRIPT_DIR="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"

if [ -d "$SCRIPT_DIR/agents" ]; then
  AGENT_COUNT=$(find "$SCRIPT_DIR/agents" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
else
  AGENT_COUNT=6
fi

if [ -d "$SCRIPT_DIR/skills" ]; then
  SKILL_COUNT=$(find "$SCRIPT_DIR/skills" -name "SKILL.md" -type f 2>/dev/null | wc -l | tr -d ' ')
else
  SKILL_COUNT=12
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
  VERSION="3.0.0"
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
══════════════════════════════════════════════════════════════════════

<multi-agent-system version="${VERSION}">

<agent-routing>
Use the following agents when the situation matches. Each agent runs as an isolated subagent.

| When | Agent | What it does |
|------|-------|-------------|
| Plan needed, complex task, architecture | plan-architect | Execution plan with dependencies, self-validates score>=8 |
| Java, Spring, API, JPA, backend | backend-dev | Spring Boot DDD, implements + tests |
| React, TypeScript, UI, component | frontend-dev | React MVVM, implements + tests |
| Python, ML, AI, LLM, RAG, FastAPI | ai-expert | Python ML/AI, implements + tests |
| Code complete, before commit, review | code-reviewer | Quality review, severity ratings, does NOT fix |
| Run tests, test failures, coverage | qa-executor | Runs tests, analyzes failures, suggests fixes |
</agent-routing>

<workflow>Plan → Execute(agents above) → Review(code-reviewer) → Test(qa-executor)</workflow>

<skills>
| Skill | Trigger |
|-------|---------|
| brainstorm | Design decisions, multiple approaches |
| task_breakdown | Decompose feature into atomic tasks |
| verify_complete | Before marking any task done |
| tdd_workflow | /tdd_workflow — Red-Green-Refactor cycle |
| test_runner | /test_runner — Execute test suites |
| coverage_report | /coverage_report — Coverage analysis |
| debug_workflow | Bugs, errors, crashes |
| git_commit | /git_commit — Structured commits |
| git_pr | /git_pr — Pull request creation |
</skills>

<best-practices>react_best_practices, spring_best_practices, python_best_practices — auto-loaded when writing code in these stacks</best-practices>

<rules>
- When modifying code, update related documentation (README, CHANGELOG, docstrings) in the same commit
- Follow Kent Beck TDD: Red (failing test) → Green (minimal implementation) → Refactor (clean up)
- Separate structural commits (rename, move, extract) from behavioral commits (new feature, bug fix)
- Commit and push are separate operations — never auto-push after commit
- PreCommit hook enforces build + test pass — commit is blocked if either fails
</rules>

<mcp>context7, filesystem, playwright</mcp>

</multi-agent-system>
EOF
