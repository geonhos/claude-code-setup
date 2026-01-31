---
name: python_best_practices
description: Python/FastAPI performance optimization guide with async patterns, database optimization, and caching strategies
model: haiku
---

# Python Best Practices

Performance optimization guide for Python and FastAPI applications.

## When to Reference

- Writing FastAPI endpoints with async operations
- Optimizing database queries with SQLAlchemy
- Implementing caching strategies
- Handling high-concurrency scenarios
- Profiling and optimizing Python code

## Priority Categories

| Priority | Section | Description |
|----------|---------|-------------|
| CRITICAL | Async Patterns | Proper async/await usage and concurrency |
| CRITICAL | Database Optimization | Query optimization, connection pooling |
| HIGH | API Performance | Response optimization, pagination |
| MEDIUM | Memory Management | Generator patterns, memory profiling |
| MEDIUM | Caching Strategies | Redis, in-memory caching |

## Quick Reference

### 1. Async Patterns (CRITICAL)

```python
# Bad: Blocking call in async function
async def get_data():
    result = requests.get(url)  # Blocks event loop!
    return result.json()

# Good: Use async HTTP client
async def get_data():
    async with httpx.AsyncClient() as client:
        result = await client.get(url)
        return result.json()
```

```python
# Bad: Sequential async calls
async def fetch_all():
    user = await fetch_user()
    posts = await fetch_posts()
    comments = await fetch_comments()

# Good: Concurrent with asyncio.gather
async def fetch_all():
    user, posts, comments = await asyncio.gather(
        fetch_user(),
        fetch_posts(),
        fetch_comments()
    )
```

### 2. Database Optimization (CRITICAL)

```python
# Bad: N+1 query problem
async def get_users_with_posts():
    users = await db.execute(select(User))
    for user in users.scalars():
        posts = await db.execute(  # N queries!
            select(Post).where(Post.user_id == user.id)
        )

# Good: Eager loading with joinedload
async def get_users_with_posts():
    result = await db.execute(
        select(User).options(joinedload(User.posts))
    )
    return result.unique().scalars().all()
```

```python
# Good: Use connection pooling
engine = create_async_engine(
    DATABASE_URL,
    pool_size=20,
    max_overflow=10,
    pool_pre_ping=True,
    pool_recycle=3600
)
```

### 3. API Performance (HIGH)

```python
# Bad: Load everything at once
@app.get("/items")
async def get_items():
    return await db.execute(select(Item))  # Could be millions

# Good: Implement pagination
@app.get("/items")
async def get_items(skip: int = 0, limit: int = 100):
    return await db.execute(
        select(Item).offset(skip).limit(limit)
    )
```

```python
# Good: Use response model for serialization
class ItemResponse(BaseModel):
    id: int
    name: str

    class Config:
        from_attributes = True

@app.get("/items", response_model=list[ItemResponse])
async def get_items():
    # Only selected fields are serialized
    ...
```

### 4. Memory Management (MEDIUM)

```python
# Bad: Load entire file into memory
def process_file(path: str):
    data = open(path).read()  # Loads entire file
    return process(data)

# Good: Use generators for large files
def process_file(path: str):
    with open(path) as f:
        for line in f:  # Memory efficient
            yield process_line(line)
```

```python
# Good: Use __slots__ for many instances
class Point:
    __slots__ = ['x', 'y']  # 40-50% less memory

    def __init__(self, x, y):
        self.x = x
        self.y = y
```

### 5. Caching Strategies (MEDIUM)

```python
# Good: Function-level caching with lru_cache
from functools import lru_cache

@lru_cache(maxsize=128)
def expensive_calculation(n: int) -> int:
    return sum(range(n))
```

```python
# Good: Redis caching for distributed systems
from redis import asyncio as aioredis

async def get_user(user_id: int):
    # Try cache first
    cached = await redis.get(f"user:{user_id}")
    if cached:
        return json.loads(cached)

    # Fetch from DB and cache
    user = await db.get(User, user_id)
    await redis.setex(f"user:{user_id}", 3600, user.json())
    return user
```

## FastAPI-Specific Optimizations

```python
# Good: Use dependencies for reusable logic
async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db)
) -> User:
    return await verify_token(token, db)

# Good: Background tasks for non-blocking operations
@app.post("/send-email")
async def send_email(
    email: EmailSchema,
    background_tasks: BackgroundTasks
):
    background_tasks.add_task(send_email_task, email)
    return {"message": "Email queued"}
```

## Verification Checklist

```
[ ] No blocking calls (requests, time.sleep) in async functions
[ ] asyncio.gather for independent concurrent operations
[ ] Eager loading (joinedload/selectinload) for relationships
[ ] Connection pooling configured
[ ] Pagination on list endpoints
[ ] Generators for large data processing
[ ] Caching for expensive computations
[ ] Background tasks for non-critical operations
```

## Summary

```
Priority Guide for Python Performance:

1. Fix blocking calls in async code (biggest impact)
2. Optimize database queries (N+1, eager loading)
3. Add pagination to list endpoints
4. Implement caching for repeated operations
5. Use generators for memory efficiency
```
