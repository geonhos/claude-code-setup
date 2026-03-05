---
name: api_test_setup
description: Sets up API testing patterns with pytest, httpx TestClient, fixtures, and coverage configuration for FastAPI projects.
model: haiku
disable-model-invocation: true
---

# API Test Setup Skill

FastAPI 프로젝트의 API 테스트 인프라를 설정합니다.

## Prerequisites

- FastAPI 프로젝트가 이미 존재해야 함 (`fastapi_setup` 스킬 실행 완료)
- 가상환경이 활성화되어 있어야 함

## Workflow

### 1. 테스트 의존성 설치

```bash
# requirements.txt에 추가
cat >> requirements.txt <<'EOF'

# Testing
pytest>=7.4.0
pytest-asyncio>=0.21.0
pytest-cov>=4.1.0
pytest-env>=1.0.0
pytest-xdist>=3.5.0
httpx>=0.25.0
factory-boy>=3.3.0
faker>=21.0.0
respx>=0.20.0
EOF

# 설치
pip install -r requirements.txt
```

### 2. 테스트 디렉토리 구조

```bash
mkdir -p tests/{api,unit,integration,fixtures}
touch tests/__init__.py
touch tests/api/__init__.py
touch tests/unit/__init__.py
touch tests/integration/__init__.py
touch tests/fixtures/__init__.py
```

### 3. pytest 설정

**pytest.ini:**
```ini
[pytest]
asyncio_mode = auto
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*

addopts = 
    -v
    --tb=short
    --strict-markers
    --cov=app
    --cov-report=term-missing
    --cov-report=html:htmlcov
    --cov-fail-under=80

markers =
    unit: Unit tests (fast, no external dependencies)
    integration: Integration tests (may use database)
    api: API endpoint tests
    slow: Slow running tests

filterwarnings =
    ignore::DeprecationWarning
    ignore::PendingDeprecationWarning

env =
    ENVIRONMENT=test
    DATABASE_URL=sqlite+aiosqlite:///:memory:
    DEBUG=false
```

### 4. Coverage 설정

**.coveragerc:**
```ini
[run]
source = app
branch = true
omit =
    app/__init__.py
    app/main.py
    */tests/*
    */.venv/*
    */migrations/*

[report]
exclude_lines =
    pragma: no cover
    def __repr__
    def __str__
    raise AssertionError
    raise NotImplementedError
    if __name__ == .__main__.:
    if TYPE_CHECKING:
    @abstractmethod
    @overload

show_missing = true
precision = 2

[html]
directory = htmlcov
```

### 5. Conftest - Core Fixtures

**tests/conftest.py:**
```python
"""Test configuration and core fixtures."""

import asyncio
from typing import AsyncGenerator, Generator

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.database import Base, get_db
from app.config import settings


# Override settings for testing
settings.environment = "test"
settings.debug = False


@pytest.fixture(scope="session")
def event_loop() -> Generator:
    """Create event loop for the test session."""
    policy = asyncio.get_event_loop_policy()
    loop = policy.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="function")
async def db_engine():
    """Create test database engine with in-memory SQLite."""
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        echo=False,
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
    async_session_maker = sessionmaker(
        db_engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autocommit=False,
        autoflush=False,
    )

    async with async_session_maker() as session:
        yield session
        await session.rollback()


@pytest.fixture(scope="function")
async def client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """Create test client with database override."""

    async def override_get_db() -> AsyncGenerator[AsyncSession, None]:
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
async def authenticated_client(
    client: AsyncClient,
    test_user: dict,
) -> AsyncClient:
    """Create authenticated test client."""
    # Login and get token
    response = await client.post(
        "/auth/login",
        json={"email": test_user["email"], "password": test_user["password"]},
    )
    token = response.json().get("access_token")
    
    client.headers["Authorization"] = f"Bearer {token}"
    return client
```

### 6. Test Fixtures

**tests/fixtures/users.py:**
```python
"""User-related test fixtures."""

import pytest
from faker import Faker

fake = Faker()


@pytest.fixture
def user_data() -> dict:
    """Generate random user data."""
    return {
        "email": fake.email(),
        "password": fake.password(length=12),
        "name": fake.name(),
    }


@pytest.fixture
def test_user() -> dict:
    """Fixed test user for authentication tests."""
    return {
        "email": "test@example.com",
        "password": "TestPassword123!",
        "name": "Test User",
    }


@pytest.fixture
def admin_user() -> dict:
    """Fixed admin user for authorization tests."""
    return {
        "email": "admin@example.com",
        "password": "AdminPassword123!",
        "name": "Admin User",
        "is_admin": True,
    }
```

**tests/fixtures/items.py:**
```python
"""Item-related test fixtures."""

import pytest
from faker import Faker

fake = Faker()


@pytest.fixture
def item_data() -> dict:
    """Generate random item data."""
    return {
        "name": fake.word().capitalize(),
        "description": fake.sentence(),
        "price": float(fake.random_int(min=100, max=10000)),
    }


@pytest.fixture
def sample_items() -> list[dict]:
    """Generate multiple sample items."""
    return [
        {"name": f"Item {i}", "description": f"Description {i}", "price": i * 100.0}
        for i in range(1, 6)
    ]
```

**tests/fixtures/__init__.py:**
```python
"""Test fixtures package."""

from tests.fixtures.users import user_data, test_user, admin_user
from tests.fixtures.items import item_data, sample_items

__all__ = [
    "user_data",
    "test_user", 
    "admin_user",
    "item_data",
    "sample_items",
]
```

### 7. API Test Patterns

**tests/api/test_health.py:**
```python
"""Health endpoint tests."""

import pytest


class TestHealthEndpoints:
    """Tests for health check endpoints."""

    @pytest.mark.api
    async def test_health_check(self, client):
        """Test health endpoint returns 200."""
        response = await client.get("/health")

        assert response.status_code == 200
        assert response.json()["status"] == "healthy"

    @pytest.mark.api
    async def test_readiness_check(self, client):
        """Test readiness endpoint returns 200."""
        response = await client.get("/health/ready")

        assert response.status_code == 200
```

**tests/api/test_crud_pattern.py:**
```python
"""CRUD endpoint test patterns."""

import pytest


class TestCreateEndpoint:
    """Tests for POST /items endpoint."""

    @pytest.mark.api
    async def test_create_success(self, client, item_data):
        """Test successful resource creation."""
        response = await client.post("/items", json=item_data)

        assert response.status_code == 201
        data = response.json()
        assert data["name"] == item_data["name"]
        assert "id" in data

    @pytest.mark.api
    async def test_create_invalid_data(self, client):
        """Test creation with invalid data returns 422."""
        response = await client.post("/items", json={})

        assert response.status_code == 422

    @pytest.mark.api
    async def test_create_duplicate(self, client, item_data):
        """Test duplicate creation returns 409."""
        await client.post("/items", json=item_data)
        response = await client.post("/items", json=item_data)

        assert response.status_code == 409


class TestReadEndpoint:
    """Tests for GET /items endpoints."""

    @pytest.mark.api
    async def test_get_list_empty(self, client):
        """Test getting empty list."""
        response = await client.get("/items")

        assert response.status_code == 200
        assert response.json() == []

    @pytest.mark.api
    async def test_get_list_with_items(self, client, sample_items):
        """Test getting list with items."""
        for item in sample_items:
            await client.post("/items", json=item)

        response = await client.get("/items")

        assert response.status_code == 200
        assert len(response.json()) == len(sample_items)

    @pytest.mark.api
    async def test_get_by_id_success(self, client, item_data):
        """Test getting item by ID."""
        create_response = await client.post("/items", json=item_data)
        item_id = create_response.json()["id"]

        response = await client.get(f"/items/{item_id}")

        assert response.status_code == 200
        assert response.json()["id"] == item_id

    @pytest.mark.api
    async def test_get_by_id_not_found(self, client):
        """Test getting non-existent item returns 404."""
        response = await client.get("/items/99999")

        assert response.status_code == 404


class TestUpdateEndpoint:
    """Tests for PUT/PATCH /items endpoints."""

    @pytest.mark.api
    async def test_update_success(self, client, item_data):
        """Test successful update."""
        create_response = await client.post("/items", json=item_data)
        item_id = create_response.json()["id"]

        update_data = {"name": "Updated Name"}
        response = await client.patch(f"/items/{item_id}", json=update_data)

        assert response.status_code == 200
        assert response.json()["name"] == "Updated Name"

    @pytest.mark.api
    async def test_update_not_found(self, client):
        """Test updating non-existent item returns 404."""
        response = await client.patch("/items/99999", json={"name": "Test"})

        assert response.status_code == 404


class TestDeleteEndpoint:
    """Tests for DELETE /items endpoints."""

    @pytest.mark.api
    async def test_delete_success(self, client, item_data):
        """Test successful deletion."""
        create_response = await client.post("/items", json=item_data)
        item_id = create_response.json()["id"]

        response = await client.delete(f"/items/{item_id}")

        assert response.status_code == 204

        # Verify deletion
        get_response = await client.get(f"/items/{item_id}")
        assert get_response.status_code == 404

    @pytest.mark.api
    async def test_delete_not_found(self, client):
        """Test deleting non-existent item returns 404."""
        response = await client.delete("/items/99999")

        assert response.status_code == 404
```

### 8. Unit Test Patterns

**tests/unit/test_services.py:**
```python
"""Service layer unit tests."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch


class TestItemService:
    """Unit tests for ItemService."""

    @pytest.fixture
    def mock_db(self):
        """Create mock database session."""
        db = AsyncMock()
        db.add = MagicMock()
        db.commit = AsyncMock()
        db.refresh = AsyncMock()
        db.execute = AsyncMock()
        db.delete = AsyncMock()
        return db

    @pytest.mark.unit
    async def test_create_calls_db_add(self, mock_db):
        """Test create method adds item to database."""
        from app.services.item_service import ItemService
        from app.schemas.item import ItemCreate

        service = ItemService(mock_db)
        data = ItemCreate(name="Test", description="Description")

        await service.create(data)

        mock_db.add.assert_called_once()
        mock_db.commit.assert_called_once()

    @pytest.mark.unit
    async def test_get_by_id_returns_none_when_not_found(self, mock_db):
        """Test get_by_id returns None for non-existent item."""
        from app.services.item_service import ItemService

        mock_result = MagicMock()
        mock_result.scalar_one_or_none.return_value = None
        mock_db.execute.return_value = mock_result

        service = ItemService(mock_db)
        result = await service.get_by_id(99999)

        assert result is None
```

### 9. Integration Test Patterns

**tests/integration/test_workflow.py:**
```python
"""Integration tests for complete workflows."""

import pytest


class TestItemWorkflow:
    """Integration tests for item CRUD workflow."""

    @pytest.mark.integration
    async def test_complete_crud_workflow(self, client, item_data):
        """Test complete CRUD workflow."""
        # Create
        create_response = await client.post("/items", json=item_data)
        assert create_response.status_code == 201
        item_id = create_response.json()["id"]

        # Read
        get_response = await client.get(f"/items/{item_id}")
        assert get_response.status_code == 200
        assert get_response.json()["name"] == item_data["name"]

        # Update
        update_response = await client.patch(
            f"/items/{item_id}",
            json={"name": "Updated"},
        )
        assert update_response.status_code == 200
        assert update_response.json()["name"] == "Updated"

        # Delete
        delete_response = await client.delete(f"/items/{item_id}")
        assert delete_response.status_code == 204

        # Verify deleted
        verify_response = await client.get(f"/items/{item_id}")
        assert verify_response.status_code == 404
```

### 10. Test Utilities

**tests/utils.py:**
```python
"""Test utilities and helpers."""

from typing import Any
import json


def assert_response_schema(response_data: dict, required_fields: list[str]) -> None:
    """Assert response contains required fields."""
    for field in required_fields:
        assert field in response_data, f"Missing required field: {field}"


def assert_pagination(response_data: dict) -> None:
    """Assert response has pagination structure."""
    assert "items" in response_data
    assert "total" in response_data
    assert "page" in response_data
    assert "size" in response_data


def load_test_data(filename: str) -> Any:
    """Load test data from JSON file."""
    with open(f"tests/data/{filename}") as f:
        return json.load(f)
```

---

## 테스트 실행 명령어

| 명령어 | 설명 |
|--------|------|
| `pytest` | 모든 테스트 실행 |
| `pytest -v` | 상세 출력 |
| `pytest -x` | 첫 실패에서 중단 |
| `pytest -m api` | API 테스트만 |
| `pytest -m unit` | Unit 테스트만 |
| `pytest -m integration` | Integration 테스트만 |
| `pytest -n auto` | 병렬 실행 |
| `pytest --cov=app` | 커버리지 측정 |
| `pytest --cov-report=html` | HTML 리포트 생성 |

---

## 생성되는 구조

```
tests/
├── __init__.py
├── conftest.py              # Core fixtures
├── utils.py                 # Test utilities
├── api/
│   ├── __init__.py
│   ├── test_health.py       # Health endpoint tests
│   └── test_crud_pattern.py # CRUD pattern tests
├── unit/
│   ├── __init__.py
│   └── test_services.py     # Service unit tests
├── integration/
│   ├── __init__.py
│   └── test_workflow.py     # Workflow tests
└── fixtures/
    ├── __init__.py
    ├── users.py             # User fixtures
    └── items.py             # Item fixtures
```

---

## 검증 체크리스트

- [ ] `pytest --collect-only` - 테스트 수집 확인
- [ ] `pytest -v` - 전체 테스트 통과
- [ ] `pytest --cov=app` - 커버리지 80% 이상
- [ ] `pytest -m api` - API 테스트 통과
- [ ] `pytest -m unit` - Unit 테스트 통과

---

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ API Test Setup Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📁 Project: {project_name}
🧪 Framework: pytest + pytest-asyncio

✅ Test dependencies installed
✅ pytest.ini configured
✅ Coverage settings configured
✅ Test fixtures created
✅ API test patterns added
✅ Unit test patterns added
✅ Integration test patterns added

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Coverage Target: 80%
Test Markers: api, unit, integration, slow
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Notes

- **Fixture 계층**: conftest.py → fixtures/ → 개별 테스트
- **테스트 격리**: 각 테스트 함수마다 새 DB 세션
- **병렬 실행**: pytest-xdist로 속도 향상
- **마커 활용**: 테스트 유형별 선택 실행
