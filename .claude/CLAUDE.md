# Development Guidelines

## Environment Setup

```bash
# Python
python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt

# Node.js
npm install && npx <tool>
```

---

## Core Workflow (6 Steps)

```
1.Requirements → 2.Plan → 3.Validate(>=8) → 4.Orchestrate → 5.Execute(parallel) → 6.Verify
```

| Step | Agent | Role |
|------|-------|------|
| 1-2 | requirements-analyst, plan-architect | Collect, Plan |
| 3 | plan-architect | Self-validate (score >= 8) |
| 4-5 | orchestrator + execution agents | Dispatch & Execute |
| 6 | code-reviewer + qa-executor | Verify (mandatory) |

**Details**: See `protocols/workflow-detail.md`

---

## Agents (15)

### Pipeline (3)
`requirements-analyst` | `plan-architect` | `orchestrator`

### Execution (7)
| Agent | Domain | Triggers |
|-------|--------|----------|
| frontend-dev | React/TS | React, UI, 컴포넌트 |
| backend-dev | Java/Spring | API, Spring, 백엔드 |
| ai-expert | Python AI/ML | ML, AI, LLM |
| database-expert | DB | DB, 스키마, 쿼리 |
| devops-engineer | Infra/CI | Docker, K8s, 배포 |
| docs-writer | Docs | 문서, README |
| refactoring-expert | Refactor | refactor, 정리 |

### Quality (5)
| Agent | Role | Triggers |
|-------|------|----------|
| code-reviewer | Code quality | review, 리뷰 |
| qa-executor | Testing | test, 테스트 |
| security-analyst | Security | security, 보안 |
| performance-analyst | Performance | performance, 성능 |
| debug-specialist | Debugging | debug, 버그 |

**Details**: See `protocols/agents-reference.md`

---

## Key Skills

| Category | Skills |
|----------|--------|
| Git | `/git_commit`, `/git_branch`, `/git_pr`, `/git_issue` |
| Dev | `/python_setup`, `/react_setup`, `/spring_boot_setup` |
| Quality | `/test_runner`, `/coverage_report` |
| Workflow | `/brainstorm`, `/task_breakdown`, `/verify_complete` |

**Full list (32)**: See `protocols/skills-reference.md`

---

## Mandatory Verification

After implementation, ALWAYS run:

| Order | Agent | Pass Criteria |
|-------|-------|---------------|
| 1 | code-reviewer | 0 Critical |
| 2 | qa-executor | All tests pass |
| 3 | security-analyst | (if auth changes) 0 Critical |

---

## Gate Functions

| Action | Required |
|--------|----------|
| Execute Plan | Plan score >= 8 |
| Merge Code | code-reviewer + qa-executor pass |
| Security Changes | security-analyst pass |

---

## Commit Format

```
[Phase N] Summary

Section:
- file: description

Refs #issue
```

---

## Prohibited

- Global installs (`pip install --user`, `npm install -g`)
- Commit `.venv/`, `node_modules/`, `.env`
- Skip verification steps
- `sudo pip install`

**Full checklists**: See `protocols/checklists.md`
