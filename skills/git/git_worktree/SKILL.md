# Git Worktree Skill

---
name: git_worktree
description: Enable parallel development on multiple branches simultaneously.
model: claude-opus-4-5-20250101
---

## Purpose

Use git worktree to work on multiple branches simultaneously without stashing or switching. This enables:
- Parallel feature development
- Quick hotfixes without context switching
- Code review in isolation
- Testing different branches side by side

## Commands

### Create Worktree
```bash
# Create worktree for existing branch
git worktree add ../project-feature feature/branch-name

# Create worktree with new branch
git worktree add -b feature/new-feature ../project-new-feature main

# Create worktree from specific commit
git worktree add ../project-hotfix hotfix/critical --detach
```

### List Worktrees
```bash
# List all worktrees
git worktree list

# Output example:
# /Users/dev/myapp              abc1234 [main]
# /Users/dev/myapp-auth         def5678 [feature/auth]
# /Users/dev/myapp-api          ghi9012 [feature/api]
```

### Remove Worktree
```bash
# Remove worktree (after merging/completing work)
git worktree remove ../project-feature

# Force remove (if branch was deleted)
git worktree remove --force ../project-feature

# Prune stale worktrees
git worktree prune
```

### Lock/Unlock Worktree
```bash
# Lock worktree (prevent accidental removal)
git worktree lock ../project-feature --reason "In active development"

# Unlock worktree
git worktree unlock ../project-feature
```

## Naming Convention

### Directory Pattern
```
../{project-name}-{feature-short}
```

### Examples
| Project | Feature | Worktree Path |
|---------|---------|---------------|
| myapp | authentication | ../myapp-auth |
| myapp | api-endpoints | ../myapp-api |
| myapp | urgent-fix | ../myapp-hotfix |
| frontend | new-dashboard | ../frontend-dashboard |

### Branch to Worktree Mapping
```
feature/user-authentication  -> ../project-auth
feature/payment-integration  -> ../project-payment
hotfix/security-patch        -> ../project-hotfix
bugfix/login-issue           -> ../project-login-fix
```

## Workflow

### Standard Development Flow
```
1. Main repo: /Users/dev/myapp (main branch)

2. Start feature A:
   git worktree add ../myapp-featureA feature/feature-a
   cd ../myapp-featureA
   # Work on feature A...

3. Urgent hotfix needed:
   cd /Users/dev/myapp
   git worktree add ../myapp-hotfix -b hotfix/urgent main
   cd ../myapp-hotfix
   # Fix and deploy...

4. Back to feature A:
   cd ../myapp-featureA
   # Continue work...

5. Cleanup after merge:
   git worktree remove ../myapp-featureA
   git worktree remove ../myapp-hotfix
```

### Parallel PR Review
```
1. Check out PR for review:
   git worktree add ../myapp-pr123 origin/pr/123
   cd ../myapp-pr123
   # Review, test, comment...

2. Compare with another PR:
   git worktree add ../myapp-pr124 origin/pr/124
   # Both available for comparison

3. Cleanup:
   git worktree remove ../myapp-pr123
   git worktree remove ../myapp-pr124
```

## Best Practices

### Do
- One worktree per feature/task
- Use descriptive short names for worktree directories
- Clean up worktrees after merge
- Lock important worktrees to prevent accidental removal
- Run `git worktree prune` periodically

### Don't
- Create too many worktrees (keep under 5 active)
- Leave stale worktrees around
- Use same worktree directory for different branches
- Forget to push changes before removing worktree

## Sharing Dependencies

### Node.js Projects
```bash
# Option 1: Separate node_modules (recommended for isolation)
cd ../myapp-feature
npm install

# Option 2: Symlink node_modules (save space, may cause issues)
ln -s /Users/dev/myapp/node_modules ./node_modules
```

### Python Projects
```bash
# Option 1: Shared virtual environment (simple projects)
source /Users/dev/myapp/.venv/bin/activate

# Option 2: Separate venv (recommended for dependency conflicts)
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Java/Maven Projects
```bash
# Local Maven repo is shared automatically (~/.m2)
# Just run build in each worktree
./mvnw clean install
```

## Use Cases

### 1. Parallel Feature Development
**Scenario**: Working on two features that touch different areas
```bash
# Main: general maintenance
# Worktree 1: Frontend redesign
# Worktree 2: API optimization

git worktree add ../myapp-frontend feature/frontend-redesign
git worktree add ../myapp-api feature/api-optimization
```

### 2. Quick Hotfix Without Stashing
**Scenario**: Critical bug while in the middle of feature work
```bash
# Don't stash, don't lose context
git worktree add ../myapp-hotfix -b hotfix/critical main
cd ../myapp-hotfix
# Fix, commit, push, deploy
# Return to original work without any stash drama
```

### 3. Code Review in Isolation
**Scenario**: Review PR without switching branches
```bash
git fetch origin pull/123/head:pr/123
git worktree add ../myapp-review pr/123
cd ../myapp-review
# Run tests, review code
# Give feedback without affecting your work
```

### 4. A/B Testing Different Approaches
**Scenario**: Try two different implementations
```bash
git worktree add -b experiment/approach-a ../myapp-approach-a main
git worktree add -b experiment/approach-b ../myapp-approach-b main
# Implement both, benchmark, choose winner
```

### 5. Bisect Without Branch Switching
**Scenario**: Debug regression with git bisect
```bash
git worktree add ../myapp-bisect HEAD --detach
cd ../myapp-bisect
git bisect start
git bisect bad
git bisect good v1.0.0
# Continue bisect in isolation
```

## Integration with git-ops Agent

The `git-ops` agent should use this skill when:
- User requests parallel branch work
- Multiple features need simultaneous development
- Quick context switch is needed without stashing
- PR review requires running code

## Safety Protocols

1. **Before Creating Worktree**
   - Verify sufficient disk space
   - Check for naming conflicts
   - Ensure branch exists (or specify -b for new)

2. **Before Removing Worktree**
   - Check for uncommitted changes
   - Verify branch is merged or backed up
   - Confirm with user for locked worktrees

3. **Periodic Maintenance**
   - Run `git worktree list` to review active worktrees
   - Run `git worktree prune` to clean up stale entries
   - Remove completed worktrees promptly

## Quality Checklist

- [ ] Worktree created with clear naming
- [ ] Dependencies handled appropriately
- [ ] Work is committed before leaving worktree
- [ ] Worktree removed after merge
- [ ] No stale worktrees left behind
- [ ] Lock used for critical work in progress
