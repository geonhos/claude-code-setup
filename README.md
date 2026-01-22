# Claude Code Agents & Skills

Claude Code를 위한 커스텀 Agent 및 Skill 라이브러리

## 구성

| 항목 | 수량 |
|------|------|
| Agents | 13개 |
| Skills | 25개 |

---

## Agents

### Pipeline (4개)

작업 흐름 관리

| Agent | 역할 |
|-------|------|
| `requirements-analyst` | 요구사항 분석 및 명확화 |
| `plan-architect` | 실행 계획 수립 |
| `plan-feedback` | Cross-LLM 검증 (Gemini CLI) |
| `orchestrator` | 작업 조율 및 분배 |

### Execution (4개)

개발 작업 수행

| Agent | 역할 | 기술 스택 |
|-------|------|-----------|
| `backend-dev` | 백엔드 개발 | Java, Spring Boot, DDD |
| `frontend-dev` | 프론트엔드 개발 | React, TypeScript, MVVM |
| `ai-expert` | AI/ML 개발 | Python, LLM, RAG |
| `git-ops` | Git 작업 관리 | Git Flow, GitHub CLI |

### Quality (5개)

품질 보증

| Agent | 역할 |
|-------|------|
| `qa-planner` | 테스트 계획 수립 |
| `qa-executor` | 테스트 실행 및 분석 |
| `qa-healer` | 테스트 실패 복구 |
| `security-analyst` | 보안 코드 리뷰, OWASP Top 10 |
| `reporter` | 실행 보고서 생성 |

---

## Skills

### Git (5개)

| Skill | 설명 |
|-------|------|
| `/git_commit` | 구조화된 커밋 메시지 |
| `/git_branch` | 브랜치 명명 규칙 |
| `/git_pr` | PR 템플릿 |
| `/git_issue` | Issue 템플릿 |
| `/git_analyze` | 변경사항 분석 |

### Python (4개)

| Skill | 설명 |
|-------|------|
| `/python_setup` | Python 프로젝트 초기화 |
| `/fastapi_setup` | FastAPI 프로젝트 구조 |
| `/api_test_setup` | API 테스트 설정 |
| `/rag_setup` | RAG 파이프라인 설정 |

### Java (3개)

| Skill | 설명 |
|-------|------|
| `/spring_boot_setup` | Spring Boot 프로젝트 |
| `/gradle_setup` | Gradle 멀티모듈 설정 |
| `/jpa_entity` | JPA Entity 생성 |

### React (3개)

| Skill | 설명 |
|-------|------|
| `/react_setup` | React/Vite 프로젝트 |
| `/nextjs_setup` | Next.js 14+ 프로젝트 |
| `/component_generator` | MVVM 컴포넌트 생성 |

### AI/ML (2개)

| Skill | 설명 |
|-------|------|
| `/mlflow_setup` | MLflow 실험 추적 |
| `/langchain_setup` | LangChain RAG 설정 |

### Infrastructure (2개)

| Skill | 설명 |
|-------|------|
| `/docker_setup` | Docker Compose 설정 |
| `/alembic_migration` | DB 마이그레이션 |

### Quality (4개)

| Skill | 설명 |
|-------|------|
| `/test_plan_template` | 테스트 계획 생성 |
| `/test_runner` | 테스트 실행 |
| `/coverage_report` | 커버리지 분석 |
| `/execution_report` | 실행 보고서 |

### Base (2개)

| Skill | 설명 |
|-------|------|
| `/project_init` | 프로젝트 초기화 |
| `/tdd_workflow` | TDD 워크플로우 |

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
