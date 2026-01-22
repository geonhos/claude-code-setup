# Python Performance Optimization Sections

Rules are organized into 5 sections, ranked by performance impact.

---

## 1. Async Patterns

**Prefix:** `async-`
**Impact:** CRITICAL
**Description:** Improper async usage can completely block the event loop, negating all benefits of async architecture. A single blocking call can halt the entire application.

**Key Patterns:**
- Use `httpx` or `aiohttp` instead of `requests`
- Use `asyncio.gather()` for concurrent operations
- Avoid `time.sleep()`, use `asyncio.sleep()`
- Run CPU-bound tasks in thread pools

---

## 2. Database Optimization

**Prefix:** `db-`
**Impact:** CRITICAL
**Description:** Database queries are often the biggest bottleneck. N+1 queries, missing indexes, and inefficient connection handling can cripple performance.

**Key Patterns:**
- Eager loading with `joinedload`/`selectinload`
- Connection pooling with proper sizing
- Batch operations for bulk updates
- Query optimization with EXPLAIN ANALYZE

---

## 3. API Performance

**Prefix:** `api-`
**Impact:** HIGH
**Description:** API design directly affects response times and server load. Proper pagination, response models, and compression significantly improve performance.

**Key Patterns:**
- Pagination for list endpoints
- Response model filtering
- GZip compression for large responses
- Streaming for large file downloads

---

## 4. Memory Management

**Prefix:** `memory-`
**Impact:** MEDIUM
**Description:** Python's memory management can be inefficient for large datasets. Proper use of generators, slots, and data structures reduces memory footprint.

**Key Patterns:**
- Generators for large iterations
- `__slots__` for many object instances
- Efficient data structures (array vs list)
- Memory profiling with `memory_profiler`

---

## 5. Caching Strategies

**Prefix:** `caching-`
**Impact:** MEDIUM
**Description:** Caching prevents redundant computations and database queries. Proper cache invalidation and TTL settings are critical.

**Key Patterns:**
- `@lru_cache` for function-level caching
- Redis for distributed caching
- Cache invalidation strategies
- Cache warming for predictable loads
