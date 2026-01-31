---
name: project_init
description: Creates basic project structure with git initialization, .gitignore, README, and environment setup. Use as the first step for any new project.
model: haiku
---

# Project Initialization Skill

새 프로젝트의 기본 구조를 생성합니다.

## Prerequisites

- 프로젝트를 생성할 부모 디렉토리에 접근 가능해야 함
- Git이 설치되어 있어야 함

## Workflow

### 1. 프로젝트 디렉토리 생성

```bash
# 프로젝트 이름 설정
PROJECT_NAME="my-project"

# 디렉토리 생성 및 이동
mkdir -p $PROJECT_NAME
cd $PROJECT_NAME
```

### 2. Git 초기화

```bash
# Git 저장소 초기화
git init

# 기본 브랜치 이름 설정 (main)
git branch -M main
```

### 3. .gitignore 생성

```bash
cat > .gitignore <<'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
.venv/
venv/
*.egg-info/
.pytest_cache/
.mypy_cache/
.coverage
htmlcov/

# Node.js
node_modules/
npm-debug.log
yarn-error.log

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Environment
.env
.env.local
.env.*.local

# Build
dist/
build/
*.egg

# Logs
*.log
logs/
EOF
```

### 4. README.md 생성

```bash
cat > README.md <<'EOF'
# {project_name}

프로젝트 설명을 여기에 작성합니다.

## Getting Started

### Prerequisites

- Python 3.9+ (또는 Node.js 18+)
- Git

### Installation

```bash
# Clone repository
git clone <repository-url>
cd {project_name}

# Setup (Python)
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Setup (Node.js)
npm install
```

### Running

```bash
# Python
python src/main.py

# Node.js
npm start
```

### Testing

```bash
# Python
pytest

# Node.js
npm test
```

## Project Structure

```
{project_name}/
├── src/           # Source code
├── tests/         # Test files
├── docs/          # Documentation
├── .gitignore
├── README.md
└── CLAUDE.md      # AI assistant instructions
```

## License

MIT
EOF
```

### 5. CLAUDE.md 생성 (AI 어시스턴트 지침)

```bash
cat > CLAUDE.md <<'EOF'
# Project Instructions

이 프로젝트에서 작업할 때 따라야 할 지침입니다.

## Project Overview

- **Name**: {project_name}
- **Language**: (Python / TypeScript / Java)
- **Framework**: (FastAPI / React / Spring Boot)

## Development Guidelines

### Code Style

- 명확하고 읽기 쉬운 코드 작성
- 함수와 클래스에 docstring 작성
- 타입 힌트 사용 (Python) / TypeScript 사용 (JS)

### Testing

- 새 기능에는 반드시 테스트 작성
- TDD 방식 권장: 테스트 먼저, 구현 나중
- 테스트 커버리지 80% 이상 유지

### Git Workflow

- 기능별 브랜치: `feature/issue-{number}-{description}`
- 커밋 메시지: `[Phase {number}] {description}`
- PR 전 테스트 통과 확인

## Commands

```bash
# 테스트 실행
pytest -v

# 린트 검사
flake8 src tests

# 타입 검사
mypy src
```

## Notes

- 환경변수는 `.env` 파일 사용 (git 무시됨)
- 시크릿 정보는 절대 커밋하지 않음
EOF
```

### 6. .env.example 생성

```bash
cat > .env.example <<'EOF'
# Environment Configuration
# Copy this file to .env and fill in the values

# Application
APP_NAME={project_name}
DEBUG=true
ENVIRONMENT=development

# Database (if needed)
# DATABASE_URL=postgresql://user:pass@localhost/dbname

# API Keys (if needed)
# ANTHROPIC_API_KEY=your_key_here
EOF
```

### 7. 초기 커밋

```bash
git add .
git commit -m "[Phase 0] Initialize project structure

Project Setup:
- Git repository initialized
- .gitignore configured (Python, Node.js, IDE, OS)
- README.md with project template
- CLAUDE.md with AI assistant instructions
- .env.example for environment configuration
"
```

---

## 생성되는 구조

```
{project_name}/
├── .git/              # Git repository
├── .gitignore         # Git ignore rules
├── .env.example       # Environment template
├── README.md          # Project documentation
└── CLAUDE.md          # AI assistant instructions
```

---

## Quick Reference

| File | Purpose |
|------|---------|
| `.gitignore` | Git에서 무시할 파일 패턴 |
| `README.md` | 프로젝트 소개 및 사용법 |
| `CLAUDE.md` | AI 어시스턴트 작업 지침 |
| `.env.example` | 환경변수 템플릿 |

---

## 검증 체크리스트

- [ ] `git status` 실행 시 clean 상태
- [ ] `git log` 실행 시 초기 커밋 확인
- [ ] `.gitignore` 파일 존재
- [ ] `README.md` 파일 존재
- [ ] `CLAUDE.md` 파일 존재

---

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Project Initialization Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📁 Project: {project_name}
📍 Location: {path}

✅ Git initialized (main branch)
✅ .gitignore configured
✅ README.md created
✅ CLAUDE.md created
✅ Initial commit created

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Next Steps:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Language-specific setup:
- Python: /python_setup
- FastAPI: /fastapi_setup  
- React: /react_setup
- Spring Boot: /spring_boot_setup

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Notes

- **최소 구조**: 언어별 설정은 별도 스킬로 분리
- **유연성**: Python, Node.js, Java 등 다양한 언어 지원
- **확장성**: 추가 설정은 후속 스킬로 확장
