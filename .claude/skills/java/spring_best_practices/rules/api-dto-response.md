---
title: Use DTOs for API Responses
impact: HIGH
section: api
tags: [api, dto, response, security]
improvement: "Prevents data leaks, reduces payload size"
---

# Use DTOs for API Responses

**Impact:** HIGH
**Improvement:** Prevents data leaks, reduces payload size, decouples API from domain

## Description

Never expose JPA entities directly in API responses. DTOs (Data Transfer Objects) provide a clean contract, prevent accidental data exposure, and allow independent evolution of API and domain.

## Problem

Exposing entities directly leaks internal structure, can expose sensitive data, and creates tight coupling between API and database schema.

### Bad Example

```java
@Entity
public class User {
    @Id
    private Long id;
    private String email;
    private String password;     // Exposed!
    private String ssn;          // Exposed!
    private LocalDateTime createdAt;

    @OneToMany(mappedBy = "user")
    private List<Post> posts;    // Triggers N+1 or loads everything
}

@RestController
public class UserController {

    @GetMapping("/users/{id}")
    public User getUser(@PathVariable Long id) {
        // Exposes password, SSN, and internal structure
        return userRepository.findById(id).orElseThrow();
    }
}
```

## Solution

Create dedicated DTOs for each use case.

### Good Example

```java
// Response DTO - only public fields
public record UserResponse(
    Long id,
    String email,
    String displayName,
    LocalDateTime memberSince
) {
    public static UserResponse from(User user) {
        return new UserResponse(
            user.getId(),
            user.getEmail(),
            user.getDisplayName(),
            user.getCreatedAt()
        );
    }
}

// Detailed response with nested data
public record UserDetailResponse(
    Long id,
    String email,
    String displayName,
    List<PostSummary> recentPosts
) {
    public static UserDetailResponse from(User user) {
        return new UserDetailResponse(
            user.getId(),
            user.getEmail(),
            user.getDisplayName(),
            user.getPosts().stream()
                .limit(5)
                .map(PostSummary::from)
                .toList()
        );
    }
}

@RestController
public class UserController {

    @GetMapping("/users/{id}")
    public UserResponse getUser(@PathVariable Long id) {
        return userRepository.findById(id)
            .map(UserResponse::from)
            .orElseThrow(() -> new NotFoundException("User", id));
    }
}
```

## JPA Projections for Read-Only

```java
// Interface projection - Hibernate generates implementation
public interface UserSummary {
    Long getId();
    String getEmail();
    String getDisplayName();
}

public interface UserRepository extends JpaRepository<User, Long> {

    // Returns projection directly - no entity loading
    Optional<UserSummary> findProjectedById(Long id);

    List<UserSummary> findAllProjectedBy();
}

// Class-based projection with constructor
public record UserSummaryDto(Long id, String email) {}

@Query("SELECT new com.example.dto.UserSummaryDto(u.id, u.email) FROM User u")
List<UserSummaryDto> findAllSummaries();
```

## DTO Patterns by Use Case

| Pattern | Use Case | Example |
|---------|----------|---------|
| `XxxResponse` | API output | `UserResponse` |
| `XxxRequest` | API input | `CreateUserRequest` |
| `XxxSummary` | List items | `UserSummary` |
| `XxxDetail` | Full object | `UserDetailResponse` |

## MapStruct for Complex Mapping

```java
@Mapper(componentModel = "spring")
public interface UserMapper {

    UserResponse toResponse(User user);

    @Mapping(target = "memberSince", source = "createdAt")
    UserDetailResponse toDetailResponse(User user);

    List<UserResponse> toResponseList(List<User> users);
}

@Service
@RequiredArgsConstructor
public class UserService {
    private final UserMapper mapper;

    public UserResponse getUser(Long id) {
        return userRepository.findById(id)
            .map(mapper::toResponse)
            .orElseThrow();
    }
}
```

## Why It Matters

- **Security**: Prevents accidental exposure of sensitive data
- **Performance**: Only serialize what's needed
- **Decoupling**: API can evolve independently from domain
- **Versioning**: Different DTOs for API versions
- **Documentation**: Clean contract for API consumers

## Related Rules

- `jpa-n-plus-one.md` - Prevent N+1 when loading for DTOs
- `api-pagination.md` - Paginate list responses

## References

- [MapStruct Documentation](https://mapstruct.org/documentation/)
- [Spring Data Projections](https://docs.spring.io/spring-data/jpa/docs/current/reference/html/#projections)
