# Rule Template

Use this template to create new performance optimization rules.

---

## Metadata Block

```markdown
---
title: Rule Title
impact: CRITICAL | HIGH | MEDIUM | LOW
section: async | bundle | server | client | rerender | rendering | js | advanced
tags: [tag1, tag2]
improvement: "2-10x performance improvement"
---
```

---

## Rule Structure

```markdown
# [Rule Title]

**Impact:** [CRITICAL/HIGH/MEDIUM/LOW]
**Improvement:** [Expected performance gain]

## Description

[2-3 sentences explaining what this rule addresses and why it matters for performance]

## Problem

[Explain the problematic pattern and its performance implications]

### Bad Example

```typescript
// Explain why this is problematic
[code example]
```

## Solution

[Explain the optimized approach]

### Good Example

```typescript
// Explain why this is better
[code example]
```

## Why It Matters

[Explain the technical reason this optimization works, with metrics if available]

## Related Rules

- [link to related rule 1]
- [link to related rule 2]

## References

- [External documentation link]
```

---

## Naming Convention

Files should be named with the section prefix:

| Section | Prefix | Example |
|---------|--------|---------|
| Eliminating Waterfalls | `async-` | `async-parallel.md` |
| Bundle Size | `bundle-` | `bundle-direct-imports.md` |
| Server Performance | `server-` | `server-caching.md` |
| Client Data Fetching | `client-` | `client-swr.md` |
| Re-render Optimization | `rerender-` | `rerender-state-split.md` |
| Rendering Performance | `rendering-` | `rendering-containment.md` |
| JavaScript Performance | `js-` | `js-batch-updates.md` |
| Advanced Patterns | `advanced-` | `advanced-refs.md` |

---

## Guidelines

1. **Be specific** - Each rule should address one optimization
2. **Show contrast** - Always include bad vs good examples
3. **Quantify gains** - Include expected performance improvements
4. **Explain why** - Help readers understand the underlying mechanics
5. **Keep it actionable** - Rules should be immediately applicable
