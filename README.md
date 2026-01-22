# Claude Code Agents & Skills

Claude Code를 위한 커스텀 Agent 및 Skill 라이브러리입니다.

---

## Overview

| 항목 | 수량 | 설명 |
|------|------|------|
| **[Agents](./.claude/agents/README.md)** | 12개 | 특화된 작업을 수행하는 AI 에이전트 |
| **[Skills](./.claude/skills/README.md)** | 25개 | 재사용 가능한 워크플로우 템플릿 |

### 벤치마크 결과

```
Agent/Skill 사용 시 정확도: 4.5/5 (+50% 향상)
구조화된 출력, 일관성 보장
```

---

## Quick Start

### Agent 사용

```bash
# 요구사항 분석
"Analyze requirements for user authentication feature"
→ requirements-analyst 자동 호출

# 실행 계획 수립
"Create execution plan for payment integration"
→ plan-architect 자동 호출
```

### Skill 사용

```bash
# 슬래시 명령으로 호출
/git_commit          # 구조화된 커밋 메시지 생성
/fastapi_setup       # FastAPI 프로젝트 구조 생성
/react_setup         # React 프로젝트 구조 생성
/tdd_workflow        # TDD 워크플로우 실행
```

---

## Agents

### Pipeline Agents (4)

작업 흐름을 관리하는 에이전트

| Agent | 역할 | 정확도 |
|-------|------|--------|
| [`requirements-analyst`](./.claude/agents/pipeline/requirements-analyst.md) | 요구사항 분석 및 명확화 | 5/5 |
| [`plan-architect`](./.claude/agents/pipeline/plan-architect.md) | 실행 계획 수립 | 5/5 |
| [`plan-feedback`](./.claude/agents/pipeline/plan-feedback.md) | Cross-LLM 검증 (Gemini CLI) | 5/5 |
| [`orchestrator`](./.claude/agents/pipeline/orchestrator.md) | 작업 조율 및 분배 | 4/5 |

### Execution Agents (4)

실제 개발 작업을 수행하는 에이전트

| Agent | 역할 | 기술 스택 | 정확도 |
|-------|------|-----------|--------|
| [`backend-dev`](./.claude/agents/execution/backend-dev.md) | 백엔드 개발 | Java, Spring Boot, DDD | 5/5 |
| [`frontend-dev`](./.claude/agents/execution/frontend-dev.md) | 프론트엔드 개발 | React, TypeScript, MVVM | 5/5 |
| [`ai-expert`](./.claude/agents/execution/ai-expert.md) | AI/ML 개발 | Python, LLM, Data Pipeline | 5/5 |
| [`git-ops`](./.claude/agents/execution/git-ops.md) | Git 작업 관리 | Git Flow, GitHub CLI | 4/5 |

### Quality Agents (4)

품질 보증을 담당하는 에이전트

| Agent | 역할 | 정확도 |
|-------|------|--------|
| [`qa-planner`](./.claude/agents/quality/qa-planner.md) | 테스트 계획 수립 | 5/5 |
| [`qa-executor`](./.claude/agents/quality/qa-executor.md) | 테스트 실행 및 분석 | 4/5 |
| [`qa-healer`](./.claude/agents/quality/qa-healer.md) | 테스트 실패 복구 | 5/5 |
| [`reporter`](./.claude/agents/quality/reporter.md) | 실행 보고서 생성 | 4/5 |

---

## Skills

### Git (5)

| Skill | 설명 | 명령 |
|-------|------|------|
| [`git_commit`](./.claude/skills/git/git_commit/SKILL.md) | 구조화된 커밋 메시지 | `/git_commit` |
| [`git_branch`](./.claude/skills/git/git_branch/SKILL.md) | 브랜치 명명 규칙 | `/git_branch` |
| [`git_pr`](./.claude/skills/git/git_pr/SKILL.md) | PR 템플릿 | `/git_pr` |
| [`git_issue`](./.claude/skills/git/git_issue/SKILL.md) | Issue 템플릿 | `/git_issue` |
| [`git_analyze`](./.claude/skills/git/git_analyze/SKILL.md) | 변경사항 분석 | `/git_analyze` |

### Python (4)

| Skill | 설명 | 명령 |
|-------|------|------|
| [`python_setup`](./.claude/skills/python/python_setup/SKILL.md) | Python 프로젝트 초기화 | `/python_setup` |
| [`fastapi_setup`](./.claude/skills/python/fastapi_setup/SKILL.md) | FastAPI 프로젝트 구조 | `/fastapi_setup` |
| [`api_test_setup`](./.claude/skills/python/api_test_setup/SKILL.md) | API 테스트 설정 | `/api_test_setup` |
| [`rag_setup`](./.claude/skills/python/rag_setup/SKILL.md) | RAG 파이프라인 설정 | `/rag_setup` |

### Java (3)

| Skill | 설명 | 명령 |
|-------|------|------|
| [`spring_boot_setup`](./.claude/skills/java/spring_boot_setup/SKILL.md) | Spring Boot 프로젝트 | `/spring_boot_setup` |
| [`gradle_setup`](./.claude/skills/java/gradle_setup/SKILL.md) | Gradle 멀티모듈 설정 | `/gradle_setup` |
| [`jpa_entity`](./.claude/skills/java/jpa_entity/SKILL.md) | JPA Entity 생성 | `/jpa_entity` |

### React (3)

| Skill | 설명 | 명령 |
|-------|------|------|
| [`react_setup`](./.claude/skills/react/react_setup/SKILL.md) | React/Vite 프로젝트 | `/react_setup` |
| [`nextjs_setup`](./.claude/skills/react/nextjs_setup/SKILL.md) | Next.js 14+ 프로젝트 | `/nextjs_setup` |
| [`component_generator`](./.claude/skills/react/component_generator/SKILL.md) | MVVM 컴포넌트 생성 | `/component_generator` |

### AI/ML (2)

| Skill | 설명 | 명령 |
|-------|------|------|
| [`mlflow_setup`](./.claude/skills/ai/mlflow_setup/SKILL.md) | MLflow 실험 추적 | `/mlflow_setup` |
| [`langchain_setup`](./.claude/skills/ai/langchain_setup/SKILL.md) | LangChain RAG 설정 | `/langchain_setup` |

### Infrastructure (2)

| Skill | 설명 | 명령 |
|-------|------|------|
| [`docker_setup`](./.claude/skills/infra/docker_setup/SKILL.md) | Docker Compose 설정 | `/docker_setup` |
| [`alembic_migration`](./.claude/skills/infra/alembic_migration/SKILL.md) | DB 마이그레이션 | `/alembic_migration` |

### Quality (4)

| Skill | 설명 | 명령 |
|-------|------|------|
| [`test_plan_template`](./.claude/skills/quality/test_plan_template/SKILL.md) | 테스트 계획 생성 | `/test_plan_template` |
| [`test_runner`](./.claude/skills/quality/test_runner/SKILL.md) | 테스트 실행 | `/test_runner` |
| [`coverage_report`](./.claude/skills/quality/coverage_report/SKILL.md) | 커버리지 분석 | `/coverage_report` |
| [`execution_report`](./.claude/skills/quality/execution_report/SKILL.md) | 실행 보고서 | `/execution_report` |

### Base & Methodology (2)

| Skill | 설명 | 명령 |
|-------|------|------|
| [`project_init`](./.claude/skills/base/project_init/SKILL.md) | 프로젝트 초기화 | `/project_init` |
| [`tdd_workflow`](./.claude/skills/methodology/tdd_workflow/SKILL.md) | TDD 워크플로우 | `/tdd_workflow` |

---

## Directory Structure

```
.claude/
├── settings.json             ← 프로젝트별 설정
├── BENCHMARK_RESULTS.md      ← 벤치마크 결과
├── agents/
│   ├── README.md             ← Agent 상세 문서
│   ├── pipeline/
│   │   ├── requirements-analyst.md
│   │   ├── plan-architect.md
│   │   ├── plan-feedback.md
│   │   └── orchestrator.md
│   ├── execution/
│   │   ├── backend-dev.md
│   │   ├── frontend-dev.md
│   │   ├── ai-expert.md
│   │   └── git-ops.md
│   └── quality/
│       ├── qa-planner.md
│       ├── qa-executor.md
│       ├── qa-healer.md
│       └── reporter.md
└── skills/
    ├── README.md             ← Skill 상세 문서
    ├── SKILLS_REGISTRY.md    ← Skill 등록 정보
    ├── git/
    ├── python/
    ├── java/
    ├── react/
    ├── ai/
    ├── infra/
    ├── quality/
    ├── base/
    └── methodology/
```

---

## Settings (settings.json)

프로젝트별 Claude Code 설정 파일입니다.

### 위치

```
.claude/settings.json
```

### 동작 원리

1. Claude Code 실행 시 `.claude/settings.json` 파일을 자동으로 감지
2. 설정값을 읽어 해당 세션에 적용
3. 프로젝트별로 다른 설정 유지 가능

### 설정 예시

```json
{
  "plansDirectory": "./plans"
}
```

### 주요 설정 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `plansDirectory` | Plan 파일 저장 경로 | `.claude/plans` |

> **참고**: 설정 파일은 프로젝트 루트의 `.claude/` 디렉토리에 위치해야 합니다.

---

## Use Cases

### 1. 새 기능 개발

```
1. /project_init              # 프로젝트 초기화
2. requirements-analyst       # 요구사항 분석
3. plan-architect            # 실행 계획 수립
4. plan-feedback             # Gemini CLI로 계획 검증
5. /fastapi_setup            # 백엔드 설정
6. backend-dev               # API 개발
7. /git_commit               # 커밋
8. /git_pr                   # PR 생성
```

### 2. 버그 수정

```
1. /git_branch               # 브랜치 생성
2. /git_analyze              # 변경사항 분석
3. qa-healer                 # 테스트 실패 복구
4. /git_commit               # 커밋
5. /git_pr                   # PR 생성
```

### 3. 테스트 계획

```
1. qa-planner                # 테스트 계획 수립
2. /test_plan_template       # 테스트 계획 문서화
3. qa-executor               # 테스트 실행
4. /coverage_report          # 커버리지 분석
```

---

## Benchmark Summary

| 항목 | Agent/Skill | 미사용 | 결과 |
|------|-------------|--------|------|
| 정확도 | 4.5/5 | 3.0/5 | **+50%** |
| 구조화 | 높음 | 낮음 | 우수 |
| 일관성 | 높음 | 가변적 | 우수 |

> 자세한 결과는 [BENCHMARK_RESULTS.md](./.claude/BENCHMARK_RESULTS.md) 참조

---

## Recommendations

### 필수 사용

- 복잡한 요구사항 분석
- 대규모 기능 개발
- 팀 프로젝트 (일관성 필요)
- CI/CD 파이프라인

### 선택적 사용

- 단순 1회성 작업
- 빠른 프로토타이핑

---

## License

MIT License

---

*Last Updated: 2026-01-22*
