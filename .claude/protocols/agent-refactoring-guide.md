# Agent Refactoring Guide

## Overview

This guide provides instructions for refactoring the remaining 14 agents to the lightweight format (~100 lines each).

---

## Target Agents (14)

### Pipeline (2)
1. `requirements-analyst`
2. `plan-architect`

### Execution (6)
3. `frontend-dev`
4. `backend-dev`
5. `ai-expert`
6. `database-expert`
7. `devops-engineer`
8. `refactoring-expert`

### Quality (5)
9. `code-reviewer`
10. `qa-executor`
11. `security-analyst`
12. `performance-analyst`
13. `debug-specialist`

### Orchestration (1)
14. `orchestrator`

---

## Refactoring Process

### Step 1: Analyze Current Size
```bash
wc -l agents/**/*.md
```

Target: Reduce files > 150 lines to ~100 lines

### Step 2: Identify Removable Content

| Content Type | Action |
|--------------|--------|
| Verbose examples (>10 lines) | Remove or link to protocols |
| Duplicate templates | Move to protocols |
| ASCII art diagrams | Simplify or remove |
| Repetitive checklists | Consolidate |
| Long code samples | Keep minimal, link to examples |

### Step 3: Apply Template

Use `protocols/agent-template-light.md` structure:

```markdown
---
name: {agent-name}
description: "{brief}. Triggers: {keywords}"
---

## Core Expertise (3-5 bullets)
## The Iron Law (1 sentence)
## DO NOT (3-5 items)
## Scope Boundaries (DOES/DOES NOT)
## Red Flags - STOP (3-5 warnings)
## Output Format (JSON template)
## Quality Checklist (3-5 items)
## Mindset (1 quote)
```

### Step 4: Preserve Essential Information

Must keep:
- Agent identity and expertise
- Scope boundaries (clear handoff targets)
- Output format (consistent JSON)
- Quality criteria

Can remove:
- Long examples (>10 lines each)
- Detailed templates (move to protocols)
- Verbose explanations
- Redundant checklists

---

## Agent-Specific Guidelines

### Pipeline Agents

#### requirements-analyst
- Keep: Requirements template structure
- Remove: Long example requirements documents
- Focus: Clarification questions, MoSCoW prioritization

#### plan-architect
- Keep: Validation criteria (5 items)
- Remove: Detailed plan examples
- Focus: Task breakdown, dependency mapping

### Execution Agents

#### frontend-dev
- Keep: React patterns summary
- Remove: Full component examples
- Focus: Component structure, state management approach

#### backend-dev
- Keep: API endpoint patterns
- Remove: Full controller/service examples
- Focus: REST conventions, error handling

#### ai-expert
- Keep: Model integration patterns
- Remove: Full training code examples
- Focus: LLM integration, data pipeline basics

#### database-expert
- Keep: Schema design principles
- Remove: Full migration examples
- Focus: Normalization, indexing, query patterns

#### devops-engineer
- Keep: Docker/K8s essentials
- Remove: Full YAML configurations
- Focus: CI/CD patterns, deployment strategy

#### refactoring-expert
- Keep: Refactoring patterns list
- Remove: Detailed before/after examples
- Focus: Code smell identification, pattern application

### Quality Agents

#### code-reviewer
- Keep: Review criteria
- Remove: Long code review examples
- Focus: Issue severity levels, feedback format

#### qa-executor
- Keep: Test types and criteria
- Remove: Full test suite examples
- Focus: Coverage targets, test naming

#### security-analyst
- Keep: OWASP Top 10 summary
- Remove: Detailed vulnerability examples
- Focus: Security checklist, severity levels

#### performance-analyst
- Keep: Metrics to measure
- Remove: Detailed profiling examples
- Focus: Bottleneck patterns, optimization targets

#### debug-specialist
- Keep: Debugging methodology
- Remove: Long debug session examples
- Focus: Root cause analysis steps

---

## Validation Checklist

After refactoring each agent:

```
[ ] File is ~100 lines (80-120 acceptable)
[ ] Template structure followed
[ ] Core expertise preserved
[ ] Scope boundaries clear
[ ] Handoff targets specified
[ ] Output format consistent
[ ] Quality criteria present
[ ] No duplicate content with protocols
```

---

## Common Patterns to Extract

Move these to shared protocols:

### Error Response Format
```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable",
    "details": {}
  }
}
```

### Task Result Format
```json
{
  "task_id": "T-XXX-001",
  "status": "completed|failed",
  "output": {
    "files_modified": [],
    "files_created": [],
    "summary": ""
  }
}
```

### Quality Levels
| Level | Description |
|-------|-------------|
| Critical | Must fix before merge |
| Major | Should fix, blocking |
| Minor | Nice to have |
| Info | Suggestion only |

---

## Execution Order

Recommended refactoring sequence:

1. **Quality agents first** (most structured)
   - code-reviewer, qa-executor, security-analyst

2. **Execution agents** (domain-specific)
   - backend-dev, frontend-dev, database-expert

3. **Pipeline agents** (workflow-critical)
   - plan-architect, orchestrator

4. **Remaining agents**
   - ai-expert, devops-engineer, etc.

---

## Estimated Effort

| Agent Category | Count | Time per Agent | Total |
|----------------|-------|----------------|-------|
| Quality | 5 | 15 min | 75 min |
| Execution | 6 | 20 min | 120 min |
| Pipeline | 3 | 25 min | 75 min |
| **Total** | **14** | - | **~4.5 hours** |

---

## Success Metrics

After complete refactoring:

| Metric | Before | After |
|--------|--------|-------|
| Avg agent size | ~400 lines | ~100 lines |
| Total agent LOC | ~6000 | ~1500 |
| Context load time | High | Low |
| Maintenance effort | High | Low |
