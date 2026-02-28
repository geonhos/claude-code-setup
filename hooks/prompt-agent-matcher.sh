#!/bin/bash
#
# Prompt Agent Matcher Hook (UserPromptSubmit)
# Analyzes user prompt keywords and injects recommended agent context.
# Output is added to Claude's context as <user-prompt-submit-hook>.
#
# Design principles:
#   - Fast execution (< 100ms, pure string matching)
#   - No output when no agents match (zero noise)
#   - Concise output to minimize per-turn token cost
#   - macOS bash 3.2 compatible (no associative arrays)

set -euo pipefail

INPUT=$(cat)

# Extract prompt text from stdin JSON
if command -v jq &>/dev/null; then
  PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
else
  PROMPT=$(echo "$INPUT" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

[ -z "$PROMPT" ] && exit 0

# Lowercase for case-insensitive English matching (Korean unaffected by tr)
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Match prompt against agent trigger patterns
# Format: agent_name|subagent_type|skills (pipe-delimited)
MATCHES=$(echo "$PROMPT_LOWER" | awk '{
  if (/요구사항|요구 사항|requirements/) print "requirements-analyst|multi-agent-system:pipeline:requirements-analyst|/brainstorm"
  if (/계획|설계|아키텍처|architecture|plan/) print "plan-architect|multi-agent-system:pipeline:plan-architect|/task_breakdown"
  if (/테스트|단위테스트|unit test|test|qa/) print "qa-executor|multi-agent-system:quality:qa-executor|/test_runner /coverage_report"
  if (/리뷰|코드리뷰|code review|review/) print "code-reviewer|multi-agent-system:quality:code-reviewer|/verify_complete"
  if (/보안|취약|owasp|xss|injection|csrf|security/) print "security-analyst|multi-agent-system:quality:security-analyst|"
  if (/버그|bug|에러|오류|crash|exception|debug|not working|안됨|안 됨/) print "debug-specialist|multi-agent-system:quality:debug-specialist|/debug_workflow"
  if (/react|next\.js|nextjs|컴포넌트|component|프론트|frontend|css|tailwind|tsx|jsx/) print "frontend-dev|multi-agent-system:execution:frontend-dev|/react_setup /component_generator"
  if (/spring|백엔드|backend|rest|endpoint|controller|java|jpa/) print "backend-dev|multi-agent-system:execution:backend-dev|/spring_boot_setup /jpa_entity"
  if (/ml |ai |llm|모델 학습|rag|embedding|langchain|pytorch|tensorflow|파인튜닝/) print "ai-expert|multi-agent-system:execution:ai-expert|/rag_setup /langchain_setup /mlflow_setup"
  if (/데이터베이스|스키마|schema|쿼리|query|sql|migration|마이그레이션|postgres|mysql|mongo/) print "database-expert|multi-agent-system:execution:database-expert|/alembic_migration"
  if (/docker|k8s|kubernetes|배포|deploy|ci\/cd|인프라|infrastructure|helm|terraform/) print "devops-engineer|multi-agent-system:execution:devops-engineer|/docker_setup"
  if (/리팩토링|리팩터|기술부채|technical debt|refactor|cleanup/) print "refactoring-expert|multi-agent-system:execution:refactoring-expert|"
  if (/성능|최적화|optimize|병목|bottleneck|느림|slow|latency|throughput/) print "performance-analyst|multi-agent-system:quality:performance-analyst|"
  if (/문서|document|readme|api docs/) print "docs-writer|multi-agent-system:execution:docs-writer|"
}')

[ -z "$MATCHES" ] && exit 0

# Build concise agent recommendation
AGENT_LIST=""
SKILL_LIST=""

while IFS='|' read -r name subtype skills; do
  AGENT_LIST="${AGENT_LIST}  - ${name} → subagent_type=\"${subtype}\"
"
  if [ -n "$skills" ]; then
    SKILL_LIST="${SKILL_LIST} ${skills}"
  fi
done <<< "$MATCHES"

# Deduplicate skills
if [ -n "$SKILL_LIST" ]; then
  SKILL_LIST=$(echo "$SKILL_LIST" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/^ *//;s/ *$//')
fi

cat << EOF
<agent-recommendation>
Dispatch these agents via Task tool:
${AGENT_LIST}$([ -n "$SKILL_LIST" ] && echo "Skills: ${SKILL_LIST}")
</agent-recommendation>
EOF
