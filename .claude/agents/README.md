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
│  2.5 PLAN FEEDBACK (Cross-LLM Validation)                            │
│     Input: Execution plan                                            │
│     Output: Validated/improved plan (via Gemini CLI)                 │
│     - Skipped for simple plans                                       │
│     - Iterates until score >= threshold                              │
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
│                        QA & SECURITY PIPELINE                        │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐              │
│  │ QA PLANNER  │ →  │ QA EXECUTOR │ →  │ QA HEALER   │              │
│  │             │    │             │    │             │              │
│  │ - Test plan │    │ - Run tests │    │ - Diagnose  │              │
│  │ - Strategy  │    │ - Analyze   │    │ - Fix       │              │
│  │ - Priority  │    │ - Report    │    │ - Verify    │              │
│  └─────────────┘    └─────────────┘    └─────────────┘              │
│                                                                      │
│  ┌─────────────────────────────────────────────────────┐            │
│  │ SECURITY ANALYST                                     │            │
│  │                                                      │            │
│  │ - OWASP Top 10 review    - Dependency CVE scan      │            │
│  │ - Auth/Authz analysis    - Threat modeling (STRIDE) │            │
│  │ - Input validation       - Remediation guidance     │            │
│  └─────────────────────────────────────────────────────┘            │
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

### Pipeline Agents (4)

| Agent | File | Model | Role |
|-------|------|-------|------|
| Requirements Analyst | `pipeline/requirements-analyst.md` | sonnet | Prompt refinement & clarification |
| Plan Architect | `pipeline/plan-architect.md` | opus | Convert requirements to actionable plan |
| Plan Feedback | `pipeline/plan-feedback.md` | sonnet | Cross-LLM plan validation via Gemini CLI |
| Orchestrator | `pipeline/orchestrator.md` | sonnet | Task dispatch & monitoring |

### Execution Agents (4)

| Agent | File | Model | Specialization |
|-------|------|-------|----------------|
| Backend Dev | `execution/backend-dev.md` | sonnet | Java, Spring Boot, DDD, API, Database |
| Frontend Dev | `execution/frontend-dev.md` | sonnet | React, TypeScript, MVVM, FSD |
| AI Expert | `execution/ai-expert.md` | sonnet | Python, ML/DL, LLM, Data Pipeline |
| Git Ops | `execution/git-ops.md` | haiku | Branch, Commit, PR, Merge |

### Quality Agents (5)

| Agent | File | Model | Role |
|-------|------|-------|------|
| QA Planner | `quality/qa-planner.md` | sonnet | Test strategy & test plan creation |
| QA Executor | `quality/qa-executor.md` | sonnet | Test execution & result analysis |
| QA Healer | `quality/qa-healer.md` | sonnet | Failure diagnosis & recovery |
| Security Analyst | `quality/security-analyst.md` | sonnet | Security code review & vulnerability assessment |
| Reporter | `quality/reporter.md` | haiku | Execution summary & report generation |

**Total: 13 Agents**

## Directory Structure

```
.claude/agents/
├── README.md                           # This file
├── pipeline/
│   ├── requirements-analyst.md         # Prompt refinement
│   ├── plan-architect.md               # Execution planning
│   ├── plan-feedback.md                # Cross-LLM validation (Gemini)
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
    ├── security-analyst.md             # Security code review
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

### 2.5 Plan Feedback
```yaml
input:
  execution_plan: from Plan Architect
  requirements: from Requirements Analyst (for context)
output:
  feedback_score: number (1-10)
  review_source: "gemini-cli"
  strengths: list
  improvements: list (area, suggestion, priority)
  missing_tasks: list
  dependency_issues: list
  revised_plan: execution_plan (if score < threshold)
  skip_reason: string (if complexity = simple)
```

**Conditional Execution Rules:**
| Complexity | Action | Threshold |
|------------|--------|-----------|
| simple | Skip | - |
| moderate | Review once | score >= 7 |
| complex | Review + iterate | score >= 8, max 2 iterations |

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
  | 'plan-feedback'
  | 'orchestrator'
  | 'backend-dev'
  | 'frontend-dev'
  | 'ai-expert'
  | 'git-ops'
  | 'qa-planner'
  | 'qa-executor'
  | 'qa-healer'
  | 'security-analyst'
  | 'reporter';
```

## Usage Examples

### Example 1: New Feature Request
```
User: "Add user authentication with JWT"

→ Requirements Analyst: Clarifies OAuth vs JWT, session handling
→ Plan Architect: Creates tasks for Backend (auth API), Frontend (login UI)
→ Plan Feedback: Gemini reviews plan (score: 6/10)
   - Missing: logout, auth middleware, protected routes
   - Plan Architect revises plan (score: 8/10) ✓
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
→ Plan Architect: Creates investigation + fix tasks (complexity: simple)
→ Plan Feedback: Skipped (simple complexity)
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
→ Plan Feedback: Gemini reviews complex plan (score: 7/10)
   - Suggests: add model versioning, fallback strategy
   - Plan Architect revises (score: 9/10) ✓
→ Orchestrator: Dispatches to ai-expert, backend-dev, frontend-dev
→ QA Planner: Creates ML validation + integration test plan
→ QA Executor: Runs tests, validates model accuracy
→ QA Healer: (no failures)
→ Reporter: Reports accuracy metrics, API endpoints, UI components
```

### Example 4: Security Review for Payment Feature
```
User: "Review the payment module for security vulnerabilities"

→ Requirements Analyst: Identifies scope (payment API, forms, data handling)
→ Plan Architect: Creates security review task (complexity: moderate)
→ Plan Feedback: Gemini confirms security focus areas
→ Orchestrator: Dispatches to security-analyst
→ Security Analyst:
   - OWASP Top 10 review (finds SQL injection risk, missing CSRF protection)
   - Auth/Authz analysis (session fixation vulnerability)
   - Dependency scan (2 CVEs in payment library)
   - Output: 5 findings (1 critical, 2 high, 2 medium)
→ Backend-dev: Applies remediation (parameterized queries, CSRF tokens)
→ QA Executor: Runs security regression tests
→ Reporter: Documents vulnerabilities found, fixes applied, verification status
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
