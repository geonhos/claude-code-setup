# Development Checklists

## Pre-Work Checklist

Before starting any development task:

- [ ] Virtual environment activated
  ```bash
  source .venv/bin/activate  # Python
  ```
- [ ] Dependencies installed
  ```bash
  pip install -r requirements.txt  # Python
  npm install                      # Node.js
  ```
- [ ] Latest code pulled
  ```bash
  git pull origin main
  ```
- [ ] Feature branch created
  ```bash
  git checkout -b feature/your-feature
  ```

---

## Pre-Commit Checklist

Before committing changes:

- [ ] Tests executed and passing
  ```bash
  # Use /test_runner skill or:
  pytest                  # Python
  npm test               # Node.js
  ./gradlew test         # Java
  ```
- [ ] Linter executed with no errors
  ```bash
  ruff check .           # Python
  npm run lint           # Node.js
  ```
- [ ] Code review requested (`code-reviewer` agent)
- [ ] No sensitive data in changes
  ```bash
  git diff --staged | grep -i "password\|secret\|key\|token"
  ```

---

## Pre-Push Checklist

Before pushing to remote:

- [ ] All tests pass
- [ ] No sensitive information committed
  - No `.env` files
  - No API keys/secrets
  - No credentials
- [ ] For security-related changes: `security-analyst` review passed
- [ ] Commit messages follow format:
  ```
  [Phase N] Summary

  Section:
  - file: description

  Refs #issue
  ```

---

## Pull Request Checklist

Before creating PR:

- [ ] Branch is up to date with main
  ```bash
  git rebase main
  ```
- [ ] All CI checks pass
- [ ] Documentation updated (if applicable)
- [ ] Breaking changes noted
- [ ] Reviewers assigned

---

## Prohibited Actions

### NEVER Do

| Action | Risk |
|--------|------|
| `pip install --user` | Global pollution |
| `npm install -g` | Global pollution |
| `sudo pip install` | System damage |
| Commit `.env` | Security breach |
| Commit `.venv/` | Repo bloat |
| Commit `node_modules/` | Repo bloat |
| Skip verification | Quality issues |
| Skip plan validation | Poor execution |

### Git Safety

| Action | Status |
|--------|--------|
| `git push --force` | DANGEROUS - avoid |
| `git reset --hard` | DANGEROUS - data loss |
| `git checkout .` | DANGEROUS - data loss |
| `git clean -f` | DANGEROUS - data loss |
| Amend pushed commits | DANGEROUS - history rewrite |

---

## Verification Gate Requirements

### Mandatory (Always Required)

| Gate | Agent | Criteria |
|------|-------|----------|
| Code Review | `code-reviewer` | 0 Critical issues |
| Test Pass | `qa-executor` | All tests pass |

### Conditional (When Applicable)

| Gate | Agent | Trigger | Criteria |
|------|-------|---------|----------|
| Security | `security-analyst` | Auth/authz changes | 0 Critical vulnerabilities |
| Performance | `performance-analyst` | Performance-sensitive code | No regressions |

---

## Emergency Procedures

### Build Failure
1. Check CI logs
2. Reproduce locally
3. Fix and re-push
4. If stuck: escalate to `debug-specialist`

### Test Failure
1. Identify failing test
2. Check recent changes
3. Fix test or code
4. Re-run full suite

### Security Incident
1. Do NOT push more changes
2. Alert security team
3. Review with `security-analyst`
4. Follow incident response procedure

---

## Quick Reference

### Environment Setup
```bash
# Python
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Node.js
npm install
```

### Common Commands
```bash
# Testing
pytest                    # Python
npm test                  # Node.js
./gradlew test           # Java

# Linting
ruff check .             # Python
npm run lint             # Node.js

# Git
git status
git add <files>
git commit -m "message"
git push origin <branch>
```
