# Claude Code Agents & Skills

Claude Code를 위한 멀티에이전트 시스템 플러그인 v4.0.0 — Harness Engineering Edition

## 설치

```
/plugin marketplace add geonhos/claude-code-setup
/plugin add multi-agent-system
```

## 철학

- **한 번의 프롬프트로 끝낸다** — `/ship`으로 plan → issue → execute → review → test → PR 전체 파이프라인 실행
- **덜 만들고, 핵심만 잘 만든다** — 6개 에이전트, 11개 스킬, 명확한 라우팅
- **Harness Engineering** — Anthropic 하네스 패턴 적용: 진행 추적, 자체 검증, 게이트 제어
- **Kent Beck TDD 원칙 내장** — Red-Green-Refactor 사이클 강제

---

## /ship — 하네스 파이프라인

**한 번의 프롬프트로 완전한 기능을 배포합니다:**

```
/ship "JWT 기반 사용자 인증 구현"
  │
  ├─ PLAN ──── plan-architect (자동 점수 ≥8)
  ├─ ISSUE ─── GitHub 이슈 생성
  ├─ BRANCH ── feature/issue-N-slug 브랜치
  ├─ EXECUTE ─ 도메인 에이전트 (backend/frontend/ai)
  ├─ REVIEW ── code-reviewer (Critical 0 필수)
  ├─ TEST ──── qa-executor (전체 테스트)
  └─ PR ────── Pull Request 생성
```

---

## Agents (6개)

| 상황 | Agent | 역할 |
|------|-------|------|
| 복잡한 작업, 설계, 아키텍처 | [`plan-architect`](agents/pipeline/plan-architect.md) | 실행 계획 수립 + 자체 검증 (score >= 8) |
| Java, Spring, API, JPA | [`backend-dev`](agents/execution/backend-dev.md) | Spring Boot DDD, 구현 + 테스트 |
| React, TypeScript, UI | [`frontend-dev`](agents/execution/frontend-dev.md) | React MVVM, 구현 + 테스트 |
| Python, ML, AI, LLM, RAG | [`ai-expert`](agents/execution/ai-expert.md) | Python ML/AI, 구현 + 테스트 |
| 코드 완성, 커밋 전, 리뷰 | [`code-reviewer`](agents/quality/code-reviewer.md) | 품질 리뷰, 수정하지 않음 |
| 테스트 실행, 실패 분석 | [`qa-executor`](agents/quality/qa-executor.md) | 테스트 실행/분석, 수정 제안 |

---

## Skills (11개)

### Harness

| Skill | 설명 |
|-------|------|
| [`/ship`](skills/ship/SKILL.md) | **전체 파이프라인** — plan → issue → execute → review → test → PR |

### Workflow

| Skill | 설명 |
|-------|------|
| [`/plan`](skills/plan/SKILL.md) | 접근법 탐색 + 실행 계획 + 점수 매기기 (`context: fork`) |
| [`/debug`](skills/debug/SKILL.md) | 가설 기반 체계적 디버깅 (`context: fork`) |

### Quality

| Skill | 설명 |
|-------|------|
| [`/tdd`](skills/tdd/SKILL.md) | Kent Beck Red-Green-Refactor |
| [`/test`](skills/test/SKILL.md) | 테스트 실행 + 커버리지 분석 |
| [`/review`](skills/review/SKILL.md) | 코드 리뷰 (code-reviewer 호출) |

### Git

| Skill | 설명 |
|-------|------|
| [`/commit`](skills/commit/SKILL.md) | 문서 점검 + 구조화된 커밋 |
| [`/pr`](skills/pr/SKILL.md) | PR 생성 + 템플릿 |

### Best Practices (자동 참조)

| Skill | 설명 |
|-------|------|
| `react_best_practices` | React/Next.js 코드 작성 시 자동 로드 |
| `spring_best_practices` | Spring Boot/JPA 코드 작성 시 자동 로드 |
| `python_best_practices` | Python/FastAPI 코드 작성 시 자동 로드 |

---

## 워크플로우

### 수동 (개별 스킬)
```
/plan → /tdd → /review → /test → /commit → /pr
```

### 자동 (하네스)
```
/ship "feature description"
  → 전체 파이프라인 자동 실행
```

---

## Hooks (5 이벤트)

| Hook | 설명 |
|------|------|
| `SessionStart` | 배너 + 라우팅 테이블 + 하네스 안내 주입 |
| `PreToolUse(Bash)` | `git commit` 감지 → 빌드 + 테스트 검증 |
| `Stop` | 작업 완료 시 검증 넛지 (코드/테스트/문서 확인) |
| `SubagentStart` | 에이전트 활동 로깅 |
| `SubagentStop` | 에이전트 완료 + 트랜스크립트 분석 |

---

## 디렉토리 구조

```
plugin.json              # 플러그인 매니페스트 (v4.0.0)

harness/
└── progress.md          # /ship 파이프라인 진행 추적

hooks/
├── hooks.json           # 훅 이벤트 설정 (5 이벤트)
├── startup.sh           # SessionStart: 배너 + 라우팅 + 하네스
├── pre-commit-guard.sh  # PreToolUse: git commit 감지
├── pre-commit.sh        # 빌드 + 테스트 검증 (7 에코시스템)
├── stop-verify.sh       # Stop: 작업 완료 검증 넛지
└── agent-progress.sh    # SubagentStart/Stop: 진행 추적

agents/                  # 에이전트 정의 (6개)
├── pipeline/            # plan-architect
├── execution/           # backend-dev, frontend-dev, ai-expert
└── quality/             # code-reviewer, qa-executor

skills/                  # 스킬 정의 (11개)
├── ship/                # Harness: 전체 파이프라인
├── plan/                # Workflow: 설계 + 분해 + 점수
├── debug/               # Workflow: 가설 기반 디버깅
├── tdd/                 # Quality: Red-Green-Refactor
├── test/                # Quality: 테스트 + 커버리지
├── review/              # Quality: 코드 리뷰
├── commit/              # Git: 구조화된 커밋
├── pr/                  # Git: PR 생성
├── react_best_practices/
├── spring_best_practices/
└── python_best_practices/
```

---

## 주요 변경사항

### v4.0.0 - Harness Engineering Edition
- **`/ship` 스킬 신규**: 한 번의 프롬프트로 plan → issue → branch → execute → review → test → PR 전체 파이프라인
- **스킬 리뉴얼**: 짧은 이름 (`/plan`, `/tdd`, `/test`, `/review`, `/debug`, `/commit`, `/pr`)
- **스킬 병합**: brainstorm + task_breakdown → `/plan`, test_runner + coverage_report → `/test`
- **`/review` 스킬 신규**: code-reviewer 에이전트 호출 스킬
- **Stop hook 추가**: 작업 완료 시 검증 넛지 (코드/테스트/문서 확인)
- **Harness progress 추적**: `harness/progress.md`로 크로스-세션 파이프라인 상태 추적
- 참고: Anthropic harness engineering, disler/claude-code-hooks-mastery, trailofbits/skills

[전체 변경 이력 → CHANGELOG.md](CHANGELOG.md)
