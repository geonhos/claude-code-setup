# Brainstorm Skill

---
name: brainstorm
description: Progressive design exploration before implementation commitment.
model: claude-opus-4-5-20250101
---

## Purpose

Enable progressive exploration of multiple approaches before committing to implementation. This skill ensures that design decisions are made with full awareness of alternatives and tradeoffs.

## When to Use

- Before starting complex feature implementation
- When multiple valid approaches exist
- When architectural decisions need to be made
- When requirements are ambiguous or open-ended

## Workflow

### Step 1: Problem Definition
- Clearly state the problem to solve
- Identify constraints and requirements
- Define success criteria

### Step 2: Explore Approaches (Minimum 3)
For each approach, document:
- **Name**: Descriptive identifier
- **Description**: How it works
- **Pros**: Benefits and advantages
- **Cons**: Drawbacks and limitations
- **Effort**: Estimated complexity (Low/Medium/High)
- **Risk**: Potential issues (Low/Medium/High)

### Step 3: Tradeoff Matrix
Create a comparison matrix:

| Criteria | Approach A | Approach B | Approach C |
|----------|------------|------------|------------|
| Complexity | Low/Med/High | Low/Med/High | Low/Med/High |
| Performance | Low/Med/High | Low/Med/High | Low/Med/High |
| Maintainability | Low/Med/High | Low/Med/High | Low/Med/High |
| Scalability | Low/Med/High | Low/Med/High | Low/Med/High |
| Time to Implement | X days | Y days | Z days |

### Step 4: Recommendation
- State recommended approach
- Explain reasoning
- Note any assumptions made

### Step 5: User Confirmation Checkpoint
**MANDATORY**: Do not proceed without user confirmation.

```
=== Brainstorm Summary ===
Problem: [description]
Approaches Explored: [count]
Recommended: [approach name]
Reasoning: [brief explanation]

Proceed with recommended approach? (yes/no/discuss further)
```

## Output Format

```markdown
# Brainstorm: [Feature/Problem Name]

## Problem Statement
[Clear description of what needs to be solved]

## Constraints
- [Constraint 1]
- [Constraint 2]

## Approaches Explored

### Approach 1: [Name]
- **Description**: ...
- **Pros**: ...
- **Cons**: ...
- **Effort**: Medium
- **Risk**: Low

### Approach 2: [Name]
...

### Approach 3: [Name]
...

## Tradeoff Matrix
| Criteria | Approach 1 | Approach 2 | Approach 3 |
|----------|------------|------------|------------|
| ... | ... | ... | ... |

## Recommendation
**Selected Approach**: [Name]
**Reasoning**: [Explanation]

## Decision Rationale
[Document why this decision was made for future reference]

---
**User Confirmation**: [ ] Approved / [ ] Needs Discussion
```

## Examples

### Example 1: Authentication Implementation
```
Problem: Implement user authentication
Approaches:
1. JWT-based stateless auth
2. Session-based auth with Redis
3. OAuth2 with external provider

Tradeoff: JWT offers simplicity, Sessions offer revocability, OAuth reduces liability
Recommendation: JWT for API-first architecture
```

### Example 2: Data Storage
```
Problem: Store user preferences
Approaches:
1. PostgreSQL (existing DB)
2. Redis (fast access)
3. Local storage (client-side)

Tradeoff: PostgreSQL for persistence, Redis for speed, Local for offline
Recommendation: PostgreSQL with Redis cache
```

## Integration

- **Triggers automatically when**: User says "brainstorm", "explore options", "alternatives", "approaches"
- **Works with**: `requirements-analyst`, `plan-architect`
- **Output feeds into**: `plan-architect` for implementation planning

## Quality Checklist

- [ ] Minimum 3 approaches explored
- [ ] All approaches have pros/cons documented
- [ ] Tradeoff matrix completed
- [ ] Clear recommendation with reasoning
- [ ] User confirmation obtained before proceeding
- [ ] Decision rationale documented for future reference
