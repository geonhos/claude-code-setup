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

## Agent 자동 사용 규칙

### 키워드 기반 자동 트리거

다음 키워드가 감지되면 해당 에이전트를 **자동으로** 사용:

| 키워드/패턴 | Agent | 우선순위 |
|------------|-------|----------|
| commit, branch, merge, push, git, gh, worktree, 커밋, 브랜치, 머지, 푸시, 풀리퀘, 이슈 생성, PR 생성, 워크트리, 병렬 브랜치 | `git-ops` | 높음 |
| security, 보안, 취약점, OWASP, XSS, SQL injection, 인증, 인가, 암호화, 해킹 | `security-analyst` | 높음 |
| test, 테스트, QA, 커버리지, 품질, 검증, 단위테스트, 통합테스트, e2e, Playwright, UI테스트 | `qa-planner` → `qa-executor` | 높음 |
| review, PR, 리뷰, 코드리뷰, 검토, pull request | `pr-reviewer` | 높음 |
| 문서 리뷰, 문서 검토, 요구사항 리뷰, 스펙 리뷰, doc review, spec review | `docs-reviewer` | 높음 |
| Docker, K8s, Kubernetes, CI/CD, 배포, 컨테이너, 파이프라인, 인프라, 쿠버네티스 | `devops-engineer` | 높음 |
| DB, database, 스키마, 쿼리, 인덱스, 데이터베이스, 마이그레이션, 테이블 | `database-expert` | 높음 |
| performance, 성능, 속도, 느림, 병목, 최적화, 프로파일링, 지연, 레이턴시 | `performance-analyst` | 중간 |
| refactor, 리팩토링, 정리, 개선, 레거시, 기술부채, 클린업 | `refactoring-expert` | 중간 |
| docs, 문서, 문서화, API docs, README, 가이드, 설명서 | `docs-writer` | 중간 |
| requirements, 요구사항, 기능 정의, 스펙, 명세 | `requirements-analyst` | 높음 |
| plan, 계획, 설계, 아키텍처, 구조, 디자인 | `plan-architect` | 높음 |
| AI, ML, 머신러닝, 딥러닝, LLM, 모델, 학습, 임베딩 | `ai-expert` | 높음 |
| React, 컴포넌트, 프론트엔드, UI, 화면, 페이지, 폼 | `frontend-dev` | 높음 |
| Spring, Java, API, 백엔드, 서버, 엔드포인트, 컨트롤러 | `backend-dev` | 높음 |

### 자동 파이프라인

복합 작업 시 자동으로 에이전트 체인 실행:

```
새 기능 구현:
  requirements-analyst → docs-reviewer → plan-architect → [execution agents] → qa-planner → qa-executor

코드 변경 완료 후:
  code-reviewer → qa-executor → (보안 관련 시) security-analyst

문서/요구사항 작성 완료 후:
  docs-reviewer

PR 생성 전:
  pr-reviewer → git-ops
```

### 필수 사용 (MUST USE)

**CRITICAL**: 아래 상황에서는 반드시 해당 Agent를 사용해야 합니다. Bash로 직접 실행하지 마세요.

| 상황 | Agent | 이유 |
|------|-------|------|
| git commit, branch, merge, push, gh pr/issue | `git-ops` | Git Flow 규칙 준수 |
| 코드 작성 완료 후 | `code-reviewer` + `qa-planner` + `qa-executor` | 품질 보장 |
| 문서/요구사항 작성 완료 후 | `docs-reviewer` | 문서 품질 보장 |
| 커밋 전 (보안 관련 변경) | `security-analyst` | 보안 검증 |
| PR 생성 시 | `pr-reviewer` | PR 리뷰 |
| 성능 이슈 언급 시 | `performance-analyst` | 성능 분석 |

---

## Agent 사용 규칙

### Git 작업 (MUST delegate to git-ops)

**중요**: 모든 Git 작업은 `git-ops` 에이전트에 위임해야 합니다. 직접 `git` 명령을 실행하지 마세요.

| 작업 | 방법 | 비고 |
|------|------|------|
| Commit | `git-ops` 에이전트 | Conventional Commits 준수 |
| Branch | `git-ops` 에이전트 | Git Flow 브랜치 네이밍 |
| Merge | `git-ops` 에이전트 | 적절한 전략 선택 |
| Push | `git-ops` 에이전트 | 안전성 검증 포함 |
| PR 생성 (gh pr) | `git-ops` 에이전트 | 템플릿 적용 |
| Issue 생성 (gh issue) | `git-ops` 에이전트 | 이슈 관리 |
| Release (gh release) | `git-ops` 에이전트 | 버전 관리 |
| Worktree | `git-ops` 에이전트 | 병렬 개발 지원 |
| 분석 | `/git_analyze` | 변경사항 분석 |

### 복잡한 작업

| 상황 | Agent |
|------|-------|
| 요구사항 불명확 | `requirements-analyst` → `docs-reviewer` |
| 계획 수립 필요 | `plan-architect` → `plan-feedback` |
| 다중 도메인 | `orchestrator` |

### 개발 작업

| 도메인 | Agent | Skill |
|--------|-------|-------|
| Python/FastAPI | `ai-expert` | `/fastapi_setup`, `/python_best_practices` |
| React | `frontend-dev` | `/react_setup`, `/react_best_practices` |
| Spring Boot | `backend-dev` | `/spring_boot_setup`, `/spring_best_practices` |
| AI/ML | `ai-expert` | `/mlflow_setup`, `/langchain_setup` |
| DevOps/Infra | `devops-engineer` | `/docker_setup` |
| Database | `database-expert` | `/alembic_migration`, `/jpa_entity` |

### 품질 관리

| 작업 | Agent | Skill |
|------|-------|-------|
| 테스트 계획 | `qa-planner` | `/test_plan_template` |
| 테스트 실행 | `qa-executor` | `/test_runner` |
| 테스트 복구 | `qa-healer` | - |
| 보안 검토 | `security-analyst` | - |
| 코드 리뷰 | `code-reviewer` | - |
| 문서 리뷰 | `docs-reviewer` | - |
| PR 리뷰 | `pr-reviewer` | Gemini CLI 통합 |
| 성능 분석 | `performance-analyst` | - |
| 커버리지 | - | `/coverage_report` |

### 코드 품질

| 작업 | Agent |
|------|-------|
| 리팩토링 | `refactoring-expert` |
| 문서 작성 | `docs-writer` |
| 문서 리뷰 | `docs-reviewer` |

### 작업 로깅

| 작업 | Agent | 설명 |
|------|-------|------|
| 작업 전 로깅 | `reporter` | 에이전트 작업 시작 전 계획 기록 |
| 작업 후 요약 | `reporter` | 완료된 작업 내용 요약 및 결과 기록 |
| 실행 리포트 | `reporter` | 전체 파이프라인 실행 결과 종합 |

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
- [ ] 변경사항 검토 (`/git_analyze`)
- [ ] 코드 리뷰 (`pr-reviewer`)

### 푸시 전
- [ ] 모든 테스트 통과
- [ ] 민감 정보 제외 확인
- [ ] 보안 관련 변경 시 `security-analyst` 실행

### PR 생성 전
- [ ] `pr-reviewer` 실행 (Gemini CLI 리뷰)
- [ ] 문서 업데이트 확인

---

## 커밋 메시지 형식

커밋 메시지는 `/git_commit` skill의 형식을 따릅니다.
자세한 내용: [/git_commit](.claude/skills/git/git_commit/SKILL.md)

---

## 금지 사항

- 전역 패키지 설치 (`pip install --user`, `npm install -g`)
- `.venv/`, `node_modules/` 커밋
- `.env` 파일 커밋
- `sudo pip install`
