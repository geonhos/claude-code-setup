#!/bin/bash
#
# PreCommit hook — fast compile/typecheck by default; full tests opt-in.
#
# Env vars:
#   HARNESS_SKIP_PRECOMMIT=1  — skip all checks
#   HARNESS_RUN_TESTS=1       — run full test suite (slower, usually CI's job)
#
# Rationale: running the full test suite on every commit blocks the
# developer for minutes and duplicates work that CI will do anyway.
# Default to the cheapest check that catches the most common breakage
# (doesn't compile / doesn't type-check).

if [ "${HARNESS_SKIP_PRECOMMIT:-0}" = "1" ]; then
    echo "[pre-commit] skipped via HARNESS_SKIP_PRECOMMIT=1"
    exit 0
fi

RUN_TESTS="${HARNESS_RUN_TESTS:-0}"
FAILED=0

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$RUN_TESTS" = "1" ]; then
    echo "Pre-commit checks (build + tests)..."
else
    echo "Pre-commit checks (fast: compile/typecheck only)"
    echo "  Full tests: HARNESS_RUN_TESTS=1 git commit ..."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# --- Java (Gradle) ---
if [ $FAILED -eq 0 ] && { [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; }; then
    echo "Java/Gradle detected"
    if [ -f "./gradlew" ]; then
        if [ "$RUN_TESTS" = "1" ]; then
            ./gradlew build || FAILED=1
        else
            ./gradlew compileJava compileTestJava || FAILED=1
        fi
    fi
fi

# --- Java (Maven) ---
if [ $FAILED -eq 0 ] && [ -f "pom.xml" ]; then
    echo "Java/Maven detected"
    MVN_CMD=""
    if [ -f "./mvnw" ]; then MVN_CMD="./mvnw"
    elif command -v mvn >/dev/null 2>&1; then MVN_CMD="mvn"
    fi
    if [ -n "$MVN_CMD" ]; then
        if [ "$RUN_TESTS" = "1" ]; then
            $MVN_CMD verify || FAILED=1
        else
            $MVN_CMD compile test-compile || FAILED=1
        fi
    fi
fi

# --- Node.js ---
if [ $FAILED -eq 0 ] && [ -f "package.json" ]; then
    echo "Node.js detected"
    if [ "$RUN_TESTS" = "1" ]; then
        if grep -q '"build"' package.json; then npm run build || FAILED=1; fi
        if [ $FAILED -eq 0 ] && grep -q '"test"' package.json; then npm test || FAILED=1; fi
    else
        # Prefer typecheck > tsc > lint
        if grep -q '"typecheck"' package.json; then
            npm run typecheck || FAILED=1
        elif grep -q '"tsc"' package.json; then
            npm run tsc || FAILED=1
        elif grep -q '"lint"' package.json; then
            npm run lint || FAILED=1
        fi
    fi
fi

# --- Python ---
if [ $FAILED -eq 0 ] && { [ -f "pytest.ini" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; }; then
    echo "Python detected"
    if [ "$RUN_TESTS" = "1" ] && command -v pytest >/dev/null 2>&1; then
        pytest || FAILED=1
    elif command -v python >/dev/null 2>&1; then
        python -m compileall -q . >/dev/null 2>&1 || true
    fi
fi

# --- Go ---
if [ $FAILED -eq 0 ] && [ -f "go.mod" ]; then
    echo "Go detected"
    if [ "$RUN_TESTS" = "1" ]; then
        go build ./... && go test ./... || FAILED=1
    else
        go build ./... || FAILED=1
    fi
fi

# --- Rust ---
if [ $FAILED -eq 0 ] && [ -f "Cargo.toml" ]; then
    echo "Rust detected"
    if [ "$RUN_TESTS" = "1" ]; then
        cargo build && cargo test || FAILED=1
    else
        cargo check || FAILED=1
    fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $FAILED -ne 0 ]; then
    echo "Pre-commit checks FAILED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

echo "Pre-commit checks passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 0
