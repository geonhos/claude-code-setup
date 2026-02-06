---
name: spring_best_practices
description: Spring Boot performance optimization guide with JPA tuning, async processing, and caching strategies
model: haiku
---

# Spring Boot Best Practices

Performance optimization guide for Spring Boot applications.

## When to Reference

- Implementing JPA/Hibernate queries
- Designing REST APIs
- Configuring connection pools
- Implementing async processing
- Adding caching layers

## Priority Categories

| Priority | Section | Description |
|----------|---------|-------------|
| CRITICAL | JPA/Hibernate | N+1 queries, fetch strategies, batch operations |
| HIGH | API Design | DTOs, pagination, response compression |
| HIGH | Async Processing | @Async, CompletableFuture, thread pools |
| MEDIUM | Caching | Spring Cache, Redis, second-level cache |
| MEDIUM | Configuration | Connection pools, thread pools, profiles |

## Quick Reference

### 1. JPA/Hibernate Optimization (CRITICAL)

```java
// Bad: N+1 query problem
@Entity
public class User {
    @OneToMany(mappedBy = "user")  // LAZY by default
    private List<Post> posts;
}

// Accessing posts in loop triggers N queries
users.forEach(user -> user.getPosts().size());

// Good: Use EntityGraph or JOIN FETCH
@EntityGraph(attributePaths = {"posts"})
List<User> findAll();

// Or with JPQL
@Query("SELECT u FROM User u JOIN FETCH u.posts")
List<User> findAllWithPosts();
```

```java
// Bad: Fetching entire entity for partial update
User user = repository.findById(id);
user.setName(newName);
repository.save(user);

// Good: Use @Modifying for direct updates
@Modifying
@Query("UPDATE User u SET u.name = :name WHERE u.id = :id")
void updateName(@Param("id") Long id, @Param("name") String name);
```

### 2. API Design (HIGH)

```java
// Bad: Returning entity directly (exposes internals)
@GetMapping("/users/{id}")
public User getUser(@PathVariable Long id) {
    return userRepository.findById(id).orElseThrow();
}

// Good: Use DTOs with projections
@GetMapping("/users/{id}")
public UserResponse getUser(@PathVariable Long id) {
    return userRepository.findById(id)
        .map(UserResponse::from)
        .orElseThrow(() -> new NotFoundException(id));
}
```

```java
// Good: Implement pagination
@GetMapping("/users")
public Page<UserResponse> getUsers(
    @PageableDefault(size = 20, sort = "id") Pageable pageable
) {
    return userRepository.findAll(pageable)
        .map(UserResponse::from);
}
```

### 3. Async Processing (HIGH)

```java
// Good: Enable async with proper thread pool
@Configuration
@EnableAsync
public class AsyncConfig implements AsyncConfigurer {

    @Override
    public Executor getAsyncExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(10);
        executor.setMaxPoolSize(50);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("async-");
        executor.initialize();
        return executor;
    }
}

// Use @Async for non-blocking operations
@Async
public CompletableFuture<EmailResult> sendEmailAsync(Email email) {
    // Runs in separate thread
    return CompletableFuture.completedFuture(emailService.send(email));
}
```

### 4. Caching Strategies (MEDIUM)

```java
// Good: Use Spring Cache abstraction
@Configuration
@EnableCaching
public class CacheConfig {
    @Bean
    public CacheManager cacheManager() {
        return new ConcurrentMapCacheManager("users", "products");
    }
}

@Service
public class UserService {

    @Cacheable(value = "users", key = "#id")
    public User findById(Long id) {
        return userRepository.findById(id).orElseThrow();
    }

    @CacheEvict(value = "users", key = "#user.id")
    public User update(User user) {
        return userRepository.save(user);
    }

    @CacheEvict(value = "users", allEntries = true)
    public void clearCache() {}
}
```

### 5. Configuration Best Practices (MEDIUM)

```yaml
# Connection Pool (HikariCP)
spring:
  datasource:
    hikari:
      maximum-pool-size: 20
      minimum-idle: 5
      idle-timeout: 300000
      connection-timeout: 20000
      max-lifetime: 1200000

# JPA Settings
  jpa:
    open-in-view: false  # Prevent lazy loading in view
    properties:
      hibernate:
        jdbc:
          batch_size: 50  # Enable batch inserts
        order_inserts: true
        order_updates: true
        generate_statistics: true  # Only in dev
```

## Transaction Best Practices

```java
// Good: Use readOnly for queries (performance hint)
@Transactional(readOnly = true)
public List<User> findAll() {
    return userRepository.findAll();
}

// Good: Narrow transaction scope
@Transactional(propagation = Propagation.REQUIRES_NEW)
public void processPayment(Payment payment) {
    // Isolated transaction
}
```

## Batch Processing

```java
// Good: Batch inserts with flush/clear
@Transactional
public void batchInsert(List<User> users) {
    int batchSize = 50;
    for (int i = 0; i < users.size(); i++) {
        entityManager.persist(users.get(i));
        if (i % batchSize == 0) {
            entityManager.flush();
            entityManager.clear();  // Prevent memory issues
        }
    }
}
```

## Verification Checklist

```
[ ] No N+1 queries (use EntityGraph or JOIN FETCH)
[ ] DTOs for API responses (not entities)
[ ] Pagination on collection endpoints
[ ] @Transactional(readOnly=true) for read operations
[ ] Batch operations for bulk inserts/updates
[ ] Connection pool properly sized
[ ] open-in-view disabled
[ ] Caching for frequently accessed data
```

## Summary

```
Priority Guide for Spring Performance:

1. Fix N+1 queries (biggest database impact)
2. Use DTOs instead of exposing entities
3. Implement pagination for lists
4. Configure connection pools properly
5. Add caching for hot data
6. Use async for non-blocking operations
```
