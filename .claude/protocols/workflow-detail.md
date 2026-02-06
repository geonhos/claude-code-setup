# Workflow Detail Protocol

## 6-Step Core Workflow

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

---

## Step Details

### Step 1: Requirements Collection
- **Agent**: `requirements-analyst`
- **Input**: User request (natural language)
- **Output**: Structured requirements document
- **Activities**:
  - Clarify ambiguous requirements
  - Identify stakeholders and constraints
  - Define acceptance criteria
  - Prioritize features (MoSCoW)

### Step 2: Plan Generation
- **Agent**: `plan-architect`
- **Input**: Validated requirements
- **Output**: Execution plan with tasks
- **Activities**:
  - Break down into tasks
  - Assign agents to tasks
  - Define dependencies
  - Estimate effort

### Step 3: Plan Validation (Self-Check)
- **Agent**: `plan-architect`
- **Input**: Generated plan
- **Output**: Validated plan (score >= 8)
- **Validation Criteria**: See Plan Validation Criteria section

### Step 4: Orchestration
- **Agent**: `orchestrator`
- **Input**: Validated plan
- **Output**: Task dispatches to agents
- **Activities**:
  - Dispatch parallel groups
  - Monitor progress
  - Handle failures

### Step 5: Parallel Execution
- **Agents**: Domain-specific execution agents
- **Input**: Task assignments
- **Output**: Implemented code/artifacts
- **Activities**: Implementation per agent specialty

### Step 6: Verification
- **Agents**: `code-reviewer` + `qa-executor`
- **Input**: Completed implementation
- **Output**: Verification report
- **Gate**: Must pass to merge/complete

---

## Plan Validation Criteria

| Criterion | Score | Description |
|-----------|-------|-------------|
| Completeness | 0-2 | All requirements mapped to tasks |
| Dependencies | 0-2 | No cycles, correct ordering |
| Agent Assignment | 0-2 | Appropriate agents for tasks |
| Feasibility | 0-2 | Specific, actionable tasks |
| Testability | 0-2 | Clear acceptance criteria |
| **Pass Threshold** | **>= 8** | |

### Scoring Guide
- **0**: Missing or critically flawed
- **1**: Partially addressed, needs improvement
- **2**: Fully addressed, production-ready

---

## Mandatory Verification Pipeline

After code implementation, ALWAYS run:

| Order | Agent | Condition | Pass Criteria |
|-------|-------|-----------|---------------|
| 1 | `code-reviewer` | Always | 0 Critical issues |
| 2 | `qa-executor` | Always | All tests pass |
| 3 | `security-analyst` | If auth/authz related | 0 Critical vulnerabilities |

### Verification Flow

```
Implementation Complete
        │
        ▼
┌───────────────────┐     FAIL      ┌─────────────────┐
│   code-reviewer   │──────────────▶│  Return to Dev  │
└─────────┬─────────┘               └─────────────────┘
          │ PASS
          ▼
┌───────────────────┐     FAIL      ┌─────────────────┐
│   qa-executor     │──────────────▶│  Return to Dev  │
└─────────┬─────────┘               └─────────────────┘
          │ PASS
          ▼
┌───────────────────┐     FAIL      ┌─────────────────┐
│ security-analyst  │──────────────▶│  Return to Dev  │
│   (conditional)   │               └─────────────────┘
└─────────┬─────────┘
          │ PASS
          ▼
    [Ready to Merge]
```

---

## Gate Functions

| Action | Required Check |
|--------|---------------|
| Execute Plan | Plan validation >= 8 |
| Merge Code | code-reviewer + qa-executor pass |
| Security Changes | security-analyst pass |

---

## Failure Handling

### Plan Validation Failure (score < 8)
1. Identify failing criteria
2. Revise plan to address gaps
3. Re-validate
4. Maximum 3 attempts before escalation

### Execution Failure
1. Log error details
2. Retry (max 2 attempts)
3. If persistent: pause and report to orchestrator
4. Orchestrator escalates to user

### Verification Failure
1. Document issues found
2. Return to execution agent for fixes
3. Re-run verification
4. Block merge until pass
