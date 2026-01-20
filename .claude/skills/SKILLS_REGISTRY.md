# Skills Registry

현재 디렉토리의 모든 스킬을 시스템에 등록하기 위한 레지스트리입니다.

## 전체 스킬 목록 (25개)

### Base (1)

| Skill | Path | Description |
|-------|------|-------------|
| `project_init` | `base/project_init` | Creates basic project structure with git, .gitignore, README |

### Git (5)

| Skill | Path | Description |
|-------|------|-------------|
| `git_analyze` | `git/git_analyze` | Analyzes Git changes with diff summaries and commit history |
| `git_branch` | `git/git_branch` | Manages Git branches with consistent naming conventions |
| `git_commit` | `git/git_commit` | Generates structured commit messages following [Phase X] format |
| `git_issue` | `git/git_issue` | Creates and manages GitHub issues with structured templates |
| `git_pr` | `git/git_pr` | Creates and manages Pull Requests with structured templates |

### Infra (2)

| Skill | Path | Description |
|-------|------|-------------|
| `docker_setup` | `infra/docker_setup` | Creates Docker and docker-compose configuration |
| `alembic_migration` | `infra/alembic_migration` | Manages database migrations with Alembic |

### Methodology (1)

| Skill | Path | Description |
|-------|------|-------------|
| `tdd_workflow` | `methodology/tdd_workflow` | Implements TDD workflow (Red-Green-Refactor) |

### Python (4)

| Skill | Path | Description |
|-------|------|-------------|
| `python_setup` | `python/python_setup` | Sets up Python project with venv, dependencies, tests |
| `fastapi_setup` | `python/fastapi_setup` | Sets up FastAPI project with routers, models, services |
| `api_test_setup` | `python/api_test_setup` | Sets up API testing with pytest, httpx, fixtures |
| `rag_setup` | `python/rag_setup` | Sets up RAG project with ChromaDB and embeddings |

### Java (3)

| Skill | Path | Description |
|-------|------|-------------|
| `spring_boot_setup` | `java/spring_boot_setup` | Sets up Spring Boot with DDD structure |
| `gradle_setup` | `java/gradle_setup` | Gradle multi-module configuration |
| `jpa_entity` | `java/jpa_entity` | JPA entity generation with patterns |

### React (3)

| Skill | Path | Description |
|-------|------|-------------|
| `react_setup` | `react/react_setup` | Sets up React/Vite with FSD structure |
| `nextjs_setup` | `react/nextjs_setup` | Sets up Next.js 14+ with App Router |
| `component_generator` | `react/component_generator` | Generates MVVM component with tests |

### AI/ML (2)

| Skill | Path | Description |
|-------|------|-------------|
| `mlflow_setup` | `ai/mlflow_setup` | Experiment tracking and model registry |
| `langchain_setup` | `ai/langchain_setup` | LLM application with RAG |

### Quality (4)

| Skill | Path | Description |
|-------|------|-------------|
| `test_plan_template` | `quality/test_plan_template` | Comprehensive test plan generation |
| `test_runner` | `quality/test_runner` | Multi-framework test execution |
| `coverage_report` | `quality/coverage_report` | Coverage analysis and recommendations |
| `execution_report` | `quality/execution_report` | Agent execution summary reports |

---

## 시스템 등록용 설정

아래 설정을 Claude Code 설정 파일에 복사하여 스킬을 등록하세요.

### settings.json 형식

```json
{
  "skills": [
    {
      "name": "project_init",
      "description": "Creates basic project structure with git initialization, .gitignore, README, and environment setup. Use as the first step for any new project.",
      "path": ".claude/skills/base/project_init/SKILL.md"
    },
    {
      "name": "git_analyze",
      "description": "Analyzes Git changes with diff summaries and commit history. Provides token-efficient code change analysis.",
      "path": ".claude/skills/git/git_analyze/SKILL.md"
    },
    {
      "name": "git_branch",
      "description": "Manages Git branches with consistent naming conventions. Handles creation, switching, deletion based on issue numbers.",
      "path": ".claude/skills/git/git_branch/SKILL.md"
    },
    {
      "name": "git_commit",
      "description": "Analyzes staged changes and generates structured commit messages following [Phase X] format.",
      "path": ".claude/skills/git/git_commit/SKILL.md"
    },
    {
      "name": "git_issue",
      "description": "Creates and manages GitHub issues with structured templates. Handles issue creation, searching, and labeling.",
      "path": ".claude/skills/git/git_issue/SKILL.md"
    },
    {
      "name": "git_pr",
      "description": "Creates and manages Pull Requests with structured templates. Handles PR creation and merge strategies.",
      "path": ".claude/skills/git/git_pr/SKILL.md"
    },
    {
      "name": "docker_setup",
      "description": "Creates Docker and docker-compose configuration for development and production environments.",
      "path": ".claude/skills/infra/docker_setup/SKILL.md"
    },
    {
      "name": "alembic_migration",
      "description": "Manages database migrations with Alembic. Handles init, revision, upgrade, downgrade, and history.",
      "path": ".claude/skills/infra/alembic_migration/SKILL.md"
    },
    {
      "name": "tdd_workflow",
      "description": "Implements Kent Beck's TDD workflow. Follows Red-Green-Refactor cycle for test-first development.",
      "path": ".claude/skills/methodology/tdd_workflow/SKILL.md"
    },
    {
      "name": "python_setup",
      "description": "Sets up Python project structure with virtual environment, dependencies, test framework. Use after project_init.",
      "path": ".claude/skills/python/python_setup/SKILL.md"
    },
    {
      "name": "fastapi_setup",
      "description": "Sets up FastAPI project with routers, models, schemas, services, database, and tests. Use after python_setup.",
      "path": ".claude/skills/python/fastapi_setup/SKILL.md"
    },
    {
      "name": "api_test_setup",
      "description": "Sets up API testing patterns with pytest, httpx TestClient, fixtures, and coverage for FastAPI projects.",
      "path": ".claude/skills/python/api_test_setup/SKILL.md"
    },
    {
      "name": "rag_setup",
      "description": "Sets up RAG project with ChromaDB, embeddings, and document processing utilities.",
      "path": ".claude/skills/python/rag_setup/SKILL.md"
    },
    {
      "name": "spring_boot_setup",
      "description": "Sets up Spring Boot project with Gradle, DDD structure, and essential configurations.",
      "path": ".claude/skills/java/spring_boot_setup/SKILL.md"
    },
    {
      "name": "gradle_setup",
      "description": "Gradle multi-module project configuration with standard plugins and dependencies.",
      "path": ".claude/skills/java/gradle_setup/SKILL.md"
    },
    {
      "name": "jpa_entity",
      "description": "JPA entity generation with BaseEntity, auditing, and common patterns.",
      "path": ".claude/skills/java/jpa_entity/SKILL.md"
    },
    {
      "name": "react_setup",
      "description": "Sets up React/TypeScript project with Vite, Feature-Sliced Design, TanStack Query.",
      "path": ".claude/skills/react/react_setup/SKILL.md"
    },
    {
      "name": "nextjs_setup",
      "description": "Sets up Next.js 14+ with App Router, TypeScript, and Tailwind CSS.",
      "path": ".claude/skills/react/nextjs_setup/SKILL.md"
    },
    {
      "name": "component_generator",
      "description": "Generates React component with MVVM pattern, TypeScript, and tests.",
      "path": ".claude/skills/react/component_generator/SKILL.md"
    },
    {
      "name": "mlflow_setup",
      "description": "Sets up MLflow for experiment tracking and model registry.",
      "path": ".claude/skills/ai/mlflow_setup/SKILL.md"
    },
    {
      "name": "langchain_setup",
      "description": "Sets up LangChain application with RAG pipeline and vector store.",
      "path": ".claude/skills/ai/langchain_setup/SKILL.md"
    },
    {
      "name": "test_plan_template",
      "description": "Generates comprehensive test plan covering unit, integration, and E2E testing.",
      "path": ".claude/skills/quality/test_plan_template/SKILL.md"
    },
    {
      "name": "test_runner",
      "description": "Multi-framework test execution with result analysis and reporting.",
      "path": ".claude/skills/quality/test_runner/SKILL.md"
    },
    {
      "name": "coverage_report",
      "description": "Coverage analysis with recommendations for improving test coverage.",
      "path": ".claude/skills/quality/coverage_report/SKILL.md"
    },
    {
      "name": "execution_report",
      "description": "Agent execution summary reports with metrics and recommendations.",
      "path": ".claude/skills/quality/execution_report/SKILL.md"
    }
  ]
}
```

---

## 카테고리별 그룹 설정

프로젝트 유형별로 필요한 스킬만 선택적으로 등록할 수 있습니다.

### Python Backend 프로젝트

```json
{
  "skills": ["project_init", "python_setup", "fastapi_setup", "api_test_setup", "docker_setup", "alembic_migration", "tdd_workflow", "git_branch", "git_commit", "git_issue", "git_pr"]
}
```

### Java Backend 프로젝트

```json
{
  "skills": ["project_init", "spring_boot_setup", "gradle_setup", "jpa_entity", "docker_setup", "tdd_workflow", "git_branch", "git_commit", "git_issue", "git_pr"]
}
```

### React Frontend 프로젝트

```json
{
  "skills": ["project_init", "react_setup", "component_generator", "tdd_workflow", "git_branch", "git_commit", "git_issue", "git_pr"]
}
```

### Next.js Fullstack 프로젝트

```json
{
  "skills": ["project_init", "nextjs_setup", "component_generator", "docker_setup", "tdd_workflow", "git_branch", "git_commit", "git_issue", "git_pr"]
}
```

### AI/ML 프로젝트

```json
{
  "skills": ["project_init", "python_setup", "rag_setup", "mlflow_setup", "langchain_setup", "docker_setup", "tdd_workflow", "git_branch", "git_commit", "git_issue", "git_pr"]
}
```

---

## 슬래시 커맨드 사용법

스킬 등록 후 다음과 같이 사용할 수 있습니다:

```bash
# 프로젝트 초기화
/project_init

# Python 프로젝트 설정
/python_setup

# FastAPI 프로젝트 설정
/fastapi_setup

# 브랜치 생성
/git_branch

# 커밋 생성
/git_commit

# PR 생성
/git_pr
```

---

## 워크플로우 예시

### 새 Python API 프로젝트

```bash
# 1. 프로젝트 초기화
/project_init

# 2. Python 환경 설정
/python_setup

# 3. FastAPI 구조 설정
/fastapi_setup

# 4. API 테스트 설정
/api_test_setup

# 5. Docker 설정
/docker_setup

# 6. 기능 개발 (TDD)
/tdd_workflow

# 7. 브랜치 생성
/git_branch

# 8. 커밋
/git_commit

# 9. PR 생성
/git_pr
```

---

## 통계

| Category | Count |
|----------|-------|
| Base | 1 |
| Git | 5 |
| Infra | 2 |
| Methodology | 1 |
| Python | 4 |
| Java | 3 |
| React | 3 |
| AI/ML | 2 |
| Quality | 4 |
| **Total** | **25** |
