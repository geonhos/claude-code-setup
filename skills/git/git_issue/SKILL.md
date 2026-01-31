---
name: git_issue
description: Creates and manages GitHub issues with structured templates. Handles issue creation, searching, and labeling for task tracking.
model: haiku
color: blue
---

# Git Issue Skill

Creates and manages GitHub issues with structured templates.

## Issue Title Format

```
[Phase {number}] {description}
```

**Examples:**
- `[Phase 5] User Authentication System`
- `[Phase 6] Fix login timeout issue`
- `[Phase 7] API Documentation`

---

## Workflow

### 1. Create Issue

```bash
gh issue create \
  --title "[Phase 5] User Authentication System" \
  --body "$(cat <<'EOF'
## Objective
Implement secure user authentication with JWT tokens.

## Implementation
- [ ] Login endpoint with email/password
- [ ] JWT token generation
- [ ] Token refresh mechanism
- [ ] Logout endpoint
- [ ] Auth middleware

## Acceptance Criteria
- Users can login with valid credentials
- JWT token expires after 24 hours
- Protected endpoints require valid token

## Technical Notes
- Use PyJWT for token handling
- Store refresh tokens in Redis
- Password hashing with bcrypt

## References
- JWT Best Practices: https://...
- Auth Design Doc: docs/auth.md
EOF
)" \
  --assignee @me \
  --label enhancement
```

### 2. Result

```
✅ Issue created: #123
🔗 https://github.com/owner/repo/issues/123

Ready to create branch!
```

---

## Issue Templates

### Feature Issue

```markdown
## Objective
{What problem does this solve?}

## Implementation
- [ ] {Task 1}
- [ ] {Task 2}
- [ ] {Task 3}

## Acceptance Criteria
- {Criterion 1}
- {Criterion 2}

## Technical Notes
{Implementation details}

## References
- {Related docs or links}
```

### Bug Issue

```markdown
## Bug Description
{What is happening?}

## Expected Behavior
{What should happen?}

## Steps to Reproduce
1. {Step 1}
2. {Step 2}
3. {Step 3}

## Environment
- OS: {os}
- Version: {version}
- Browser: {if applicable}

## Logs/Screenshots
{Error logs or screenshots}

## Possible Cause
{If known}
```

### Refactor Issue

```markdown
## Objective
{Why refactor?}

## Current State
{What's wrong with current implementation?}

## Proposed Changes
- {Change 1}
- {Change 2}

## Impact
- Files affected: {list}
- Breaking changes: {yes/no}

## Success Metrics
- {Metric 1: e.g., 30% performance improvement}
```

### Documentation Issue

```markdown
## Objective
{What documentation is needed?}

## Scope
- [ ] {Doc 1}
- [ ] {Doc 2}

## Target Audience
{Who will read this?}

## References
- {Existing docs to update}
```

---

## Issue Labels

### Common Labels

| Label | Color | Description |
|-------|-------|-------------|
| `enhancement` | 🟢 | New feature |
| `bug` | 🔴 | Bug fix |
| `documentation` | 🔵 | Documentation |
| `refactor` | 🟡 | Code refactoring |
| `test` | 🟣 | Testing |
| `chore` | ⚪ | Maintenance |

### Priority Labels

| Label | Description |
|-------|-------------|
| `priority: high` | Urgent |
| `priority: medium` | Normal |
| `priority: low` | Can wait |

### Status Labels

| Label | Description |
|-------|-------------|
| `status: ready` | Ready to work |
| `status: in-progress` | Being worked on |
| `status: blocked` | Blocked by something |
| `status: review` | Under review |

---

## Issue Management

### Search Issues

```bash
# Issues assigned to me
gh issue list --assignee @me

# By state
gh issue list --state open
gh issue list --state closed

# By label
gh issue list --label bug
gh issue list --label "priority: high"

# By search term
gh issue list --search "authentication"

# Combined
gh issue list --assignee @me --state open --label enhancement
```

### View Issue

```bash
# View details
gh issue view 123

# Open in web
gh issue view 123 --web

# JSON output
gh issue view 123 --json title,body,labels
```

### Update Issue

```bash
# Add label
gh issue edit 123 --add-label "priority: high"

# Remove label
gh issue edit 123 --remove-label "status: ready"

# Change assignee
gh issue edit 123 --add-assignee username

# Change title
gh issue edit 123 --title "[Phase 5] Updated Title"
```

### Close Issue

```bash
# Close issue
gh issue close 123

# Close with comment
gh issue close 123 --comment "Completed in PR #124"

# Reopen
gh issue reopen 123
```

---

## Issue to Branch Flow

```bash
# 1. Create issue
gh issue create --title "[Phase 5] Feature" --assignee @me
# → Issue #123 created

# 2. Create branch (linked to issue)
gh issue develop 123 --checkout
# → Branch created and linked

# Or manually
git checkout -b feature/issue-123-description

# 3. After work, create PR (auto-close issue)
gh pr create --body "Closes #123"
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| Create | `gh issue create` |
| List | `gh issue list` |
| View | `gh issue view {num}` |
| Edit | `gh issue edit {num}` |
| Close | `gh issue close {num}` |
| Reopen | `gh issue reopen {num}` |
| Comment | `gh issue comment {num}` |
| Search | `gh issue list --search "query"` |

---

## Best Practices

1. **Clear title** - Understandable at a glance
2. **Detailed description** - Include goal, implementation, and acceptance criteria
3. **Checklists** - Track progress
4. **Use labels** - For categorization and filtering
5. **Assign owner** - Clear responsibility
6. **Link issues** - Reference related issues (`#123`)

---

## Examples

### Create Feature Issue
```bash
gh issue create \
  --title "[Phase 8] Payment Gateway Integration" \
  --body "## Objective
Integrate Stripe payment gateway.

## Implementation
- [ ] Stripe SDK setup
- [ ] Payment intent creation
- [ ] Webhook handling
- [ ] Refund support

## Acceptance Criteria
- Users can pay with credit card
- Transactions are recorded
- Webhooks update order status" \
  --label enhancement \
  --assignee @me
```

### Create Bug Issue
```bash
gh issue create \
  --title "[Phase 8] Fix payment timeout error" \
  --body "## Bug Description
Payment fails after 30 seconds.

## Steps to Reproduce
1. Add item to cart
2. Proceed to checkout
3. Wait 30+ seconds

## Expected
Payment should complete.

## Logs
\`\`\`
TimeoutError: Payment gateway timeout
\`\`\`" \
  --label bug \
  --label "priority: high"
```
