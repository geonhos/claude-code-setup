---
name: coverage_report
description: Generates and analyzes code coverage reports with gap identification and improvement recommendations.
model: haiku
---

# Coverage Report Skill

Generates and analyzes code coverage reports.

## Supported Tools

| Language | Tool | Output |
|----------|------|--------|
| Python | pytest-cov | HTML, XML, Term |
| JavaScript | Jest/Vitest | HTML, LCOV, Text |
| Java | JaCoCo | HTML, XML |
| Go | go test | HTML, Func |

## Workflow

### 1. Collect Coverage

#### Python
```bash
# Collect coverage
pytest --cov=src --cov-report=html --cov-report=xml --cov-report=term-missing

# Output locations
# - htmlcov/index.html (HTML)
# - coverage.xml (XML)
# - Terminal output (Term)
```

#### JavaScript
```bash
# Jest
npm test -- --coverage --coverageReporters="html" --coverageReporters="lcov" --coverageReporters="text"

# Vitest
npm test -- --coverage

# Output locations
# - coverage/lcov-report/index.html
# - coverage/lcov.info
```

#### Java
```bash
# Gradle + JaCoCo
./gradlew test jacocoTestReport

# Output locations
# - build/reports/jacoco/test/html/index.html
# - build/reports/jacoco/test/jacocoTestReport.xml
```

### 2. Coverage Metrics

| Metric | Description | Target |
|--------|-------------|--------|
| **Statements** | Executed code lines | >= 80% |
| **Branches** | if/else branches | >= 75% |
| **Functions** | Called functions | >= 85% |
| **Lines** | Covered lines | >= 80% |

### 3. Report Template

```markdown
# Coverage Report

## Summary
| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| Statements | 85.4% | 80% | Pass |
| Branches | 72.1% | 75% | Fail |
| Functions | 91.0% | 85% | Pass |
| Lines | 86.2% | 80% | Pass |

## Coverage by Module

| Module | Statements | Branches | Lines |
|--------|------------|----------|-------|
| src/auth | 92% | 88% | 91% |
| src/api | 85% | 72% | 84% |
| src/utils | 78% | 65% | 76% |

## Uncovered Files

| File | Coverage | Gap |
|------|----------|-----|
| src/utils/legacy.ts | 12% | 68% |
| src/api/deprecated.ts | 0% | 100% |

## Uncovered Lines

### src/api/users.ts
```typescript
// Lines 45-52 not covered
async function handleEdgeCase() {  // <- Not covered
  if (condition) {
    return special;
  }
}
```

## Recommendations

1. **High Priority**: Improve branch coverage in `src/api`
2. **Medium**: Add tests for `src/utils/legacy.ts`
3. **Consider**: Remove or test `src/api/deprecated.ts`
```

### 4. Gap Analysis

#### Identify Coverage Gaps
```python
# Analyze gaps from coverage data
def analyze_coverage_gaps(coverage_data):
    gaps = []
    for file, data in coverage_data.items():
        if data['coverage'] < 80:
            gaps.append({
                'file': file,
                'current': data['coverage'],
                'gap': 80 - data['coverage'],
                'uncovered_lines': data['missing']
            })
    return sorted(gaps, key=lambda x: x['gap'], reverse=True)
```

#### Priority Decision
| Coverage | Priority | Action |
|----------|----------|--------|
| < 50% | Critical | Immediate action |
| 50-70% | Medium | Plan improvement |
| 70-80% | Low | Nice to have |
| >= 80% | OK | Maintain |

### 5. CI Integration

#### GitHub Actions Badge
```yaml
- name: Coverage Badge
  uses: cicirello/jacoco-badge-generator@v2
  with:
    jacoco-csv-file: build/reports/jacoco/test/jacocoTestReport.csv
```

#### Codecov Integration
```yaml
- name: Upload to Codecov
  uses: codecov/codecov-action@v3
  with:
    files: ./coverage.xml
    fail_ci_if_error: true
    verbose: true
```

### 6. Output Format

```json
{
  "summary": {
    "statements": { "covered": 1024, "total": 1199, "percentage": 85.4 },
    "branches": { "covered": 312, "total": 399, "percentage": 78.2 },
    "functions": { "covered": 182, "total": 200, "percentage": 91.0 },
    "lines": { "covered": 989, "total": 1148, "percentage": 86.1 }
  },
  "modules": [
    { "name": "src/auth", "statements": 92, "branches": 88, "lines": 91 }
  ],
  "gaps": [
    { "file": "src/utils/legacy.ts", "coverage": 12, "gap": 68, "priority": "high" }
  ],
  "recommendations": [
    "Add unit tests for handleEdgeCase function",
    "Remove deprecated.ts or add deprecation tests"
  ]
}
```

## Quick Commands

| Action | Python | JavaScript | Java |
|--------|--------|------------|------|
| Generate | `pytest --cov` | `npm test -- --coverage` | `./gradlew jacocoTestReport` |
| HTML | `--cov-report=html` | `--coverageReporters="html"` | Built-in |
| XML | `--cov-report=xml` | `--coverageReporters="lcov"` | Built-in |
| Min Check | `--cov-fail-under=80` | `coverageThreshold` | `violationRules` |

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Coverage Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Statements:  85.4%  ████████░░  Pass
Branches:    72.1%  ███████░░░  Warning
Functions:   91.0%  █████████░  Pass
Lines:       86.1%  ████████░░  Pass

Overall: 83.7% (Target: 80%)

Gaps Found: 3 files below threshold
Recommendations: 2

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
