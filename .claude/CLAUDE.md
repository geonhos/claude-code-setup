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

## Agent 사용 규칙

### Git 작업

| 작업 | 도구 |
|------|------|
| Commit | `git-ops` 또는 `/git_commit` |
| Branch | `git-ops` 또는 `/git_branch` |
| PR | `/git_pr` |
| 분석 | `/git_analyze` |

### 복잡한 작업

| 상황 | Agent |
|------|-------|
| 요구사항 불명확 | `requirements-analyst` |
| 계획 수립 필요 | `plan-architect` → `plan-feedback` |
| 다중 도메인 | `orchestrator` |

### 개발 작업

| 도메인 | Agent | Skill |
|--------|-------|-------|
| Python/FastAPI | `ai-expert` | `/fastapi_setup`, `/python_best_practices` |
| React | `frontend-dev` | `/react_setup`, `/react_best_practices` |
| Spring Boot | `backend-dev` | `/spring_boot_setup`, `/spring_best_practices` |
| AI/ML | `ai-expert` | `/mlflow_setup`, `/langchain_setup` |

### 품질 관리

| 작업 | Agent | Skill |
|------|-------|-------|
| 테스트 계획 | `qa-planner` | `/test_plan_template` |
| 테스트 실행 | `qa-executor` | `/test_runner` |
| 테스트 복구 | `qa-healer` | - |
| 보안 검토 | `security-analyst` | - |
| 커버리지 | - | `/coverage_report` |

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

### 푸시 전
- [ ] 모든 테스트 통과
- [ ] 민감 정보 제외 확인
- [ ] 보안 관련 변경 시 `security-analyst` 실행

---

## 커밋 메시지 형식

```
[Phase X] 요약

섹션:
- 변경 내용

Refs #이슈번호

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

---

## 금지 사항

- 전역 패키지 설치 (`pip install --user`, `npm install -g`)
- `.venv/`, `node_modules/` 커밋
- `.env` 파일 커밋
- `sudo pip install`
