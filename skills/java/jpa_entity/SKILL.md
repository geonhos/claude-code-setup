---
name: jpa_entity
description: Generates JPA entities with proper annotations, relationships, and base entity inheritance following DDD patterns.
model: haiku
color: purple
---

# JPA Entity Generator Skill

Generates JPA entities following DDD patterns.

## Prerequisites

- Spring Boot project setup complete
- spring-boot-starter-data-jpa dependency

## Workflow

### 1. Gather Entity Information

Confirm with user:
- Entity name
- Field list (name, type, constraints)
- Relationships (OneToMany, ManyToOne, etc.)
- Business rules

### 2. BaseEntity (Common Parent Class)

```java
package com.example.domain.model;

import jakarta.persistence.*;
import lombok.Getter;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.time.LocalDateTime;

@Getter
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
public abstract class BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @CreatedDate
    @Column(updatable = false)
    private LocalDateTime createdAt;

    @LastModifiedDate
    private LocalDateTime updatedAt;

    @Version
    private Long version;
}
```

### 3. Entity Template

```java
package com.example.domain.model;

import jakarta.persistence.*;
import jakarta.validation.constraints.*;
import lombok.*;

import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "{table_name}")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor(access = AccessLevel.PRIVATE)
@Builder
public class {EntityName} extends BaseEntity {

    // ==================== Fields ====================

    @NotBlank
    @Size(max = 100)
    @Column(nullable = false, length = 100)
    private String name;

    @Email
    @Column(unique = true)
    private String email;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Status status;

    @Embedded
    private Address address;

    // ==================== Relationships ====================

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "parent_id")
    private ParentEntity parent;

    @OneToMany(mappedBy = "parent", cascade = CascadeType.ALL, orphanRemoval = true)
    @Builder.Default
    private List<ChildEntity> children = new ArrayList<>();

    // ==================== Business Methods ====================

    public void updateName(String name) {
        validateName(name);
        this.name = name;
    }

    public void addChild(ChildEntity child) {
        children.add(child);
        child.setParent(this);
    }

    public void removeChild(ChildEntity child) {
        children.remove(child);
        child.setParent(null);
    }

    // ==================== Validation ====================

    private void validateName(String name) {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Name cannot be blank");
        }
    }

    // ==================== Factory Methods ====================

    public static {EntityName} create(String name, String email) {
        return {EntityName}.builder()
            .name(name)
            .email(email)
            .status(Status.ACTIVE)
            .build();
    }
}
```

### 4. Value Object (Embedded)

```java
package com.example.domain.model;

import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import lombok.*;

@Embeddable
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@EqualsAndHashCode
public class Address {

    @Column(length = 100)
    private String street;

    @Column(length = 50)
    private String city;

    @Column(length = 10)
    private String zipCode;

    public static Address of(String street, String city, String zipCode) {
        return new Address(street, city, zipCode);
    }
}
```

### 5. Enum Type

```java
package com.example.domain.model;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

@Getter
@RequiredArgsConstructor
public enum Status {
    ACTIVE("Active"),
    INACTIVE("Inactive"),
    DELETED("Deleted");

    private final String description;
}
```

### 6. Repository Interface

```java
package com.example.domain.repository;

import com.example.domain.model.{EntityName};
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface {EntityName}Repository extends JpaRepository<{EntityName}, Long> {

    Optional<{EntityName}> findByEmail(String email);

    List<{EntityName}> findByStatus(Status status);

    @Query("SELECT e FROM {EntityName} e WHERE e.name LIKE %:keyword%")
    List<{EntityName}> searchByName(@Param("keyword") String keyword);

    boolean existsByEmail(String email);
}
```

### 7. JPA Auditing Configuration

```java
package com.example.infrastructure.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

@Configuration
@EnableJpaAuditing
public class JpaConfig {
}
```

## Relationship Patterns

### OneToMany / ManyToOne (Bidirectional)

```java
// Parent side
@OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
private List<OrderItem> items = new ArrayList<>();

public void addItem(OrderItem item) {
    items.add(item);
    item.setOrder(this);
}

// Child side
@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "order_id", nullable = false)
private Order order;

void setOrder(Order order) {
    this.order = order;
}
```

### ManyToMany

```java
// Recommended: Manage intermediate table directly
@OneToMany(mappedBy = "user")
private List<UserRole> userRoles = new ArrayList<>();
```

### OneToOne

```java
@OneToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "profile_id")
private UserProfile profile;
```

## Annotation Reference

| Annotation | Usage |
|------------|-------|
| `@Entity` | Entity declaration |
| `@Table` | Table mapping |
| `@Id` | Primary key |
| `@GeneratedValue` | PK generation strategy |
| `@Column` | Column mapping |
| `@Enumerated` | Enum mapping |
| `@Embedded` | Value Object |
| `@ManyToOne` | N:1 relationship |
| `@OneToMany` | 1:N relationship |
| `@JoinColumn` | Foreign key |
| `@Version` | Optimistic locking |

## Validation Annotations

| Annotation | Usage |
|------------|-------|
| `@NotNull` | Cannot be null |
| `@NotBlank` | Cannot be empty string |
| `@Size` | Length constraint |
| `@Email` | Email format |
| `@Min/@Max` | Number range |
| `@Pattern` | Regex pattern |

## Verification Checklist

- [ ] Use `@NoArgsConstructor(access = PROTECTED)`
- [ ] Set `fetch = LAZY` on `@ManyToOne`
- [ ] Implement bidirectional relationship helper methods
- [ ] Use `@Embeddable` for Value Objects
- [ ] Implement business logic inside entity

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
JPA Entity Generated
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Entity: {EntityName}
Table: {table_name}
Relationships: {count}

Files Created:
- domain/model/{EntityName}.java
- domain/repository/{EntityName}Repository.java

- BaseEntity inheritance
- Validation annotations
- Business methods

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
