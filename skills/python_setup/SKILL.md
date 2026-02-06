---
name: python_setup
description: Sets up Python project structure with virtual environment, dependencies, test framework, and basic working code. Use after project_init for Python projects.
model: haiku
---

# Python Project Setup Skill

Sets up Python project structure with a basic working state.

## Prerequisites

- Project directory already exists (created with `project_init` skill)
- Git is initialized

## Workflow

### 1. Verify Project Info

Check project info in current directory:

```bash
# Check current directory
pwd

# Extract project name
PROJECT_NAME=$(basename $(pwd))
echo "Project: $PROJECT_NAME"
```

### 2. Create and Activate Virtual Environment

```bash
# Create virtual environment
python -m venv .venv

# Activate
source .venv/bin/activate

# Verify Python path
which python
```

### 3. Create Project Structure

```bash
# Directory structure
mkdir -p src tests docs

# Initialize Python packages
touch src/__init__.py
touch tests/__init__.py
```

### 4. Create Basic Source File

**src/main.py:**
```python
"""Main module for {project_name}."""


def main() -> None:
    """Main entry point."""
    print("Hello, {project_name}!")


if __name__ == "__main__":
    main()
```

### 5. Create Basic Test File

**tests/test_main.py:**
```python
"""Tests for main module."""

from src.main import main


def test_main(capsys):
    """Test main function outputs correctly."""
    main()
    captured = capsys.readouterr()
    assert "{project_name}" in captured.out
```

### 6. Create Dependency Files

**requirements.txt:**
```
# Testing
pytest>=7.0.0

# Code Quality
black>=23.0.0
flake8>=6.0.0
mypy>=1.0.0
```

**requirements-dev.txt (optional):**
```
-r requirements.txt

# Development
ipython>=8.0.0
```

### 7. Install Dependencies

```bash
# Install dependencies
pip install -r requirements.txt

# Verify installation
pip list
```

### 8. Create pyproject.toml

```toml
[project]
name = "{project_name}"
version = "0.1.0"
description = "{description}"
requires-python = ">=3.9"

[tool.pytest.ini_options]
testpaths = ["tests"]
python_files = ["test_*.py"]
python_functions = ["test_*"]

[tool.black]
line-length = 88
target-version = ["py39"]

[tool.mypy]
python_version = "3.9"
warn_return_any = true
warn_unused_configs = true

[tool.flake8]
max-line-length = 88
extend-ignore = ["E203"]
```

### 9. Verify Test Execution

```bash
# Run tests
pytest -v

# Verify results (should be PASSED)
```

### 10. Code Quality Check (Optional)

```bash
# Check formatting
black --check src tests

# Lint check
flake8 src tests

# Type check
mypy src
```

### 11. Commit

```bash
git add .
git commit -m "[Phase 0] Setup Python project structure

Python Environment:
- Virtual environment created (.venv)
- Dependencies installed (pytest, black, flake8, mypy)

Project Structure:
- src/ directory with main module
- tests/ directory with basic test
- requirements.txt for dependencies

Verification:
- All tests passing
"
```

## Generated Structure

```
{project_name}/
├── .venv/                 # Virtual environment (git ignored)
├── src/
│   ├── __init__.py
│   └── main.py           # Basic runnable module
├── tests/
│   ├── __init__.py
│   └── test_main.py      # Basic passing test
├── docs/
├── requirements.txt       # Dependencies
├── pyproject.toml        # Project config
└── (existing files: .gitignore, README.md, CLAUDE.md, etc.)
```

## Verification Checklist

After execution, verify:

- [ ] `.venv/` directory exists
- [ ] `which python` outputs `.venv/bin/python`
- [ ] `pytest -v` shows passing tests
- [ ] `python src/main.py` shows output

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Python Project Setup Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📁 Project: {project_name}
🐍 Python: $(python --version)
📦 Virtual Env: .venv

✅ Virtual environment created
✅ Dependencies installed
✅ Project structure created
✅ Tests passing

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Next Steps:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Activate virtual environment:
   source .venv/bin/activate

2. Start development:
   - Modify src/main.py
   - Add tests to tests/test_main.py

3. TDD workflow:
   - Write failing test
   - Implement code
   - Refactor

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Notes

- **Virtual environment required**: All work should be done in activated venv
- **Tests first**: Start with passing tests
- **Minimal dependencies**: Only essential tools (pytest, black, flake8, mypy)
