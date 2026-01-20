---
name: git_pr
description: Creates and manages Pull Requests with structured templates. Handles PR creation, description formatting, and merge strategies.
model: haiku
color: purple
---

# Git PR Skill

Creates and manages Pull Requests with structured templates.

## PR Title Format

```
[Phase {number}] {description}
```

**Examples:**
- `[Phase 5] User Authentication System`
- `[Phase 6] Fix login redirect issue`
- `[Phase 7] Refactor database connection`

---

## Workflow

### 1. Push Branch

```bash
# First push (set upstream)
git push -u origin feature/issue-123-user-auth

# Subsequent pushes
git push
```

### 2. Create PR

```bash
gh pr create \
  --title "[Phase 5] User Authentication" \
  --body "$(cat <<'EOF'
## Summary
- Implement user authentication with JWT
- Add login/logout endpoints
- Add auth middleware

## Changes
- `app/auth/`: Authentication module
- `app/middleware/`: Auth middleware
- `tests/test_auth.py`: Auth tests

## Related Issue
Closes #123

## Checklist
- [x] Tests passing
- [x] Code reviewed (self)
- [ ] Ready for team review

## Test Plan
1. POST /auth/login with valid credentials
2. Access protected endpoint with token
3. Verify token expiration
EOF
)"
```

### 3. Result

```
✅ Pull Request created: #124
🔗 https://github.com/owner/repo/pull/124
📋 Closes #123

Ready for review!
```

---

## PR Template

### Standard Template

```markdown
## Summary
{1-3 bullet points describing changes}

## Changes
- `{path}`: {description}
- `{path}`: {description}

## Related Issue
Closes #{issue_number}

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] Self-reviewed
- [ ] Ready for review

## Test Plan
{Steps to verify the changes}

## Screenshots (if UI changes)
{Add screenshots}
```

### Minimal Template

```markdown
## Summary
{Brief description}

## Related Issue
Closes #{issue_number}

## Test Plan
{How to test}
```

---

## PR Types

### Feature PR

```markdown
## Summary
- Add user profile management feature
- Implement avatar upload with S3
- Add profile validation

## Changes
- `app/routers/profile.py`: Profile endpoints
- `app/services/profile.py`: Profile service
- `app/schemas/profile.py`: Profile schemas

## Related Issue
Closes #45

## Checklist
- [x] Unit tests added
- [x] Integration tests added
- [x] API docs updated
- [ ] Ready for review

## Test Plan
1. Create profile: POST /profile
2. Upload avatar: POST /profile/avatar
3. Get profile: GET /profile/{id}
```

### Bug Fix PR

```markdown
## Summary
- Fix null pointer exception in user service
- Add null checks for optional fields

## Root Cause
User object was accessed without checking existence.

## Changes
- `app/services/user.py`: Add null checks
- `tests/test_user.py`: Add edge case tests

## Related Issue
Closes #67

## Test Plan
1. Create user without optional fields
2. Verify no exceptions thrown
```

### Refactor PR

```markdown
## Summary
- Refactor database connection to use connection pooling
- Improve query performance by 40%

## Changes
- `app/database.py`: Implement connection pool
- `app/config.py`: Add pool settings
- `config/database.yaml`: Pool configuration

## Related Issue
Closes #89

## Breaking Changes
None

## Test Plan
1. Run load test with 100 concurrent users
2. Verify connection reuse in logs
```

---

## PR Management

### Update PR

```bash
# Push additional commits
git add .
git commit -m "Address review feedback"
git push
```

### Edit PR

```bash
# Edit title
gh pr edit --title "[Phase 5] Updated Title"

# Edit body
gh pr edit --body "New description"

# Add label
gh pr edit --add-label "enhancement"
```

### Request Review

```bash
# Add reviewer
gh pr edit --add-reviewer username

# Multiple reviewers
gh pr edit --add-reviewer user1,user2
```

---

## Merge Strategies

| Strategy | Command | When to Use |
|----------|---------|-------------|
| **Squash** | `gh pr merge --squash` | Feature branches (recommended) |
| **Merge** | `gh pr merge --merge` | Release branches |
| **Rebase** | `gh pr merge --rebase` | Linear history preferred |

### Merge PR

```bash
# Squash merge (recommended)
gh pr merge --squash --delete-branch

# Specify merge commit message
gh pr merge --squash --subject "[Phase 5] Feature" --body "Closes #123"
```

### Post-Merge Cleanup

```bash
git checkout main
git pull origin main
git branch -d feature/issue-123-user-auth
git fetch --prune
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| Create PR | `gh pr create` |
| List PRs | `gh pr list` |
| View PR | `gh pr view {number}` |
| Edit PR | `gh pr edit {number}` |
| Checkout PR | `gh pr checkout {number}` |
| Merge PR | `gh pr merge {number}` |
| Close PR | `gh pr close {number}` |
| Add reviewer | `gh pr edit --add-reviewer {user}` |
| Add label | `gh pr edit --add-label {label}` |

---

## Best Practices

1. **Small PRs** - 300 lines or less recommended
2. **Clear title** - What was done at a glance
3. **Detailed description** - Why and how it was done
4. **Include tests** - Add tests with PR
5. **Self-review** - Review yourself before requesting
6. **Link issues** - Auto-close with `Closes #N`

---

## Troubleshooting

### PR Conflict

```bash
# Update main then rebase
git checkout main && git pull
git checkout feature/issue-123
git rebase main
# Resolve conflicts
git add .
git rebase --continue
git push --force-with-lease
```

### Wrong Base Branch

```bash
# Change base branch
gh pr edit --base develop
```
