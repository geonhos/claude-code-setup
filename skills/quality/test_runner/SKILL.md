---
name: test_runner
description: Executes test suites across different frameworks and generates structured results.
model: haiku
---

# Test Runner Skill

Executes tests across various frameworks and analyzes results.

## Supported Frameworks

| Language | Framework | Command |
|----------|-----------|---------|
| Python | pytest | `pytest` |
| JavaScript | Jest | `npm test` |
| JavaScript | Vitest | `npm test` |
| Java | JUnit | `./gradlew test` |
| Go | testing | `go test` |

## Workflow

### 1. Verify Environment

```bash
# Python
source .venv/bin/activate
which python

# JavaScript
node --version
npm --version

# Java
java --version
./gradlew --version
```

### 2. Run Tests

#### Python (pytest)
```bash
# All tests
pytest -v

# With coverage
pytest --cov=src --cov-report=html --cov-report=term-missing

# Specific tests
pytest tests/test_specific.py -v

# Filter by keyword
pytest -k "test_login" -v

# Marked tests
pytest -m "slow" -v

# Parallel execution
pytest -n auto
```

#### JavaScript (Jest/Vitest)
```bash
# All tests
npm test

# With coverage
npm test -- --coverage

# Watch mode
npm test -- --watch

# Specific file
npm test -- path/to/test.spec.ts

# Pattern matching
npm test -- --testNamePattern="login"
```

#### Java (Gradle + JUnit)
```bash
# All tests
./gradlew test

# Specific test class
./gradlew test --tests "UserServiceTest"

# Specific method
./gradlew test --tests "UserServiceTest.testLogin"

# Generate report
./gradlew test jacocoTestReport
```

### 3. Analyze Results

#### Result Parsing Template
```
Test Results Summary
═══════════════════════════════════════
Total:     {total}
Passed:    {passed} ({pass_rate}%)
Failed:    {failed}
Skipped:   {skipped}
Duration:  {duration}s
═══════════════════════════════════════
```

#### Failure Analysis Template
```
Failed Test: {test_name}
─────────────────────────────────────
File:     {file_path}:{line}
Error:    {error_type}
Message:  {error_message}

Stack Trace:
{stack_trace}

Possible Cause:
- {analysis}
─────────────────────────────────────
```

### 4. CI/CD Integration

#### GitHub Actions
```yaml
- name: Run Tests
  run: |
    npm test -- --coverage --ci

- name: Upload Coverage
  uses: codecov/codecov-action@v3
```

#### pytest CI Configuration
```bash
pytest \
  --junitxml=test-results.xml \
  --cov=src \
  --cov-report=xml \
  --cov-report=term
```

### 5. Test Results JSON

```json
{
  "summary": {
    "total": 50,
    "passed": 47,
    "failed": 2,
    "skipped": 1,
    "duration_seconds": 12.5,
    "pass_rate": 94
  },
  "failures": [
    {
      "name": "test_user_login_invalid_password",
      "file": "tests/test_auth.py:45",
      "error": "AssertionError",
      "message": "Expected 401, got 500",
      "category": "true_failure"
    }
  ],
  "coverage": {
    "statements": 85,
    "branches": 78,
    "functions": 90,
    "lines": 86
  }
}
```

### 6. Quick Reference

| Action | Python | JavaScript | Java |
|--------|--------|------------|------|
| Run all | `pytest` | `npm test` | `./gradlew test` |
| Verbose | `pytest -v` | `npm test -- --verbose` | `./gradlew test --info` |
| Coverage | `--cov=src` | `--coverage` | `jacocoTestReport` |
| Single | `-k "name"` | `--testNamePattern` | `--tests "Name"` |
| Watch | `ptw` | `--watch` | `--continuous` |
| Parallel | `-n auto` | `--maxWorkers=4` | `--parallel` |

## Output Format

```markdown
# Test Execution Report

## Summary
- **Date**: {timestamp}
- **Environment**: {env}
- **Duration**: {duration}

## Results
| Metric | Value |
|--------|-------|
| Total | {total} |
| Passed | {passed} |
| Failed | {failed} |
| Pass Rate | {rate}% |
| Coverage | {coverage}% |

## Failed Tests
### 1. {test_name}
- **Error**: {error}
- **File**: {file}
- **Analysis**: {analysis}

## Next Steps
- [ ] Fix failing tests
- [ ] Re-run regression
```

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Test Execution Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Results: {passed}/{total} passed ({rate}%)
Duration: {duration}s
Coverage: {coverage}%

{failed > 0 ? "X " + failed + " tests failed" : "All tests passed"}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
