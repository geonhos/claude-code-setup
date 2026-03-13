# Claude Code Agents & Skills

Claude Code를 위한 멀티에이전트 시스템 플러그인 v3.0.1

## 설치

```
/plugin marketplace add geonhos/claude-code-setup
/plugin add multi-agent-system
```

## 철학

- **덜 만들고, 핵심만 잘 만든다** — 실제 사용 데이터 기반으로 필수 에이전트/스킬만 유지
- **컨텍스트 관리가 핵심** — 서브에이전트 격리, 명확한 라우팅 테이블
- **Kent Beck TDD 원칙 내장** — Red-Green-Refactor 사이클 강제
- **Plan 먼저, 실행은 나중에** — 복잡한 작업은 plan-architect로 설계 후 실행

---

## Agents (6개)

세션 시작 시 라우팅 테이블이 자동 주입됩니다:

| 상황 | Agent | 역할 |
|------|-------|------|
| 복잡한 작업, 설계, 아키텍처 | [`plan-architect`](agents/pipeline/plan-architect.md) | 실행 계획 수립 + 자체 검증 (score >= 8) |
| Java, Spring, API, JPA | [`backend-dev`](agents/execution/backend-dev.md) | Spring Boot DDD, 구현 + 테스트 |
| React, TypeScript, UI | [`frontend-dev`](agents/execution/frontend-dev.md) | React MVVM, 구현 + 테스트 |
| Python, ML, AI, LLM, RAG | [`ai-expert`](agents/execution/ai-expert.md) | Python ML/AI, 구현 + 테스트 |
| 코드 완성, 커밋 전, 리뷰 | [`code-reviewer`](agents/quality/code-reviewer.md) | 품질 리뷰, 수정하지 않음 |
| 테스트 실행, 실패 분석 | [`qa-executor`](agents/quality/qa-executor.md) | 테스트 실행/분석, 수정 제안 |

---

## Skills (12개)

### Workflow (자동 트리거)

| Skill | 설명 |
|-------|------|
| `brainstorm` | 설계 탐색 — 최소 3개 접근법 비교 (`context: fork`) |
| `task_breakdown` | 2-5분 단위 atomic 태스크 분해 (`context: fork`) |
| `verify_complete` | 태스크 완료 전 필수 검증 |
| `debug_workflow` | 체계적 가설 기반 디버깅 (`context: fork`) |

### Quality (사용자 호출)

| Skill | 설명 |
|-------|------|
| [`/tdd_workflow`](skills/tdd_workflow/SKILL.md) | Kent Beck Red-Green-Refactor |
| [`/test_runner`](skills/test_runner/SKILL.md) | 테스트 실행 + 결과 분석 |
| [`/coverage_report`](skills/coverage_report/SKILL.md) | 커버리지 분석 + 갭 식별 |

### Git (사용자 호출)

| Skill | 설명 |
|-------|------|
| [`/git_commit`](skills/git_commit/SKILL.md) | 문서 점검 + 구조화된 커밋 메시지 |
| [`/git_pr`](skills/git_pr/SKILL.md) | PR 생성 + 템플릿 |

### Best Practices (자동 참조)

| Skill | 설명 |
|-------|------|
| `react_best_practices` | React/Next.js 코드 작성 시 자동 로드 |
| `spring_best_practices` | Spring Boot/JPA 코드 작성 시 자동 로드 |
| `python_best_practices` | Python/FastAPI 코드 작성 시 자동 로드 |

---

## 워크플로우

```
Plan → Execute → Review → Test
```

| 단계 | 담당 | 설명 |
|------|------|------|
| Plan | `plan-architect` | 실행 계획 수립, 자체 검증 (score >= 8) |
| Execute | `backend-dev` / `frontend-dev` / `ai-expert` | 도메인별 구현 |
| Review | `code-reviewer` | 코드 품질 리뷰 |
| Test | `qa-executor` | 테스트 실행 + 검증 |

---

## 디렉토리 구조

```
plugin.json              # 플러그인 매니페스트
marketplace.json         # 마켓플레이스 정보

hooks/
├── hooks.json           # 훅 이벤트 설정
├── startup.sh           # SessionStart: 배너 + 라우팅 테이블 + 규칙
├── pre-commit.sh        # 빌드 + 테스트 검증 스크립트
├── pre-commit-guard.sh  # PreToolUse: git commit 감지 → pre-commit.sh 실행
└── agent-progress.sh    # SubagentStart/Stop: 진행 추적

agents/                  # 에이전트 정의 (6개)
├── pipeline/            # plan-architect
├── execution/           # backend-dev, frontend-dev, ai-expert
└── quality/             # code-reviewer, qa-executor

skills/                  # 스킬 정의 (12개)
├── brainstorm/          # Workflow
├── tdd_workflow/        # Quality
├── git_commit/          # Git
├── react_best_practices/ # Best Practices
└── ...
```

---

## 주요 변경사항

### v3.0.1 - 버그 수정 + 문서 점검
- **PreCommit → PreToolUse**: 지원되지 않던 `PreCommit` hook을 `PreToolUse` + `Bash` matcher로 교체
- **Playwright MCP 수정**: 존재하지 않던 `@anthropic-ai/mcp-server-playwright` → `@playwright/mcp@latest`
- **git_commit 스킬**: Documentation Freshness Check 단계 추가 (커밋 전 문서 최신화 점검)

### v3.0.0 - 실사용 기반 슬림화
- **에이전트**: 15개 → 6개 (-60%) — 실사용 데이터 기반 미사용 에이전트 삭제
- **스킬**: 32개 → 12개 (-63%) — 핵심 워크플로우/품질/Git만 유지
- **프로토콜**: 9개 → 1개 — 불필요한 레퍼런스 문서 삭제
- **라우팅 테이블**: startup hook에 명확한 상황→에이전트 매핑 주입
- 권위자 best practice 반영 (Kent Beck, Boris Cherny, Shrivu Shankar)

### v2.4.0 - Skills 2.0 적용
- Skills 2.0 전면 적용 (`context: fork`, `allowed-tools`, `argument-hint`)

### v2.3.1 - Agent 스코핑, Playwright MCP

### v2.0.0 - 간소화 + 워크플로우

[전체 변경 이력 → CHANGELOG.md](CHANGELOG.md)
