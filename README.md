# Claude Code Agents & Skills

Claude Code를 위한 멀티에이전트 시스템 플러그인

## 설치

Claude Code에서 실행:

```
/plugin marketplace add geonhos/claude-code-setup
/plugin add multi-agent-system
```

설치 완료! 세션 시작 시 자동으로 에이전트와 스킬이 소개됩니다.

```
===== Multi-Agent System 활성화 =====

23개 전문 에이전트와 34개 스킬이 로드되었습니다.

[Agents]
- Pipeline: requirements-analyst, plan-architect, plan-feedback, brainstorm-facilitator, orchestrator
- Execution: git-ops, backend-dev, frontend-dev, ai-expert, devops-engineer, database-expert, docs-writer, refactoring-expert
- Quality: qa-planner, qa-executor, qa-healer, code-reviewer, pr-reviewer, docs-reviewer, security-analyst, performance-analyst, debug-specialist, reporter

[Skills]
- Git: /git_commit, /git_branch, /git_pr, /git_issue, /git_analyze, /git_worktree
- Dev: /python_setup, /fastapi_setup, /react_setup, /spring_boot_setup
- Quality: /test_runner, /coverage_report, /test_plan_template
- Workflow: /brainstorm, /checkpoint, /verify_complete, /debug_workflow, /task_breakdown

==========================================
```

## 구성

| 항목 | 수량 |
|------|------|
| Agents | 23개 |
| Skills | 34개 |

---

## Agents

### Pipeline (5개)

작업 흐름 관리

| Agent | 역할 |
|-------|------|
| [`requirements-analyst`](agents/pipeline/requirements-analyst.md) | 요구사항 분석 및 명확화 |
| [`plan-architect`](agents/pipeline/plan-architect.md) | 실행 계획 수립 (atomic 2-5min task breakdown) |
| [`plan-feedback`](agents/pipeline/plan-feedback.md) | Cross-LLM 검증 (Gemini CLI) |
| [`orchestrator`](agents/pipeline/orchestrator.md) | 작업 조율 및 분배 (checkpoint 실행 지원) |
| [`brainstorm-facilitator`](agents/pipeline/brainstorm-facilitator.md) | 설계 탐색 및 결정 촉진 (NEW) |

### Execution (8개)

개발 작업 수행

| Agent | 역할 | 기술 스택 |
|-------|------|-----------|
| [`backend-dev`](agents/execution/backend-dev.md) | 백엔드 개발 | Java, Spring Boot, DDD |
| [`frontend-dev`](agents/execution/frontend-dev.md) | 프론트엔드 개발 | React, TypeScript, MVVM |
| [`ai-expert`](agents/execution/ai-expert.md) | AI/ML 개발 | Python, LLM, RAG |
| [`git-ops`](agents/execution/git-ops.md) | Git 작업 관리 | Git Flow, GitHub CLI |
| [`devops-engineer`](agents/execution/devops-engineer.md) | DevOps/인프라 | Docker, K8s, CI/CD |
| [`database-expert`](agents/execution/database-expert.md) | 데이터베이스 | Schema, Query 최적화 |
| [`refactoring-expert`](agents/execution/refactoring-expert.md) | 리팩토링 | 레거시 개선, 기술부채 |
| [`docs-writer`](agents/execution/docs-writer.md) | 문서화 | API docs, README |

### Quality (10개)

품질 보증

| Agent | 역할 |
|-------|------|
| [`qa-planner`](agents/quality/qa-planner.md) | 테스트 계획 수립 |
| [`qa-executor`](agents/quality/qa-executor.md) | 테스트 실행 및 분석 |
| [`qa-healer`](agents/quality/qa-healer.md) | 테스트 실패 복구 |
| [`security-analyst`](agents/quality/security-analyst.md) | 보안 코드 리뷰, OWASP Top 10 |
| [`pr-reviewer`](agents/quality/pr-reviewer.md) | PR 리뷰 (Gemini CLI) |
| [`docs-reviewer`](agents/quality/docs-reviewer.md) | 문서 품질 리뷰 |
| [`reporter`](agents/quality/reporter.md) | 실행 보고서 생성 |
| [`code-reviewer`](agents/quality/code-reviewer.md) | 코드 품질 리뷰 |
| [`performance-analyst`](agents/quality/performance-analyst.md) | 성능 분석 및 최적화 |
| [`debug-specialist`](agents/quality/debug-specialist.md) | 체계적 가설 기반 디버깅 (NEW) |

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
| [`/git_worktree`](skills/git/git_worktree/SKILL.md) | 병렬 브랜치 개발 (NEW) |

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

### Quality (4개)

| Skill | 설명 |
|-------|------|
| [`/test_plan_template`](skills/quality/test_plan_template/SKILL.md) | 테스트 계획 생성 |
| [`/test_runner`](skills/quality/test_runner/SKILL.md) | 테스트 실행 |
| [`/coverage_report`](skills/quality/coverage_report/SKILL.md) | 커버리지 분석 |
| [`/execution_report`](skills/quality/execution_report/SKILL.md) | 실행 보고서 |

### Base (2개)

| Skill | 설명 |
|-------|------|
| [`/project_init`](skills/base/project_init/SKILL.md) | 프로젝트 초기화 |
| [`/tdd_workflow`](skills/methodology/tdd_workflow/SKILL.md) | TDD 워크플로우 |

### Workflow (5개) (NEW)

| Skill | 설명 |
|-------|------|
| [`/brainstorm`](skills/workflow/brainstorm/SKILL.md) | 설계 탐색 - 최소 3개 접근법 비교 후 결정 |
| [`/checkpoint`](skills/workflow/checkpoint/SKILL.md) | 실행 체크포인트 - 5개 태스크마다 검증 |
| [`/task_breakdown`](skills/workflow/task_breakdown/SKILL.md) | 태스크 분해 - 2-5분 단위 atomic 태스크 |
| [`/debug_workflow`](skills/workflow/debug_workflow/SKILL.md) | 디버깅 워크플로우 - 가설 기반 체계적 디버깅 |
| [`/verify_complete`](skills/workflow/verify_complete/SKILL.md) | 완료 검증 - 태스크 완료 전 필수 검증 |

---

## 디렉토리 구조

```
# 플러그인 구조 (루트)
plugin.json                # 플러그인 매니페스트
marketplace.json           # 마켓플레이스 정보
.claude-plugin/
└── marketplace.json       # 마켓플레이스 정보 (복사본)

agents/                    # 에이전트 정의
├── pipeline/              # 워크플로우 에이전트
├── execution/             # 개발 에이전트
└── quality/               # 품질 에이전트

skills/                    # 스킬 정의
├── git/                   # Git 관련 (worktree 포함)
├── python/                # Python 관련
├── java/                  # Java 관련
├── react/                 # React 관련
├── ai/                    # AI/ML 관련
├── infra/                 # 인프라 관련
├── quality/               # 품질 관련
├── base/                  # 기본
├── methodology/           # 방법론
└── workflow/              # 워크플로우 (brainstorm, checkpoint, etc.)

# 프로젝트 설정 (Standalone 사용 시)
.claude/
├── CLAUDE.md              # 개발 지침
├── settings.json          # 프로젝트 설정
└── protocols/             # 공통 프로토콜

# Generated directories (gitignored)
plans/                     # 실행 계획
logs/                      # 에이전트 로그
reports/                   # 실행 리포트
```

---

## 사용 예시

### 새 기능 개발 (Enhanced Pipeline)

```
/project_init → requirements-analyst → brainstorm-facilitator (복잡한 결정 시)
→ plan-architect (atomic 2-5min tasks) → [execution agents with checkpoint every 5 tasks]
→ /verify_complete → qa-executor → /git_commit → /git_pr
```

### 보안 검토

```
security-analyst → backend-dev (수정) → qa-executor (검증)
```

### 버그 수정 (Systematic Debugging)

```
debug-specialist (reproduce → hypothesize → test → fix → verify)
→ /verify_complete → /git_commit → /git_pr
```

### 병렬 기능 개발 (Git Worktree)

```
/git_worktree (create ../project-feature) → [개발] → /git_worktree (remove)
```

### 체크포인트 실행

```
orchestrator (batch_size: 5)
→ [Task 1-5] → /checkpoint (summary + verification)
→ [Task 6-10] → /checkpoint
→ ... → completion
```
