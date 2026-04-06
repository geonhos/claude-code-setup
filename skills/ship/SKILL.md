---
name: ship
description: "Full pipeline harness: one prompt to ship a complete feature. Runs plan → score → issue → branch → execute → review → test → PR automatically."
model: opus
allowed-tools: Agent, Bash, Read, Write, Edit, Grep, Glob
argument-hint: "[feature description]"
---

# Ship — Full Pipeline Harness

One prompt. One feature. Fully shipped.

## When to Use

- User describes a feature, bug fix, or refactor to implement end-to-end
- User says "ship", "implement", "build", "deliver"
- Any task that requires plan → code → test → PR

## Pipeline Overview

```
/ship "Add user authentication with JWT"
  │
  ├─ Stage 1: PLAN ──────── plan-architect agent (auto-scored ≥8)
  ├─ Stage 2: ISSUE ─────── gh issue create
  ├─ Stage 3: BRANCH ────── git checkout -b feature/issue-N-slug
  ├─ Stage 4: EXECUTE ───── domain agents (backend/frontend/ai)
  ├─ Stage 5: REVIEW ────── code-reviewer agent
  ├─ Stage 6: TEST ──────── qa-executor agent
  ├─ Stage 7: PR ─────────── gh pr create
  └─ Stage 8: PROGRESS ──── update harness/progress.md
```

## Pipeline Execution

### Stage 1: PLAN

Spawn `plan-architect` agent to create an execution plan.

**Instructions for plan-architect:**
1. Analyze the feature requirement
2. Decompose into atomic tasks (2-5 min each)
3. Assign each task to the appropriate agent (backend-dev, frontend-dev, ai-expert)
4. Map dependencies and parallel groups
5. Self-validate with score ≥ 8/10
6. If score < 8, iterate and fix issues automatically

**Expected output:** Validated execution plan with tasks, agents, dependencies, and score.

**Gate:** Plan must score ≥ 8. If after 2 attempts it still fails, STOP and ask the user for clarification.

```
[ PLAN ] Feature: {description}
         Score: {N}/10 ✅
         Tasks: {count} | Agents: {list}
         Complexity: {simple|moderate|complex}
```

### Stage 2: ISSUE

Create a GitHub/GitLab issue from the validated plan.

```bash
# Detect remote platform
REMOTE_URL=$(git remote get-url origin 2>/dev/null)

# GitHub
gh issue create \
  --title "feat: {feature-slug}" \
  --body "$(cat <<'EOF'
## Description
{feature description from user prompt}

## Execution Plan
- Complexity: {level}
- Tasks: {count}
- Agents: {agent list}

## Tasks
{task list from plan with checkboxes}

## Acceptance Criteria
{from plan validation}
EOF
)"
```

**Gate:** Issue must be created successfully. Capture issue number.

```
[ ISSUE ] Created #{issue_number}: {title}
```

### Stage 3: BRANCH

Create a feature branch linked to the issue.

```bash
# Slugify feature name
SLUG=$(echo "{feature}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 40)
BRANCH="feature/issue-${ISSUE_NUMBER}-${SLUG}"

git checkout -b "$BRANCH"
```

```
[ BRANCH ] Created: {branch_name}
```

### Stage 4: EXECUTE

For each task in the plan (respecting dependency order and parallel groups):

1. **Route to agent** based on plan assignment:
   - Java/Spring/API → `backend-dev` agent
   - React/TypeScript/UI → `frontend-dev` agent
   - Python/ML/AI → `ai-expert` agent

2. **Agent implements:**
   - Write code
   - Write tests (TDD: test first, then implementation)
   - Verify acceptance criteria

3. **Commit after each logical group:**
   ```bash
   git add {specific files}
   git commit -m "feat(scope): {task description}

   Refs #{issue_number}"
   ```

**Parallel execution:** When tasks in the same parallel group have no cross-dependencies, spawn multiple agents simultaneously using the Agent tool.

**Progress tracking per task:**
```
[ EXEC ] Task {id}: {description}
         Agent: {agent_name}
         Status: ✅ Complete | ❌ Failed | ⏳ In Progress
```

**Gate:** All tasks must pass their acceptance criteria. If a task fails:
1. Analyze the failure
2. Attempt auto-fix (max 2 retries)
3. If still failing, report to user and pause

### Stage 5: REVIEW

Spawn `code-reviewer` agent to review ALL changes since branch creation.

```bash
# Show all changes for review
git diff main...HEAD
```

**Review criteria:**
- Critical (blocks ship): security vulnerabilities, data loss risks, broken logic
- Major (should fix): performance issues, missing error handling, bad patterns
- Minor (nice to fix): naming, style, minor optimizations

**Gate:** Zero critical issues. If critical issues found:
1. Auto-fix critical issues
2. Re-run review
3. Max 2 fix-review cycles

```
[ REVIEW ] Critical: {0} | Major: {N} | Minor: {N}
           Status: ✅ Approved | ❌ Blocked
```

### Stage 6: TEST

Spawn `qa-executor` agent to run the full test suite.

**Test execution:**
1. Auto-detect test framework
2. Run full test suite (not just new tests)
3. Analyze any failures
4. Generate coverage report for changed files

**Gate:** All tests must pass. If failures:
1. Categorize: True Failure vs Test Bug vs Flaky vs Environment
2. Fix True Failures and Test Bugs
3. Re-run tests
4. Max 2 fix-test cycles

```
[ TEST ] Passed: {N} | Failed: {N} | Skipped: {N}
         Coverage: {X}% (changed files)
         Status: ✅ All Green | ❌ Failures
```

### Stage 7: PR

Create a pull request with full context.

```bash
# Push branch
git push -u origin "$BRANCH"

# Create PR
gh pr create \
  --title "feat: {feature description}" \
  --body "$(cat <<'EOF'
## Summary
{1-3 bullet points from plan}

## Changes
{file-by-file summary from commits}

## Execution Plan
- Plan Score: {N}/10
- Tasks Completed: {completed}/{total}
- Agents Used: {list}

## Test Results
- Tests: {passed}/{total} passing
- Coverage: {X}% on changed files

## Review Status
- Critical Issues: 0
- Major Issues: {N} (addressed)

Closes #{issue_number}

## Test Plan
{verification steps from plan}
EOF
)"
```

```
[ PR ] Created #{pr_number}: {title}
       URL: {pr_url}
       Closes #{issue_number}
```

### Stage 8: PROGRESS

Update the harness progress file for cross-session tracking.

Write to `harness/progress.md`:
```markdown
# Ship Progress

## Latest: {feature name}
- **Status**: Shipped
- **Issue**: #{issue_number}
- **PR**: #{pr_number}
- **Branch**: {branch}
- **Plan Score**: {N}/10
- **Tasks**: {completed}/{total}
- **Tests**: {passed}/{total}
- **Date**: {YYYY-MM-DD}
```

## Final Output

After all stages complete, display a summary:

```
══════════════════════════════════════════════════════
  SHIP COMPLETE
══════════════════════════════════════════════════════
  Feature : {description}
  Issue   : #{issue_number}
  PR      : #{pr_number} → {pr_url}
  Branch  : {branch_name}
  Plan    : {score}/10 | {task_count} tasks
  Tests   : {passed}/{total} ✅
  Review  : Approved ✅
══════════════════════════════════════════════════════
```

## Error Handling

| Stage | Failure | Action |
|-------|---------|--------|
| PLAN | Score < 8 after 2 tries | Ask user for clarification |
| ISSUE | gh not authenticated | Prompt user to run `! gh auth login` |
| EXECUTE | Task fails after 2 retries | Pause, report to user |
| REVIEW | Critical issues after 2 fixes | Pause, report to user |
| TEST | Failures after 2 fix cycles | Pause, report to user |
| PR | Push rejected | Check branch protection, report |

## Pipeline Interruption

If the pipeline is interrupted mid-execution:
1. Check `harness/progress.md` for last completed stage
2. Resume from the next stage
3. Do not re-execute completed stages

## Rules

- NEVER skip any stage (even for "simple" features)
- NEVER auto-push without creating PR first
- NEVER merge the PR (user decides when to merge)
- ALWAYS commit after each logical task group
- ALWAYS run full test suite, not just new tests
- ALWAYS create issue before branching
- If `gh` CLI is not available, skip ISSUE and PR stages but complete all others
