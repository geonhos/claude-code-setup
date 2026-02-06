# Agents Reference

## Overview

15 agents organized into 3 categories:
- **Pipeline** (3): Workflow orchestration
- **Execution** (7): Domain implementation
- **Quality** (5): Verification and analysis

---

## Pipeline Agents (3)

### requirements-analyst
- **Role**: Requirements collection and refinement
- **Triggers**: 요구사항, requirements, 기능 정의
- **Input**: User requests (natural language)
- **Output**: Structured requirements document
- **Key Activities**:
  - Clarify ambiguous requirements
  - Identify constraints and stakeholders
  - Define acceptance criteria
  - Prioritize (MoSCoW method)

### plan-architect
- **Role**: Execution planning + self-validation
- **Triggers**: plan, 계획, 설계, 아키텍처
- **Input**: Validated requirements
- **Output**: Validated execution plan (score >= 8)
- **Key Activities**:
  - Task breakdown
  - Agent assignment
  - Dependency mapping
  - Self-validation against 5 criteria

### orchestrator
- **Role**: Parallel execution coordination
- **Triggers**: (Internal - receives validated plans)
- **Input**: Validated plan from plan-architect
- **Output**: Dispatched tasks, progress tracking
- **Key Activities**:
  - Parallel group dispatch
  - Progress monitoring
  - Failure handling and retry
  - Trigger verification pipeline

---

## Execution Agents (7)

### frontend-dev
- **Role**: React/TypeScript implementation
- **Triggers**: React, UI, 컴포넌트, 프론트엔드
- **Tech Stack**: React, TypeScript, Next.js, CSS/Tailwind
- **Scope**:
  - Component implementation
  - State management
  - API integration (client-side)
  - UI/UX implementation

### backend-dev
- **Role**: Java/Spring backend implementation
- **Triggers**: API, Spring, 백엔드, 서버
- **Tech Stack**: Java, Spring Boot, REST APIs
- **Scope**:
  - API endpoint implementation
  - Business logic
  - Service layer
  - Controller layer

### ai-expert
- **Role**: Python AI/ML implementation
- **Triggers**: ML, AI, LLM, 모델, 학습
- **Tech Stack**: Python, PyTorch, TensorFlow, LangChain
- **Scope**:
  - Model training/inference
  - Data pipelines
  - LLM integration
  - ML experiments

### database-expert
- **Role**: Database schema and queries
- **Triggers**: DB, 스키마, 쿼리, 마이그레이션
- **Tech Stack**: PostgreSQL, MySQL, Redis, MongoDB
- **Scope**:
  - Schema design
  - Migration scripts
  - Query optimization
  - Database administration

### devops-engineer
- **Role**: Infrastructure and CI/CD
- **Triggers**: Docker, K8s, 배포, CI/CD
- **Tech Stack**: Docker, Kubernetes, GitHub Actions, Terraform
- **Scope**:
  - Container configuration
  - CI/CD pipelines
  - Infrastructure as Code
  - Deployment automation

### docs-writer
- **Role**: Technical documentation
- **Triggers**: 문서, README, API docs
- **Formats**: Markdown, OpenAPI, JSDoc, Sphinx
- **Scope**:
  - API documentation
  - README files
  - Architecture docs (ADR)
  - User guides

### refactoring-expert
- **Role**: Code refactoring and cleanup
- **Triggers**: refactor, 리팩토링, 정리, 개선
- **Scope**:
  - Code smell removal
  - Design pattern application
  - Performance optimization
  - Technical debt reduction

---

## Quality Agents (5)

### code-reviewer
- **Role**: Code and documentation quality
- **Triggers**: review, 리뷰, 코드리뷰, 검토
- **Priority**: HIGH (mandatory in verification)
- **Pass Criteria**: 0 Critical issues
- **Reviews**:
  - Code quality
  - Best practices
  - Security issues
  - Documentation accuracy

### qa-executor
- **Role**: Test planning and execution
- **Triggers**: test, 테스트, QA
- **Priority**: HIGH (mandatory in verification)
- **Pass Criteria**: All tests pass
- **Activities**:
  - Test plan creation
  - Test execution
  - Coverage analysis
  - Bug reporting

### security-analyst
- **Role**: Security verification
- **Triggers**: security, 보안, 취약점
- **Priority**: HIGH (conditional - auth/authz changes)
- **Pass Criteria**: 0 Critical vulnerabilities
- **Reviews**:
  - Authentication/Authorization
  - Input validation
  - Dependency vulnerabilities
  - OWASP Top 10

### performance-analyst
- **Role**: Performance analysis
- **Triggers**: performance, 성능, 느림
- **Priority**: MEDIUM
- **Activities**:
  - Performance profiling
  - Bottleneck identification
  - Optimization recommendations
  - Load testing

### debug-specialist
- **Role**: Debugging and troubleshooting
- **Triggers**: debug, 버그, 에러, crash
- **Priority**: HIGH (when issues occur)
- **Activities**:
  - Root cause analysis
  - Error reproduction
  - Fix recommendation
  - Regression prevention

---

## Trigger Priority

| Priority | Agents |
|----------|--------|
| HIGH | requirements-analyst, plan-architect, frontend-dev, backend-dev, ai-expert, database-expert, devops-engineer, code-reviewer, qa-executor, security-analyst, debug-specialist |
| MEDIUM | performance-analyst, refactoring-expert, docs-writer |

---

## Agent Boundaries

### Universal DO NOT Rules
- NEVER skip verification step
- NEVER implement outside domain boundary
- NEVER approve with critical issues
- NEVER skip plan validation

### Handoff Protocol
1. Complete assigned task
2. Report results to orchestrator
3. Include output artifacts
4. Flag any blockers or concerns
