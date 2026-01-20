---
name: tdd_workflow
description: Implements Kent Beck's Test-Driven Development workflow. Follows Red-Green-Refactor cycle by writing failing tests first, implementing minimal code to pass, then refactoring. Ensures test coverage and clean code through disciplined TDD practice.
model: haiku
color: red
---

# TDD Workflow Skill (Kent Beck Method)

Guides through Test-Driven Development using the Red-Green-Refactor cycle.

## Language-Specific Tools (Quick Reference)

| Language | Test Framework | Assertion | Mock | Coverage |
|----------|---------------|-----------|------|----------|
| **Java** | JUnit 5 | AssertJ | Mockito | JaCoCo |
| **Python** | pytest | pytest/unittest | unittest.mock | pytest-cov |
| **JavaScript** | Jest / Vitest | Jest matchers | Jest mock | Jest --coverage |
| **Go** | testing | testify | gomock | go test -cover |
| **Rust** | cargo test | assert! | mockall | tarpaulin |

## TDD Cycle

```
RED → GREEN → REFACTOR → REPEAT
```

1. **RED**: Write a failing test
2. **GREEN**: Write minimal code to pass the test
3. **REFACTOR**: Improve code while keeping tests green

## Workflow

### Phase 1: RED - Write Failing Test

**Steps:**
1. Ask user for:
   - Feature/function to implement
   - Expected behavior
   - Input/output examples
   - Edge cases

2. Write test first:
   - Create test file if needed
   - Write descriptive test name
   - Define expected behavior
   - Use assertions

3. Run test and verify it **fails**:
   ```bash
   # Python
   pytest path/to/test_file.py -v

   # JavaScript/TypeScript
   npm test -- path/to/test.spec.ts

   # Go
   go test ./...

   # Rust
   cargo test
   ```

4. Confirm failure reason is correct (not syntax error)

### Phase 2: GREEN - Minimal Implementation

**Steps:**
1. Write **simplest code** to make test pass:
   - No premature optimization
   - Hardcode if necessary
   - Focus on making test green

2. Run test again:
   ```bash
   # Same command as Phase 1
   ```

3. Verify test **passes**

4. If still failing:
   - Debug implementation
   - Fix issues
   - Re-run test
   - Repeat until green

### Phase 3: REFACTOR - Improve Code

**Steps:**
1. Review code for improvements:
   - Remove duplication
   - Improve naming
   - Extract functions/methods
   - Simplify logic
   - Apply design patterns

2. Run tests after each refactor:
   - Ensure tests still pass
   - No behavior changes

3. Ask: "Any more refactoring needed?"
   - If yes: Continue refactoring
   - If no: Move to next feature

### Phase 4: REPEAT

Return to Phase 1 for next test case or feature.

## Best Practices

### Test Writing
- **One concept per test**: Each test should verify one behavior
- **Descriptive names**: `test_user_login_with_invalid_password_returns_error`
- **AAA Pattern**: Arrange, Act, Assert
- **No test logic**: Tests should be simple and obvious

### Implementation
- **Fake it till you make it**: Start with hardcoded values
- **Triangulation**: Add tests to force generalization
- **Obvious implementation**: If solution is clear, implement directly

### Refactoring
- **Small steps**: One change at a time
- **Run tests frequently**: After each small change
- **Remove duplication**: DRY principle
- **Keep tests green**: Never refactor with failing tests

## Example Workflow

### Example 1: Python Function

**RED Phase:**
```python
# test_calculator.py
def test_add_two_positive_numbers():
    calc = Calculator()
    result = calc.add(2, 3)
    assert result == 5
```

Run: `pytest test_calculator.py -v` → **FAILS** (Calculator class doesn't exist)

**GREEN Phase:**
```python
# calculator.py
class Calculator:
    def add(self, a, b):
        return 5  # Hardcoded to pass test
```

Run: `pytest test_calculator.py -v` → **PASSES**

**REFACTOR Phase:**
Add another test to force real implementation:
```python
def test_add_two_different_numbers():
    calc = Calculator()
    result = calc.add(1, 4)
    assert result == 5
```

Now refactor to general solution:
```python
class Calculator:
    def add(self, a, b):
        return a + b  # Real implementation
```

Run: `pytest test_calculator.py -v` → **PASSES** (both tests)

### Example 2: JavaScript API Endpoint

**RED Phase:**
```javascript
// user.test.js
describe('User API', () => {
  test('GET /users/:id returns user', async () => {
    const response = await request(app).get('/users/1');
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('id', 1);
    expect(response.body).toHaveProperty('name');
  });
});
```

Run: `npm test` → **FAILS** (endpoint doesn't exist)

**GREEN Phase:**
```javascript
// routes/users.js
app.get('/users/:id', (req, res) => {
  res.status(200).json({ id: 1, name: 'John Doe' });
});
```

Run: `npm test` → **PASSES**

**REFACTOR Phase:**
```javascript
// routes/users.js
app.get('/users/:id', async (req, res) => {
  const userId = parseInt(req.params.id);
  const user = await userService.findById(userId);
  res.status(200).json(user);
});
```

Run: `npm test` → **PASSES**

## TDD Rules (Kent Beck's Three Laws)

1. **Don't write production code** until you have a failing test
2. **Don't write more test** than is sufficient to fail
3. **Don't write more code** than is sufficient to pass the test

## Language-Specific Commands

### Python
```bash
# Run tests
pytest
pytest path/to/test.py -v
pytest -k "test_name"

# Coverage
pytest --cov=src tests/
```

### JavaScript/TypeScript
```bash
# Run tests
npm test
npm test -- --watch
npm test -- path/to/test.spec.ts

# Coverage
npm test -- --coverage
```

### Go
```bash
# Run tests
go test ./...
go test -v ./...
go test -run TestFunctionName

# Coverage
go test -cover ./...
```

### Rust
```bash
# Run tests
cargo test
cargo test --verbose
cargo test test_name

# Coverage
cargo tarpaulin
```

## User Interaction

**At each phase, ask:**

**RED Phase:**
- "What feature should we implement?"
- "What's the expected behavior?"
- "Test is failing correctly. Proceed to GREEN? (yes/no)"

**GREEN Phase:**
- "Test is passing. Proceed to REFACTOR? (yes/no)"

**REFACTOR Phase:**
- "Any refactoring needed? (yes/no/done)"
- If done: "Add another test? (yes/no)"

## Output Format

Display progress clearly:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 RED Phase: Writing failing test
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Test: test_user_login_with_valid_credentials
File: tests/test_auth.py

✅ Test created
❌ Test failing (expected)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🟢 GREEN Phase: Minimal implementation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Implementation: src/auth/login.py

✅ Test passing

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔵 REFACTOR Phase: Code improvement
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Changes:
- Extracted validate_credentials()
- Improved error messages

✅ Tests still passing
```

## Notes

- Always run tests before starting (ensure clean state)
- Commit after each GREEN phase (optional but recommended)
- Keep test suite fast (mock external dependencies)
- Write tests at the right level (unit, integration, e2e)
- Use TDD for new features, not exploratory code
