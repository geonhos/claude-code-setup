---
name: tdd
description: "Kent Beck TDD cycle: Red (failing test) -> Green (minimal code) -> Refactor (clean up). Enforces test-first development."
model: haiku
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
argument-hint: "[feature to implement]"
---

# TDD — Red-Green-Refactor

Strict Kent Beck TDD cycle. Write the test first, then make it pass, then clean up.

## Cycle

```
RED ──────► GREEN ──────► REFACTOR ──────► RED (next)
write test   make pass    clean up         next feature
(must fail)  (minimal)    (no new behavior)
```

## Phase 1: RED (Write Failing Test)

1. Write a test that describes the desired behavior
2. Run it — it MUST fail
3. If it passes, the test is wrong or the feature already exists

```bash
# Run the specific test
{test_command} {test_file}::{test_name}
```

```
RED: {test_name}
  Expected: FAIL
  Actual  : FAIL ✅ (proceed to GREEN)
```

## Phase 2: GREEN (Minimal Implementation)

1. Write the MINIMUM code to make the test pass
2. No optimization, no cleanup, no extras
3. Run the test — it MUST pass now

```
GREEN: {test_name}
  Expected: PASS
  Actual  : PASS ✅ (proceed to REFACTOR)
```

## Phase 3: REFACTOR (Clean Up)

1. Improve code structure without changing behavior
2. Run ALL tests — everything must still pass
3. Common refactors: extract method, rename, remove duplication

```
REFACTOR: {description}
  Tests: {N}/{N} still passing ✅
```

## Framework Commands

| Stack | Test Command | Watch |
|-------|-------------|-------|
| Python/pytest | `python -m pytest -xvs {path}` | `ptw {path}` |
| JS/Jest | `npx jest {path} --verbose` | `npx jest --watch` |
| JS/Vitest | `npx vitest run {path}` | `npx vitest` |
| Go | `go test -v -run {name} ./...` | - |
| Rust | `cargo test {name} -- --nocapture` | `cargo watch -x test` |
| Java/Gradle | `./gradlew test --tests {class}` | - |

## Rules

- NEVER write implementation before the test
- NEVER write more code than needed to pass the test
- NEVER add new behavior during REFACTOR phase
- ALWAYS run tests after each phase transition
- One test at a time — don't batch
