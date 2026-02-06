---
name: debug_workflow
description: Systematic debugging using hypothesis-driven approach.
model: claude-opus-4-5-20250101
---

# Debug Workflow Skill

## Purpose

Provide a systematic, scientific approach to debugging issues. This skill prevents random changes and ensures thorough investigation before applying fixes.

## The Iron Law
NO FIX WITHOUT COMPLETED 5-STEP PROCESS

## DO NOT
- [ ] NEVER skip the reproduction step
- [ ] NEVER proceed with single hypothesis (require 2+)
- [ ] NEVER fix without testing hypotheses first
- [ ] NEVER skip final verification step

## Core Principles

1. **Reproduce First**: Never guess at fixes without reproducing the issue
2. **Hypothesize Before Acting**: Form theories before making changes
3. **Test Hypotheses Systematically**: Validate each theory with evidence
4. **Minimal Fixes**: Apply the smallest change that fixes the issue
5. **Verify Thoroughly**: Ensure the fix doesn't break other things

## Workflow (5 Steps)

### Step 1: Reproduce
**Goal**: Confirm the issue exists and understand its behavior

Actions:
- Document exact steps to reproduce
- Note any variations in behavior
- Capture error messages, stack traces, logs
- Identify environment details

Output:
```markdown
## Reproduction
- **Steps**:
  1. [step 1]
  2. [step 2]
  3. [step 3]
- **Expected**: [what should happen]
- **Actual**: [what actually happens]
- **Error**: [exact error message]
- **Environment**: [OS, version, dependencies]
- **Reproducible**: Always / Sometimes / Intermittent
```

### Step 2: Hypothesize (Minimum 2)
**Goal**: Form multiple theories about the cause

For each hypothesis:
- State the theory
- Assign confidence level (%)
- Explain supporting evidence
- Describe how to test

Output:
```markdown
## Hypotheses

### Hypothesis 1: [Name] (Confidence: X%)
- **Theory**: [explanation]
- **Evidence For**: [supporting observations]
- **Evidence Against**: [contradicting observations]
- **Test**: [how to validate]

### Hypothesis 2: [Name] (Confidence: Y%)
- **Theory**: [explanation]
- **Evidence For**: [supporting observations]
- **Evidence Against**: [contradicting observations]
- **Test**: [how to validate]
```

**Why minimum 2?**
- Prevents tunnel vision
- Encourages thorough investigation
- Often the first guess is wrong

### Step 3: Test Hypotheses
**Goal**: Validate or invalidate each hypothesis

For each hypothesis:
1. Design a test that would confirm/deny
2. Execute the test
3. Record results
4. Update confidence levels

Output:
```markdown
## Hypothesis Testing

### Test for Hypothesis 1
- **Test Performed**: [description]
- **Result**: [outcome]
- **Conclusion**: Confirmed / Rejected / Inconclusive

### Test for Hypothesis 2
- **Test Performed**: [description]
- **Result**: [outcome]
- **Conclusion**: Confirmed / Rejected / Inconclusive
```

### Step 4: Fix
**Goal**: Apply minimal fix for the confirmed cause

Rules:
- Fix only what's broken
- Avoid "while I'm here" changes
- Keep the diff minimal
- Add comments explaining the fix

Output:
```markdown
## Fix Applied

### Root Cause
[Confirmed cause based on hypothesis testing]

### Fix Description
[What was changed and why]

### Files Modified
- `path/to/file.py`: [description of change]

### Diff Summary
- Lines added: X
- Lines removed: Y
- Lines changed: Z
```

### Step 5: Verify
**Goal**: Ensure the fix works and doesn't break anything

Verification checklist:
- [ ] Original issue no longer reproduces
- [ ] Related functionality still works
- [ ] All existing tests pass
- [ ] Edge cases tested
- [ ] No new warnings or errors

Output:
```markdown
## Verification

### Issue Resolution
- **Original Steps**: [reproduce steps]
- **Result After Fix**: [expected behavior now occurs]

### Regression Check
- **Unit Tests**: PASS
- **Integration Tests**: PASS
- **Related Features Tested**: [list]

### Edge Cases
- [Edge case 1]: PASS
- [Edge case 2]: PASS
```

## Debug Log Template

```markdown
# Debug Log: [Issue Title]

**Date**: YYYY-MM-DD
**Reporter**: [name/source]
**Severity**: Critical / High / Medium / Low

---

## 1. Issue Description
[Brief description of the problem]

## 2. Reproduction
- **Steps**:
  1. ...
- **Expected**: ...
- **Actual**: ...
- **Reproducible**: Always / Sometimes

## 3. Hypotheses

### H1: [Name] (Confidence: X%)
- Theory: ...
- Test: ...

### H2: [Name] (Confidence: Y%)
- Theory: ...
- Test: ...

## 4. Testing Results

| Hypothesis | Test | Result | Conclusion |
|------------|------|--------|------------|
| H1 | ... | ... | Confirmed/Rejected |
| H2 | ... | ... | Confirmed/Rejected |

## 5. Root Cause
[Confirmed cause]

## 6. Fix
- **Description**: ...
- **Files**: ...
- **Commit**: ...

## 7. Verification
- [ ] Issue resolved
- [ ] Tests pass
- [ ] No regressions

---
**Status**: Resolved / In Progress / Needs More Info
**Time Spent**: X hours
```

## Common Debugging Patterns

### Pattern 1: Null/Undefined Error
```
Hypothesis 1: Variable not initialized
Hypothesis 2: Async timing issue
Hypothesis 3: Wrong scope/closure
Test: Add logging before access point
```

### Pattern 2: Intermittent Failure
```
Hypothesis 1: Race condition
Hypothesis 2: Resource exhaustion
Hypothesis 3: External dependency flakiness
Test: Run under different loads/conditions
```

### Pattern 3: Works Locally, Fails in CI
```
Hypothesis 1: Environment difference
Hypothesis 2: Missing dependency
Hypothesis 3: Path/permission issue
Test: Compare environment variables and paths
```

## Integration

- **Triggered by**: Keywords "debug", "bug", "error", "not working", "crash"
- **Works with**: `qa-healer` for automated recovery
- **Escalates to**: Human when no hypothesis confirmed after N attempts

## Anti-Patterns to Avoid

1. **Random Changes**: Making changes without hypothesis
2. **Single Hypothesis**: Only considering one cause
3. **Skip Verification**: Assuming fix works without testing
4. **Large Fixes**: Changing more than necessary
5. **No Documentation**: Not recording the investigation

## Quality Checklist

- [ ] Issue reproduced and documented
- [ ] At least 2 hypotheses formed
- [ ] Each hypothesis tested systematically
- [ ] Root cause identified with evidence
- [ ] Minimal fix applied
- [ ] Fix verified with tests
- [ ] No regressions introduced
- [ ] Debug log completed