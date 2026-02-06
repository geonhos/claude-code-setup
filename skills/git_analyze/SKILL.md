---
name: git_analyze
description: Analyzes Git changes with diff summaries and commit history. Provides token-efficient code change analysis and history insights.
model: haiku
---

# Git Analyze Skill

Analyzes Git changes and history to provide insights.

## Use Cases

1. **Change Summary** - Quick overview before code review
2. **History Analysis** - Understand past change patterns
3. **Impact Analysis** - Identify impact of changes
4. **Token Efficiency** - Provide summaries instead of full diffs

---

## Part 1: Diff Analysis

### Current Changes (Unstaged)

```bash
# List changed files
git diff --name-only

# Change statistics
git diff --stat

# Specific file diff
git diff {file}
```

### Staged Changes

```bash
# List staged files
git diff --cached --name-only

# Staged statistics
git diff --cached --stat

# Specific file
git diff --cached {file}
```

### Branch Comparison

```bash
# Compare main with current branch
git diff main...HEAD --stat

# Changed files only
git diff main...HEAD --name-only

# Specific path only
git diff main...HEAD -- src/
```

---

## Diff Summary Format

### Request Analysis

```
Please analyze the following changes:
1. Number of changed files
2. Summary of key changes
3. Potential issues
4. Areas requiring testing
```

### Output Format

```markdown
## Change Summary

### Statistics
- Files: 5
- Added: +150 lines
- Deleted: -30 lines

### Key Changes
1. **app/auth/login.py** - Added login handler
   - JWT token generation logic
   - Password verification

2. **app/middleware/auth.py** - Auth middleware
   - Token verification
   - Permission checks

### Impact Analysis
- Affected endpoints: /api/login, /api/protected/*
- Dependencies added: PyJWT

### Warnings
- Verify token expiration time setting
- Recommend adding error handling

### Recommended Tests
- [ ] Login with valid credentials
- [ ] Login with invalid password
- [ ] Access with expired token
```

---

## Part 2: History Analysis

### Recent Commits

```bash
# Last 10 commits
git log -10 --oneline

# Detailed info
git log -10 --format="%h %s (%an, %ar)"

# Graph view
git log -10 --oneline --graph
```

### File History

```bash
# Specific file history
git log --follow -p {file}

# File change summary
git log --follow --oneline {file}

# Who modified when
git log --follow --format="%h %s (%an)" {file}
```

### Author Statistics

```bash
# Commits by author
git shortlog -sn

# Recent commit authors
git log -20 --format="%an" | sort | uniq -c | sort -rn
```

### Date Range

```bash
# Commits in date range
git log --since="2024-01-01" --until="2024-01-31" --oneline

# Last 7 days
git log --since="7 days ago" --oneline

# Last month
git log --since="1 month ago" --oneline
```

---

## History Summary Format

### Request Analysis

```
Please analyze recent commit history:
1. Main work flow
2. Active areas
3. Patterns and trends
```

### Output Format

```markdown
## History Analysis (Last 2 weeks)

### Statistics
- Total commits: 25
- Period: 2024-01-01 ~ 2024-01-14
- Main authors: user1 (15), user2 (10)

### Main Work Flow
1. **Phase 5** - Authentication system (8 commits)
   - Login/logout implementation
   - JWT token handling

2. **Phase 6** - User profile (5 commits)
   - Profile CRUD
   - Avatar upload

### Active Areas
| Directory | Change Count |
|-----------|--------------|
| app/auth/ | 12 |
| app/users/ | 8 |
| tests/ | 15 |

### Patterns
- Test commits accompany implementation (TDD)
- Clear separation by Phase

### Areas of Concern
- app/database.py: Modified multiple times (needs stabilization?)
```

---

## Part 3: Blame Analysis

### Who Changed What

```bash
# Authors by file
git blame {file}

# Specific line range
git blame -L 10,20 {file}

# Summary
git blame --line-porcelain {file} | grep "^author " | sort | uniq -c
```

### Find Commit by Change

```bash
# Commits adding specific text
git log -S "function_name" --oneline

# Regex search
git log -G "pattern" --oneline
```

---

## Part 4: Impact Analysis

### Files Changed Together

```bash
# Analyze co-change patterns
git log --format='' --name-only | sort | uniq -c | sort -rn | head -20
```

### Change Frequency

```bash
# Frequently changed files
git log --format='' --name-only | sort | uniq -c | sort -rn | head -10
```

### Code Churn

```bash
# Recent change volume analysis
git log --since="30 days" --format='' --numstat | \
  awk '{add+=$1; del+=$2} END {print "Added:", add, "Deleted:", del}'
```

---

## Quick Reference

### Diff Commands

| Action | Command |
|--------|---------|
| Unstaged changes | `git diff` |
| Staged changes | `git diff --cached` |
| Branch diff | `git diff main...HEAD` |
| File diff | `git diff {file}` |
| Stats only | `git diff --stat` |
| Names only | `git diff --name-only` |

### Log Commands

| Action | Command |
|--------|---------|
| Recent commits | `git log -10 --oneline` |
| With graph | `git log --oneline --graph` |
| File history | `git log --follow {file}` |
| Author stats | `git shortlog -sn` |
| Date range | `git log --since="7 days ago"` |
| Search content | `git log -S "text"` |

### Analysis Commands

| Action | Command |
|--------|---------|
| File blame | `git blame {file}` |
| Frequent files | `git log --name-only \| sort \| uniq -c` |
| Contributors | `git shortlog -sn` |

---

## Token-Efficient Analysis

### Instead of Full Diff

❌ `git diff` (hundreds of lines)

✅ Summary approach:
```bash
# 1. Get stats first
git diff --stat

# 2. Then details for specific files
git diff {specific_file}
```

### Instead of Full History

❌ `git log -p` (thousands of lines)

✅ Summary approach:
```bash
# 1. Get summary first
git log -20 --oneline

# 2. Then details for specific commits
git show {commit_hash}
```

---

## Best Practices

1. **Stats first** - Get overview before detailed analysis
2. **Limit scope** - Analyze only necessary areas
3. **Summary first** - Prioritize summaries for token efficiency
4. **Identify patterns** - Watch frequently changed files
5. **Impact analysis** - Consider ripple effects of changes
