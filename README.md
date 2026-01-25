# Claude Code Agents & Skills

Claude Code를 위한 커스텀 Agent 및 Skill 라이브러리

## 구성

| 항목 | 수량 |
|------|------|
| Agents | 14개 |
| Skills | 25개 |

---

## Agents

### Pipeline (4개)

작업 흐름 관리

| Agent | 역할 |
|-------|------|
| [`requirements-analyst`](.claude/agents/pipeline/requirements-analyst.md) | 요구사항 분석 및 명확화 |
| [`plan-architect`](.claude/agents/pipeline/plan-architect.md) | 실행 계획 수립 |
| [`plan-feedback`](.claude/agents/pipeline/plan-feedback.md) | Cross-LLM 검증 (Gemini CLI) |
| [`orchestrator`](.claude/agents/pipeline/orchestrator.md) | 작업 조율 및 분배 |

### Execution (4개)

개발 작업 수행

| Agent | 역할 | 기술 스택 |
|-------|------|-----------|
| [`backend-dev`](.claude/agents/execution/backend-dev.md) | 백엔드 개발 | Java, Spring Boot, DDD |
| [`frontend-dev`](.claude/agents/execution/frontend-dev.md) | 프론트엔드 개발 | React, TypeScript, MVVM |
| [`ai-expert`](.claude/agents/execution/ai-expert.md) | AI/ML 개발 | Python, LLM, RAG |
| [`git-ops`](.claude/agents/execution/git-ops.md) | Git 작업 관리 | Git Flow, GitHub CLI |

### Quality (6개)

품질 보증

| Agent | 역할 |
|-------|------|
| [`qa-planner`](.claude/agents/quality/qa-planner.md) | 테스트 계획 수립 |
| [`qa-executor`](.claude/agents/quality/qa-executor.md) | 테스트 실행 및 분석 |
| [`qa-healer`](.claude/agents/quality/qa-healer.md) | 테스트 실패 복구 |
| [`security-analyst`](.claude/agents/quality/security-analyst.md) | 보안 코드 리뷰, OWASP Top 10 |
| [`pr-reviewer`](.claude/agents/quality/pr-reviewer.md) | PR 리뷰 (Gemini CLI) |
| [`reporter`](.claude/agents/quality/reporter.md) | 실행 보고서 생성 |

---

## Skills

### Git (5개)

| Skill | 설명 |
|-------|------|
| [`/git_commit`](.claude/skills/git/git_commit/SKILL.md) | 구조화된 커밋 메시지 |
| [`/git_branch`](.claude/skills/git/git_branch/SKILL.md) | 브랜치 명명 규칙 |
| [`/git_pr`](.claude/skills/git/git_pr/SKILL.md) | PR 템플릿 |
| [`/git_issue`](.claude/skills/git/git_issue/SKILL.md) | Issue 템플릿 |
| [`/git_analyze`](.claude/skills/git/git_analyze/SKILL.md) | 변경사항 분석 |

### Python (4개)

| Skill | 설명 |
|-------|------|
| [`/python_setup`](.claude/skills/python/python_setup/SKILL.md) | Python 프로젝트 초기화 |
| [`/fastapi_setup`](.claude/skills/python/fastapi_setup/SKILL.md) | FastAPI 프로젝트 구조 |
| [`/api_test_setup`](.claude/skills/python/api_test_setup/SKILL.md) | API 테스트 설정 |
| [`/rag_setup`](.claude/skills/python/rag_setup/SKILL.md) | RAG 파이프라인 설정 |

### Java (3개)

| Skill | 설명 |
|-------|------|
| [`/spring_boot_setup`](.claude/skills/java/spring_boot_setup/SKILL.md) | Spring Boot 프로젝트 |
| [`/gradle_setup`](.claude/skills/java/gradle_setup/SKILL.md) | Gradle 멀티모듈 설정 |
| [`/jpa_entity`](.claude/skills/java/jpa_entity/SKILL.md) | JPA Entity 생성 |

### React (3개)

| Skill | 설명 |
|-------|------|
| [`/react_setup`](.claude/skills/react/react_setup/SKILL.md) | React/Vite 프로젝트 |
| [`/nextjs_setup`](.claude/skills/react/nextjs_setup/SKILL.md) | Next.js 14+ 프로젝트 |
| [`/component_generator`](.claude/skills/react/component_generator/SKILL.md) | MVVM 컴포넌트 생성 |

### AI/ML (2개)

| Skill | 설명 |
|-------|------|
| [`/mlflow_setup`](.claude/skills/ai/mlflow_setup/SKILL.md) | MLflow 실험 추적 |
| [`/langchain_setup`](.claude/skills/ai/langchain_setup/SKILL.md) | LangChain RAG 설정 |

### Infrastructure (2개)

| Skill | 설명 |
|-------|------|
| [`/docker_setup`](.claude/skills/infra/docker_setup/SKILL.md) | Docker Compose 설정 |
| [`/alembic_migration`](.claude/skills/infra/alembic_migration/SKILL.md) | DB 마이그레이션 |

### Quality (4개)

| Skill | 설명 |
|-------|------|
| [`/test_plan_template`](.claude/skills/quality/test_plan_template/SKILL.md) | 테스트 계획 생성 |
| [`/test_runner`](.claude/skills/quality/test_runner/SKILL.md) | 테스트 실행 |
| [`/coverage_report`](.claude/skills/quality/coverage_report/SKILL.md) | 커버리지 분석 |
| [`/execution_report`](.claude/skills/quality/execution_report/SKILL.md) | 실행 보고서 |

### Base (2개)

| Skill | 설명 |
|-------|------|
| [`/project_init`](.claude/skills/base/project_init/SKILL.md) | 프로젝트 초기화 |
| [`/tdd_workflow`](.claude/skills/methodology/tdd_workflow/SKILL.md) | TDD 워크플로우 |

---

## 디렉토리 구조

```
.claude/
├── CLAUDE.md              # 개발 지침
├── settings.json          # 프로젝트 설정
├── agents/
│   ├── pipeline/          # 워크플로우 에이전트
│   ├── execution/         # 개발 에이전트
│   └── quality/           # 품질 에이전트
└── skills/
    ├── git/               # Git 관련
    ├── python/            # Python 관련
    ├── java/              # Java 관련
    ├── react/             # React 관련
    ├── ai/                # AI/ML 관련
    ├── infra/             # 인프라 관련
    ├── quality/           # 품질 관련
    ├── base/              # 기본
    └── methodology/       # 방법론
```

---

## 사용 예시

### 새 기능 개발

```
/project_init → requirements-analyst → plan-architect →
backend-dev/frontend-dev → qa-executor → /git_commit → /git_pr
```

### 보안 검토

```
security-analyst → backend-dev (수정) → qa-executor (검증)
```

### 버그 수정

```
/git_branch → qa-healer → /git_commit → /git_pr
```
