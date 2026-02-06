# Skills Reference

## Overview

32 skills organized into 4 categories:
- **Git** (6): Version control operations
- **Development** (4): Project setup
- **Quality** (3): Testing and coverage
- **Workflow** (4): Process automation

---

## Git Skills (6)

| Skill | Description | Usage |
|-------|-------------|-------|
| `/git_commit` | Generate commit message | After staging changes |
| `/git_branch` | Create feature branch | Start new work |
| `/git_pr` | Create pull request | Ready for review |
| `/git_issue` | Create GitHub issue | Track bugs/features |
| `/git_worktree` | Manage git worktrees | Parallel development |
| `/git_analyze` | Analyze changes | Before commit |

### Commit Message Format
```
[Phase {number}] {summary}

{Section}:
- {file}: {description}

Refs #{issue_number}
```

---

## Development Skills (4)

| Skill | Description | Tech Stack |
|-------|-------------|------------|
| `/python_setup` | Python project init | venv, requirements.txt |
| `/fastapi_setup` | FastAPI project | FastAPI, uvicorn, pydantic |
| `/react_setup` | React project | React, TypeScript, Vite |
| `/spring_boot_setup` | Spring Boot project | Java, Maven/Gradle |

### Python Setup Steps
```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Node.js Setup Steps
```bash
npm install
npx <tool>
```

---

## Quality Skills (3)

| Skill | Description | Output |
|-------|-------------|--------|
| `/test_runner` | Execute tests | Test results, failures |
| `/coverage_report` | Generate coverage | Coverage percentage |
| `/test_plan_template` | Create test plan | Structured test plan |

### Test Execution Flow
```
/test_runner
    │
    ├── Run unit tests
    ├── Run integration tests
    ├── Generate report
    └── Return results
```

---

## Workflow Skills (4)

| Skill | Description | When to Use |
|-------|-------------|-------------|
| `/brainstorm` | Design exploration | Complex decisions (3+ alternatives) |
| `/task_breakdown` | Decompose tasks | Large features |
| `/debug_workflow` | Structured debugging | Bug investigation |
| `/verify_complete` | Completion check | Before closing task |

### Brainstorm Output
```markdown
## Options
1. Option A: [description]
   - Pros: ...
   - Cons: ...

2. Option B: [description]
   - Pros: ...
   - Cons: ...

3. Option C: [description]
   - Pros: ...
   - Cons: ...

## Recommendation
[Selected option with rationale]
```

---

## Extended Skills (15)

### File Operations
| Skill | Description |
|-------|-------------|
| `/search_code` | Search codebase |
| `/find_references` | Find symbol references |
| `/analyze_dependencies` | Dependency analysis |

### Documentation
| Skill | Description |
|-------|-------------|
| `/generate_api_docs` | OpenAPI generation |
| `/create_readme` | README template |
| `/write_adr` | Architecture decision |

### Analysis
| Skill | Description |
|-------|-------------|
| `/code_metrics` | Code complexity |
| `/security_scan` | Vulnerability check |
| `/performance_profile` | Performance analysis |

### Deployment
| Skill | Description |
|-------|-------------|
| `/docker_build` | Build container |
| `/k8s_deploy` | Kubernetes deployment |
| `/ci_pipeline` | CI/CD setup |

### Database
| Skill | Description |
|-------|-------------|
| `/db_migrate` | Run migrations |
| `/db_seed` | Seed test data |
| `/db_backup` | Backup database |

---

## Skill Invocation

### Direct Invocation
```
User: /git_commit
Assistant: [Analyzes staged changes and generates commit message]
```

### Context-Aware Invocation
```
User: "I need to create a PR for this feature"
Assistant: [Automatically invokes /git_pr skill]
```

---

## Skill Composition

Skills can be combined for complex workflows:

### Feature Development
```
/git_branch → /react_setup → [implement] → /test_runner → /git_commit → /git_pr
```

### Bug Fix
```
/debug_workflow → [fix] → /test_runner → /git_commit → /git_pr
```

### Documentation
```
/generate_api_docs → /create_readme → /git_commit
```
