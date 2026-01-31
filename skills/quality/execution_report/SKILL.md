---
name: execution_report
description: Generates comprehensive execution reports summarizing all agent activities, prompts used, and outcomes.
model: haiku
color: white
---

# Execution Report Skill

Generates comprehensive reports summarizing agent execution results.

## Report Types

| Type | Purpose | When to Use |
|------|---------|-------------|
| Feature Report | Single feature implementation results | On feature completion |
| Sprint Report | Sprint summary | On sprint end |
| Daily Report | Daily work summary | End of day |
| Incident Report | Issue/failure analysis | On problem occurrence |

## Workflow

### 1. Data Collection

Collect from agent outputs:
- Requirements analysis results
- Execution plan
- Task results
- Test results
- Code changes

### 2. Feature Report Template

```markdown
# Execution Report: {Feature Name}

## Executive Summary

{2-3 sentence overview of what was accomplished}

**Status**: Completed / Partial / Failed
**Duration**: {start} - {end} ({total time})
**Agents Involved**: {list}

---

## 1. Requirements

### Original Request
> {original user prompt}

### Refined Requirements
| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-001 | {requirement} | High | Done |
| FR-002 | {requirement} | Medium | Done |

---

## 2. Execution Plan

### Tasks Completed
| ID | Task | Agent | Status | Duration |
|----|------|-------|--------|----------|
| T-001 | Create database schema | backend-dev | Done | 2m |
| T-002 | Implement API endpoint | backend-dev | Done | 5m |
| T-003 | Create UI component | frontend-dev | Done | 4m |
| T-004 | Write tests | qa-executor | Done | 3m |

### Blocked/Skipped Tasks
| ID | Task | Reason |
|----|------|--------|
| T-005 | {task} | {reason} |

---

## 3. Code Changes

### Files Created ({count})
| File | Purpose |
|------|---------|
| `src/api/users.ts` | User API endpoints |
| `src/components/UserForm.tsx` | User form component |

### Files Modified ({count})
| File | Changes |
|------|---------|
| `src/routes.ts` | Added user routes |
| `package.json` | Added dependencies |

### Files Deleted ({count})
| File | Reason |
|------|--------|
| `src/old/legacy.ts` | Deprecated code removed |

---

## 4. Test Results

### Summary
| Metric | Value |
|--------|-------|
| Total Tests | 45 |
| Passed | 45 |
| Failed | 0 |
| Coverage | 87% |

### Test Types
| Type | Passed | Failed |
|------|--------|--------|
| Unit | 30 | 0 |
| Integration | 12 | 0 |
| E2E | 3 | 0 |

---

## 5. Resource Usage

### Token Consumption
| Agent | Tokens | Percentage |
|-------|--------|------------|
| backend-dev | 5,234 | 40% |
| frontend-dev | 4,128 | 31% |
| qa-executor | 2,456 | 19% |
| Other | 1,312 | 10% |
| **Total** | **13,130** | 100% |

### API Calls
| Type | Count |
|------|-------|
| LLM Calls | 23 |
| Tool Uses | 45 |

### Estimated Cost
~$0.39 (based on current pricing)

---

## 6. Issues & Resolutions

### Issues Encountered
| # | Issue | Severity | Resolution |
|---|-------|----------|------------|
| 1 | Database connection timeout | Medium | Increased pool size |
| 2 | Type mismatch in API | Low | Fixed interface |

### Lessons Learned
- {lesson 1}
- {lesson 2}

---

## 7. Recommendations

### Immediate Actions
- [ ] {action 1}
- [ ] {action 2}

### Future Improvements
- {improvement 1}
- {improvement 2}

---

## 8. Appendix

### Prompts Used
<details>
<summary>Click to expand</summary>

#### requirements-analyst
```
{prompt}
```

#### backend-dev
```
{prompt}
```
</details>

### Full Change Log
<details>
<summary>Click to expand</summary>

```diff
+ src/api/users.ts
+ src/components/UserForm.tsx
M src/routes.ts
M package.json
- src/old/legacy.ts
```
</details>
```

### 3. Sprint Report Template

```markdown
# Sprint Report: Sprint {N}

## Overview
- **Sprint Goal**: {goal}
- **Duration**: {start_date} - {end_date}
- **Team**: {agents involved}

## Completed Features
| Feature | Tasks | Coverage | Status |
|---------|-------|----------|--------|
| User Auth | 8 | 92% | Done |
| Dashboard | 5 | 85% | Done |
| Payments | 6 | 78% | Partial |

## Velocity
| Metric | Planned | Actual | Rate |
|--------|---------|--------|------|
| Tasks | 20 | 18 | 90% |
| Story Points | 40 | 36 | 90% |

## Quality Metrics
| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| Coverage | 80% | 85% | Pass |
| Bug Count | <5 | 3 | Pass |
| Tech Debt | 0 | 1 | Warning |

## Resource Summary
| Metric | Value |
|--------|-------|
| Total Tokens | 45,678 |
| Total Cost | ~$1.37 |
| Avg per Task | 2,538 |

## Retrospective
### What Went Well
- {positive 1}
- {positive 2}

### What Could Improve
- {improvement 1}
- {improvement 2}

### Action Items
- [ ] {action 1}
- [ ] {action 2}
```

### 4. Output Format

```json
{
  "report_type": "feature",
  "feature": "User Authentication",
  "status": "completed",
  "summary": {
    "tasks_total": 8,
    "tasks_completed": 8,
    "tasks_failed": 0,
    "duration_minutes": 15,
    "test_coverage": 92
  },
  "files": {
    "created": 5,
    "modified": 3,
    "deleted": 1
  },
  "resources": {
    "total_tokens": 13130,
    "api_calls": 23,
    "estimated_cost_usd": 0.39
  },
  "agents": [
    { "name": "backend-dev", "tokens": 5234, "tasks": 3 },
    { "name": "frontend-dev", "tokens": 4128, "tasks": 2 }
  ],
  "issues": [
    { "description": "DB timeout", "resolution": "Increased pool" }
  ],
  "recommendations": [
    "Add caching for frequently accessed data"
  ]
}
```

## Quick Summary Format

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{Feature Name} - Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Tasks: {completed}/{total}
Coverage: {coverage}%
Duration: {duration}
Cost: ~${cost} ({tokens} tokens)

Files: +{created} ~{modified} -{deleted}
Issues: {issues_count} (resolved: {resolved})

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Report Generated
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Type: {report_type}
Feature: {feature_name}
Output: {output_file}

Sections:
- Executive Summary
- Requirements
- Execution Plan
- Code Changes
- Test Results
- Resource Usage
- Recommendations

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
