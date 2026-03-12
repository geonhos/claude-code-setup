# Claude Code Agents & Skills

Claude Code를 위한 멀티에이전트 시스템 플러그인 v2.4.0

## 설치

Claude Code에서 실행:

```
/plugin marketplace add geonhos/claude-code-setup
/plugin add multi-agent-system
```

설치 완료! 세션 시작 시 자동으로 에이전트와 스킬이 소개됩니다.

```xml
<multi-agent-system version="2.4.0">
<summary>15 agents, 32 skills loaded</summary>

<workflow>
1.Requirements → 2.Plan → 3.Validate(≥8) → 4.Orchestrate → 5.Execute(parallel) → 6.Verify
</workflow>

<agents>
<pipeline>requirements-analyst, plan-architect, orchestrator</pipeline>
<execution>frontend-dev, backend-dev, ai-expert, database-expert, devops-engineer, docs-writer, refactoring-expert</execution>
<quality>code-reviewer, qa-executor, security-analyst, performance-analyst, debug-specialist</quality>
</agents>

<routing>semantic — agent descriptions drive automatic dispatch</routing>

<mcp-servers>context7, filesystem, playwright</mcp-servers>
</multi-agent-system>
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

워크플로우 관리 — `model: inherit` (호출자 모델 상속)

| Agent | 역할 | Skills |
|-------|------|--------|
| [`requirements-analyst`](agents/pipeline/requirements-analyst.md) | 요구사항 분석 및 명확화 | brainstorm |
| [`plan-architect`](agents/pipeline/plan-architect.md) | 실행 계획 수립 + 자체 검증 | task_breakdown |
| [`orchestrator`](agents/pipeline/orchestrator.md) | Plan 기반 병렬 실행 조율 | — |

### Execution (7개)

개발 작업 수행 — `model: sonnet`, 읽기/쓰기 도구 전체 사용

| Agent | 역할 | Skills |
|-------|------|--------|
| [`backend-dev`](agents/execution/backend-dev.md) | 백엔드 (Java, Spring Boot, DDD) | spring_best_practices, jpa_entity |
| [`frontend-dev`](agents/execution/frontend-dev.md) | 프론트엔드 (React, TypeScript, MVVM) | react_best_practices, component_generator |
| [`ai-expert`](agents/execution/ai-expert.md) | AI/ML (Python, LLM, RAG) | python_best_practices, rag_setup |
| [`database-expert`](agents/execution/database-expert.md) | 데이터베이스 (Schema, Query 최적화) | alembic_migration |
| [`devops-engineer`](agents/execution/devops-engineer.md) | DevOps/인프라 (Docker, K8s, CI/CD) | docker_setup |
| [`refactoring-expert`](agents/execution/refactoring-expert.md) | 리팩토링 (레거시 개선, 기술부채) | — |
| [`docs-writer`](agents/execution/docs-writer.md) | 문서화 (API docs, README) | — |

### Quality (5개)

품질 보증 — `model: sonnet`, 읽기 전용 도구 (debug-specialist 제외)

| Agent | 역할 | Skills | Memory |
|-------|------|--------|--------|
| [`code-reviewer`](agents/quality/code-reviewer.md) | 코드/문서 품질 리뷰 | verify_complete | project |
| [`qa-executor`](agents/quality/qa-executor.md) | 테스트 계획/실행/분석 통합 | test_runner, coverage_report | — |
| [`security-analyst`](agents/quality/security-analyst.md) | 보안 코드 리뷰, OWASP Top 10 | — | project |
| [`performance-analyst`](agents/quality/performance-analyst.md) | 성능 분석 및 최적화 | — | — |
| [`debug-specialist`](agents/quality/debug-specialist.md) | 체계적 가설 기반 디버깅 | debug_workflow | — |

---

## Skills

### Git (6개)

| Skill | 설명 |
|-------|------|
| [`/git_commit`](skills/git_commit/SKILL.md) | 구조화된 커밋 메시지 |
| [`/git_branch`](skills/git_branch/SKILL.md) | 브랜치 명명 규칙 |
| [`/git_pr`](skills/git_pr/SKILL.md) | PR 템플릿 |
| [`/git_issue`](skills/git_issue/SKILL.md) | Issue 템플릿 |
| [`/git_analyze`](skills/git_analyze/SKILL.md) | 변경사항 분석 |
| [`/git_worktree`](skills/git_worktree/SKILL.md) | 병렬 브랜치 개발 |

### Python (5개)

| Skill | 설명 |
|-------|------|
| [`/python_setup`](skills/python_setup/SKILL.md) | Python 프로젝트 초기화 |
| [`/fastapi_setup`](skills/fastapi_setup/SKILL.md) | FastAPI 프로젝트 구조 |
| [`/api_test_setup`](skills/api_test_setup/SKILL.md) | API 테스트 설정 |
| [`/rag_setup`](skills/rag_setup/SKILL.md) | RAG 파이프라인 설정 |
| [`/python_best_practices`](skills/python_best_practices/SKILL.md) | Python 모범 사례 |

### Java (4개)

| Skill | 설명 |
|-------|------|
| [`/spring_boot_setup`](skills/spring_boot_setup/SKILL.md) | Spring Boot 프로젝트 |
| [`/gradle_setup`](skills/gradle_setup/SKILL.md) | Gradle 멀티모듈 설정 |
| [`/jpa_entity`](skills/jpa_entity/SKILL.md) | JPA Entity 생성 |
| [`/spring_best_practices`](skills/spring_best_practices/SKILL.md) | Spring 모범 사례 |

### React (4개)

| Skill | 설명 |
|-------|------|
| [`/react_setup`](skills/react_setup/SKILL.md) | React/Vite 프로젝트 |
| [`/nextjs_setup`](skills/nextjs_setup/SKILL.md) | Next.js 14+ 프로젝트 |
| [`/component_generator`](skills/component_generator/SKILL.md) | MVVM 컴포넌트 생성 |
| [`/react_best_practices`](skills/react_best_practices/SKILL.md) | React 모범 사례 |

### AI/ML (2개)

| Skill | 설명 |
|-------|------|
| [`/mlflow_setup`](skills/mlflow_setup/SKILL.md) | MLflow 실험 추적 |
| [`/langchain_setup`](skills/langchain_setup/SKILL.md) | LangChain RAG 설정 |

### Infrastructure (2개)

| Skill | 설명 |
|-------|------|
| [`/docker_setup`](skills/docker_setup/SKILL.md) | Docker Compose 설정 |
| [`/alembic_migration`](skills/alembic_migration/SKILL.md) | DB 마이그레이션 |

### Quality (3개)

| Skill | 설명 |
|-------|------|
| [`/test_plan_template`](skills/test_plan_template/SKILL.md) | 테스트 계획 생성 |
| [`/test_runner`](skills/test_runner/SKILL.md) | 테스트 실행 |
| [`/coverage_report`](skills/coverage_report/SKILL.md) | 커버리지 분석 |

### Base (2개)

| Skill | 설명 |
|-------|------|
| [`/project_init`](skills/project_init/SKILL.md) | 프로젝트 초기화 |
| [`/tdd_workflow`](skills/tdd_workflow/SKILL.md) | TDD 워크플로우 |

### Workflow (4개)

| Skill | 설명 |
|-------|------|
| [`/brainstorm`](skills/brainstorm/SKILL.md) | 설계 탐색 - 최소 3개 접근법 비교 |
| [`/task_breakdown`](skills/task_breakdown/SKILL.md) | 태스크 분해 - 2-5분 단위 atomic 태스크 |
| [`/debug_workflow`](skills/debug_workflow/SKILL.md) | 디버깅 워크플로우 |
| [`/verify_complete`](skills/verify_complete/SKILL.md) | 완료 검증 |

---

## 디렉토리 구조

```
# 플러그인 구조 (루트)
plugin.json                # 플러그인 매니페스트
marketplace.json           # 마켓플레이스 정보

hooks/
├── hooks.json               # 훅 이벤트 설정
├── startup.sh               # SessionStart: ASCII Art 배너
└── agent-progress.sh        # SubagentStart/Stop: 진행 추적

agents/                    # 에이전트 정의 (15개)
├── pipeline/              # 워크플로우 에이전트 (3개)
├── execution/             # 개발 에이전트 (7개)
└── quality/               # 품질 에이전트 (5개)

skills/                    # 스킬 정의 (32개, flat 구조)
├── git_commit/            # Git 관련 (6개)
├── python_setup/          # Python 관련 (5개)
├── spring_boot_setup/     # Java 관련 (4개)
├── react_setup/           # React 관련 (4개)
├── brainstorm/            # Workflow 관련 (4개)
└── ...                    # 총 32개 스킬

# 프로젝트 설정
.claude/
├── settings.json          # 프로젝트 설정
└── protocols/             # 공통 프로토콜
    ├── workflow-detail.md     # 6단계 워크플로우 상세
    ├── agents-reference.md    # 15개 에이전트 레퍼런스
    ├── skills-reference.md    # 32개 스킬 레퍼런스
    ├── checklists.md          # 개발 체크리스트
    ├── agent-template-light.md # 경량 에이전트 템플릿
    ├── agent-refactoring-guide.md # 에이전트 리팩토링 가이드
    ├── boundary-protocol.md   # 역할 경계 프로토콜
    └── logging.md             # 로깅 프로토콜

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

## 주요 변경사항

### v2.4.0 - Skills 2.0 적용 + 프로젝트 정리
- **Skills 2.0 전면 적용**: `context: fork`, `allowed-tools`, `argument-hint` 등 신규 필드 적용
- **서브에이전트 격리**: `brainstorm`, `debug_workflow`, `task_breakdown`에 `context: fork` 적용 (메인 컨텍스트 보호)
- **도구 제한**: 16개 스킬에 `allowed-tools` 적용 (git 스킬은 read-only, 워크플로우 스킬은 분석 전용)
- **자동완성 힌트**: 11개 스킬에 `argument-hint` 추가 (`/brainstorm [topic]` 등)
- **Best practices 자동 참조**: `react_best_practices`, `spring_best_practices`, `python_best_practices`에서 `disable-model-invocation` 제거 → Claude가 코드 작성 시 자동 트리거
- **startup.sh 동적화**: 에이전트/스킬/MCP/버전 수치를 파일시스템에서 자동 계산 (하드코딩 제거)
- **Plans 정리**: 완료된 플랜 9개 `plans/archived/`로 이동
- **설정 중복 제거**: `settings.local.json`의 중복 `enabledPlugins` 제거

### v2.3.1 - Agent 스코핑, 스킬 프리로딩, Playwright MCP
- Agent frontmatter 강화, 모델/도구/스킬 스코핑, Playwright MCP, Semantic routing

### v2.2.0 - 동적 에이전트 매칭 훅 + CLAUDE.md 제거

### v2.0.0 - 간소화 + 6단계 워크플로우
- 에이전트: 23개 → 15개 (-35%), 6단계 명시적 워크플로우, Plan 자체 검증, 병렬 실행

[전체 변경 이력 → CHANGELOG.md](CHANGELOG.md)
