---
name: best_practices
description: "Use before writing or reviewing React/Next.js, Spring Boot/JPA, or Python/FastAPI code. Delegates to context7 MCP for fresh, version-accurate framework documentation instead of bundling stale rules. **Invoke proactively** whenever you're about to write or modify .tsx/.jsx/.ts (React), .java (Spring/JPA), or .py (FastAPI/SQLAlchemy/async) — call context7 first, then write."
model: inherit
allowed-tools: mcp__context7__resolve-library-id, mcp__context7__query-docs, Read
---

# best_practices — context7-Backed Framework Guidance

Replaces the old `react_best_practices`, `spring_best_practices`, and `python_best_practices` skills with a thin stub that pulls **current** documentation from the upstream framework rather than bundling rules that go stale.

## When to invoke

Claude should consult this skill **before writing or reviewing** code in these stacks (decided by Claude based on the active task, not a formal file-glob trigger):

| Stack | File patterns | Look up |
|-------|---------------|---------|
| React / Next.js | `*.tsx`, `*.jsx`, `*.ts` in components/, hooks/, app/ | `react`, `next`, `tanstack-query`, `zustand`, `react-hook-form` |
| Spring Boot / JPA | `*.java` with `@Service`, `@Entity`, `@RestController`, `@Repository` | `spring-boot`, `spring-data-jpa`, `hibernate` |
| Python / FastAPI | `*.py` with `FastAPI`, `async def`, `pydantic`, SQLAlchemy | `fastapi`, `pydantic`, `sqlalchemy`, `httpx`, `asyncio` |

## Protocol

1. Identify the library or framework you're about to use (e.g. "TanStack Query v5 useMutation").
2. Call `mcp__context7__resolve-library-id` with the library name to get its canonical ID.
3. Call `mcp__context7__query-docs` with the resolved ID and a focused question (not "tell me about X" — ask the *exact* thing you're about to write).
4. Apply the returned guidance. If context7 returns nothing for a niche question, fall back to first principles and note the gap.

## Why this is better than the old skills

- **No stale rules.** v3 React rules don't catch v4-only patterns. context7 reflects whatever the upstream just published.
- **No maintenance debt.** Old skills hard-coded 600+ lines that drifted from the source of truth.
- **Targeted.** Old skills loaded the whole rule sheet on every relevant file. context7 fetches only what you ask about.

## Skip when

- You're editing tests, scripts, or config — the cost of a docs round-trip outweighs the benefit.
- The task is trivial (rename, format, comment-only).
- You already pulled the doc earlier in the same conversation.

## Companion plugins worth installing

For deeper stack-specific guidance beyond raw docs:

- **anthropics/claude-plugins-official** → `code-review` (security + correctness review with confidence scoring)
- **wshobson/agents** → `tdd-workflows`, `debugging-toolkit`, `unit-testing` (workflow specialists by stack)

Install with `/plugin marketplace add <repo>` then `/plugin install <name>@<marketplace>`. See the plugin README for the full companion plugin map.
