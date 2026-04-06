---
name: debug
description: "Systematic hypothesis-driven debugging. Reproduce, hypothesize, verify, fix."
model: opus
context: fork
allowed-tools: Read, Grep, Glob, Bash
argument-hint: "[error description or stack trace]"
---

# Debug — Hypothesis-Driven Debugging

Systematic approach: don't guess randomly, form hypotheses and test them.

## Workflow

### 1. Reproduce

Confirm the bug exists and is reproducible:
```bash
# Run the failing command/test
{reproduction_command}
```

Capture:
- Error message / stack trace
- Expected vs actual behavior
- Environment (OS, version, config)

### 2. Hypothesize

Form ranked hypotheses (most likely first):

```
Hypothesis 1: {description} — Likelihood: HIGH
  Evidence for: {what supports this}
  Test: {how to verify}

Hypothesis 2: {description} — Likelihood: MEDIUM
  Evidence for: {what supports this}
  Test: {how to verify}

Hypothesis 3: {description} — Likelihood: LOW
  Evidence for: {what supports this}
  Test: {how to verify}
```

### 3. Verify

Test each hypothesis in order:
1. Read relevant code
2. Add targeted logging/assertions if needed
3. Run the test
4. Confirm or reject hypothesis

```
Hypothesis 1: {CONFIRMED | REJECTED}
  Result: {what you found}
```

### 4. Fix

Once root cause is confirmed:
1. Write a test that reproduces the bug (RED)
2. Apply the minimal fix (GREEN)
3. Run full test suite to prevent regressions

### 5. Report

```
BUG REPORT
══════════
  Error     : {description}
  Root Cause: {explanation}
  Fix       : {what was changed}
  Files     : {list}
  Tests     : {new test added}
  Regression: {full suite status}
```

## Rules

- NEVER apply a fix without understanding the root cause
- NEVER skip writing a regression test
- Test hypotheses in order of likelihood (don't start with the unlikely)
- If stuck after 3 hypotheses, widen the search scope
