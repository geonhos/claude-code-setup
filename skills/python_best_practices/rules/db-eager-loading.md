---
title: Use Eager Loading to Prevent N+1 Queries
impact: CRITICAL
section: db
tags: [database, sqlalchemy, n+1, joinedload]
improvement: "Reduces query count from N+1 to 1"
---

# Use Eager Loading to Prevent N+1 Queries

**Impact:** CRITICAL
**Improvement:** Reduces query count from N+1 to 1-2 queries

## Description

N+1 queries occur when fetching a collection and then accessing related objects for each item. This creates one query for the collection plus N queries for relationships.

## Problem

Lazy loading relationships in loops creates excessive database queries. For 100 users with posts, you get 101 queries instead of 1-2.

### Bad Example

```python
from sqlalchemy.orm import relationship

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    posts = relationship("Post", back_populates="user")  # Lazy by default

# N+1 Query Problem
async def get_users_with_post_count():
    result = await db.execute(select(User))  # Query 1
    users = result.scalars().all()

    for user in users:
        # Each access triggers a new query!
        post_count = len(user.posts)  # Query 2, 3, 4... N+1

    return users

# With 100 users = 101 queries!
```

## Solution

Use eager loading options to fetch relationships in a single query.

### Good Example (joinedload)

```python
from sqlalchemy.orm import joinedload

async def get_users_with_posts():
    result = await db.execute(
        select(User)
        .options(joinedload(User.posts))  # JOIN in single query
    )
    # Use unique() to deduplicate joined results
    return result.unique().scalars().all()

# Result: 1 query with JOIN
```

### Good Example (selectinload)

```python
from sqlalchemy.orm import selectinload

async def get_users_with_posts():
    result = await db.execute(
        select(User)
        .options(selectinload(User.posts))  # Second query with IN
    )
    return result.scalars().all()

# Result: 2 queries (SELECT users, SELECT posts WHERE user_id IN (...))
```

## When to Use Each

| Strategy | Use When | Query Pattern |
|----------|----------|---------------|
| `joinedload` | Few related items per parent | Single JOIN query |
| `selectinload` | Many related items per parent | Two queries with IN clause |
| `subqueryload` | Complex queries, many parents | Subquery for each relationship |

## Nested Relationships

```python
# Load users → posts → comments
result = await db.execute(
    select(User)
    .options(
        joinedload(User.posts)
        .joinedload(Post.comments)
    )
)
```

## Conditional Loading

```python
from sqlalchemy.orm import contains_eager

# Load only active posts
result = await db.execute(
    select(User)
    .join(User.posts)
    .where(Post.is_active == True)
    .options(contains_eager(User.posts))
)
```

## Why It Matters

- **Query count**: N+1 scales linearly with data size
- **Database load**: Each query has overhead (connection, parsing, execution)
- **Network latency**: Multiple round trips compound delay
- **Connection exhaustion**: Too many queries can exhaust pool

## Related Rules

- `db-connection-pooling.md` - Proper connection pool configuration
- `db-batch-operations.md` - Bulk inserts and updates

## References

- [SQLAlchemy Relationship Loading](https://docs.sqlalchemy.org/en/20/orm/loading_relationships.html)
- [SQLAlchemy Async](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html)
