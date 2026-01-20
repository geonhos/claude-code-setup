# Multi-Agent Architecture

A pipeline-based multi-agent system for automated software development.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER PROMPT                                  │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  1. REQUIREMENTS ANALYST                                             │
│     Input: Raw prompt                                                │
│     Output: Refined requirements (structured JSON)                   │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  2. PLAN ARCHITECT                                                   │
│     Input: Refined requirements                                      │
│     Output: Execution plan (tasks, dependencies, assignments)        │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  3. ORCHESTRATOR                                                     │
│     - Dispatches tasks to execution agents                           │
│     - Monitors progress                                              │
│     - Handles failures & retries                                     │
└─────────────────────────────────────────────────────────────────────┘
                                │
       ┌────────────────┬───────┴───────┬────────────────┐
       ▼                ▼               ▼                ▼
┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐
│ BACKEND    │  │ FRONTEND   │  │ AI EXPERT  │  │ GIT OPS    │
│ (Java)     │  │ (React)    │  │ (Python)   │  │            │
│            │  │            │  │            │  │            │
│ - API      │  │ - UI/UX    │  │ - ML/DL    │  │ - Branch   │
│ - DB       │  │ - Components│ │ - LLM      │  │ - Commit   │
│ - Server   │  │ - State    │  │ - Data     │  │ - PR       │
└────────────┘  └────────────┘  └────────────┘  └────────────┘
       │                │               │                │
       └────────────────┴───────┬───────┴────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        QA PIPELINE                                   │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐              │
│  │ QA PLANNER  │ →  │ QA EXECUTOR │ →  │ QA HEALER   │              │
│  │             │    │             │    │             │              │
│  │ - Test plan │    │ - Run tests │    │ - Diagnose  │              │
│  │ - Strategy  │    │ - Analyze   │    │ - Fix       │              │
│  │ - Priority  │    │ - Report    │    │ - Verify    │              │
│  └─────────────┘    └─────────────┘    └─────────────┘              │
└─────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│  REPORTER                                                            │
│     - Summarize all prompts & results                                │
│     - Generate final report                                          │
└─────────────────────────────────────────────────────────────────────┘
```

## Agent Specifications

### Pipeline Agents (3)

| Agent | File | Model | Role |
|-------|------|-------|------|
| Requirements Analyst | `pipeline/requirements-analyst.md` | sonnet | Prompt refinement & clarification |
| Plan Architect | `pipeline/plan-architect.md` | opus | Convert requirements to actionable plan |
| Orchestrator | `pipeline/orchestrator.md` | sonnet | Task dispatch & monitoring |

### Execution Agents (4)

| Agent | File | Model | Specialization |
|-------|------|-------|----------------|
| Backend Dev | `execution/backend-dev.md` | sonnet | Java, Spring Boot, DDD, API, Database |
| Frontend Dev | `execution/frontend-dev.md` | sonnet | React, TypeScript, MVVM, FSD |
| AI Expert | `execution/ai-expert.md` | sonnet | Python, ML/DL, LLM, Data Pipeline |
| Git Ops | `execution/git-ops.md` | haiku | Branch, Commit, PR, Merge |

### Quality Agents (4)

| Agent | File | Model | Role |
|-------|------|-------|------|
| QA Planner | `quality/qa-planner.md` | sonnet | Test strategy & test plan creation |
| QA Executor | `quality/qa-executor.md` | sonnet | Test execution & result analysis |
| QA Healer | `quality/qa-healer.md` | sonnet | Failure diagnosis & recovery |
| Reporter | `quality/reporter.md` | haiku | Execution summary & report generation |

**Total: 11 Agents**

## Directory Structure

```
.claude/agents/
├── README.md                           # This file
├── pipeline/
│   ├── requirements-analyst.md         # Prompt refinement
│   ├── plan-architect.md               # Execution planning
│   └── orchestrator.md                 # Task dispatch
├── execution/
│   ├── backend-dev.md                  # Java/Spring Boot
│   ├── frontend-dev.md                 # React/TypeScript
│   ├── ai-expert.md                    # Python/ML/LLM
│   └── git-ops.md                      # Git operations
└── quality/
    ├── qa-planner.md                   # Test planning
    ├── qa-executor.md                  # Test execution
    ├── qa-healer.md                    # Failure recovery
    └── reporter.md                     # Reporting
```

## Data Flow

### 1. Requirements Analyst
```yaml
input:
  raw_prompt: string
output:
  refined_prompt: string
  requirements:
    functional: list
    non_functional: list
    constraints: list
  domain: [backend, frontend, ai]
  clarifications: list
```

### 2. Plan Architect
```yaml
input:
  requirements: from Requirements Analyst
output:
  execution_plan:
    tasks: list (id, description, agent, dependencies, priority)
    complexity: simple | moderate | complex
    critical_path: list[task_id]
    risk_areas: list
```

### 3. Orchestrator
```yaml
input:
  execution_plan: from Plan Architect
output:
  task_results: list (task_id, status, output, agent_used)
  overall_status: success | partial | failed
  metrics: (completed, in_progress, failed)
```

### 4a-d. Execution Agents
```yaml
input:
  task: single task from Orchestrator
  context: dependencies output, requirements
output:
  files_created: list
  files_modified: list
  tests_written: list
  test_results: (passed, failed, coverage)
  status: completed | failed
```

### 5a. QA Planner
```yaml
input:
  implementation: from Execution Agents
  requirements: original requirements
output:
  test_plan:
    test_cases: list (id, name, priority, type)
    coverage_target: percentage
    risk_areas: list
  estimated_effort: string
```

### 5b. QA Executor
```yaml
input:
  test_plan: from QA Planner
  codebase: implemented code
output:
  execution_summary: (total, passed, failed, skipped)
  coverage: percentage
  failures: list (test_id, error, root_cause, reproduction)
  flaky_tests: list
```

### 5c. QA Healer
```yaml
input:
  failures: from QA Executor
output:
  fixes_applied: list (test_id, fix_type, file, change)
  verification: (tests_run, passed, failed)
  preventive_recommendations: list
```

### 6. Reporter
```yaml
input:
  all_agent_outputs: aggregated
output:
  report_type: execution | sprint
  summary: (tasks_completed, coverage, duration)
  prompts_used: list (agent, prompt, tokens)
  files_changed: (created, modified, deleted)
  resource_usage: (tokens, api_calls, cost)
  recommendations: list
```

## QA Pipeline Detail

The QA process is split into three specialized agents:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        QA PIPELINE FLOW                              │
└─────────────────────────────────────────────────────────────────────┘

  Implementation          Test Plan           Test Results         Fixed Code
  from Execution  ──────►  created   ──────►   generated   ──────►  verified
       │                     │                    │                    │
       ▼                     ▼                    ▼                    ▼
┌─────────────┐       ┌─────────────┐      ┌─────────────┐     ┌─────────────┐
│ QA PLANNER  │       │ QA EXECUTOR │      │ QA HEALER   │     │   DONE      │
│             │       │             │      │             │     │             │
│ Analyzes:   │       │ Executes:   │      │ Fixes:      │     │ Verified:   │
│ - Coverage  │       │ - Unit      │      │ - Code bugs │     │ - All pass  │
│ - Risk areas│       │ - Integration│     │ - Test bugs │     │ - Coverage  │
│ - Priorities│       │ - E2E       │      │ - Flaky     │     │ - Stable    │
└─────────────┘       └─────────────┘      └─────────────┘     └─────────────┘
```

### QA Agent Responsibilities

| Agent | Input | Output | Escalation |
|-------|-------|--------|------------|
| QA Planner | Implemented code | Test plan with priorities | If requirements unclear |
| QA Executor | Test plan | Pass/fail results, diagnostics | If environment issues |
| QA Healer | Failed tests | Fixes, verification | If architectural change needed |

## Model Selection Strategy

| Task Type | Recommended Model | Reason |
|-----------|-------------------|--------|
| Complex planning | opus | Deep reasoning, architecture decisions |
| Code generation | sonnet | Balance of quality and speed |
| Simple operations | haiku | Fast, cost-effective for routine tasks |
| Clarification/QA | sonnet | Good at asking questions and analysis |

## Communication Protocol

```typescript
interface AgentMessage {
  from: AgentType;
  to: AgentType;
  type: 'request' | 'response' | 'error';
  payload: {
    task_id: string;
    content: unknown;
    metadata: {
      timestamp: string;
      tokens_used?: number;
      model_used?: string;
    };
  };
}

type AgentType = 
  | 'requirements-analyst'
  | 'plan-architect'
  | 'orchestrator'
  | 'backend-dev'
  | 'frontend-dev'
  | 'ai-expert'
  | 'git-ops'
  | 'qa-planner'
  | 'qa-executor'
  | 'qa-healer'
  | 'reporter';
```

## Usage Examples

### Example 1: New Feature Request
```
User: "Add user authentication with JWT"

→ Requirements Analyst: Clarifies OAuth vs JWT, session handling
→ Plan Architect: Creates tasks for Backend (auth API), Frontend (login UI)
→ Orchestrator: Dispatches to backend-dev, then frontend-dev
→ QA Planner: Creates test plan (security, validation, E2E)
→ QA Executor: Runs tests, reports 2 failures
→ QA Healer: Fixes validation bug, verifies all pass
→ Reporter: Summarizes implementation, lists endpoints created
```

### Example 2: Bug Fix with Regression
```
User: "Fix the payment processing timeout issue"

→ Requirements Analyst: Identifies affected components
→ Plan Architect: Creates investigation + fix tasks
→ Orchestrator: Dispatches to backend-dev
→ QA Planner: Creates regression test plan
→ QA Executor: Runs regression, finds 1 new failure
→ QA Healer: Diagnoses side effect, applies fix
→ Reporter: Documents root cause and fix applied
```

### Example 3: AI Feature Implementation
```
User: "Add sentiment analysis to customer reviews"

→ Requirements Analyst: Clarifies model requirements, accuracy targets
→ Plan Architect: Creates tasks for AI (model), Backend (API), Frontend (UI)
→ Orchestrator: Dispatches to ai-expert, backend-dev, frontend-dev
→ QA Planner: Creates ML validation + integration test plan
→ QA Executor: Runs tests, validates model accuracy
→ QA Healer: (no failures)
→ Reporter: Reports accuracy metrics, API endpoints, UI components
```

## Error Handling

| Error Type | Handler | Recovery |
|------------|---------|----------|
| Agent timeout | Orchestrator | Retry with extended timeout |
| Task failure | Orchestrator | Reassign or escalate to QA Healer |
| Test failure | QA Healer | Diagnose, fix, verify |
| Plan ambiguity | Plan Architect | Request clarification |
| Unrecoverable | Reporter | Document and escalate to user |

## Metrics & Monitoring

Each agent reports:
- `tokens_used`: Token consumption
- `execution_time`: Time taken
- `status`: Success/failure
- `retries`: Number of retry attempts

Reporter aggregates all metrics into final report with:
- Total token usage
- Cost estimate
- Success rate
- Quality metrics (coverage, pass rate)
