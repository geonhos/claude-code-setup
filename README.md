# Claude Code Agents & Skills

Claude Code를 위한 멀티에이전트 시스템 플러그인 v4.1.0 — Harness Engineering Edition (Learning Loop)

## 설치

```
/plugin marketplace add geonhos/claude-code-setup
/plugin add multi-agent-system
```

## 철학

- **한 번의 프롬프트로 끝낸다** — `/ship`으로 plan → issue → execute → review → test → PR 전체 파이프라인 실행
- **덜 만들고, 핵심만 잘 만든다** — 6개 에이전트, 13개 스킬, 명확한 라우팅
- **학습하는 하네스** — 훅이 자동으로 피드백 신호를 수집하고, `/retro`가 주간 리포트와 draft 메모를 생성하며, `/retro-review`를 통한 사람 승인 뒤에만 시스템이 변경됨
- **Kent Beck TDD 원칙 내장** — Red-Green-Refactor 사이클 강제

---

## /ship — 하네스 파이프라인

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

## Learning Loop — 하네스의 자기 개선

```
[평일]  사용자 ──► /ship 또는 개별 스킬 사용
           │
           └──► 훅이 자동 수집:
                 • UserPromptSubmit 좌절 키워드
                 • PostToolUse /ship 직후 재수정
                 • PreToolUse git revert / reset --hard
                 → logs/feedback-signals.jsonl

[주 1회 자동]  /retro  (또는 /schedule "weekly mon 09:00" /retro)
                  │
                  ├──► logs/retro-YYYY-WW.md    리포트
                  └──► memory/_draft/*.md       draft 메모

[주 1회 수동 5분]  /retro-review
                     │
                     └──► 승인/기각/수정/보류
                          → 승인만 memory/ 로 이동하여 장기 기억화
```

**중요**: Layer 1(수집) · Layer 2(분석) 자동, **Layer 3(반영)는 반드시 사람**. 승인 없이는 하네스가 스스로 바뀌지 않음.

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

## Skills (13개)

### Harness

| Skill | 설명 |
|-------|------|
| [`/ship`](skills/ship/SKILL.md) | **전체 파이프라인** — plan → issue → execute → review → test → PR |

### Learning Loop (신규)

| Skill | 설명 |
|-------|------|
| [`/retro`](skills/retro/SKILL.md) | 주간 회고 — feedback-signals.jsonl 분석 + 리포트 + draft 메모 생성 |
| [`/retro-review`](skills/retro-review/SKILL.md) | draft 메모를 승인/기각/수정/보류 (사람 게이트) |

### Workflow

| Skill | 설명 |
|-------|------|
| [`/plan`](skills/plan/SKILL.md) | 접근법 탐색 + 실행 계획 + 점수 매기기 |
| [`/debug`](skills/debug/SKILL.md) | 가설 기반 체계적 디버깅 |

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

## 워크플로우 가이드 ("3파일 룰")

건드릴 파일 수로 선택:

| 파일 수 | 권장 플로우 |
|---------|-------------|
| 1–2 파일 | 직접 작업 → `git commit` (pre-commit 훅 자동 검증) |
| 3–5 파일 | `/plan` → 승인 → `/tdd` (핵심 경로) → `/commit` |
| 6+ 파일 또는 크로스 도메인 | `/ship "..."` (풀 파이프라인) |

### 조합 패턴

| 패턴 | 시나리오 | 순서 |
|------|---------|------|
| A | 대형 기능 | `/plan` → `/tdd` (task별) → `/review` → `/commit` → `/pr` |
| B | 빠른 버그픽스 | `/debug` → `/tdd` (재현 테스트) → `/commit` |
| C | 원샷 배포 | `/ship "feature"` |
| D | 하네스 자기 개선 | `/retro-review` → 스킬 수정 → CHANGELOG (expected/verify) |

### 안티패턴

- ❌ 오타 수정에 `/ship`  → ✅ 직접 수정 + `git commit`
- ❌ `/plan` 생략 후 `/ship`  → ✅ 복잡한 기능은 `/plan` 먼저
- ❌ `/retro` 결과 자동 반영  → ✅ 반드시 `/retro-review` 거쳐라

---

## Hooks (7 이벤트)

| Hook | 설명 |
|------|------|
| `SessionStart` | slim 배너 + 대기 중 draft 메모 수 알림 |
| `UserPromptSubmit` | 좌절 키워드 탐지 → feedback-signals.jsonl |
| `PreToolUse(Bash)` | `git commit` 감지 → pre-commit.sh 실행 (기본: compile only) |
| `PostToolUse(Edit/Write/Bash)` | post-ship 재수정 / git revert 탐지 → feedback-signals.jsonl |
| `Stop` | 변경 사항 있을 때만 검증 넛지 (read-only 턴 skip) |
| `SubagentStart` | 에이전트 활동 로깅 |
| `SubagentStop` | 에이전트 완료 + 트랜스크립트 분석 → agent-progress.jsonl |

### 환경 변수 (Kill Switches)

| 변수 | 기본 | 효과 |
|------|------|------|
| `HARNESS_AUTO_FEEDBACK` | `1` | `0` = 신호 수집 전체 off |
| `HARNESS_SKIP_PRECOMMIT` | `0` | `1` = pre-commit 검증 완전 skip |
| `HARNESS_RUN_TESTS` | `0` | `1` = pre-commit 시 풀 테스트 실행 (기본은 compile only) |

---

## 디렉토리 구조

```
plugin.json              # 플러그인 매니페스트 (v4.1.0)

harness/
└── progress.md          # /ship 파이프라인 진행 추적

hooks/
├── hooks.json           # 훅 이벤트 설정 (7 이벤트)
├── startup.sh           # SessionStart: slim 배너 + draft 알림
├── feedback-capture.sh  # UserPromptSubmit + PostToolUse: 암묵 신호
├── pre-commit-guard.sh  # PreToolUse: git commit stdin 파싱
├── pre-commit.sh        # 빠른 검증 (기본 compile only, HARNESS_RUN_TESTS=1로 풀 테스트)
├── stop-verify.sh       # Stop: 변경이 있을 때만 넛지
└── agent-progress.sh    # SubagentStart/Stop: 진행 추적

agents/                  # 에이전트 정의 (6개)
├── pipeline/            # plan-architect
├── execution/           # backend-dev, frontend-dev, ai-expert
└── quality/             # code-reviewer, qa-executor

skills/                  # 스킬 정의 (13개)
├── ship/                # Harness: 전체 파이프라인
├── retro/               # Learning: 주간 회고 + draft 생성
├── retro-review/        # Learning: draft 승인 게이트
├── plan/ debug/         # Workflow
├── tdd/ test/ review/   # Quality
├── commit/ pr/          # Git
└── {react|spring|python}_best_practices/

memory/
├── _draft/              # /retro가 생성하는 draft 메모 (승인 대기)
└── MEMORY.md            # 승인된 메모 인덱스

logs/
├── feedback-signals.jsonl   # 암묵 bad 신호
├── agent-progress.jsonl     # 에이전트 활동
├── agent-progress-summary.md
├── retro-YYYY-WW.md         # /retro 주간 리포트
└── retro-decisions.jsonl    # /retro-review 결정 기록
```

---

## 주요 변경사항

### v4.1.0 - Learning Loop
- **`/retro`, `/retro-review` 스킬 신규** — 주간 회고 + 사람 승인 게이트
- **feedback-capture.sh 훅 신규** — 좌절 키워드, post-ship 재수정, git revert 자동 포착
- **startup.sh 대폭 축소** — 중복 라우팅 테이블 제거 (세션당 ~1200 토큰 절감)
- **pre-commit 기본값 변경** — 풀 빌드/테스트 → compile/typecheck only (HARNESS_RUN_TESTS=1로 opt-in)
- **pre-commit-guard.sh stdin 수정** — `$TOOL_INPUT` env var → stdin JSON (이전에 훅이 작동 안 했음)
- **stop-verify.sh 조건부화** — git diff 없으면 skip
- **hooks 경로 `$CLAUDE_PLUGIN_ROOT` 사용** — 표준화
- **duplicate marketplace.json 제거** — 루트 파일 dead code 정리

### v4.0.0 - Harness Engineering Edition
- `/ship` 스킬 신규, 하네스 파이프라인 도입
- Stop hook 추가, harness/progress.md 추적

[전체 변경 이력 → CHANGELOG.md](CHANGELOG.md)
