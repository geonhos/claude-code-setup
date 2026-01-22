---
title: Never Use Blocking Calls in Async Functions
impact: CRITICAL
section: async
tags: [async, blocking, event-loop, httpx]
improvement: "Prevents complete application freeze"
---

# Never Use Blocking Calls in Async Functions

**Impact:** CRITICAL
**Improvement:** Prevents complete application freeze under load

## Description

Blocking calls in async functions halt the entire event loop, preventing any other coroutines from executing. This completely negates the benefits of async architecture.

## Problem

Synchronous libraries like `requests`, `time.sleep()`, or synchronous database drivers block the event loop. Under load, a single blocking call can make the entire application unresponsive.

### Bad Example

```python
import requests
import time

async def fetch_data(url: str):
    # BLOCKS THE ENTIRE EVENT LOOP
    response = requests.get(url)  # All other requests wait
    return response.json()

async def process_with_delay():
    # BLOCKS THE ENTIRE EVENT LOOP
    time.sleep(5)  # Nothing else can run for 5 seconds
    return "done"
```

## Solution

Use async-compatible libraries for all I/O operations.

### Good Example

```python
import httpx
import asyncio

async def fetch_data(url: str):
    # Non-blocking - other coroutines can run
    async with httpx.AsyncClient() as client:
        response = await client.get(url)
        return response.json()

async def process_with_delay():
    # Non-blocking - yields control to event loop
    await asyncio.sleep(5)
    return "done"
```

## Common Blocking Calls to Avoid

| Blocking | Async Alternative |
|----------|-------------------|
| `requests.get()` | `httpx.AsyncClient().get()` |
| `time.sleep()` | `asyncio.sleep()` |
| `open().read()` | `aiofiles.open()` |
| `subprocess.run()` | `asyncio.create_subprocess_exec()` |
| SQLAlchemy sync | SQLAlchemy async with `AsyncSession` |

## Running CPU-Bound Tasks

For CPU-intensive operations, use thread/process pools:

```python
import asyncio
from concurrent.futures import ThreadPoolExecutor

executor = ThreadPoolExecutor(max_workers=4)

async def cpu_intensive_task(data):
    loop = asyncio.get_event_loop()
    # Run in thread pool, doesn't block event loop
    result = await loop.run_in_executor(
        executor,
        heavy_computation,
        data
    )
    return result
```

## Why It Matters

- **Event loop blocking**: One blocking call stops ALL concurrent operations
- **Scalability**: Async only scales with non-blocking I/O
- **Response times**: Blocked requests queue up exponentially
- **Resource waste**: Server sits idle during blocking waits

## Related Rules

- `async-gather.md` - Concurrent async operations
- `async-semaphore.md` - Limiting concurrent operations

## References

- [HTTPX Documentation](https://www.python-httpx.org/)
- [asyncio Documentation](https://docs.python.org/3/library/asyncio.html)
