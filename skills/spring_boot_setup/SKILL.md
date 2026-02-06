---
name: spring_boot_setup
description: Sets up Spring Boot project with Gradle, DDD structure, and essential configurations. Creates production-ready project skeleton.
model: haiku
---

# Spring Boot Project Setup Skill

Sets up a Spring Boot project with DDD structure and working state.

## Prerequisites

- Java 17+ installed
- Gradle 8+ (wrapper recommended)
- Git initialized

## Workflow

### 1. Verify Project Information

```bash
# Check current directory
pwd
PROJECT_NAME=$(basename $(pwd))
echo "Project: $PROJECT_NAME"

# Check Java version
java --version
```

### 2. Create Project with Spring Initializr

**Option A: Using curl**
```bash
curl https://start.spring.io/starter.zip \
  -d type=gradle-project \
  -d language=java \
  -d bootVersion=3.2.0 \
  -d baseDir=${PROJECT_NAME} \
  -d groupId=com.example \
  -d artifactId=${PROJECT_NAME} \
  -d name=${PROJECT_NAME} \
  -d packageName=com.example.${PROJECT_NAME} \
  -d javaVersion=17 \
  -d dependencies=web,data-jpa,validation,lombok,h2,actuator \
  -o project.zip && unzip project.zip && rm project.zip
```

**Option B: Manual creation**
Create the structure manually as shown below

### 3. Create DDD Project Structure

```bash
# Base package path
BASE_PKG="src/main/java/com/example/${PROJECT_NAME}"

# DDD layer directories
mkdir -p ${BASE_PKG}/{domain,application,infrastructure,interfaces}
mkdir -p ${BASE_PKG}/domain/{model,repository,service,event}
mkdir -p ${BASE_PKG}/application/{command,query,service}
mkdir -p ${BASE_PKG}/infrastructure/{persistence,config,external}
mkdir -p ${BASE_PKG}/interfaces/{rest,dto}

# Test directories
TEST_PKG="src/test/java/com/example/${PROJECT_NAME}"
mkdir -p ${TEST_PKG}/{domain,application,infrastructure,interfaces}
mkdir -p ${TEST_PKG}/architecture

# Resource directories
mkdir -p src/main/resources/{db/migration,static,templates}
mkdir -p src/test/resources
```

### 4. Configure build.gradle

```groovy
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.2.0'
    id 'io.spring.dependency-management' version '1.1.4'
}

group = 'com.example'
version = '0.0.1-SNAPSHOT'

java {
    sourceCompatibility = '17'
}

configurations {
    compileOnly {
        extendsFrom annotationProcessor
    }
}

repositories {
    mavenCentral()
}

dependencies {
    // Spring Boot Starters
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'org.springframework.boot:spring-boot-starter-validation'
    implementation 'org.springframework.boot:spring-boot-starter-actuator'

    // Lombok
    compileOnly 'org.projectlombok:lombok'
    annotationProcessor 'org.projectlombok:lombok'

    // Database
    runtimeOnly 'com.h2database:h2'
    // runtimeOnly 'org.postgresql:postgresql'

    // Testing
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
    testImplementation 'com.tngtech.archunit:archunit-junit5:1.2.1'

    // Test Lombok
    testCompileOnly 'org.projectlombok:lombok'
    testAnnotationProcessor 'org.projectlombok:lombok'
}

tasks.named('test') {
    useJUnitPlatform()
}
```

### 5. Configure application.yml

**src/main/resources/application.yml:**
```yaml
spring:
  application:
    name: ${PROJECT_NAME}

  datasource:
    url: jdbc:h2:mem:testdb
    driver-class-name: org.h2.Driver
    username: sa
    password:

  jpa:
    hibernate:
      ddl-auto: create-drop
    show-sql: true
    properties:
      hibernate:
        format_sql: true

  h2:
    console:
      enabled: true
      path: /h2-console

management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics

logging:
  level:
    com.example: DEBUG
    org.hibernate.SQL: DEBUG
```

### 6. ArchUnit Architecture Test

**src/test/java/.../architecture/ArchitectureTest.java:**
```java
package com.example.${PROJECT_NAME}.architecture;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.*;
import static com.tngtech.archunit.library.Architectures.layeredArchitecture;

@AnalyzeClasses(
    packages = "com.example.${PROJECT_NAME}",
    importOptions = ImportOption.DoNotIncludeTests.class
)
class ArchitectureTest {

    @ArchTest
    static final ArchRule layerDependencies = layeredArchitecture()
        .consideringAllDependencies()
        .layer("Interfaces").definedBy("..interfaces..")
        .layer("Application").definedBy("..application..")
        .layer("Domain").definedBy("..domain..")
        .layer("Infrastructure").definedBy("..infrastructure..")

        .whereLayer("Interfaces").mayNotBeAccessedByAnyLayer()
        .whereLayer("Application").mayOnlyBeAccessedByLayers("Interfaces")
        .whereLayer("Domain").mayOnlyBeAccessedByLayers("Application", "Infrastructure")
        .whereLayer("Infrastructure").mayNotBeAccessedByAnyLayer();

    @ArchTest
    static final ArchRule domainShouldNotDependOnInfrastructure =
        noClasses()
            .that().resideInAPackage("..domain..")
            .should().dependOnClassesThat().resideInAPackage("..infrastructure..");

    @ArchTest
    static final ArchRule controllersShouldBeInInterfacesPackage =
        classes()
            .that().haveSimpleNameEndingWith("Controller")
            .should().resideInAPackage("..interfaces.rest..");
}
```

### 7. Sample Domain Entity

**src/main/java/.../domain/model/BaseEntity.java:**
```java
package com.example.${PROJECT_NAME}.domain.model;

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
}
```

### 8. Health Check Controller

**src/main/java/.../interfaces/rest/HealthController.java:**
```java
package com.example.${PROJECT_NAME}.interfaces.rest;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class HealthController {

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of(
            "status", "UP",
            "service", "${PROJECT_NAME}"
        ));
    }
}
```

### 9. Run Tests

```bash
# Set Gradle Wrapper permissions
chmod +x gradlew

# Build and test
./gradlew build

# Run tests only
./gradlew test

# Run application (verification)
./gradlew bootRun
```

### 10. Initial Commit

```bash
git add .
git commit -m "[Phase 0] Initialize Spring Boot project

Project Structure:
- Spring Boot 3.2 with Gradle
- DDD layered architecture (domain, application, infrastructure, interfaces)
- ArchUnit architecture tests

Dependencies:
- Spring Web, Data JPA, Validation
- Lombok, H2, Actuator

Configuration:
- application.yml with H2 in-memory database
- JPA auditing enabled

Verification:
- All tests passing
- ArchUnit constraints validated
"
```

## Generated Structure

```
${PROJECT_NAME}/
├── build.gradle
├── settings.gradle
├── gradlew
├── gradlew.bat
├── src/
│   ├── main/
│   │   ├── java/com/example/${PROJECT_NAME}/
│   │   │   ├── Application.java
│   │   │   ├── domain/
│   │   │   │   ├── model/
│   │   │   │   │   └── BaseEntity.java
│   │   │   │   ├── repository/
│   │   │   │   ├── service/
│   │   │   │   └── event/
│   │   │   ├── application/
│   │   │   │   ├── command/
│   │   │   │   ├── query/
│   │   │   │   └── service/
│   │   │   ├── infrastructure/
│   │   │   │   ├── persistence/
│   │   │   │   ├── config/
│   │   │   │   └── external/
│   │   │   └── interfaces/
│   │   │       ├── rest/
│   │   │       │   └── HealthController.java
│   │   │       └── dto/
│   │   └── resources/
│   │       ├── application.yml
│   │       └── db/migration/
│   └── test/
│       └── java/com/example/${PROJECT_NAME}/
│           └── architecture/
│               └── ArchitectureTest.java
└── .gitignore
```

## Verification Checklist

- [ ] `./gradlew build` succeeds
- [ ] `./gradlew test` all tests pass
- [ ] ArchUnit architecture tests pass
- [ ] `./gradlew bootRun` then verify `http://localhost:8080/api/health` responds

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Spring Boot Project Setup Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Project: ${PROJECT_NAME}
Java: 17
Spring Boot: 3.2.0
Build: Gradle

- DDD structure created
- ArchUnit tests configured
- Health endpoint available
- All tests passing

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Next Steps:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Define domain entities in domain/model/
2. Create repositories in domain/repository/
3. Implement services in application/service/
4. Add REST endpoints in interfaces/rest/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
