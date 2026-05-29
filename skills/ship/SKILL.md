---
name: ship
description: "One-prompt feature delivery. A thin conductor that drives native Claude Code through enforced gates: plan (score ≥8) → branch → implement → review (Critical=0) → test (green) → PR. Delegates the doing to native CC; the harness only sequences and gates."
model: opus
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Skill, Agent, TodoWrite
argument-hint: "[feature description]"
---

# Ship — Gated Pipeline Conductor

One prompt. One feature. Fully shipped — with every gate enforced.

`/ship` does **not** implement features with custom agents. It is a thin
conductor: it sequences native Claude Code work and the surviving harness
gates so the discipline (a scored plan, a clean review, green tests) is
*enforced* rather than left to memory. The "doing" is native CC; the harness
only orchestrates and gates.

## When to Use

- A feature, fix, or refactor that should go plan → code → review → test → PR
- User says "ship", "deliver", "build end-to-end"
- 6+ files or cross-domain work (smaller work: just implement directly)

## Delegation map (what runs each stage)

| Stage | Runs via | Companion substitute (if installed) |
|-------|----------|-------------------------------------|
| IMPLEMENT | native Claude Code (TodoWrite + edits, native subagents for parallel work) | `wshobson:tdd-workflows` for a TDD inner loop |
| REVIEW | built-in `/review` | `anthropics:code-review` (richer) — supplement, don't replace |
| Security pass | built-in `/security-review` (run for any auth/data-handling change) | — |
| TEST | pre-commit hook + native test run | `wshobson:unit-testing` |
| COMMIT / PR | inline `git` + `gh` | `anthropics:commit-commands` |

## Pipeline

```
/ship "Add JWT authentication"
  ├─ 1 PLAN    → /plan gate (score ≥8)        [GATE]
  ├─ 2 BRANCH  → git checkout -b feature/...
  ├─ 3 IMPLEMENT → native CC, commit per logical group
  ├─ 4 REVIEW  → /review, fix Criticals       [GATE: Critical=0]
  ├─ 5 TEST    → run suite, fix true failures  [GATE: all green]
  └─ 6 PR      → gh pr create
```

### 1. PLAN — `[GATE]`
Invoke the `/plan` skill. It explores approaches, decomposes into verifiable
tasks, and self-scores. **Gate: score ≥ 8.** If it still scores < 8 after 2
iterations, STOP and ask the user for clarification. Record the score; it goes
in the PR body.

### 2. BRANCH
```bash
SLUG=$(echo "{feature}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/--*/-/g' | head -c 40)
git checkout -b "feature/${SLUG}"
```
If `gh` is available, create a tracking issue first and name the branch
`feature/issue-N-${SLUG}`. If not, skip the issue and proceed.

### 3. IMPLEMENT
Work the plan natively — TodoWrite for task tracking, direct edits, and native
subagents (the `Agent` tool) for independent parallel tasks. Write tests
alongside code. **Commit after each logical group** so the pre-commit hook
validates incrementally (`Refs #N` if an issue exists). No custom domain agents.

### 4. REVIEW — `[GATE: Critical = 0]`
Run the built-in `/review` skill (or `anthropics:code-review` if installed)
over `git diff main...HEAD`. For any auth/data-handling change, also run
`/security-review`. **Gate: zero Critical findings.** Fix Criticals and
re-review; max 2 cycles, then pause and report.

### 5. TEST — `[GATE: all green]`
Run the full test suite (auto-detect framework). **Gate: all pass.** On
failure, classify (true failure / test bug / flaky / environment) and fix true
failures + test bugs; re-run, max 2 cycles, then pause and report.

### 6. PR
```bash
git push -u origin "$(git branch --show-current)"
gh pr create --title "feat: {feature}" --body "$(cat <<'EOF'
## Summary
{1-3 bullets}

## Plan
- Score: {N}/10

## Review / Test
- Review: Critical 0
- Tests: {passed}/{total} ✅
EOF
)"
```
Never merge the PR — the user decides when.

## Progress marker
Write a one-line status to `harness/progress.md` as stages complete
(`Status: In Progress` while running, `Status: Shipped` at the end). The Stop
hook uses this to nudge completion of an active pipeline; on resume, continue
from the last completed stage.

## Rules
- NEVER skip a gate (plan score, review, tests) — that enforcement *is* the value.
- NEVER auto-push without creating a PR; NEVER merge the PR.
- ALWAYS commit per logical group so pre-commit validates incrementally.
- If `gh` is unavailable, skip ISSUE/PR but run every other stage and gate.
