---
name: commit
description: "Analyze staged changes, check doc freshness, and create structured commits with conventional format."
model: haiku
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
argument-hint: "[message]"
---

# Commit — Structured Git Commits

Analyze changes, verify docs, create clean commits.

## Workflow

### 1. Status Check

```bash
git status --short
git diff --cached --stat
git diff --cached --name-only
```

### 2. Stage Changes

```bash
# Stage specific files (NEVER use git add -A or git add .)
git add {specific files}
```

### 3. Analyze Changes

Categorize files:

| Section | Patterns |
|---------|----------|
| Source | src/, lib/, app/ |
| Tests | tests/, __tests__/, *_test.* |
| Deps | requirements.txt, package.json, go.mod |
| Config | config/, *.yaml, *.toml |
| Docs | README.md, docs/, CHANGELOG.md |
| Infra | Dockerfile, .github/, CI configs |

### 4. Doc Freshness Check

Scan for documentation affected by code changes:

| Code Change | Check |
|-------------|-------|
| Public API changed | README usage, API docs |
| Deps added/removed | Install section |
| Config format changed | Config section |
| Directory structure changed | Directory tree |
| New feature / bug fix | CHANGELOG.md |
| Function signature changed | Docstrings |

**Rules:**
- Only update docs that **already exist**
- Only update sections **actually affected**
- Include doc updates in the **same commit**

### 5. Commit

Format: Conventional Commits

```bash
git commit -m "$(cat <<'EOF'
{type}({scope}): {summary}

{body - what changed and why}

{Section}:
- {file}: {description}

Refs #{issue_number}
EOF
)"
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `perf`

### 6. Verify

```bash
git log -1 --oneline
git status --short
```

## Rules

- One logical change per commit
- Never commit broken code (tests must pass)
- Never stage .env, credentials, or secrets
- Separate structural commits (rename, move) from behavioral (feat, fix)
