# Verify Complete Skill

---
name: verify_complete
description: Explicit verification before marking any task complete.
model: claude-opus-4-5-20250101
---

## Purpose

Ensure every task is thoroughly verified before being marked as complete. This skill enforces explicit validation and prevents premature task completion.

## The Iron Law
VERIFICATION IS MANDATORY - NO EXCEPTIONS

## DO NOT
- [ ] NEVER skip verification for any task
- [ ] NEVER mark complete without running tests
- [ ] NEVER assume "obvious" correctness
- [ ] NEVER skip verification for "simple" tasks

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "It's obviously correct" | Run verification anyway |
| "Tests are slow" | Run them anyway |
| "Just a config change" | Verify config is applied |
| "I already tested manually" | Run automated verification |

## Core Rule

**NEVER skip verification. This is MANDATORY for every task.**

## Verification Checklist

Before marking ANY task as complete, verify:

### 1. Acceptance Criteria
- [ ] All acceptance criteria from task definition are met
- [ ] Each criterion has been explicitly checked
- [ ] Any deviations are documented and approved

### 2. Code Quality
- [ ] Code compiles/parses without errors
- [ ] No linting errors or warnings
- [ ] Type checks pass (if applicable)
- [ ] Code follows project conventions

### 3. Tests
- [ ] Tests pass locally
- [ ] New code has appropriate test coverage
- [ ] No existing tests broken

### 4. Files
- [ ] All expected files exist
- [ ] Files are saved (not just in memory)
- [ ] File permissions are correct
- [ ] No unintended files modified

### 5. Documentation
- [ ] Changes are documented (if required)
- [ ] Comments are added for complex logic
- [ ] README updated (if needed)

## Verification Commands by Language

### Python
```bash
# Syntax check
python -m py_compile path/to/file.py

# Lint
ruff check path/to/file.py
# or
flake8 path/to/file.py

# Type check
mypy path/to/file.py

# Tests
pytest path/to/tests/test_file.py -v
```

### TypeScript/JavaScript
```bash
# Type check
npx tsc --noEmit

# Lint
npx eslint path/to/file.ts

# Tests
npx jest path/to/tests/file.test.ts
# or
npx vitest run path/to/tests/file.test.ts
```

### Java/Kotlin
```bash
# Compile
./gradlew compileJava
# or
mvn compile

# Tests
./gradlew test --tests "TestClassName"
# or
mvn test -Dtest=TestClassName
```

### Go
```bash
# Build
go build ./...

# Lint
golangci-lint run

# Tests
go test ./path/to/package/...
```

### Rust
```bash
# Build
cargo build

# Lint
cargo clippy

# Tests
cargo test
```

## Verification Flow

```
Task Implementation
        |
        v
+------------------+
| Run Verifications |
+------------------+
        |
        v
+------------------+
| All Pass?        |
+------------------+
     |        |
     No      Yes
     |        |
     v        v
+--------+  +------------------+
| Fix    |  | Mark Complete    |
| Issues |  +------------------+
+--------+
     |
     +----> [Loop back to Run Verifications]
```

## Verification Report Template

```markdown
## Verification Report: [Task ID]

### Task
- **ID**: T-XXX
- **Description**: [brief description]
- **File(s)**: [file paths]

### Acceptance Criteria
| Criterion | Status | Evidence |
|-----------|--------|----------|
| [Criterion 1] | PASS/FAIL | [how verified] |
| [Criterion 2] | PASS/FAIL | [how verified] |

### Automated Checks
| Check | Command | Result |
|-------|---------|--------|
| Syntax | `python -m py_compile ...` | PASS |
| Lint | `ruff check ...` | PASS |
| Type | `mypy ...` | PASS |
| Test | `pytest ...` | PASS (5/5) |

### Manual Verification
- [ ] Files exist and are saved
- [ ] Output matches expected format
- [ ] Functionality works as described

### Verification Result
- **Status**: VERIFIED / NEEDS WORK
- **Notes**: [any observations]
- **Verified By**: [agent/human]
- **Timestamp**: [ISO timestamp]
```

## Integration with Task Completion

### In Orchestrator
```python
def complete_task(task_id):
    # Run verification BEFORE marking complete
    verification = run_verify_complete(task_id)

    if not verification.passed:
        return TaskResult(
            status="needs_work",
            issues=verification.issues,
            action="fix and re-verify"
        )

    # Only now mark as complete
    mark_task_complete(task_id)
    return TaskResult(status="completed")
```

### In Agent Workflow
```
1. Implement task
2. Run verify_complete checks
3. If any fail:
   a. Fix the issues
   b. Re-run verify_complete
   c. Repeat until all pass
4. Only then report task complete
```

## Common Verification Failures

### 1. Test Failures
```
Issue: Tests not passing
Action:
1. Read test output
2. Fix implementation or test
3. Re-run tests
```

### 2. Lint Errors
```
Issue: Style violations
Action:
1. Run auto-fix if available
2. Manually fix remaining issues
3. Re-run lint
```

### 3. Missing Files
```
Issue: Expected file not created
Action:
1. Check file path is correct
2. Ensure write operation succeeded
3. Verify file permissions
```

### 4. Type Errors
```
Issue: Type check failures
Action:
1. Add/fix type annotations
2. Handle edge cases
3. Re-run type checker
```

## Never Skip Scenarios

Even under time pressure, NEVER skip verification for:

1. **Security-related changes** - Authentication, authorization, encryption
2. **Data-modifying code** - Database operations, file writes
3. **API endpoints** - Input validation, error handling
4. **Financial calculations** - Any monetary operations
5. **User-facing features** - UI/UX changes

## Quality Checklist

- [ ] This skill is invoked for EVERY task completion
- [ ] All acceptance criteria explicitly verified
- [ ] Automated checks run and pass
- [ ] Manual verification performed where needed
- [ ] Verification report generated
- [ ] No assumptions made about "obvious" correctness
