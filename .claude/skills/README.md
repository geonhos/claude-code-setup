# Skills Library

A comprehensive collection of reusable skills for the multi-agent development system.

## Overview

Skills are specialized workflows that agents can invoke to perform common tasks. Each skill provides step-by-step instructions, templates, and validation checklists.

## Directory Structure

```
skills/
├── README.md                      # This file
├── SKILLS_REGISTRY.md             # System registration config
├── base/                          # Project initialization
│   └── project_init/              # ✅ Basic project structure
├── git/                           # Version control
│   ├── git_analyze/
│   ├── git_branch/
│   ├── git_commit/
│   ├── git_issue/
│   └── git_pr/
├── infra/                         # Infrastructure
│   ├── alembic_migration/
│   └── docker_setup/
├── methodology/                   # Development practices
│   └── tdd_workflow/
├── python/                        # Python development
│   ├── python_setup/
│   ├── fastapi_setup/
│   └── rag_setup/
├── java/                          # Java development
│   ├── spring_boot_setup/
│   ├── gradle_setup/
│   └── jpa_entity/
├── react/                         # React development
│   ├── react_setup/
│   ├── nextjs_setup/
│   └── component_generator/
├── ai/                            # AI/ML development
│   ├── mlflow_setup/
│   └── langchain_setup/
└── quality/                       # QA & Reporting
    ├── test_plan_template/
    ├── test_runner/
    ├── coverage_report/
    └── execution_report/
```

## Skills by Category

### Base
| Skill | Description | Model |
|-------|-------------|-------|
| `project_init` | Basic project structure with git, .gitignore, README | haiku |

### Git Operations
| Skill | Description | Model |
|-------|-------------|-------|
| `git_analyze` | Analyze repository state and changes | haiku |
| `git_branch` | Create and manage branches | haiku |
| `git_commit` | Generate structured commit messages | haiku |
| `git_issue` | Create GitHub issues | haiku |
| `git_pr` | Create pull requests | haiku |

### Infrastructure
| Skill | Description | Model |
|-------|-------------|-------|
| `docker_setup` | Docker and docker-compose configuration | haiku |
| `alembic_migration` | Database migration management | haiku |

### Methodology
| Skill | Description | Model |
|-------|-------------|-------|
| `tdd_workflow` | Test-Driven Development (Red-Green-Refactor) | haiku |

### Python
| Skill | Description | Model |
|-------|-------------|-------|
| `python_setup` | Python project with venv, pytest | haiku |
| `fastapi_setup` | FastAPI project structure | haiku |
| `api_test_setup` | API testing with pytest, httpx, fixtures | haiku |
| `rag_setup` | RAG with ChromaDB and embeddings | haiku |

### Java
| Skill | Description | Model |
|-------|-------------|-------|
| `spring_boot_setup` | Spring Boot with DDD structure | haiku |
| `gradle_setup` | Gradle multi-module configuration | haiku |
| `jpa_entity` | JPA entity generation with patterns | haiku |

### React
| Skill | Description | Model |
|-------|-------------|-------|
| `react_setup` | React/Vite with FSD structure | haiku |
| `nextjs_setup` | Next.js 14+ with App Router | haiku |
| `component_generator` | MVVM component with tests | haiku |

### AI/ML
| Skill | Description | Model |
|-------|-------------|-------|
| `mlflow_setup` | Experiment tracking and model registry | haiku |
| `langchain_setup` | LLM application with RAG | haiku |

### Quality
| Skill | Description | Model |
|-------|-------------|-------|
| `test_plan_template` | Comprehensive test plan generation | haiku |
| `test_runner` | Multi-framework test execution | haiku |
| `coverage_report` | Coverage analysis and recommendations | haiku |
| `execution_report` | Agent execution summary reports | haiku |

## Agent-Skill Mapping

| Agent | Primary Skills |
|-------|----------------|
| **backend-dev** | spring_boot_setup, gradle_setup, jpa_entity, tdd_workflow |
| **frontend-dev** | react_setup, nextjs_setup, component_generator, tdd_workflow |
| **ai-expert** | python_setup, fastapi_setup, api_test_setup, rag_setup, mlflow_setup, langchain_setup |
| **git-ops** | git_analyze, git_branch, git_commit, git_issue, git_pr |
| **qa-planner** | test_plan_template |
| **qa-executor** | test_runner, coverage_report |
| **qa-healer** | tdd_workflow |
| **reporter** | execution_report |

## Skill Structure

Each skill follows this structure:

```markdown
---
name: skill_name
description: Brief description of the skill
model: haiku
color: color_name
---

# Skill Title

Brief introduction.

## Prerequisites
- Required setup

## Workflow
### 1. Step One
...

### 2. Step Two
...

## Quick Reference
| Command | Description |
|---------|-------------|

## Generated Structure
```
project/
├── files/
└── created/
```

## Verification Checklist
- [ ] Check 1
- [ ] Check 2

## Summary Report
```
━━━━━━━━━━━━━━━━━━━━━━━━
✅ Skill Complete
━━━━━━━━━━━━━━━━━━━━━━━━
```
```

## Usage

### Invoking Skills

Skills can be invoked by agents or directly:

```
/spring_boot_setup
/react_setup
/test_plan_template
```

### Skill Parameters

Some skills accept parameters:

```
/jpa_entity --name=User --fields=name:string,email:string
/component_generator --feature=payment --type=form
```

## Creating New Skills

1. Create directory: `skills/{category}/{skill_name}/`
2. Create `SKILL.md` with frontmatter
3. Follow the standard structure
4. Add to this README

### Skill Frontmatter

```yaml
---
name: my_skill
description: What this skill does
model: haiku  # haiku for simple, sonnet for complex
color: blue   # Visual identifier
---
```

## Model Selection

| Complexity | Model | Use Case |
|------------|-------|----------|
| Simple | haiku | Templates, boilerplate, simple workflows |
| Moderate | sonnet | Code generation, analysis |
| Complex | opus | Architecture decisions, planning |

## Metrics

| Category | Skills Count |
|----------|--------------|
| Base | 1 |
| Git | 5 |
| Infrastructure | 2 |
| Methodology | 1 |
| Python | 4 |
| Java | 3 |
| React | 3 |
| AI/ML | 2 |
| Quality | 4 |
| **Total** | **25** |
