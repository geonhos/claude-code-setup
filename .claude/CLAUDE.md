# Development Guidelines

This document defines the development principles and best practices for all projects in this workspace.

## Dependency Management Principles

### Core Rules

1. **Minimize Local Dependencies**
   - Avoid global package installations
   - Keep system environment clean
   - Prevent version conflicts between projects

2. **Use Virtual Environments**
   - Python: Always use `venv` or `virtualenv`
   - Node.js: Use project-local `node_modules`
   - Each project must have isolated dependencies

3. **Lock Dependencies**
   - Maintain version lock files
   - Ensure reproducible builds
   - Document all dependencies

## Python Development

### Virtual Environment Setup

**Always create and activate venv before starting work:**

```bash
# Create virtual environment
python -m venv .venv

# Activate (macOS/Linux)
source .venv/bin/activate

# Activate (Windows)
.venv\Scripts\activate

# Verify activation
which python  # Should point to .venv/bin/python
```

### Dependency Management

```bash
# Install packages (only in activated venv)
pip install package-name

# Lock dependencies
pip freeze > requirements.txt

# Install from requirements
pip install -r requirements.txt
```

### Best Practices

**✅ DO:**
- Create `.venv` in project root
- Add `.venv/` to `.gitignore`
- Use `requirements.txt` or `pyproject.toml`
- Use Poetry or pipenv for complex projects
- Document Python version in README

**❌ DON'T:**
- Install packages globally with `pip install --user`
- Mix system Python with project dependencies
- Commit virtual environment to git
- Use `sudo pip install`

### Poetry (Recommended)

```bash
# Initialize project
poetry init

# Add dependency
poetry add package-name

# Install dependencies
poetry install

# Activate shell
poetry shell
```

## Node.js Development

### Package Management

```bash
# Initialize project
npm init -y

# Install dependencies (local only)
npm install package-name

# Use package manager lock files
npm ci  # Use package-lock.json
```

**✅ DO:**
- Use `package-lock.json` or `yarn.lock`
- Install locally: `npm install` (not `npm install -g`)
- Use `npx` for CLI tools: `npx eslint .`

**❌ DON'T:**
- Install packages globally unless necessary
- Commit `node_modules/` to git

## Project Structure

### Python Project

```
project/
├── .venv/                 # Virtual environment (not in git)
├── src/                   # Source code
├── tests/                 # Tests
├── requirements.txt       # Dependencies (pip)
├── pyproject.toml        # Project config (Poetry)
├── .gitignore            # Include .venv/
└── README.md             # Setup instructions
```

### Node.js Project

```
project/
├── node_modules/         # Dependencies (not in git)
├── src/                  # Source code
├── package.json          # Project config
├── package-lock.json     # Lock file
├── .gitignore           # Include node_modules/
└── README.md            # Setup instructions
```

## Agent & Skill Usage Rules

이 워크스페이스에서는 `.claude/agents/`와 `.claude/skills/`에 정의된 Agent와 Skill을 활용합니다.

### Git 작업 규칙

| 작업 | 사용할 도구 | 호출 방법 |
|------|------------|----------|
| Commit | git-ops agent 또는 /git_commit | Task tool 또는 Skill |
| Branch 생성 | git-ops agent 또는 /git_branch | Task tool 또는 Skill |
| PR 생성 | git-ops agent 또는 /git_pr | Task tool 또는 Skill |
| 변경사항 분석 | /git_analyze | Skill |
| 단순 status/diff | Bash 직접 실행 | 예외 허용 |

**규칙:**
- commit & push 요청 시 → `git-ops` agent 사용 권장
- PR 생성 시 → `/git_pr` skill 사용 필수
- 브랜치 전략 필요 시 → `git-ops` agent 사용 필수

### 복잡한 작업 규칙

| 작업 복잡도 | 사용할 Agent |
|------------|-------------|
| 요구사항 불명확 | `requirements-analyst` |
| 실행 계획 필요 | `plan-architect` → `plan-feedback` |
| 다중 도메인 작업 | `orchestrator` |

### 개발 작업 규칙

| 도메인 | Agent | Skill |
|--------|-------|-------|
| Python 프로젝트 초기화 | - | `/python_setup` |
| FastAPI 프로젝트 | `ai-expert` | `/fastapi_setup` |
| React 프로젝트 | `frontend-dev` | `/react_setup` |
| Spring Boot 프로젝트 | `backend-dev` | `/spring_boot_setup` |
| AI/ML 개발 | `ai-expert` | `/mlflow_setup`, `/langchain_setup` |

### 품질 관리 규칙

| 작업 | Agent | Skill |
|------|-------|-------|
| 테스트 계획 | `qa-planner` | `/test_plan_template` |
| 테스트 실행 | `qa-executor` | `/test_runner` |
| TDD 워크플로우 | - | `/tdd_workflow` |
| 커버리지 분석 | - | `/coverage_report` |
| 테스트 실패 복구 | `qa-healer` | - |

### Cross-LLM 검증

복잡한 계획(complexity >= moderate) 수립 시:
```
plan-architect → plan-feedback (Gemini CLI) → orchestrator
```

## Git Best Practices

### .gitignore Essentials

```gitignore
# Python
.venv/
__pycache__/
*.pyc
.pytest_cache/

# Node.js
node_modules/
npm-debug.log

# Environment
.env
.env.local
```

## Environment Variables

### Management

**✅ DO:**
- Use `.env` files for local development
- Provide `.env.example` template
- Never commit `.env` to git
- Use different .env for different environments

**Example .env.example:**
```bash
# API Keys
ANTHROPIC_API_KEY=your_api_key_here
GITHUB_TOKEN=your_token_here

# Database
DATABASE_URL=postgresql://localhost/mydb

# Environment
ENVIRONMENT=development
```

## Code Quality Standards

### Testing

- Write tests for all new features
- Use TDD workflow when appropriate
- Maintain test coverage > 80%
- Run tests before commits

### Code Style

- Follow language-specific style guides
- Use linters and formatters
- Configure pre-commit hooks
- Keep code DRY (Don't Repeat Yourself)

## Commit Guidelines

> **권장**: `/git_commit` skill 또는 `git-ops` agent 사용

Follow the structured commit message format:

```
[Phase X] Summary

Section 1:
- Change description

Section 2:
- Change description

Closes #issue_number

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

### Skill/Agent 사용 예시

```bash
# Skill 사용 (권장)
/git_commit

# Agent 사용 (복잡한 커밋)
→ git-ops agent 호출
```

## Reminders

**Before starting work:**
1. ✅ Activate virtual environment
2. ✅ Check dependencies are installed
3. ✅ Pull latest changes
4. ✅ Create feature branch (`/git_branch` 또는 `git-ops`)

**Before committing:**
1. ✅ Run tests (`/test_runner`)
2. ✅ Run linters
3. ✅ Review changes (`/git_analyze`)
4. ✅ Use `/git_commit` 또는 `git-ops` agent

**Before pushing:**
1. ✅ Ensure all tests pass
2. ✅ Update documentation if needed
3. ✅ Verify no sensitive data in commits

**For complex tasks:**
1. ✅ Use `requirements-analyst` for unclear requirements
2. ✅ Use `plan-architect` + `plan-feedback` for planning
3. ✅ Use domain-specific agents (backend-dev, frontend-dev, ai-expert)
