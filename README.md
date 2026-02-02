# Claude Code Agents & Skills

Claude Code를 위한 멀티에이전트 시스템 플러그인 v2.0

## 설치

Claude Code에서 실행:

```
/plugin marketplace add geonhos/claude-code-setup
/plugin add multi-agent-system
```

설치 완료! 세션 시작 시 자동으로 에이전트와 스킬이 소개됩니다.

```
===== Multi-Agent System v2.0 활성화 =====

15개 전문 에이전트와 32개 스킬이 로드되었습니다.

[Agents]
- Pipeline: requirements-analyst, plan-architect, orchestrator
- Execution: backend-dev, frontend-dev, ai-expert, database-expert, devops-engineer, docs-writer, refactoring-expert
- Quality: code-reviewer, qa-executor, security-analyst, performance-analyst, debug-specialist

[Skills]
- Git: /git_commit, /git_branch, /git_pr, /git_issue, /git_analyze, /git_worktree
- Dev: /python_setup, /fastapi_setup, /react_setup, /spring_boot_setup
- Quality: /test_runner, /coverage_report, /test_plan_template
- Workflow: /brainstorm, /verify_complete, /debug_workflow, /task_breakdown

==========================================
```

## 구성

| 항목 | 수량 |
|------|------|
| Agents | 15개 |
| Skills | 32개 |

---

## 핵심 워크플로우 (6단계)

v2.0에서는 명확한 6단계 워크플로우를 제공합니다:

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ 1. 요구사항   │───▶│ 2. Plan 생성 │───▶│ 3. Plan 검증 │
│    수집       │    │              │    │  (자체검증)   │
│requirements- │    │plan-architect│    │              │
│   analyst    │    │              │    │              │
└──────────────┘    └──────────────┘    └──────┬───────┘
                                               │
                    ┌──────────────────────────┘
                    ▼
┌──────────────────────────────────────────────────────┐
│              4. Orchestrator (병렬 조율)              │
└───────────────────────┬──────────────────────────────┘
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   [Agent A]       [Agent B]       [Agent C]  ← 5. 병렬 실행
        └───────────────┼───────────────┘
                        ▼
┌──────────────────────────────────────────────────────┐
│     6. 구현 검증 (code-reviewer + qa-executor)        │
└──────────────────────────────────────────────────────┘
```

| 단계 | 에이전트 | 역할 |
|-----|---------|------|
| 1 | `requirements-analyst` | 요구사항 수집 및 정제 |
| 2 | `plan-architect` | 실행 계획 수립 |
| 3 | `plan-architect` | Plan 자체 검증 (score >= 8) |
| 4 | `orchestrator` | Agent 병렬 실행 조율 |
| 5 | execution agents | 도메인별 병렬 구현 |
| 6 | `code-reviewer` + `qa-executor` | 코드/테스트 검증 |

---

## Agents

### Pipeline (3개)

워크플로우 관리

| Agent | 역할 |
|-------|------|
| [`requirements-analyst`](agents/pipeline/requirements-analyst.md) | 요구사항 분석 및 명확화 |
| [`plan-architect`](agents/pipeline/plan-architect.md) | 실행 계획 수립 + 자체 검증 |
| [`orchestrator`](agents/pipeline/orchestrator.md) | Plan 기반 병렬 실행 조율 |

### Execution (7개)

개발 작업 수행

| Agent | 역할 | 기술 스택 |
|-------|------|-----------|
| [`backend-dev`](agents/execution/backend-dev.md) | 백엔드 개발 | Java, Spring Boot, DDD |
| [`frontend-dev`](agents/execution/frontend-dev.md) | 프론트엔드 개발 | React, TypeScript, MVVM |
| [`ai-expert`](agents/execution/ai-expert.md) | AI/ML 개발 | Python, LLM, RAG |
| [`database-expert`](agents/execution/database-expert.md) | 데이터베이스 | Schema, Query 최적화 |
| [`devops-engineer`](agents/execution/devops-engineer.md) | DevOps/인프라 | Docker, K8s, CI/CD |
| [`refactoring-expert`](agents/execution/refactoring-expert.md) | 리팩토링 | 레거시 개선, 기술부채 |
| [`docs-writer`](agents/execution/docs-writer.md) | 문서화 | API docs, README |

### Quality (5개)

품질 보증

| Agent | 역할 |
|-------|------|
| [`code-reviewer`](agents/quality/code-reviewer.md) | 코드/문서 품질 리뷰 |
| [`qa-executor`](agents/quality/qa-executor.md) | 테스트 계획/실행/분석 통합 |
| [`security-analyst`](agents/quality/security-analyst.md) | 보안 코드 리뷰, OWASP Top 10 |
| [`performance-analyst`](agents/quality/performance-analyst.md) | 성능 분석 및 최적화 |
| [`debug-specialist`](agents/quality/debug-specialist.md) | 체계적 가설 기반 디버깅 |

---

## Skills

### Git (6개)

| Skill | 설명 |
|-------|------|
| [`/git_commit`](skills/git/git_commit/SKILL.md) | 구조화된 커밋 메시지 |
| [`/git_branch`](skills/git/git_branch/SKILL.md) | 브랜치 명명 규칙 |
| [`/git_pr`](skills/git/git_pr/SKILL.md) | PR 템플릿 |
| [`/git_issue`](skills/git/git_issue/SKILL.md) | Issue 템플릿 |
| [`/git_analyze`](skills/git/git_analyze/SKILL.md) | 변경사항 분석 |
| [`/git_worktree`](skills/git/git_worktree/SKILL.md) | 병렬 브랜치 개발 |

### Python (5개)

| Skill | 설명 |
|-------|------|
| [`/python_setup`](skills/python/python_setup/SKILL.md) | Python 프로젝트 초기화 |
| [`/fastapi_setup`](skills/python/fastapi_setup/SKILL.md) | FastAPI 프로젝트 구조 |
| [`/api_test_setup`](skills/python/api_test_setup/SKILL.md) | API 테스트 설정 |
| [`/rag_setup`](skills/python/rag_setup/SKILL.md) | RAG 파이프라인 설정 |
| [`/python_best_practices`](skills/python/python_best_practices/SKILL.md) | Python 모범 사례 |

### Java (4개)

| Skill | 설명 |
|-------|------|
| [`/spring_boot_setup`](skills/java/spring_boot_setup/SKILL.md) | Spring Boot 프로젝트 |
| [`/gradle_setup`](skills/java/gradle_setup/SKILL.md) | Gradle 멀티모듈 설정 |
| [`/jpa_entity`](skills/java/jpa_entity/SKILL.md) | JPA Entity 생성 |
| [`/spring_best_practices`](skills/java/spring_best_practices/SKILL.md) | Spring 모범 사례 |

### React (4개)

| Skill | 설명 |
|-------|------|
| [`/react_setup`](skills/react/react_setup/SKILL.md) | React/Vite 프로젝트 |
| [`/nextjs_setup`](skills/react/nextjs_setup/SKILL.md) | Next.js 14+ 프로젝트 |
| [`/component_generator`](skills/react/component_generator/SKILL.md) | MVVM 컴포넌트 생성 |
| [`/react_best_practices`](skills/react/react_best_practices/SKILL.md) | React 모범 사례 |

### AI/ML (2개)

| Skill | 설명 |
|-------|------|
| [`/mlflow_setup`](skills/ai/mlflow_setup/SKILL.md) | MLflow 실험 추적 |
| [`/langchain_setup`](skills/ai/langchain_setup/SKILL.md) | LangChain RAG 설정 |

### Infrastructure (2개)

| Skill | 설명 |
|-------|------|
| [`/docker_setup`](skills/infra/docker_setup/SKILL.md) | Docker Compose 설정 |
| [`/alembic_migration`](skills/infra/alembic_migration/SKILL.md) | DB 마이그레이션 |

### Quality (3개)

| Skill | 설명 |
|-------|------|
| [`/test_plan_template`](skills/quality/test_plan_template/SKILL.md) | 테스트 계획 생성 |
| [`/test_runner`](skills/quality/test_runner/SKILL.md) | 테스트 실행 |
| [`/coverage_report`](skills/quality/coverage_report/SKILL.md) | 커버리지 분석 |

### Base (2개)

| Skill | 설명 |
|-------|------|
| [`/project_init`](skills/base/project_init/SKILL.md) | 프로젝트 초기화 |
| [`/tdd_workflow`](skills/methodology/tdd_workflow/SKILL.md) | TDD 워크플로우 |

### Workflow (4개)

| Skill | 설명 |
|-------|------|
| [`/brainstorm`](skills/workflow/brainstorm/SKILL.md) | 설계 탐색 - 최소 3개 접근법 비교 |
| [`/task_breakdown`](skills/workflow/task_breakdown/SKILL.md) | 태스크 분해 - 2-5분 단위 atomic 태스크 |
| [`/debug_workflow`](skills/workflow/debug_workflow/SKILL.md) | 디버깅 워크플로우 |
| [`/verify_complete`](skills/workflow/verify_complete/SKILL.md) | 완료 검증 |

---

## 디렉토리 구조

```
# 플러그인 구조 (루트)
plugin.json                # 플러그인 매니페스트
marketplace.json           # 마켓플레이스 정보

hooks/
└── hooks.json             # SessionStart 훅 설정

agents/                    # 에이전트 정의 (15개)
├── pipeline/              # 워크플로우 에이전트 (3개)
├── execution/             # 개발 에이전트 (7개)
└── quality/               # 품질 에이전트 (5개)

skills/                    # 스킬 정의 (32개)
├── git/                   # Git 관련
├── python/                # Python 관련
├── java/                  # Java 관련
├── react/                 # React 관련
├── ai/                    # AI/ML 관련
├── infra/                 # 인프라 관련
├── quality/               # 품질 관련
├── base/                  # 기본
├── methodology/           # 방법론
└── workflow/              # 워크플로우

# 프로젝트 설정
.claude/
├── CLAUDE.md              # 개발 지침
├── settings.json          # 프로젝트 설정
└── protocols/             # 공통 프로토콜

# Generated directories (gitignored)
plans/                     # 실행 계획
logs/                      # 에이전트 로그
```

---

## 사용 예시

### 새 기능 개발 (6단계 파이프라인)

```
requirements-analyst → plan-architect (자체 검증)
→ orchestrator (병렬 조율) → [execution agents 병렬 실행]
→ code-reviewer + qa-executor (필수 검증)
→ /git_commit → /git_pr
```

### 보안 검토

```
security-analyst → backend-dev (수정) → qa-executor (검증)
```

### 버그 수정

```
debug-specialist (reproduce → hypothesize → test → fix → verify)
→ /verify_complete → /git_commit
```

### 설계 탐색

```
/brainstorm (3+ 접근법 비교) → 사용자 결정 → plan-architect
```

---

## v2.0 주요 변경사항

### 간소화
- 에이전트: 23개 → 15개 (-35%)
- 스킬: 34개 → 32개 (-6%)
- 외부 의존성 제거 (Gemini CLI 불필요)

### 새로운 기능
- **6단계 명시적 워크플로우**: 요구사항 → Plan → 검증 → 조율 → 실행 → 검증
- **Plan 자체 검증**: plan-architect가 자동으로 Plan 검증 (점수 8/10 이상 필요)
- **병렬 실행**: orchestrator가 의존성 분석 후 병렬 그룹으로 실행
- **필수 구현 검증**: code-reviewer + qa-executor 자동 실행

### 통합된 에이전트
- `code-reviewer`: docs-reviewer 기능 통합
- `qa-executor`: qa-planner + qa-healer 기능 통합

### 삭제된 에이전트
- `git-ops` → `/git_commit` 스킬 사용
- `plan-feedback` → plan-architect 자체 검증
- `brainstorm-facilitator` → `/brainstorm` 스킬
- `pr-reviewer`, `docs-reviewer`, `qa-planner`, `qa-healer`, `reporter`
