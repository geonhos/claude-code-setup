---
name: test
description: "Run tests, analyze failures, and report coverage. Auto-detects framework (Jest, pytest, Vitest, Go, Rust, Gradle)."
model: haiku
allowed-tools: Bash, Read, Grep, Glob
argument-hint: "[test path or pattern]"
---

# Test — Execute + Analyze + Coverage

Run tests, parse results, analyze failures, and report coverage in one command.

## Workflow

### 1. Detect Framework

```bash
# Auto-detect by project files
[ -f "package.json" ] && grep -q '"jest"' package.json && echo "jest"
[ -f "package.json" ] && grep -q '"vitest"' package.json && echo "vitest"
[ -f "pytest.ini" ] || [ -f "pyproject.toml" ] && echo "pytest"
[ -f "go.mod" ] && echo "go"
[ -f "Cargo.toml" ] && echo "rust"
[ -f "build.gradle" ] || [ -f "build.gradle.kts" ] && echo "gradle"
[ -f "pom.xml" ] && echo "maven"
```

### 2. Run Tests

| Framework | Command |
|-----------|---------|
| Jest | `npx jest --coverage --verbose {path}` |
| Vitest | `npx vitest run --coverage {path}` |
| pytest | `python -m pytest -v --tb=short --cov {path}` |
| Go | `go test -v -cover ./...` |
| Rust | `cargo test -- --nocapture` |
| Gradle | `./gradlew test` |
| Maven | `./mvnw test` |

If a specific path/pattern is provided, run only those tests.

### 3. Analyze Results

Parse output into structured result:

```
TEST RESULTS
════════════
Passed  : {N}
Failed  : {N}
Skipped : {N}
Total   : {N}
Duration: {N}s
```

### 4. Failure Analysis

For each failure, categorize:

| Category | Description | Action |
|----------|-------------|--------|
| True Failure | Code bug | Fix the code |
| Test Bug | Test is wrong | Fix the test |
| Flaky | Intermittent | Re-run to confirm |
| Environment | Setup issue | Fix environment |

Report per failure:
```
FAILURE: {test_name}
  Category : {category}
  Error    : {error message}
  File     : {file}:{line}
  Cause    : {root cause analysis}
  Fix      : {suggested fix}
```

### 5. Coverage Report

For changed files only (if `--coverage` supported):

```
COVERAGE (changed files)
════════════════════════
{file}          : {X}% ({uncovered lines})
{file}          : {X}% ({uncovered lines})
────────────────────────
Average         : {X}%
```

Identify gaps:
- Untested public functions
- Missing edge cases
- Uncovered error paths

## Output Format

```
══════════════════════════════════
  TEST REPORT
══════════════════════════════════
  Framework : {name}
  Status    : {PASS | FAIL}
  Tests     : {passed}/{total}
  Coverage  : {X}%
  Duration  : {N}s
══════════════════════════════════
{failure details if any}
{coverage gaps if any}
```

## Rules

- NEVER claim tests pass without actually running them
- NEVER skip failed test analysis
- Always run the FULL suite unless a specific path is given
- Report coverage for changed files, not just new code
