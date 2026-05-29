---
name: plan
description: "Explore approaches, evaluate tradeoffs, then produce a scored execution plan with verifiable, implementation-agnostic tasks and dependencies."
model: opus
context: fork
allowed-tools: Read, Grep, Glob, Bash
argument-hint: "[feature or problem description]"
---

# Plan — Design + Decompose + Score

Combines brainstorming, task breakdown, and plan validation in one flow.

## When to Use

- Before starting complex feature implementation
- When multiple valid approaches exist
- When you need to evaluate tradeoffs before committing
- User says "plan", "design", "how should we", "explore approaches"

## Workflow

### Phase 1: Explore (Brainstorm)

**Minimum 3 approaches.** For each:

| Field | Description |
|-------|-------------|
| Name | Descriptive identifier |
| How | How it works (2-3 sentences) |
| Pros | Key benefits |
| Cons | Key drawbacks |
| Effort | Low / Medium / High |
| Risk | Low / Medium / High |

**Tradeoff Matrix:**

| Criteria | Approach A | Approach B | Approach C |
|----------|------------|------------|------------|
| Complexity | | | |
| Performance | | | |
| Maintainability | | | |
| Scalability | | | |
| Effort | | | |

**Output:**
```
Recommended: {approach name}
Reasoning: {why this one wins}
```

**MANDATORY:** Ask user to confirm approach before proceeding to Phase 2.

### Phase 2: Decompose (Task Breakdown)

Break the selected approach into atomic tasks.

**Granularity rules:**
- Each task: 2-5 minutes
- Single file per task (test pairs allowed)
- Every task has a verification method
- Each task independently verifiable

**Task format:**
```yaml
- id: T-{seq}
  type: CREATE | MODIFY | DELETE | REFACTOR | TEST | CONFIG | DOC
  file: {path}
  description: {what to do}
  depends_on: [T-{N}]  # or []
  acceptance:
    - {criterion 1}
    - {criterion 2}
  verify: {command to verify}
```

Tasks are implementation-agnostic: they describe *what* and *how to verify*,
not *which agent*. Execution is native Claude Code (and any installed companion
plugins) — `/plan` no longer routes tasks to bundled agents.

**Parallel groups:** Group independent tasks for concurrent execution:
```yaml
groups:
  1: [T-001, T-002]   # concurrent
  2: [T-003, T-004]   # after group 1
  3: [T-005]           # after group 2
```

### Phase 3: Score (Self-Validation)

Rate the plan on 5 criteria (2 points each, total 10):

| Criteria | 2 pts | 1 pt | 0 pts |
|----------|-------|------|-------|
| Completeness | All requirements covered | Minor gaps | Major missing |
| Dependencies | Correct, no cycles | Minor issues | Cycles/errors |
| Scope / Right-sizing | All tasks atomic (single concern, verifiable) | A few oversized | Many vague/monolithic |
| Feasibility | All executable | Some unclear | Many unclear |
| Testability | All have criteria | Most have | None have |

**Gate:** Score must be >= 8/10. If < 8, fix issues and re-score.

### Phase 4: Output

```markdown
# Plan: {Feature Name}

## Approach
**Selected:** {name}
**Reasoning:** {why}
**Alternatives considered:** {list}

## Overview
- Complexity: {simple | moderate | complex}
- Tasks: {N}
- Parallel Groups: {N}

## Validation
- Score: {N}/10 {pass_emoji}
- Issues: {list or "None"}

## Tasks

### Group 1 (parallel)
| ID | Type | File | Description | Verify |
|----|------|------|-------------|--------|
| T-001 | CREATE | src/auth/handler.py | Login handler | unit test green |
| T-002 | CREATE | tests/test_auth.py | Auth tests | pytest passes |

### Group 2 (after Group 1)
...

## Critical Path
T-001 → T-003 → T-005 → T-008

## Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| {risk} | {H/M/L} | {strategy} |
```

Save plan to `./plans/PLAN-{ID}_{slug}.md`.

## Rules

- NEVER skip brainstorming (always explore >= 3 approaches)
- NEVER proceed without user confirmation on approach
- NEVER create a plan with score < 8
- NEVER write implementation code (plan only)
- NEVER tie a task to a specific bundled agent — tasks are implementation-agnostic; execution is native Claude Code
