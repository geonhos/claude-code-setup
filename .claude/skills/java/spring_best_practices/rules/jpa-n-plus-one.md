---
title: Prevent N+1 Queries with Fetch Strategies
impact: CRITICAL
section: jpa
tags: [jpa, hibernate, n+1, entitygraph, fetch]
improvement: "Reduces query count from N+1 to 1-2"
---

# Prevent N+1 Queries with Fetch Strategies

**Impact:** CRITICAL
**Improvement:** Reduces query count from N+1 to 1-2 queries

## Description

N+1 queries occur when Hibernate lazily loads relationships for each entity in a collection. For 100 entities with relationships, this creates 101 database queries.

## Problem

Default LAZY fetch type triggers separate queries when accessing relationships in loops. This compounds with nested relationships.

### Bad Example

```java
@Entity
public class User {
    @Id
    private Long id;

    @OneToMany(mappedBy = "user")  // LAZY by default
    private List<Post> posts;
}

// Controller or Service
public List<UserDto> getAllUsersWithPosts() {
    List<User> users = userRepository.findAll();  // Query 1

    return users.stream()
        .map(user -> new UserDto(
            user.getName(),
            user.getPosts().size()  // Query 2, 3, 4... N+1!
        ))
        .toList();
}

// With 100 users = 101 queries!
```

## Solution 1: EntityGraph

```java
public interface UserRepository extends JpaRepository<User, Long> {

    @EntityGraph(attributePaths = {"posts"})
    List<User> findAll();

    // Named EntityGraph
    @EntityGraph(value = "User.withPosts")
    Optional<User> findById(Long id);
}

@Entity
@NamedEntityGraph(
    name = "User.withPosts",
    attributeNodes = @NamedAttributeNode("posts")
)
public class User {
    // ...
}
```

## Solution 2: JOIN FETCH

```java
public interface UserRepository extends JpaRepository<User, Long> {

    @Query("SELECT u FROM User u JOIN FETCH u.posts")
    List<User> findAllWithPosts();

    @Query("SELECT DISTINCT u FROM User u " +
           "JOIN FETCH u.posts " +
           "WHERE u.status = :status")
    List<User> findByStatusWithPosts(@Param("status") Status status);
}
```

## Solution 3: Batch Fetching

```java
@Entity
public class User {
    @OneToMany(mappedBy = "user")
    @BatchSize(size = 25)  // Fetch 25 at a time
    private List<Post> posts;
}

// Or globally in application.yml
spring:
  jpa:
    properties:
      hibernate:
        default_batch_fetch_size: 25
```

## When to Use Each

| Strategy | Use When | Trade-off |
|----------|----------|-----------|
| EntityGraph | Always know what to fetch | Declarative, type-safe |
| JOIN FETCH | Complex queries with conditions | Flexible, explicit |
| Batch Fetching | Can't predict access patterns | Global, less control |

## Nested Relationships

```java
// Fetch user -> posts -> comments
@Query("SELECT u FROM User u " +
       "JOIN FETCH u.posts p " +
       "JOIN FETCH p.comments")
List<User> findAllWithPostsAndComments();

// Or with EntityGraph
@EntityGraph(attributePaths = {"posts", "posts.comments"})
List<User> findAll();
```

## Detecting N+1 in Development

```yaml
# application-dev.yml
spring:
  jpa:
    properties:
      hibernate:
        generate_statistics: true

logging:
  level:
    org.hibernate.stat: DEBUG
    org.hibernate.SQL: DEBUG
```

## Why It Matters

- **Query explosion**: N+1 scales linearly with data
- **Connection exhaustion**: Too many queries overwhelm pool
- **Latency**: Network round trips compound
- **Database load**: Each query has parsing/planning overhead

## Related Rules

- `jpa-projections.md` - Use projections for read-only data
- `jpa-batch-operations.md` - Batch inserts and updates

## References

- [Hibernate Fetching Strategies](https://docs.jboss.org/hibernate/orm/6.2/userguide/html_single/Hibernate_User_Guide.html#fetching)
- [Spring Data JPA EntityGraph](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#jpa.entity-graph)
