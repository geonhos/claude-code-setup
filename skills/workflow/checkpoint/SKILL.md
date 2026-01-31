# Checkpoint Skill

---
name: checkpoint
description: Batch execution with periodic verification pauses.
model: claude-opus-4-5-20250101
---

## Purpose

Pause execution for verification after completing N tasks (default: 5). This ensures that work is validated incrementally and allows for early course correction.

## Configuration

| Parameter | Default | Description |
|-----------|---------|-------------|
| batch_size | 5 | Number of tasks before checkpoint |
| auto_continue | false | Continue without user input if all tests pass |
| rollback_on_failure | true | Offer rollback if verification fails |

## Workflow

### Step 1: Track Task Completion
- Maintain count of completed tasks since last checkpoint
- Record files modified/created for each task
- Track test status if applicable

### Step 2: Trigger Checkpoint (After N Tasks)
When task count reaches batch_size:
1. Pause execution
2. Generate checkpoint summary
3. Run verification checks
4. Wait for user decision

### Step 3: Present Summary
Display comprehensive summary of changes since last checkpoint.

### Step 4: Request Verification
- If auto_continue is false: Wait for user input
- If auto_continue is true and tests pass: Continue automatically
- If any tests fail: Always pause for user decision

### Step 5: Handle Response
- **Continue**: Reset counter, proceed with next batch
- **Rollback**: Revert changes since last checkpoint
- **Pause**: Stop execution, save state for later

## Checkpoint Summary Template

```
=== Checkpoint N ===
Tasks Completed: X (this batch) / Y (total)
Time Elapsed: Z minutes

## Changes Since Last Checkpoint

### Files Created
- path/to/new/file1.py
- path/to/new/file2.ts

### Files Modified
- path/to/modified/file1.py (added: 25 lines, removed: 10 lines)
- path/to/modified/file2.ts (added: 15 lines, removed: 5 lines)

### Files Deleted
- (none)

## Test Status
- Unit Tests: PASS (45/45)
- Lint: PASS
- Type Check: PASS

## Summary of Work
1. T-001: Created user authentication module
2. T-002: Added login API endpoint
3. T-003: Implemented JWT token generation
4. T-004: Created user model
5. T-005: Added password hashing utility

## Next Tasks
- T-006: Add logout endpoint
- T-007: Implement token refresh
- T-008: Add rate limiting

---
Continue execution? (yes/no/rollback)
```

## Rollback Procedure

If user requests rollback:

1. **Identify Rollback Scope**
   - List all changes since last checkpoint
   - Confirm rollback scope with user

2. **Execute Rollback**
   ```bash
   # Revert file changes
   git checkout HEAD~N -- [modified files]

   # Remove created files
   rm [created files]

   # Restore deleted files (if any)
   git checkout HEAD~N -- [deleted files]
   ```

3. **Verify Rollback**
   - Confirm files are restored to previous state
   - Run tests to verify system stability

4. **Update State**
   - Reset checkpoint counter
   - Mark rolled-back tasks as pending

## Integration with Orchestrator

The orchestrator calls checkpoint at these points:
1. After every N tasks (configurable)
2. After critical tasks (marked in plan)
3. Before phase transitions
4. After any task failure

## Output Format

```json
{
  "checkpoint_id": "CP-003",
  "batch_number": 3,
  "tasks_completed": ["T-011", "T-012", "T-013", "T-014", "T-015"],
  "files_created": ["path/to/file1", "path/to/file2"],
  "files_modified": ["path/to/file3", "path/to/file4"],
  "files_deleted": [],
  "test_status": {
    "unit": "pass",
    "lint": "pass",
    "type_check": "pass"
  },
  "summary": "Completed API endpoints for user management",
  "next_tasks": ["T-016", "T-017", "T-018"],
  "action_required": "user_confirmation"
}
```

## Examples

### Example 1: Successful Checkpoint
```
=== Checkpoint 2 ===
Tasks Completed: 5 (this batch) / 10 (total)

Files Modified: 3
Tests: ALL PASS

Continue execution? (yes/no/rollback)
> yes

[Continuing with next batch...]
```

### Example 2: Checkpoint with Test Failure
```
=== Checkpoint 2 ===
Tasks Completed: 5 (this batch) / 10 (total)

Files Modified: 3
Tests: FAILED (2 failures)
  - test_user_login: AssertionError
  - test_token_validation: TypeError

Recommended: Fix failures before continuing.

Options:
1. Fix and continue
2. Rollback this batch
3. Pause execution

Choice?
```

## Quality Checklist

- [ ] Batch size is configurable
- [ ] Summary includes all file changes
- [ ] Test status is integrated
- [ ] Rollback option is available
- [ ] Next tasks are clearly listed
- [ ] Execution state is preserved for pause/resume
