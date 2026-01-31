---
name: alembic_migration
description: Manages database migrations with Alembic. Handles init, revision creation, upgrade, downgrade, and migration history.
model: haiku
color: orange
---

# Alembic Migration Skill

Database migration workflow using Alembic.

## Prerequisites

- SQLAlchemy models must be defined
- Virtual environment must be activated

## Workflow

### 1. Initialize Alembic (First Time Only)

```bash
# Verify Alembic installation
pip install alembic

# Initialize Alembic
alembic init alembic
```

### 2. Configure alembic.ini

```ini
# Modify alembic.ini
# Find and update the sqlalchemy.url line

# Synchronous SQLite (for development)
sqlalchemy.url = sqlite:///./app.db

# For async usage, convert to synchronous URL
# sqlite+aiosqlite:///./app.db -> sqlite:///./app.db
```

### 3. Configure env.py

**Modify alembic/env.py:**
```python
from logging.config import fileConfig

from sqlalchemy import engine_from_config
from sqlalchemy import pool

from alembic import context

# Import models (important!)
from app.database import Base
from app.models import item  # Import all models

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Configure MetaData
target_metadata = Base.metadata


def run_migrations_offline() -> None:
    """Run migrations in 'offline' mode."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    """Run migrations in 'online' mode."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

### 4. Create Migration

#### Auto-generate (Detect Model Changes)
```bash
# Auto-detect model changes
alembic revision --autogenerate -m "Add item table"
```

#### Manual Creation
```bash
# Create empty migration file
alembic revision -m "Custom migration"
```

### 5. Apply Migration

```bash
# Upgrade to latest
alembic upgrade head

# Upgrade to specific revision
alembic upgrade <revision_id>

# Upgrade one step at a time
alembic upgrade +1
```

### 6. Rollback Migration

```bash
# Rollback one step
alembic downgrade -1

# Rollback to specific revision
alembic downgrade <revision_id>

# Rollback to beginning (drops all tables)
alembic downgrade base
```

### 7. Check Status

```bash
# Check current revision
alembic current

# Migration history
alembic history

# Pending migrations
alembic heads
```

## Common Scenarios

### Adding a New Model

1. Create model file
```python
# app/models/user.py
from sqlalchemy import Column, Integer, String
from app.database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    email = Column(String(255), unique=True, nullable=False)
    name = Column(String(100))
```

2. Add import to env.py
```python
from app.models import item, user  # Add user
```

3. Create and apply migration
```bash
alembic revision --autogenerate -m "Add user table"
alembic upgrade head
```

### Adding a Column

1. Modify model
```python
class User(Base):
    # ... existing columns
    phone = Column(String(20))  # Add new column
```

2. Create and apply migration
```bash
alembic revision --autogenerate -m "Add phone column to user"
alembic upgrade head
```

### Removing a Column

1. Remove column from model
2. Create and apply migration
```bash
alembic revision --autogenerate -m "Remove phone column from user"
alembic upgrade head
```

## Migration File Structure

```python
"""Add user table

Revision ID: abc123def456
Revises:
Create Date: 2024-01-01 12:00:00.000000

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers
revision = 'abc123def456'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'users',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('email', sa.String(255), nullable=False),
        sa.Column('name', sa.String(100), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('email')
    )


def downgrade() -> None:
    op.drop_table('users')
```

## Generated Structure

```
project/
├── alembic/
│   ├── versions/           # Migration files
│   │   ├── abc123_add_user_table.py
│   │   └── def456_add_phone_column.py
│   ├── env.py              # Alembic environment configuration
│   ├── script.py.mako      # Migration template
│   └── README
├── alembic.ini             # Alembic configuration
└── app/
    └── models/
```

## Commit Example

```bash
git add alembic/ alembic.ini
git commit -m "[Phase X] Add database migration

Migration:
- Add user table with email and name columns
- Auto-generated from SQLAlchemy models

Commands:
- alembic upgrade head (apply)
- alembic downgrade -1 (rollback)
"
```

## Important Notes

- **autogenerate Limitations**: Cannot detect column renames or table renames
- **Data Migrations**: Must be written manually
- **Production**: Always backup before running migrations
- **downgrade Testing**: Verify rollback works correctly

## Quick Reference

| Command | Description |
|---------|-------------|
| `alembic init alembic` | Initialize |
| `alembic revision --autogenerate -m "msg"` | Auto-generate migration |
| `alembic upgrade head` | Apply latest |
| `alembic downgrade -1` | Rollback one step |
| `alembic current` | Current status |
| `alembic history` | History |
