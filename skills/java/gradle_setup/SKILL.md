---
name: gradle_setup
description: Configures Gradle build with multi-module support, dependency management, and common plugins for Java projects.
model: haiku
---

# Gradle Setup Skill

Configures Gradle build system and supports multi-module project setup.

## Prerequisites

- Java 17+ installed
- Project directory exists

## Workflow

### 1. Install Gradle Wrapper

```bash
# Generate Gradle Wrapper (skip if already exists)
gradle wrapper --gradle-version 8.5

# Set permissions
chmod +x gradlew
```

### 2. Configure settings.gradle

**Single Module:**
```groovy
rootProject.name = '${PROJECT_NAME}'
```

**Multi Module:**
```groovy
rootProject.name = '${PROJECT_NAME}'

include 'core'
include 'api'
include 'batch'
include 'common'
```

### 3. build.gradle (Root)

```groovy
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.2.0' apply false
    id 'io.spring.dependency-management' version '1.1.4'
    id 'jacoco'
}

allprojects {
    group = 'com.example'
    version = '0.0.1-SNAPSHOT'

    repositories {
        mavenCentral()
    }
}

subprojects {
    apply plugin: 'java'
    apply plugin: 'io.spring.dependency-management'
    apply plugin: 'jacoco'

    java {
        sourceCompatibility = '17'
    }

    configurations {
        compileOnly {
            extendsFrom annotationProcessor
        }
    }

    dependencies {
        // Lombok
        compileOnly 'org.projectlombok:lombok'
        annotationProcessor 'org.projectlombok:lombok'
        testCompileOnly 'org.projectlombok:lombok'
        testAnnotationProcessor 'org.projectlombok:lombok'

        // Testing
        testImplementation 'org.springframework.boot:spring-boot-starter-test'
    }

    test {
        useJUnitPlatform()
        finalizedBy jacocoTestReport
    }

    jacocoTestReport {
        dependsOn test
        reports {
            xml.required = true
            html.required = true
        }
    }
}
```

### 4. Module-specific build.gradle

**core/build.gradle (Domain Layer):**
```groovy
dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'org.springframework.boot:spring-boot-starter-validation'
}
```

**api/build.gradle (API Layer):**
```groovy
plugins {
    id 'org.springframework.boot'
}

dependencies {
    implementation project(':core')
    implementation project(':common')

    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-actuator'

    runtimeOnly 'com.h2database:h2'
    runtimeOnly 'org.postgresql:postgresql'
}
```

**common/build.gradle (Shared Utilities):**
```groovy
dependencies {
    implementation 'org.apache.commons:commons-lang3:3.14.0'
    implementation 'com.google.guava:guava:32.1.3-jre'
}
```

### 5. Dependency Management

**gradle/libs.versions.toml (Version Catalog):**
```toml
[versions]
spring-boot = "3.2.0"
lombok = "1.18.30"
archunit = "1.2.1"
testcontainers = "1.19.3"

[libraries]
spring-boot-web = { module = "org.springframework.boot:spring-boot-starter-web" }
spring-boot-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-test = { module = "org.springframework.boot:spring-boot-starter-test" }
lombok = { module = "org.projectlombok:lombok", version.ref = "lombok" }
archunit = { module = "com.tngtech.archunit:archunit-junit5", version.ref = "archunit" }
testcontainers-postgresql = { module = "org.testcontainers:postgresql", version.ref = "testcontainers" }

[bundles]
testing = ["spring-boot-test", "archunit"]

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
```

### 6. Useful Gradle Tasks

**Add to build.gradle:**
```groovy
// Aggregate test coverage report
task jacocoRootReport(type: JacocoReport) {
    dependsOn subprojects*.test

    additionalSourceDirs.from = files(subprojects.sourceSets.main.allSource.srcDirs)
    sourceDirectories.from = files(subprojects.sourceSets.main.allSource.srcDirs)
    classDirectories.from = files(subprojects.sourceSets.main.output)
    executionData.from = files(subprojects.jacocoTestReport.executionData)

    reports {
        html.required = true
        xml.required = true
    }
}

// Check dependency updates
task dependencyUpdates {
    doLast {
        println "Run: ./gradlew dependencyUpdates"
    }
}
```

### 7. Add .gitignore

```gitignore
# Gradle
.gradle/
build/
!gradle/wrapper/gradle-wrapper.jar

# IDE
.idea/
*.iml
.vscode/

# Compiled
*.class
*.jar
*.war

# Logs
*.log

# OS
.DS_Store
Thumbs.db
```

## Quick Reference

| Command | Description |
|---------|-------------|
| `./gradlew build` | Full build |
| `./gradlew test` | Run tests |
| `./gradlew clean` | Delete build artifacts |
| `./gradlew bootRun` | Run application |
| `./gradlew dependencies` | Dependency tree |
| `./gradlew :api:build` | Build specific module |
| `./gradlew jacocoRootReport` | Aggregate coverage |

## Generated Structure

```
${PROJECT_NAME}/
├── build.gradle              # Root build config
├── settings.gradle           # Module includes
├── gradle/
│   ├── wrapper/
│   │   ├── gradle-wrapper.jar
│   │   └── gradle-wrapper.properties
│   └── libs.versions.toml    # Version catalog
├── gradlew
├── gradlew.bat
├── core/
│   └── build.gradle
├── api/
│   └── build.gradle
└── common/
    └── build.gradle
```

## Verification Checklist

- [ ] `./gradlew build` succeeds
- [ ] `./gradlew test` passes
- [ ] Multi-module dependencies work correctly
- [ ] Version catalog applied

## Summary Report

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Gradle Setup Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Gradle: 8.5
Modules: [list]
Version Catalog: Configured

- Wrapper installed
- Multi-module configured
- JaCoCo coverage enabled

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
