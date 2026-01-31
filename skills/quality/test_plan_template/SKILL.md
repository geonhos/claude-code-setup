---
name: test_plan_template
description: Generates comprehensive test plans with test cases, priorities, and coverage targets for features.
model: haiku
color: yellow
---

# Test Plan Template Skill

Generates systematic test plans for features.

## Workflow

### 1. Gather Information

Confirm with user:
- Feature/function name
- Key requirements
- Risk areas
- Test environment

### 2. Test Plan Template

**test-plan-{feature}.md:**
```markdown
# Test Plan: {Feature Name}

## 1. Overview

### 1.1 Feature Description
{Brief description of the feature}

### 1.2 Scope
**In Scope:**
- {list of features to test}

**Out of Scope:**
- {explicitly excluded items}

### 1.3 Risk Assessment
| Risk | Probability | Impact | Priority |
|------|-------------|--------|----------|
| {risk} | High/Medium/Low | High/Medium/Low | P0/P1/P2 |

---

## 2. Test Strategy

### 2.1 Test Levels
| Level | Coverage Target | Tools |
|-------|-----------------|-------|
| Unit | 80% | Jest/pytest/JUnit |
| Integration | 70% | TestClient/MockMvc |
| E2E | Critical paths | Playwright/Cypress |

### 2.2 Test Types
- [ ] Functional Testing
- [ ] Negative Testing
- [ ] Boundary Testing
- [ ] Performance Testing (if applicable)
- [ ] Security Testing (if applicable)
- [ ] Accessibility Testing (if applicable)

---

## 3. Test Cases

### 3.1 Priority Definitions
| Priority | Criteria | SLA |
|----------|----------|-----|
| P0 | Business critical, no workaround | Must pass |
| P1 | Important, has workaround | Should pass |
| P2 | Nice to have | May skip |

### 3.2 Test Case List

#### TC-001: {Happy Path - Main Flow}
| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Type** | E2E |
| **Preconditions** | {setup required} |
| **Steps** | 1. {step}<br>2. {step} |
| **Expected Result** | {outcome} |
| **Test Data** | {data needed} |

#### TC-002: {Validation - Required Fields}
| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Type** | Integration |
| **Preconditions** | {setup} |
| **Steps** | 1. Submit form without required field |
| **Expected Result** | Validation error displayed |

#### TC-003: {Error Handling - Network Failure}
| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Type** | Integration |
| **Preconditions** | Network interceptor configured |
| **Steps** | 1. Trigger network failure |
| **Expected Result** | Error message shown, retry available |

#### TC-004: {Boundary - Max Length Input}
| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Type** | Unit |
| **Steps** | 1. Input max length string |
| **Expected Result** | Accepted or truncated gracefully |

---

## 4. Test Data

### 4.1 Valid Data Sets
| Field | Valid Values |
|-------|--------------|
| {field} | {value1}, {value2} |

### 4.2 Invalid Data Sets
| Field | Invalid Values | Expected Error |
|-------|----------------|----------------|
| {field} | {value} | {error message} |

### 4.3 Boundary Values
| Field | Min | Max | Just Over Max |
|-------|-----|-----|---------------|
| {field} | {val} | {val} | {val} |

---

## 5. Environment Requirements

### 5.1 Test Environment
- Environment: {dev/staging/local}
- Database: {H2/PostgreSQL/Mock}
- External Services: {mocked/live}

### 5.2 Dependencies
- [ ] {dependency 1}
- [ ] {dependency 2}

---

## 6. Automation Coverage

### 6.1 Automated Tests
| Test Case | Status | File |
|-----------|--------|------|
| TC-001 | Automated | tests/e2e/feature.spec.ts |
| TC-002 | Automated | tests/integration/api.test.ts |
| TC-003 | Manual | - |

### 6.2 Automation Candidates
- {test case that should be automated}

---

## 7. Schedule

### 7.1 Milestones
- [ ] Test Plan Review
- [ ] Test Case Development
- [ ] Test Execution
- [ ] Bug Fixes
- [ ] Regression Testing
- [ ] Sign-off

---

## 8. Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| QA Lead | | | |
| Dev Lead | | | |
| Product Owner | | | |
```

### 3. Test Case Matrix

```markdown
## Test Matrix

| Scenario | Happy | Error | Boundary | Security | A11y |
|----------|-------|-------|----------|----------|------|
| Create   | TC-001 | TC-010 | TC-020 | TC-030 | TC-040 |
| Read     | TC-002 | TC-011 | TC-021 | TC-031 | TC-041 |
| Update   | TC-003 | TC-012 | TC-022 | TC-032 | TC-042 |
| Delete   | TC-004 | TC-013 | TC-023 | TC-033 | TC-043 |
```

### 4. Risk-Based Prioritization

| Risk Level | Test Coverage | Focus |
|------------|---------------|-------|
| High | 100% | All scenarios |
| Medium | 80% | Happy + Error paths |
| Low | 50% | Happy paths only |

## Quick Templates

### Unit Test Case
```yaml
id: TC-U-001
name: {function}_returns_{expected}_when_{condition}
type: unit
priority: P0
input: {input values}
expected: {expected output}
```

### Integration Test Case
```yaml
id: TC-I-001
name: {endpoint}_{method}_returns_{status}
type: integration
priority: P0
setup: {preconditions}
request:
  method: POST
  path: /api/resource
  body: {payload}
expected:
  status: 201
  body: {response}
```

### E2E Test Case
```yaml
id: TC-E-001
name: user_can_{complete_action}
type: e2e
priority: P0
steps:
  - Navigate to {page}
  - Fill in {form}
  - Click {button}
expected:
  - See {confirmation}
  - Data saved correctly
```

## Output Format

```json
{
  "test_plan": {
    "feature": "{feature_name}",
    "version": "1.0",
    "created": "{date}",
    "test_cases": {
      "total": 20,
      "p0": 8,
      "p1": 8,
      "p2": 4
    },
    "coverage": {
      "unit": 80,
      "integration": 70,
      "e2e": 5
    }
  }
}
```

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Test Plan Generated
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Feature: {feature_name}
Test Cases: {total}
  - P0 (Critical): {count}
  - P1 (Important): {count}
  - P2 (Nice to have): {count}

Coverage Targets:
  - Unit: 80%
  - Integration: 70%
  - E2E: Critical paths

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
