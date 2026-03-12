#!/bin/bash

# Claude Code PreCommit hook
# Detects project type, runs build & tests, blocks commit on failure
# Skips gracefully if no test framework is detected

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running pre-commit checks..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

FAILED=0

# --- Java (Gradle) ---
if [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    echo "Java/Gradle project detected"
    if [ -f "./gradlew" ]; then
        echo "Running ./gradlew build..."
        ./gradlew build
        if [ $? -ne 0 ]; then
            echo "Gradle build failed! Commit aborted."
            FAILED=1
        else
            echo "Gradle build + tests passed!"
        fi
    else
        echo "gradlew not found, skipping"
    fi
fi

# --- Java (Maven) ---
if [ -f "pom.xml" ] && [ $FAILED -eq 0 ]; then
    echo "Java/Maven project detected"
    if [ -f "./mvnw" ]; then
        echo "Running ./mvnw verify..."
        ./mvnw verify
    elif command -v mvn > /dev/null 2>&1; then
        echo "Running mvn verify..."
        mvn verify
    else
        echo "Maven not found, skipping"
        FAILED=0
    fi
    if [ $? -ne 0 ] && [ $FAILED -eq 0 ]; then
        echo "Maven build failed! Commit aborted."
        FAILED=1
    elif [ $FAILED -eq 0 ]; then
        echo "Maven build + tests passed!"
    fi
fi

# --- Python ---
if [ -f "pytest.ini" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
    if [ $FAILED -eq 0 ]; then
        echo "Python project detected"
        if command -v pytest > /dev/null 2>&1; then
            echo "Running pytest..."
            pytest
            if [ $? -ne 0 ]; then
                echo "Tests failed! Commit aborted."
                FAILED=1
            else
                echo "All tests passed!"
            fi
        else
            echo "pytest not found, skipping tests"
        fi
    fi
fi

# --- Node.js ---
if [ -f "package.json" ] && [ $FAILED -eq 0 ]; then
    echo "Node.js project detected"

    # Build check
    if grep -q '"build"' package.json; then
        echo "Running npm run build..."
        npm run build
        if [ $? -ne 0 ]; then
            echo "Build failed! Commit aborted."
            FAILED=1
        else
            echo "Build passed!"
        fi
    fi

    # Test check
    if [ $FAILED -eq 0 ] && grep -q '"test"' package.json; then
        echo "Running npm test..."
        npm test
        if [ $? -ne 0 ]; then
            echo "Tests failed! Commit aborted."
            FAILED=1
        else
            echo "All tests passed!"
        fi
    fi
fi

# --- Go ---
if [ -f "go.mod" ] && [ $FAILED -eq 0 ]; then
    echo "Go project detected"
    echo "Running go build && go test..."
    go build ./...
    if [ $? -ne 0 ]; then
        echo "Build failed! Commit aborted."
        FAILED=1
    else
        go test ./...
        if [ $? -ne 0 ]; then
            echo "Tests failed! Commit aborted."
            FAILED=1
        else
            echo "Build + tests passed!"
        fi
    fi
fi

# --- Rust ---
if [ -f "Cargo.toml" ] && [ $FAILED -eq 0 ]; then
    echo "Rust project detected"
    echo "Running cargo build && cargo test..."
    cargo build
    if [ $? -ne 0 ]; then
        echo "Build failed! Commit aborted."
        FAILED=1
    else
        cargo test
        if [ $? -ne 0 ]; then
            echo "Tests failed! Commit aborted."
            FAILED=1
        else
            echo "Build + tests passed!"
        fi
    fi
fi

# --- No framework detected ---
if [ $FAILED -eq 0 ]; then
    # Check if any framework was detected by looking at output
    # If none matched, this is a non-testable project — allow commit
    if [ ! -f "build.gradle" ] && [ ! -f "build.gradle.kts" ] && \
       [ ! -f "pom.xml" ] && [ ! -f "pytest.ini" ] && \
       [ ! -f "setup.py" ] && [ ! -f "pyproject.toml" ] && \
       [ ! -f "package.json" ] && [ ! -f "go.mod" ] && \
       [ ! -f "Cargo.toml" ]; then
        echo "No test framework detected, skipping tests"
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
