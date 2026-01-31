---
name: fastapi_setup
description: Sets up FastAPI project structure with routers, models, schemas, services, database, and comprehensive testing. Use after python_setup for API projects.
model: haiku
---

# FastAPI Project Setup Skill

Sets up standard FastAPI project structure and test infrastructure.

## Prerequisites

- Python project already exists (`python_setup` skill completed)
- Virtual environment is activated

## Workflow

### 1. Verify Project Info

```bash
# Verify virtual environment
which python

# Project name
PROJECT_NAME=$(basename $(pwd))
```

### 2. Install FastAPI Dependencies

```bash
# Add to requirements.txt
cat >> requirements.txt <<'EOF'

# FastAPI
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
python-multipart>=0.0.6

# Database
sqlalchemy>=2.0.0
aiosqlite>=0.19.0

# Data Validation
pydantic>=2.5.0
pydantic-settings>=2.1.0

# HTTP Client
httpx>=0.25.0

# Testing
pytest>=7.4.0
pytest-asyncio>=0.21.0
pytest-cov>=4.1.0
pytest-env>=1.0.0
factory-boy>=3.3.0
EOF

# Install
pip install -r requirements.txt
```

### 3. Create Directory Structure

```bash
# Remove existing src/ and change to app/ structure
rm -rf src/
mkdir -p app/{routers,models,schemas,services}
mkdir -p tests/{api,unit,integration}
touch app/__init__.py
touch app/routers/__init__.py
touch app/models/__init__.py
touch app/schemas/__init__.py
touch app/services/__init__.py
touch tests/__init__.py
touch tests/api/__init__.py
touch tests/unit/__init__.py
touch tests/integration/__init__.py
```

### 4. Create Core Files

**app/config.py:**
```python
"""Application configuration."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings."""

    app_name: str = "{project_name}"
    debug: bool = True
    database_url: str = "sqlite+aiosqlite:///./app.db"

    class Config:
        env_file = ".env"


settings = Settings()
```

**app/database.py:**
```python
"""Database configuration."""

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker, declarative_base

from app.config import settings

engine = create_async_engine(
    settings.database_url,
    echo=settings.debug,
)

async_session = sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

Base = declarative_base()


async def get_db() -> AsyncSession:
    """Dependency for getting database session."""
    async with async_session() as session:
        yield session
```

**app/main.py:**
```python
"""FastAPI application entry point."""

from fastapi import FastAPI

from app.config import settings
from app.routers import health

app = FastAPI(
    title=settings.app_name,
    debug=settings.debug,
)

# Register routers
app.include_router(health.router)


@app.on_event("startup")
async def startup():
    """Application startup handler."""
    pass


@app.on_event("shutdown")
async def shutdown():
    """Application shutdown handler."""
    pass
```

### 5. Health Check Router

**app/routers/health.py:**
```python
"""Health check endpoints."""

from fastapi import APIRouter

router = APIRouter(prefix="/health", tags=["health"])


@router.get("")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy"}


@router.get("/ready")
async def readiness_check():
    """Readiness check endpoint."""
    return {"status": "ready"}
```

**app/routers/__init__.py:**
```python
"""API routers."""

from app.routers import health

__all__ = ["health"]
```

### 6. Sample Model, Schema, Service

**app/models/item.py:**
```python
"""Item model."""

from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func

from app.database import Base


class Item(Base):
    """Item database model."""

    __tablename__ = "items"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    description = Column(String(500))
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, onupdate=func.now())
```

**app/schemas/item.py:**
```python
"""Item schemas."""

from datetime import datetime
from pydantic import BaseModel


class ItemBase(BaseModel):
    """Base item schema."""

    name: str
    description: str | None = None


class ItemCreate(ItemBase):
    """Schema for creating item."""

    pass


class ItemResponse(ItemBase):
    """Schema for item response."""

    id: int
    created_at: datetime

    class Config:
        from_attributes = True
```

**app/services/item_service.py:**
```python
"""Item service."""

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.item import Item
from app.schemas.item import ItemCreate


class ItemService:
    """Service for item operations."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(self, data: ItemCreate) -> Item:
        """Create a new item."""
        item = Item(**data.model_dump())
        self.db.add(item)
        await self.db.commit()
        await self.db.refresh(item)
        return item

    async def get_all(self) -> list[Item]:
        """Get all items."""
        result = await self.db.execute(select(Item))
        return result.scalars().all()
```

---

## Testing Infrastructure

### 7. pytest Configuration

**pytest.ini:**
```ini
[pytest]
asyncio_mode = auto
testpaths = tests
python_files = test_*.py
python_functions = test_*
addopts =
    -v
    --cov=app
    --cov-report=term-missing
    --cov-report=html
    --cov-fail-under=80

filterwarnings =
    ignore::DeprecationWarning

env =
    DATABASE_URL=sqlite+aiosqlite:///./test.db
    DEBUG=true
```

**.coveragerc:**
```ini
[run]
source = app
omit =
    app/__init__.py
    */tests/*
    */.venv/*

[report]
exclude_lines =
    pragma: no cover
    def __repr__
    raise NotImplementedError
    if __name__ == .__main__.:
    if TYPE_CHECKING:

show_missing = true
```

### 8. Conftest - Test Fixtures

**tests/conftest.py:**
```python
"""Test configuration and fixtures."""

import asyncio
from typing import AsyncGenerator, Generator

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.database import Base, get_db


# Test database URL (in-memory for isolation)
TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"


@pytest.fixture(scope="session")
def event_loop() -> Generator:
    """Create event loop for session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="function")
async def db_engine():
    """Create test database engine."""
    engine = create_async_engine(
        TEST_DATABASE_URL,
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    yield engine

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

    await engine.dispose()


@pytest.fixture(scope="function")
async def db_session(db_engine) -> AsyncGenerator[AsyncSession, None]:
    """Create test database session."""
    async_session = sessionmaker(
        db_engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    async with async_session() as session:
        yield session


@pytest.fixture(scope="function")
async def client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """Create test client with database override."""

    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db

    async with AsyncClient(
        app=app,
        base_url="http://test",
        headers={"Content-Type": "application/json"},
    ) as ac:
        yield ac

    app.dependency_overrides.clear()


@pytest.fixture
def sample_item_data() -> dict:
    """Sample item data for testing."""
    return {
        "name": "Test Item",
        "description": "A test item description",
    }
```

### 9. API Test Pattern

**tests/api/test_health.py:**
```python
"""Tests for health check endpoints."""

import pytest


class TestHealthEndpoints:
    """Test class for health endpoints."""

    @pytest.mark.asyncio
    async def test_health_check_returns_200(self, client):
        """Test that health check returns 200 OK."""
        response = await client.get("/health")

        assert response.status_code == 200
        assert response.json() == {"status": "healthy"}

    @pytest.mark.asyncio
    async def test_readiness_check_returns_200(self, client):
        """Test that readiness check returns 200 OK."""
        response = await client.get("/health/ready")

        assert response.status_code == 200
        assert response.json() == {"status": "ready"}
```

**tests/api/test_items.py:**
```python
"""Tests for item endpoints."""

import pytest


class TestCreateItem:
    """Tests for creating items."""

    @pytest.mark.asyncio
    async def test_create_item_success(self, client, sample_item_data):
        """Test successful item creation."""
        response = await client.post("/items", json=sample_item_data)

        assert response.status_code == 201
        data = response.json()
        assert data["name"] == sample_item_data["name"]
        assert "id" in data

    @pytest.mark.asyncio
    async def test_create_item_missing_name_returns_422(self, client):
        """Test that missing name returns validation error."""
        response = await client.post("/items", json={"description": "test"})

        assert response.status_code == 422


class TestGetItems:
    """Tests for retrieving items."""

    @pytest.mark.asyncio
    async def test_get_items_empty_list(self, client):
        """Test getting empty list of items."""
        response = await client.get("/items")

        assert response.status_code == 200
        assert response.json() == []


class TestGetItem:
    """Tests for retrieving single item."""

    @pytest.mark.asyncio
    async def test_get_item_not_found_returns_404(self, client):
        """Test that non-existent item returns 404."""
        response = await client.get("/items/999")

        assert response.status_code == 404
```

### 10. Unit Test Pattern

**tests/unit/test_services.py:**
```python
"""Unit tests for services."""

import pytest
from unittest.mock import AsyncMock, MagicMock

from app.services.item_service import ItemService
from app.schemas.item import ItemCreate


class TestItemService:
    """Tests for ItemService."""

    @pytest.fixture
    def mock_db(self):
        """Create mock database session."""
        db = AsyncMock()
        db.add = MagicMock()
        db.commit = AsyncMock()
        db.refresh = AsyncMock()
        return db

    @pytest.fixture
    def service(self, mock_db):
        """Create service with mock db."""
        return ItemService(mock_db)

    @pytest.mark.asyncio
    async def test_create_item_adds_to_db(self, service, mock_db):
        """Test that create adds item to database."""
        data = ItemCreate(name="Test", description="Description")

        await service.create(data)

        mock_db.add.assert_called_once()
        mock_db.commit.assert_called_once()
```

### 11. Test Factory

**tests/factories.py:**
```python
"""Test factories."""

import factory
from factory.alchemy import SQLAlchemyModelFactory

from app.models.item import Item


class ItemFactory(SQLAlchemyModelFactory):
    """Factory for creating Item instances."""

    class Meta:
        model = Item
        sqlalchemy_session = None  # Set in conftest
        sqlalchemy_session_persistence = "commit"

    name = factory.Sequence(lambda n: f"Item {n}")
    description = factory.Faker("sentence")
```

---

## Final Steps

### 12. Update .env

```bash
cat >> .env <<'EOF'

# Database
DATABASE_URL=sqlite+aiosqlite:///./app.db

# Application
DEBUG=True
EOF
```

### 13. Run Tests

```bash
# Run all tests
pytest

# Specific file
pytest tests/api/test_items.py

# Specific class
pytest tests/api/test_items.py::TestCreateItem

# Coverage report
pytest --cov=app --cov-report=html
open htmlcov/index.html

# Test server run
uvicorn app.main:app --reload &
sleep 2
curl http://localhost:8000/health
kill %1
```

### 14. Commit

```bash
git add .
git commit -m "[Phase 0] Setup FastAPI project with testing infrastructure

FastAPI Setup:
- FastAPI application with uvicorn
- SQLAlchemy async database configuration
- Pydantic settings and schemas

Project Structure:
- app/routers/ - API endpoints
- app/models/ - SQLAlchemy models
- app/schemas/ - Pydantic schemas
- app/services/ - Business logic

Testing Infrastructure:
- pytest-asyncio with coverage (>80% required)
- Test database with in-memory SQLite
- API tests (health, CRUD patterns)
- Unit tests with mocking
- Test fixtures and factories
"
```

## Generated Structure

```
{project}/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI app
│   ├── config.py            # Configuration
│   ├── database.py          # DB connection
│   ├── routers/
│   │   ├── __init__.py
│   │   └── health.py        # Health check
│   ├── models/
│   │   ├── __init__.py
│   │   └── item.py          # Sample model
│   ├── schemas/
│   │   ├── __init__.py
│   │   └── item.py          # Sample schema
│   └── services/
│       ├── __init__.py
│       └── item_service.py  # Sample service
├── tests/
│   ├── __init__.py
│   ├── conftest.py          # Test fixtures
│   ├── factories.py         # Test factory
│   ├── api/
│   │   ├── __init__.py
│   │   ├── test_health.py   # Health tests
│   │   └── test_items.py    # CRUD tests
│   ├── unit/
│   │   ├── __init__.py
│   │   └── test_services.py # Service tests
│   └── integration/
│       └── __init__.py
├── pytest.ini
├── .coveragerc
├── requirements.txt
└── .env
```

## Test Commands

| Command | Description |
|---------|-------------|
| `pytest` | Run all tests |
| `pytest -v` | Verbose output |
| `pytest tests/api/` | API tests only |
| `pytest tests/unit/` | Unit tests only |
| `pytest --cov=app` | Measure coverage |
| `pytest -n auto` | Parallel execution (requires pytest-xdist) |

## Test Writing Guidelines

1. **Test names**: `test_<action>_<expected_result>`
2. **AAA pattern**: Arrange, Act, Assert
3. **Single assert**: One verification per test
4. **Independence**: No dependencies between tests
5. **Use fixtures**: Minimize duplicate code

## Verification Checklist

- [ ] `pytest -v` passes
- [ ] Coverage 80% or higher
- [ ] `uvicorn app.main:app --reload` runs
- [ ] `http://localhost:8000/docs` accessible
- [ ] `http://localhost:8000/health` responds

## Notes

- **Async first**: Use async/await pattern
- **Dependency injection**: Use FastAPI Depends
- **Test isolation**: New DB session per test (in-memory)
- **Mocking**: Use mock for external services
- **Coverage**: Maintain 80%+ coverage
