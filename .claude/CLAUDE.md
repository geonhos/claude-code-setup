# 개발 지침

## 환경 설정

### Python
```bash
python -m venv .venv
source .venv/bin/activate  # macOS/Linux
pip install -r requirements.txt
```

### Node.js
```bash
npm install  # 로컬 설치만
npx <tool>   # CLI 도구 실행
```

---

## 핵심 워크플로우 (6단계)

모든 복잡한 작업은 다음 6단계를 따릅니다:

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ 1. 요구사항   │───▶│ 2. Plan 생성 │───▶│ 3. Plan 검증 │
│    수집       │    │              │    │  (자체검증)   │
│requirements- │    │plan-architect│    │              │
│   analyst    │    │              │    │              │
└──────────────┘    └──────────────┘    └──────┬───────┘
                                               │
                    ┌──────────────────────────┘
                    ▼
┌──────────────────────────────────────────────────────┐
│              4. Orchestrator (병렬 조율)              │
└───────────────────────┬──────────────────────────────┘
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
   [Agent A]       [Agent B]       [Agent C]  ← 5. 병렬 실행
        └───────────────┼───────────────┘
                        ▼
┌──────────────────────────────────────────────────────┐
│     6. 구현 검증 (code-reviewer + qa-executor)        │
└──────────────────────────────────────────────────────┘
```

| 단계 | 에이전트 | 역할 | 필수 |
|-----|---------|------|-----|
| 1 | `requirements-analyst` | 요구사항 수집 및 정제 | O |
| 2 | `plan-architect` | 실행 계획 수립 | O |
| 3 | `plan-architect` | Plan 자체 검증 (score >= 8) | O |
| 4 | `orchestrator` | Agent 병렬 실행 조율 | O |
| 5 | execution agents | 도메인별 병렬 구현 | O |
| 6 | `code-reviewer` + `qa-executor` | 코드/테스트 검증 | O |

---

## 에이전트 목록 (15개)

### Pipeline (3개)
| 에이전트 | 역할 |
|---------|------|
| `requirements-analyst` | 요구사항 수집 및 정제 |
| `plan-architect` | 실행 계획 수립 + 자체 검증 |
| `orchestrator` | Plan 기반 Agent 병렬 실행 조율 |

### Execution (7개)
| 에이전트 | 역할 | 트리거 키워드 |
|---------|------|--------------|
| `frontend-dev` | React/TypeScript 구현 | React, UI, 컴포넌트, 프론트엔드 |
| `backend-dev` | Java/Spring 구현 | API, Spring, 백엔드, 서버 |
| `ai-expert` | Python AI/ML 구현 | ML, AI, LLM, 모델 |
| `database-expert` | DB 스키마/쿼리 | DB, 스키마, 쿼리, 마이그레이션 |
| `devops-engineer` | 인프라/CI/CD | Docker, K8s, 배포, CI/CD |
| `docs-writer` | 문서 작성 | 문서, README, API docs |
| `refactoring-expert` | 리팩토링 | refactor, 정리, 개선 |

### Quality (5개)
| 에이전트 | 역할 | 트리거 키워드 |
|---------|------|--------------|
| `code-reviewer` | 코드/문서 품질 검증 | review, 리뷰, 검토 |
| `qa-executor` | 테스트 계획/실행/분석 | test, 테스트, QA |
| `security-analyst` | 보안 검증 | security, 보안, 취약점 |
| `performance-analyst` | 성능 분석 | performance, 성능, 느림 |
| `debug-specialist` | 디버깅 | debug, 버그, 에러 |

---

## 자동 트리거 규칙

### 키워드 기반 자동 트리거

| 키워드/패턴 | Agent | 우선순위 |
|------------|-------|----------|
| 요구사항, requirements, 기능 정의 | `requirements-analyst` | 높음 |
| plan, 계획, 설계, 아키텍처 | `plan-architect` | 높음 |
| React, 컴포넌트, 프론트엔드, UI | `frontend-dev` | 높음 |
| Spring, Java, API, 백엔드 | `backend-dev` | 높음 |
| AI, ML, LLM, 모델, 학습 | `ai-expert` | 높음 |
| DB, database, 스키마, 쿼리 | `database-expert` | 높음 |
| Docker, K8s, CI/CD, 배포 | `devops-engineer` | 높음 |
| review, 리뷰, 코드리뷰, 검토 | `code-reviewer` | 높음 |
| test, 테스트, QA | `qa-executor` | 높음 |
| security, 보안, 취약점 | `security-analyst` | 높음 |
| performance, 성능, 느림 | `performance-analyst` | 중간 |
| debug, 버그, 에러, crash | `debug-specialist` | 높음 |
| refactor, 리팩토링, 정리 | `refactoring-expert` | 중간 |
| 문서, docs, README | `docs-writer` | 중간 |

### 필수 검증 파이프라인 (Mandatory Verify)

코드 구현 완료 후 **반드시** 다음 검증 수행:

| 순서 | 에이전트 | 조건 | 통과 기준 |
|-----|---------|------|----------|
| 1 | `code-reviewer` | 항상 | Critical 이슈 0개 |
| 2 | `qa-executor` | 항상 | 모든 테스트 통과 |
| 3 | `security-analyst` | 조건부 (인증/인가 관련) | Critical 취약점 0개 |

---

## Plan 검증 기준

plan-architect가 Plan 생성 후 자체 검증 수행:

| 항목 | 점수 | 기준 |
|------|-----|------|
| 완전성 | 0-2 | 모든 요구사항 → 태스크 매핑 |
| 의존성 | 0-2 | 순환 없음, 순서 올바름 |
| 에이전트 할당 | 0-2 | 적합한 에이전트 할당 |
| 실현 가능성 | 0-2 | 구체적, 실행 가능 |
| 테스트 가능성 | 0-2 | 검증 기준 정의됨 |
| **통과 기준** | **≥8** | |

---

## 스킬 목록 (32개)

### Git 스킬
| 스킬 | 설명 |
|------|------|
| `/git_commit` | 커밋 메시지 생성 |
| `/git_branch` | 브랜치 생성 |
| `/git_pr` | PR 생성 |
| `/git_issue` | 이슈 생성 |
| `/git_worktree` | 워크트리 관리 |
| `/git_analyze` | 변경사항 분석 |

### 개발 스킬
| 스킬 | 설명 |
|------|------|
| `/python_setup` | Python 프로젝트 설정 |
| `/fastapi_setup` | FastAPI 설정 |
| `/react_setup` | React 프로젝트 설정 |
| `/spring_boot_setup` | Spring Boot 설정 |

### 품질 스킬
| 스킬 | 설명 |
|------|------|
| `/test_runner` | 테스트 실행 |
| `/coverage_report` | 커버리지 리포트 |
| `/test_plan_template` | 테스트 계획 템플릿 |

### 워크플로우 스킬
| 스킬 | 설명 |
|------|------|
| `/brainstorm` | 설계 탐색 (3+ 대안) |
| `/task_breakdown` | 태스크 분해 |
| `/debug_workflow` | 디버깅 워크플로우 |
| `/verify_complete` | 완료 검증 |

---

## 체크리스트

### 작업 시작 전
- [ ] 가상환경 활성화
- [ ] 의존성 설치 확인
- [ ] 최신 코드 pull
- [ ] Feature branch 생성

### 커밋 전
- [ ] 테스트 실행 (`/test_runner`)
- [ ] 린터 실행
- [ ] 코드 리뷰 (`code-reviewer`)

### 푸시 전
- [ ] 모든 테스트 통과
- [ ] 민감 정보 제외 확인
- [ ] 보안 관련 변경 시 `security-analyst` 실행

---

## 커밋 메시지 형식

커밋 메시지는 `/git_commit` skill의 형식을 따릅니다.

```
[Phase {number}] {summary}

{Section}:
- {file}: {description}

Refs #{issue_number}
```

---

## Boundary Enforcement

모든 에이전트는 자신의 역할 범위 내에서만 작업합니다.

### Universal DO NOT Rules
- [ ] NEVER skip verification step
- [ ] NEVER implement outside domain boundary
- [ ] NEVER approve with critical issues
- [ ] NEVER skip plan validation

### Gate Functions

| Action | Required Check |
|--------|---------------|
| Plan 실행 | Plan 검증 통과 (score >= 8) |
| 코드 머지 | code-reviewer + qa-executor 통과 |
| 보안 관련 변경 | security-analyst 통과 |

---

## 금지 사항

- 전역 패키지 설치 (`pip install --user`, `npm install -g`)
- `.venv/`, `node_modules/` 커밋
- `.env` 파일 커밋
- `sudo pip install`
- 검증 단계 생략
