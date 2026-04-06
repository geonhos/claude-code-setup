---
name: review
description: "Invoke code-reviewer agent for comprehensive code and documentation review with severity ratings."
model: haiku
allowed-tools: Read, Grep, Glob, Bash
argument-hint: "[file path or branch diff]"
---

# Review — Code Quality Gate

Trigger a comprehensive code review using the code-reviewer agent.

## When to Use

- After implementation is complete
- Before committing significant changes
- User says "review", "check code", "look at this"

## Workflow

### 1. Identify Scope

```bash
# Option A: Review staged changes
git diff --cached --name-only

# Option B: Review branch changes
git diff main...HEAD --name-only

# Option C: Review specific files
# (from argument)
```

### 2. Spawn code-reviewer Agent

Pass all changed files to the `code-reviewer` agent for review.

The agent reviews for:
- Security vulnerabilities (injection, XSS, auth bypass)
- Performance issues (N+1, memory leaks, blocking calls)
- Logic errors (off-by-one, null handling, race conditions)
- Code patterns (DRY, SOLID, naming, structure)
- Documentation accuracy (stale docs, missing updates)

### 3. Severity Rating

| Level | Icon | Meaning | Action |
|-------|------|---------|--------|
| Critical | RED | Security, data loss, crash | Must fix before merge |
| Major | ORANGE | Performance, wrong behavior | Should fix |
| Minor | YELLOW | Style, naming, small improvements | Nice to fix |
| Suggestion | BLUE | Alternative approaches | Consider |

### 4. Output Format

```
══════════════════════════════════
  CODE REVIEW
══════════════════════════════════
  Files Reviewed : {N}
  Critical       : {N}
  Major          : {N}
  Minor          : {N}
  Suggestions    : {N}
  Verdict        : APPROVED | CHANGES REQUESTED
══════════════════════════════════

{per-file findings}
```

## Rules

- code-reviewer does NOT implement fixes (only suggests)
- Zero critical issues required for APPROVED verdict
- Always review documentation alongside code changes
