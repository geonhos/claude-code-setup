---
name: git_commit
description: Analyzes staged changes, checks documentation freshness, and generates structured commit messages following [Phase X] format. Includes status check, staging, doc update, and commit execution.
model: haiku
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
argument-hint: "[message]"
---

# Git Commit Skill

Analyzes changes and generates structured commit messages.

## Workflow

### 1. Check Status

```bash
# Check current status
git status --short

# Check staged changes
git diff --cached --stat
git diff --cached --name-only
```

### 2. Stage Changes (Optional)

```bash
# Stage specific files (preferred - avoids accidentally staging secrets)
git add src/api/auth.py tests/test_auth.py

# Stage by directory
git add src/ tests/

# Stage with patch review
git add -p
```

**IMPORTANT**: Avoid `git add -A` or `git add .` which can accidentally
stage sensitive files (.env, credentials) or large binaries.

### 3. Analyze Changes

Categorize changed files by section:

| Section | Files |
|---------|-------|
| **Source Code** | src/, lib/, app/ |
| **Tests** | tests/, __tests__/, *_test.* |
| **Dependencies** | requirements.txt, package.json, pyproject.toml |
| **Configuration** | config/, *.yaml, *.json |
| **Documentation** | README.md, docs/, *.md |
| **Infrastructure** | Dockerfile, docker-compose.yml, .github/ |
| **Other** | .gitignore, LICENSE, etc. |

### 4. Documentation Freshness Check

Before committing, scan for documentation that may be stale due to your code changes.

**Check targets** (if they exist in the project):

```bash
# Find documentation files in the project
find . -maxdepth 3 -name "README.md" -o -name "CHANGELOG.md" -o -name "*.md" -path "*/docs/*" 2>/dev/null | head -20
```

**What to verify:**

| Changed | Check |
|---------|-------|
| Public API (endpoints, functions, CLI args) | README usage examples, API docs |
| Dependencies added/removed | README install section, requirements |
| Config format changed | README configuration section |
| File/directory structure changed | README directory tree |
| New feature or bug fix | CHANGELOG.md (if project uses one) |
| Function signature or behavior | Docstrings / JSDoc / KDoc in changed files |

**Rules:**
- Only update docs that **already exist** — do not create new doc files
- Only update sections that are **actually affected** by the code change
- If no docs are affected, skip this step entirely
- Include doc updates in the **same commit** as the code change

### 5. Generate Commit Message

**Format:**
```
[Phase {number}] {summary}

{Section 1}:
- {file}: {description}

{Section 2}:
- {file}: {description}

Refs #{issue_number}
```

**Rules:**
- Title: 50 characters or less
- Body: Wrap at 72 characters
- Use `Closes #N` for final commit, `Refs #N` for intermediate commits

### 6. Execute Commit

```bash
git commit -m "$(cat <<'EOF'
[Phase 5] Implement user authentication

Source Code:
- app/auth/login.py: Login handler with JWT
- app/auth/middleware.py: Auth middleware

Tests:
- tests/test_auth.py: Authentication unit tests

Dependencies:
- requirements.txt: Added PyJWT, passlib

Refs #123
EOF
)"
```

---

## Commit Types

| Type | When to Use |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `refactor` | Refactoring (no behavior change) |
| `test` | Add/modify tests |
| `docs` | Documentation |
| `chore` | Build, config, etc. |
| `style` | Code style (formatting) |

---

## Examples

### Feature Commit
```
[Phase 3] Add user profile endpoint

Source Code:
- app/routers/users.py: GET /users/{id}/profile endpoint
- app/schemas/user.py: UserProfile response schema
- app/services/user_service.py: get_profile method

Tests:
- tests/api/test_users.py: Profile endpoint tests

Refs #45
```

### Bug Fix Commit
```
[Phase 3] Fix login session timeout issue

Source Code:
- app/auth/session.py: Extend session TTL to 24h
- app/config.py: Add SESSION_TTL setting

Tests:
- tests/test_session.py: Session expiry tests

Closes #67
```

### Refactor Commit
```
[Phase 4] Refactor database connection pooling

Source Code:
- app/database.py: Implement connection pool
- app/config.py: Add pool size settings

Configuration:
- config/database.yaml: Pool configuration

Refs #89
```

---

## Auto-Detection

### Issue Number
```bash
# Extract from branch name
git branch --show-current | grep -oE 'issue-[0-9]+' | grep -oE '[0-9]+'

# Example: feature/issue-123-auth → 123
```

### Phase Number
```bash
# Extract from recent commit
git log -1 --format=%s | grep -oE '\[Phase ([0-9]+)\]' | grep -oE '[0-9]+'

# Next Phase = last + 1
```

---

## Best Practices

1. **Small commits** - One logical change = one commit
2. **Commit often** - Save progress frequently
3. **Commit after tests pass** - Never commit broken code
4. **Clear messages** - Describe what and why
