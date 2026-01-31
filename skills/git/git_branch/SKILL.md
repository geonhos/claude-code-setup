---
name: git_branch
description: Manages Git branches with consistent naming conventions. Handles creation, switching, deletion, and cleanup based on issue numbers.
model: haiku
color: cyan
---

# Git Branch Skill

Manages branches with consistent naming conventions.

## Branch Naming Convention

```
{type}/issue-{number}-{short-description}
```

### Branch Types

| Type | Description | Example |
|------|-------------|---------|
| `feature` | New feature | `feature/issue-123-user-auth` |
| `fix` | Bug fix | `fix/issue-456-login-error` |
| `refactor` | Refactoring | `refactor/issue-789-db-pool` |
| `docs` | Documentation | `docs/issue-101-api-docs` |
| `test` | Testing | `test/issue-202-unit-tests` |
| `chore` | Maintenance | `chore/issue-303-ci-setup` |

### Naming Rules

- Use lowercase only
- Use hyphens instead of spaces (`-`)
- Always include issue number
- Keep description concise (3-4 words)

---

## Workflow

### 1. Create Branch

```bash
# Update main
git checkout main
git pull origin main

# Create branch
git checkout -b feature/issue-123-user-authentication
```

### 2. Auto-Generate Branch Name

Auto-generate from issue info:

```bash
ISSUE_NUMBER=123
TYPE="feature"

# Get issue title
TITLE=$(gh issue view $ISSUE_NUMBER --json title -q '.title')
# [Phase 5] User Authentication System

# Generate branch name
BRANCH=$(echo "$TITLE" | \
  sed 's/\[Phase [0-9]*\] //' | \
  tr '[:upper:]' '[:lower:]' | \
  tr ' ' '-' | \
  tr -cd 'a-z0-9-' | \
  cut -c1-30)

git checkout -b "${TYPE}/issue-${ISSUE_NUMBER}-${BRANCH}"
# → feature/issue-123-user-authentication-sys
```

### 3. Link to Issue (GitHub)

```bash
# Link with GitHub CLI
gh issue develop 123 --checkout

# Or manually create branch and link
gh issue develop 123 --name feature/issue-123-user-auth
```

---

## Branch Management

### Switch Branch

```bash
# Switch branch
git checkout feature/issue-123-user-auth

# Or (Git 2.23+)
git switch feature/issue-123-user-auth
```

### List Branches

```bash
# Local branches
git branch

# All including remote
git branch -a

# Search by issue number
git branch | grep issue-123
```

### Delete Branch

```bash
# Delete local (merged branch)
git branch -d feature/issue-123-user-auth

# Force delete local
git branch -D feature/issue-123-user-auth

# Delete remote
git push origin --delete feature/issue-123-user-auth
```

### Cleanup Stale Branches

```bash
# Prune branches deleted from remote
git fetch --prune

# Delete merged local branches
git branch --merged main | grep -v "main" | xargs -n 1 git branch -d

# Check stale branches
git for-each-ref --sort=-committerdate --format='%(refname:short) %(committerdate:relative)' refs/heads/
```

---

## Branch Strategy

### Git Flow (Simple)

```
main (production)
  └── feature/issue-XXX-description
  └── fix/issue-XXX-description
```

### Development Flow

```bash
# 1. Start from main
git checkout main
git pull

# 2. Create feature branch
git checkout -b feature/issue-123-new-feature

# 3. Work and commit
git add .
git commit -m "[Phase X] ..."

# 4. Push to remote
git push -u origin feature/issue-123-new-feature

# 5. Create PR and merge

# 6. Local cleanup
git checkout main
git pull
git branch -d feature/issue-123-new-feature
```

---

## Sync with Remote

### Update Branch

```bash
# Update main then rebase
git checkout main
git pull
git checkout feature/issue-123-feature
git rebase main

# After resolving conflicts
git add .
git rebase --continue

# Force push to remote (use with caution)
git push --force-with-lease
```

### Fetch All

```bash
# Fetch all remote branches
git fetch --all

# Checkout remote branch
git checkout -b local-branch origin/remote-branch
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| Create | `git checkout -b {branch}` |
| Switch | `git checkout {branch}` |
| List | `git branch -a` |
| Delete local | `git branch -d {branch}` |
| Delete remote | `git push origin --delete {branch}` |
| Rename | `git branch -m {old} {new}` |
| Current | `git branch --show-current` |
| Prune | `git fetch --prune` |

---

## Examples

### Create Feature Branch
```bash
git checkout main && git pull
git checkout -b feature/issue-42-payment-gateway
```

### Create Fix Branch
```bash
git checkout main && git pull
git checkout -b fix/issue-99-null-pointer
```

### Cleanup After Merge
```bash
git checkout main
git pull origin main
git branch -d feature/issue-42-payment-gateway
git fetch --prune
```
