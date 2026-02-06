---
name: task_breakdown
description: Decompose features into atomic 2-5 minute tasks.
model: claude-opus-4-5-20250101
---

# Task Breakdown Skill

## Purpose

Break down features into small, independently verifiable tasks that can be completed in 2-5 minutes each. This ensures:
- Progress is visible and measurable
- Issues are caught early
- Parallel execution is possible
- Rollback scope is minimized

## Granularity Rules

### Time Constraint
- **Minimum**: 2 minutes (avoid trivial tasks)
- **Maximum**: 5 minutes (ensure quick feedback)
- **Ideal**: 3-4 minutes per task

### Scope Constraints
1. **Single File Rule**: Each task modifies at most one file
   - Exception: Test file can accompany implementation file
2. **Single Responsibility**: One clear outcome per task
3. **Independent Verification**: Can be verified without other tasks
4. **Clear Boundaries**: Start and end states are well-defined

### Task Types

| Type | Description | Typical Duration |
|------|-------------|------------------|
| CREATE | Create new file from scratch | 3-5 min |
| MODIFY | Change existing file | 2-4 min |
| DELETE | Remove file (with cleanup) | 2 min |
| REFACTOR | Restructure without behavior change | 3-5 min |
| TEST | Write test for existing code | 3-5 min |
| CONFIG | Update configuration | 2-3 min |
| DOC | Documentation update | 2-4 min |

## Task Template

```yaml
id: T-{feature}-{sequence}
type: CREATE | MODIFY | DELETE | REFACTOR | TEST | CONFIG | DOC
duration: 2-5 min
priority: HIGH | MEDIUM | LOW

file:
  path: /absolute/path/to/file.ext
  action: create | modify | delete

description: |
  Brief description of what this task accomplishes.
  Include specific requirements or constraints.

input:
  - Dependencies or prerequisites
  - Required context from previous tasks

output:
  - Expected result
  - Artifacts created/modified

verification:
  command: "pytest tests/test_file.py -k test_name"
  expected: "1 passed"
  manual_check: "Verify X appears in Y"

acceptance_criteria:
  - [ ] Criterion 1
  - [ ] Criterion 2
```

## Breakdown Process

### Step 1: Identify Feature Scope
- What is the complete feature?
- What are the acceptance criteria?
- What are the dependencies?

### Step 2: List Components
- Files to create
- Files to modify
- Tests to write
- Documentation to update

### Step 3: Sequence Tasks
- Order by dependencies
- Group by parallelizability
- Mark critical path

### Step 4: Validate Granularity
For each task, check:
- [ ] Can be done in 2-5 minutes?
- [ ] Touches single file (except test pairs)?
- [ ] Has clear verification method?
- [ ] Is independently understandable?

### Step 5: Add Verification
Each task must have:
- Automated check (if possible)
- Manual verification step
- Clear success criteria

## Examples

### Example 1: Add Login Endpoint

**Feature**: User login with JWT

**Breakdown**:
```yaml
# T-LOGIN-001
id: T-LOGIN-001
type: CREATE
duration: 4 min
file:
  path: /src/models/user.py
  action: create
description: Create User model with email and hashed password fields
verification:
  command: "python -c 'from src.models.user import User; print(User)'"
  expected: "class 'User'"

# T-LOGIN-002
id: T-LOGIN-002
type: CREATE
duration: 5 min
file:
  path: /src/api/auth.py
  action: create
description: Create login endpoint that validates credentials and returns JWT
verification:
  command: "python -c 'from src.api.auth import login; print(login)'"
  expected: "function"

# T-LOGIN-003
id: T-LOGIN-003
type: CREATE
duration: 4 min
file:
  path: /tests/test_auth.py
  action: create
description: Write tests for login endpoint (success, invalid password, user not found)
verification:
  command: "pytest tests/test_auth.py -v"
  expected: "3 passed"
```

### Example 2: Refactor Large Function

**Feature**: Split 200-line function into smaller functions

**Breakdown**:
```yaml
# T-REFACTOR-001
id: T-REFACTOR-001
type: REFACTOR
duration: 3 min
file:
  path: /src/services/processor.py
  action: modify
description: Extract validation logic into _validate_input() function
verification:
  command: "pytest tests/test_processor.py"
  expected: "all passed"

# T-REFACTOR-002
id: T-REFACTOR-002
type: REFACTOR
duration: 3 min
file:
  path: /src/services/processor.py
  action: modify
description: Extract transformation logic into _transform_data() function
verification:
  command: "pytest tests/test_processor.py"
  expected: "all passed"

# T-REFACTOR-003
id: T-REFACTOR-003
type: REFACTOR
duration: 2 min
file:
  path: /src/services/processor.py
  action: modify
description: Update main function to use extracted helpers
verification:
  command: "pytest tests/test_processor.py"
  expected: "all passed"
```

## Anti-Patterns

### Too Large
```yaml
# BAD: Takes 30+ minutes, touches 5 files
id: T-BAD-001
description: Implement entire authentication system
files: [user.py, auth.py, middleware.py, tests.py, config.py]
```

### Too Small
```yaml
# BAD: Takes 30 seconds, trivial
id: T-BAD-002
description: Add import statement
```

### Unclear Verification
```yaml
# BAD: No way to verify completion
id: T-BAD-003
description: Improve code quality
verification: none
```

## Integration

- **Used by**: `plan-architect` when creating execution plans
- **Validates with**: `verify_complete` before marking tasks done
- **Reports to**: `orchestrator` for progress tracking

## Quality Checklist

- [ ] All tasks are 2-5 minutes
- [ ] Single file per task (test pairs allowed)
- [ ] Each task has verification command
- [ ] Dependencies are explicit
- [ ] Parallel groups identified
- [ ] Critical path marked