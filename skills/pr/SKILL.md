---
name: pr
description: "Create pull requests with structured templates, auto-generated summary, and issue linking."
model: haiku
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
argument-hint: "[base-branch]"
---

# PR — Pull Request Creation

Create well-structured PRs with auto-generated descriptions.

## Workflow

### 1. Analyze Changes

```bash
# All commits on this branch
git log main..HEAD --oneline

# Full diff summary
git diff main...HEAD --stat

# Current branch
git branch --show-current
```

### 2. Push Branch

```bash
git push -u origin $(git branch --show-current)
```

### 3. Create PR

```bash
gh pr create \
  --title "{type}: {description}" \
  --body "$(cat <<'EOF'
## Summary
- {bullet 1}
- {bullet 2}
- {bullet 3}

## Changes
- `{path}`: {description}

## Related Issue
Closes #{issue_number}

## Test Results
- Tests: {passed}/{total} passing
- Coverage: {X}% on changed files

## Checklist
- [x] Tests added/updated
- [x] Documentation updated
- [x] Self-reviewed
- [ ] Ready for team review

## Test Plan
{steps to verify}
EOF
)"
```

### 4. Output

```
PR CREATED
══════════
  Number : #{pr_number}
  Title  : {title}
  URL    : {url}
  Base   : {base_branch}
  Closes : #{issue_number}
```

## PR Types

| Type | Title Prefix | Template Focus |
|------|-------------|----------------|
| Feature | `feat:` | Summary + changes + test plan |
| Bug Fix | `fix:` | Root cause + fix + test plan |
| Refactor | `refactor:` | Motivation + breaking changes |

## Management

| Action | Command |
|--------|---------|
| List | `gh pr list` |
| View | `gh pr view {N}` |
| Edit | `gh pr edit {N}` |
| Reviewer | `gh pr edit --add-reviewer {user}` |
| Merge | `gh pr merge --squash --delete-branch` |

## Rules

- NEVER auto-merge (user decides)
- Always link to issue with `Closes #N`
- Keep title under 70 characters
- Include test results in description
