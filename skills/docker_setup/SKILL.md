---
name: docker_setup
description: Creates Docker and docker-compose configuration for development and production environments.
model: haiku
---

# Docker Setup Skill

Creates Docker and docker-compose configuration files.

## Prerequisites

- Project must already exist
- Must have requirements.txt or package.json

## Workflow

### 1. Check Project Type

```bash
# Check for Python project
if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    echo "Python project detected"
fi

# Check for Node.js project
if [ -f "package.json" ]; then
    echo "Node.js project detected"
fi
```

### 2. Python Dockerfile

**Dockerfile:**
```dockerfile
# Build stage
FROM python:3.11-slim as builder

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /app/wheels -r requirements.txt

# Production stage
FROM python:3.11-slim

WORKDIR /app

# Create non-root user
RUN addgroup --system app && adduser --system --group app

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy wheels from builder
COPY --from=builder /app/wheels /wheels
RUN pip install --no-cache-dir /wheels/*

# Copy application
COPY --chown=app:app . .

# Switch to non-root user
USER app

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Expose port
EXPOSE 8000

# Run application
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 3. Python Development Dockerfile

**Dockerfile.dev:**
```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install development dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install development tools
RUN pip install --no-cache-dir \
    pytest \
    pytest-cov \
    black \
    flake8 \
    mypy

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Expose port
EXPOSE 8000

# Run with reload
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

### 4. docker-compose.yml

**docker-compose.yml:**
```yaml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://postgres:postgres@db:5432/app
      - DEBUG=false
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - app-network

  db:
    image: postgres:15-alpine
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=app
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - app-network

volumes:
  postgres_data:

networks:
  app-network:
    driver: bridge
```

### 5. docker-compose.dev.yml

**docker-compose.dev.yml:**
```yaml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "8000:8000"
    volumes:
      - .:/app
      - /app/.venv  # Exclude venv
    environment:
      - DATABASE_URL=sqlite+aiosqlite:///./app.db
      - DEBUG=true
    command: uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

  # Optional: ChromaDB for RAG projects
  # chromadb:
  #   image: chromadb/chroma:latest
  #   ports:
  #     - "8001:8000"
  #   volumes:
  #     - chroma_data:/chroma/chroma

  # Optional: Ollama for LLM
  # ollama:
  #   image: ollama/ollama:latest
  #   ports:
  #     - "11434:11434"
  #   volumes:
  #     - ollama_data:/root/.ollama

# volumes:
#   chroma_data:
#   ollama_data:
```

### 6. .dockerignore

**.dockerignore:**
```
# Git
.git
.gitignore

# Python
.venv
__pycache__
*.pyc
*.pyo
*.pyd
.pytest_cache
.mypy_cache
.coverage
htmlcov

# IDE
.vscode
.idea
*.swp

# Environment
.env
.env.local
.env.*.local

# Docker
Dockerfile*
docker-compose*
.dockerignore

# Data
data/
*.db
*.sqlite

# Documentation
docs/
*.md
!README.md

# Tests (optional, remove for test image)
tests/
pytest.ini
```

### 7. Makefile (Optional)

**Makefile:**
```makefile
.PHONY: help build run stop dev test clean

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

build:  ## Build production image
	docker-compose build

run:  ## Run production containers
	docker-compose up -d

stop:  ## Stop all containers
	docker-compose down

dev:  ## Run development environment
	docker-compose -f docker-compose.dev.yml up

dev-build:  ## Build and run development environment
	docker-compose -f docker-compose.dev.yml up --build

test:  ## Run tests in container
	docker-compose -f docker-compose.dev.yml run --rm app pytest -v

logs:  ## Show container logs
	docker-compose logs -f

shell:  ## Open shell in app container
	docker-compose exec app /bin/bash

clean:  ## Remove all containers and volumes
	docker-compose down -v --remove-orphans
	docker system prune -f
```

### 8. Commit

```bash
git add Dockerfile* docker-compose* .dockerignore Makefile
git commit -m "[Phase 0] Add Docker configuration

Docker Setup:
- Multi-stage Dockerfile for production
- Development Dockerfile with hot reload
- docker-compose for production with PostgreSQL
- docker-compose.dev for local development

Features:
- Non-root user for security
- Health checks
- Volume mounts for development
- Makefile for common commands
"
```

## Generated Structure

```
project/
├── Dockerfile              # Production image
├── Dockerfile.dev          # Development image
├── docker-compose.yml      # Production environment
├── docker-compose.dev.yml  # Development environment
├── .dockerignore           # Docker excluded files
└── Makefile                # Convenience commands
```

## Usage

```bash
# Run development environment
make dev

# Or
docker-compose -f docker-compose.dev.yml up

# Build and run production
make build
make run

# Run tests
make test

# View logs
make logs

# Cleanup
make clean
```

## Environment-Specific Configuration

### Development
- Source code mounted (hot reload)
- SQLite database
- DEBUG=true
- Testing tools included

### Production
- Multi-stage build (lightweight)
- PostgreSQL database
- Non-root user
- Health check included
- DEBUG=false

## Notes

- **Secret Management**: Use Docker secrets or environment variable management tools in production
- **Volume Backup**: Regular backup of database volumes required
- **Image Size**: Minimize production image (exclude unnecessary files)
