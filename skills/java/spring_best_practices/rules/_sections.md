# Spring Boot Performance Optimization Sections

Rules are organized into 5 sections, ranked by performance impact.

---

## 1. JPA/Hibernate Optimization

**Prefix:** `jpa-`
**Impact:** CRITICAL
**Description:** JPA misuse is the #1 cause of Spring application performance issues. N+1 queries, improper fetch strategies, and missing batch operations can cripple database performance.

**Key Patterns:**
- EntityGraph and JOIN FETCH for eager loading
- @Modifying queries for bulk updates
- Batch inserts with flush/clear
- Projections for read-only queries

---

## 2. API Design

**Prefix:** `api-`
**Impact:** HIGH
**Description:** Proper API design prevents over-fetching, reduces payload sizes, and improves client performance. DTOs, pagination, and compression are essential.

**Key Patterns:**
- DTOs instead of entity exposure
- Pagination for collection endpoints
- Response compression (GZip)
- Proper HTTP caching headers

---

## 3. Async Processing

**Prefix:** `async-`
**Impact:** HIGH
**Description:** Async processing improves throughput by not blocking threads on I/O operations. Proper thread pool configuration is critical.

**Key Patterns:**
- @Async with CompletableFuture
- Custom thread pool executors
- @Scheduled for background jobs
- WebFlux for reactive streams

---

## 4. Caching Strategies

**Prefix:** `caching-`
**Impact:** MEDIUM
**Description:** Caching reduces database load and improves response times. Proper cache configuration and invalidation strategies are essential.

**Key Patterns:**
- Spring Cache abstraction
- Redis for distributed caching
- Hibernate second-level cache
- Cache eviction strategies

---

## 5. Configuration Best Practices

**Prefix:** `config-`
**Impact:** MEDIUM
**Description:** Proper configuration of connection pools, thread pools, and JPA settings can significantly impact performance without code changes.

**Key Patterns:**
- HikariCP connection pool tuning
- Thread pool sizing
- Hibernate batch settings
- Profile-specific configurations
