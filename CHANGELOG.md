# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Entry template (v4.1+):** each behaviour-changing entry SHOULD include
> `expected:` (what improvement is anticipated) and `verify:` (how the next
> `/retro` can confirm it actually improved). This gives every change a
> falsifiable prediction so the learning loop can evaluate it.

## [4.1.0] - 2026-04-17

### Added — Learning Loop

- **`/retro` 스킬 신규** — 주간 회고 (`skills/retro/SKILL.md`)
  - `logs/feedback-signals.jsonl` + `logs/agent-progress.jsonl` 분석 (기본 7일 윈도우)
  - `logs/retro-YYYY-WW.md` 리포트 자동 생성
  - 패턴 ≥3회 · ≥2 세션 조건 만족 시 `memory/_draft/feedback_*.md` 초안 생성
  - expected: 주간 5분 회고로 반복 실수를 패턴화하여 잡음
  - verify: 3주 후 /retro의 "Top patterns" 섹션이 줄어드는지 확인

- **`/retro-review` 스킬 신규** — 사람 게이트 (`skills/retro-review/SKILL.md`)
  - `memory/_draft/` 의 각 draft에 대해 Approve/Reject/Edit/Defer
  - 승인 시 `memory/feedback_{slug}.md` 로 이동 + `MEMORY.md` 인덱스 업데이트
  - 결정 기록 → `logs/retro-decisions.jsonl`
  - expected: 자동 신호가 그대로 memory로 흘러가 시스템이 왜곡되는 걸 차단
  - verify: 신호 수집이 돌아가는 동안 `memory/` 항목이 사람 승인 없이 늘어나지 않는지 감사

- **`feedback-capture.sh` 훅 신규** — 암묵 bad 신호 자동 포착
  - `UserPromptSubmit` — 좌절 키워드 (다시, 틀렸, 이상, 아니야, undo, revert, wrong, not what, doesn't work, broken ...)
  - `PostToolUse(Edit/Write)` — `harness/progress.md` 갱신 후 1시간 이내 재수정 → `post_ship_rework`
  - `PostToolUse(Bash)` — `git revert` / `git reset --hard` → `strong_bad_git_undo`
  - `HARNESS_AUTO_FEEDBACK=0` 으로 전체 off
  - expected: /ship의 실제 품질 신호가 측정 가능해짐
  - verify: 1주일 후 `logs/feedback-signals.jsonl` 에 의미 있는 카테고리 분포가 찍히는지 확인

- **`memory/_draft/` 디렉토리** — draft 메모 스테이징

### Changed — 기존 훅 · 문서 최적화

- **`startup.sh` 대폭 축소** — 배너는 유지하되 중복 라우팅/스킬/룰 테이블 제거
  - expected: 세션당 ~1200 tokens 절감 (에이전트 description · 스킬 description에서 이미 노출되는 정보였음)
  - verify: 사용자 리포트로 컨텍스트 소비 감소 확인 or 다음 /retro에서 회귀 없음

- **`pre-commit.sh` 기본값 변경** — 풀 빌드 + 풀 테스트 → 컴파일/타입체크만
  - 풀 테스트는 `HARNESS_RUN_TESTS=1 git commit ...` 으로 opt-in
  - `HARNESS_SKIP_PRECOMMIT=1` 로 완전 skip
  - expected: 커밋당 평균 1–5분 → 수 초 단축; CI와의 중복 제거
  - verify: 3주 후 /retro 에서 frustration 신호가 커밋 주변에 몰리는 현상이 감소했는지 확인

- **`pre-commit-guard.sh`** — `$TOOL_INPUT` 환경변수 파싱 → stdin JSON + `jq` 파싱
  - Claude Code 훅 규약은 stdin JSON 입력이라 이전 구현은 사실상 동작하지 않았음
  - expected: git commit 감지가 실제 작동
  - verify: `bash -n`, 실제 commit 시 pre-commit.sh 트리거 로그 확인

- **`stop-verify.sh` 조건부화** — `git diff --quiet` 로 변경 없는 턴에서는 skip
  - expected: read-only/탐색 턴의 stop 넛지 노이즈 제거
  - verify: 탐색 세션 로그에서 `<stop-verification>` 출현 빈도 감소

- **`hooks.json` 확장** — `UserPromptSubmit`, `PostToolUse(Edit|Write|Bash)` 이벤트 추가; 모든 훅이 `$CLAUDE_PLUGIN_ROOT` 우선 사용 (fallback 유지)

### Removed

- 루트 `marketplace.json` — `.claude-plugin/marketplace.json` 과 중복된 dead code

### Philosophy

v4.1 은 하네스 자체가 **정적 도구 → 학습하는 시스템**으로 전환하는 첫 버전.
- **Layer 1 (수집)** · **Layer 2 (분석)** 은 완전 자동
- **Layer 3 (반영)** 은 `/retro-review` 를 통해 항상 사람 승인

자동 신호가 memory 로 흘러가 시스템이 스스로 변질되는 것을 구조적으로 차단.

## [4.0.0] - 2026-04-06

### Added — Harness Engineering

- **`/ship` 스킬 (핵심 신기능)**
  - 한 번의 프롬프트로 전체 파이프라인 실행: PLAN → ISSUE → BRANCH → EXECUTE → REVIEW → TEST → PR
  - 각 스테이지 게이트 제어 (plan score ≥8, critical issues 0, tests all green)
  - 실패 시 자동 재시도 (최대 2회) 후 사용자에게 보고
  - `harness/progress.md`로 크로스-세션 진행 추적

- **`/plan` 스킬 (병합)**
  - `brainstorm` + `task_breakdown` 통합
  - 접근법 탐색 (최소 3개) → 트레이드오프 매트릭스 → 태스크 분해 → 자체 점수 매기기

- **`/review` 스킬 (신규)**
  - code-reviewer 에이전트를 스킬로 직접 호출
  - Critical/Major/Minor/Suggestion 심각도 분류

- **Stop hook 추가**
  - 작업 완료 시 검증 넛지 (코드 완성도, 테스트, 문서 확인)
  - 활성 `/ship` 파이프라인 감지 시 파이프라인 완료 여부 확인

- **`harness/` 디렉토리**
  - `progress.md` — 파이프라인 진행 상태 크로스-세션 추적

### Changed — Skill 리뉴얼

- **스킬 이름 단축** (UX 개선)
  - `tdd_workflow` → `/tdd`
  - `debug_workflow` → `/debug`
  - `git_commit` → `/commit`
  - `git_pr` → `/pr`

- **스킬 병합** (중복 제거)
  - `test_runner` + `coverage_report` → `/test`
  - `brainstorm` + `task_breakdown` → `/plan`

- **startup.sh 업데이트**
  - 하네스 파이프라인 안내 섹션 추가
  - Stop hook 규칙 추가

### Removed

- `brainstorm` 스킬 (→ `/plan`으로 병합)
- `task_breakdown` 스킬 (→ `/plan`으로 병합)
- `verify_complete` 스킬 (→ `/ship` 파이프라인 내 흡수)
- `test_runner` 스킬 (→ `/test`로 병합)
- `coverage_report` 스킬 (→ `/test`로 병합)
- `git_commit` 스킬 (→ `/commit`으로 이름 변경)
- `git_pr` 스킬 (→ `/pr`로 이름 변경)
- `tdd_workflow` 스킬 (→ `/tdd`로 이름 변경)
- `debug_workflow` 스킬 (→ `/debug`로 이름 변경)

### Inspiration

- [Anthropic Harness Engineering Blog](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) — 진행 추적, 게이트 제어, 단일 기능 세션
- [disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) — Stop hook 패턴
- [trailofbits/skills](https://github.com/trailofbits/skills) — 보안 중심 스킬 구조

---

## [3.0.1] - 2026-03-13

### Fixed

- **PreCommit hook 오류 수정**
  - `PreCommit`은 Claude Code가 지원하지 않는 hook 이벤트 — 플러그인 로드 실패 원인
  - `PreToolUse` + `matcher: "Bash"`로 교체하여 `git commit` 명령 시에만 빌드/테스트 검증 실행
  - 새 `pre-commit-guard.sh`: `TOOL_INPUT`에서 `git commit` 여부를 판별, 비커밋 명령은 즉시 통과

- **Playwright MCP 패키지명 수정**
  - `@anthropic-ai/mcp-server-playwright` (존재하지 않음) → `@playwright/mcp@latest`

### Added

- **git_commit 스킬: Documentation Freshness Check** (4단계 신규)
  - 커밋 전 코드 변경에 영향받는 문서(README, CHANGELOG, docs/, docstrings)를 자동 점검
  - 이미 존재하는 문서만 업데이트, 새 문서 생성 안 함
  - 모든 프로젝트에서 `/git_commit` 사용 시 적용

---

## [3.0.0] - 2026-03-12

### Breaking Changes

- **에이전트 대폭 간소화**: 15개 → 6개 (-60%)
  - 실사용 데이터 분석 기반 (전체 프로젝트 세션 로그 분석)
  - 유지: plan-architect, backend-dev, frontend-dev, ai-expert, code-reviewer, qa-executor
  - 삭제: requirements-analyst, orchestrator, database-expert, devops-engineer, docs-writer, refactoring-expert, security-analyst, performance-analyst, debug-specialist

- **스킬 대폭 간소화**: 32개 → 12개 (-63%)
  - 유지: brainstorm, task_breakdown, verify_complete, debug_workflow, tdd_workflow, test_runner, coverage_report, git_commit, git_pr, react/spring/python_best_practices
  - 삭제: 20개 setup/template/reference 스킬

- **프로토콜 정리**: 9개 → 1개 (checklists.md만 유지)
  - 삭제: agent-template, agent-template-light, agent-refactoring-guide, agents-reference, skills-reference, boundary-protocol, workflow-detail, logging

### Added

- **에이전트 라우팅 테이블** (`startup.sh`)
  - 세션 시작 시 명확한 "상황 → 에이전트" 매핑을 XML로 주입
  - Claude가 시맨틱 라우팅으로 정확한 에이전트를 선택하도록 지원

- **startup.sh에 `<rules>` 섹션 추가**
  - 문서 자동 업데이트 규칙 (코드 변경 시 관련 문서 동시 업데이트)
  - Kent Beck TDD 원칙 (Red → Green → Refactor)
  - 구조적/행위적 커밋 분리
  - commit/push 분리 (자동 push 금지)

- **PreCommit 훅** (`hooks/pre-commit.sh`)
  - Claude Code가 커밋 시 빌드 + 테스트 자동 실행
  - 실패 시 커밋 차단
  - 지원: Java(Gradle/Maven), Python(pytest), Node.js(npm), Go, Rust
  - 테스트 프레임워크 없는 프로젝트는 통과

### Changed

- startup.sh: 슬림 6-에이전트 구조 반영, 라우팅 테이블 + 규칙 추가
- README.md: 전면 재작성, 철학 섹션 추가
- git_commit 스킬: "Post-Commit: Push" 섹션 및 "Always push" 규칙 제거 (commit/push 분리)
- 권위자 best practice 반영 (Kent Beck, Boris Cherny, Shrivu Shankar)

---

## [2.4.0] - 2026-03-12

### Added

- **Skills 2.0 전면 적용** (32개 스킬)
  - `context: fork`: `brainstorm`, `debug_workflow`, `task_breakdown` — 격리된 서브에이전트에서 실행, 메인 컨텍스트 보호
  - `allowed-tools`: 16개 스킬에 도구 제한 적용
    - Git 스킬 6개: read-only (`Bash, Read, Grep, Glob`)
    - 워크플로우 스킬 3개: 분석 전용 (`Read, Grep, Glob, Bash`)
    - Setup 스킬 4개: 쓰기 포함 (`Read, Edit, Write, Bash, Grep, Glob`)
    - Quality 스킬 3개: read-only
  - `argument-hint`: 11개 스킬에 자동완성 힌트 추가
    - `/brainstorm [topic]`, `/debug_workflow [error-description]`, `/task_breakdown [feature]`
    - `/component_generator [component-name]`, `/project_init [project-name]`, `/jpa_entity [entity-name]`
    - `/test_runner [test-path]`, `/coverage_report [source-path]`, `/git_analyze [file-or-branch]`
    - `/tdd_workflow [feature]`

- **startup.sh 동적화**
  - 에이전트/스킬/MCP 서버 수를 파일시스템에서 자동 계산
  - 버전을 `plugin.json`에서 자동 읽기
  - 하드코딩 완전 제거

### Changed

- **Best practices 스킬 자동 참조** (3개)
  - `react_best_practices`, `spring_best_practices`, `python_best_practices`
  - `disable-model-invocation: true` 제거 → Claude가 코드 작성 시 자동 트리거
  - 이전: 사용자가 `/react_best_practices`로 수동 호출해야만 참조
  - 이후: React/Spring/Python 코드 작성 시 Claude가 자동으로 참조

- **Plans 아카이브 정리**
  - 완료된 플랜 9개를 `plans/archived/`로 이동
  - PLAN-002 (agent-enhancement), PLAN-003 (superpowers), PLAN-004 (boundary-definitions)
  - PLAN-plugin-simplification v1, 고아 파일 2개 (generic-zooming-milner, wobbly-scribbling-diffie)

- **설정 중복 제거**
  - `.claude/settings.local.json`의 `enabledPlugins` 중복 항목 제거

- 버전 2.3.1 → 2.4.0

---

## [2.3.1] - 2026-03-05

### Added

- **Agent frontmatter 강화** (15개 전체)
  - `model`: pipeline=`inherit`, execution/quality=`sonnet`
  - `tools`: quality agent는 읽기 전용 (`Read, Grep, Glob, Bash`), execution은 쓰기 포함
  - `skills`: 관련 스킬 프리로딩 (10개 agent에 적용)
  - `memory: project`: code-reviewer, security-analyst (cross-session 학습)

- **Playwright MCP 서버** (`.mcp.json`)
  - `@anthropic-ai/mcp-server-playwright` 추가
  - 브라우저 자동화, E2E 테스트, 스크린샷 캡처 지원

- **스킬 frontmatter 개선** (32개 전체)
  - `disable-model-invocation: true`: template/reference 스킬 20개에 적용
  - `user-invocable: false`: `verify_complete` (내부 전용)
  - `argument-hint`: git 스킬 4개에 사용 힌트 추가
  - deprecated 모델 ID (`claude-opus-4-5-20250101`) → alias (`opus`, `haiku`) 교체

- **git_commit 안전성 개선**
  - `git add -A` / `git add .` 안티패턴 경고 추가
  - selective staging 권장 가이드

### Removed

- **`hooks/prompt-agent-matcher.sh`** (UserPromptSubmit 키워드 매칭 훅)
  - Agent description 기반 semantic routing으로 대체
  - 매 턴 ~150 토큰 context injection 비용 절감
  - 피드백 루프 버그 원천 차단

### Changed

- 버전 2.2.0 → 2.3.1
- startup.sh: Auto Triggers 섹션 → semantic routing 안내로 교체
- MCP 서버 목록: memory → playwright

---

## [2.2.0] - 2026-02-28

### Added

- **UserPromptSubmit 동적 에이전트 매칭 훅** (`hooks/prompt-agent-matcher.sh`)
  - 매 프롬프트마다 키워드 분석 후 적합한 에이전트/스킬 추천을 컨텍스트에 주입
  - 14개 에이전트 트리거 패턴 (한국어 + 영어 키워드)
  - 25ms 이내 실행, 매칭 없으면 무출력 (토큰 낭비 제로)
  - macOS bash 3.2 호환 (associative array 미사용)

### Removed

- **`.claude/CLAUDE.md` 제거**
  - 정적 CLAUDE.md의 역할을 동적 훅으로 완전 대체
  - `SessionStart` 훅: 워크플로우/에이전트 개요 (세션 시작 시)
  - `UserPromptSubmit` 훅: 에이전트 추천 (매 프롬프트)
  - `settings.json` deny 규칙: 금지 사항 강제
  - 장점: 컨텍스트 압축에도 생존, 매 턴 불필요한 토큰 소비 제거

### Changed

- 버전 2.1.2 → 2.2.0 (plugin.json, marketplace.json, startup.sh, README.md)

---

## [2.1.2] - 2026-02-06

### Fixed

- **Skills 로딩 오류 수정**
  - `plugin.json`의 `skills` 필드를 개별 경로 배열에서 디렉토리 경로 문자열(`"./skills"`)로 변경
  - Claude Code 플러그인 스펙에 맞게 스킬 디렉토리를 flat 구조로 평탄화
  - Before: `skills/category/skill_name/SKILL.md` (2단계 중첩, 로딩 실패)
  - After: `skills/skill_name/SKILL.md` (1단계, 정상 로딩)

- **SKILL.md frontmatter 위치 수정** (5개 파일)
  - 영향 파일: brainstorm, debug_workflow, git_worktree, task_breakdown, verify_complete
  - YAML frontmatter(`---`)가 파일 최상단이 아닌 `# Title` 뒤에 위치하던 문제 수정

### Changed

- **디렉토리 구조 간소화**
  - `skills/` 하위 카테고리 디렉토리(ai, git, python 등) 제거
  - 32개 스킬이 `skills/` 바로 아래에 flat하게 배치
  - `.claude-plugin/marketplace.json` 버전 및 설명 동기화

---

## [2.1.1] - 2026-02-06

### Fixed

- **Hook 경로 오류 수정**
  - Before: `bash hooks/startup.sh` (상대경로 → 다른 프로젝트에서 `No such file or directory`)
  - After: 플러그인 캐시 디렉토리에서 동적으로 스크립트 탐색
  - 어떤 프로젝트에서든 플러그인 훅 정상 동작

### Changed

- **ASCII Art 배너**
  - 스프링부트 스타일 "MAS" 대형 ASCII Art 배너 적용
  - `══════` 이중선 구분자로 시각적 구분 강화
  - `:: Multi-Agent System ::` 태그라인 추가

---

## [2.1.0] - 2026-02-06

### Added

- **구조화된 Hook** (`hooks/startup.sh`)
  - 외부 스크립트로 분리하여 유지보수성 향상
  - 박스 스타일 시각적 출력
  - XML 태그 기반 형식으로 Claude 인식 개선
  - 전체 자동 트리거 목록 포함 (13개)

### Changed

- **Hook 실행 방식**
  - Before: `hooks.json` 내 inline cat 명령
  - After: `bash hooks/startup.sh` 외부 스크립트 호출

---

## [2.0.0] - 2026-02-02

### Breaking Changes

- **에이전트 대폭 간소화**: 23개 → 15개 (-35%)
- **외부 의존성 제거**: Gemini CLI 의존 에이전트 삭제

### Added

- **6단계 명시적 워크플로우**
  ```
  요구사항 수집 → Plan 생성 → Plan 검증 → Orchestrator → 병렬 실행 → 구현 검증
  ```

- **Plan 자체 검증** (`plan-architect`)
  - 5가지 기준으로 자동 검증 (완전성, 의존성, 에이전트 할당, 실현 가능성, 테스트 가능성)
  - 점수 8/10 이상 필요
  - 순환 의존성 자동 탐지

- **병렬 실행 지원** (`orchestrator`)
  - 의존성 분석 후 병렬 그룹으로 태스크 분류
  - 동시 실행으로 실행 시간 단축

- **필수 구현 검증**
  - 모든 구현 완료 후 `code-reviewer` + `qa-executor` 자동 실행
  - Critical 이슈 0개, 모든 테스트 통과 필수

### Changed

- **`code-reviewer` 확장**
  - docs-reviewer 기능 통합
  - 코드 리뷰 + 문서 리뷰 지원
  - 리뷰 타입: code, docs

- **`qa-executor` 확장**
  - qa-planner 기능 통합 (테스트 계획)
  - qa-healer 기능 통합 (실패 분석 및 수정 제안)
  - 완전한 QA 사이클: 계획 → 실행 → 분석 → 수정 제안

- **`orchestrator` 간소화**
  - checkpoint 기능 제거 (복잡도 감소)
  - plan-feedback 호출 제거 (자체 검증으로 대체)
  - 병렬 실행에 집중

### Removed

- **삭제된 에이전트 (8개)**
  - `git-ops` → `/git_commit` 스킬 사용
  - `plan-feedback` → plan-architect 자체 검증
  - `brainstorm-facilitator` → `/brainstorm` 스킬
  - `reporter` → 필요시 수동 생성
  - `pr-reviewer` → code-reviewer 통합
  - `docs-reviewer` → code-reviewer 통합
  - `qa-planner` → qa-executor 통합
  - `qa-healer` → qa-executor 통합

- **삭제된 스킬 (2개)**
  - `/checkpoint` → orchestrator 간소화로 불필요
  - `/execution_report` → reporter 삭제로 불필요

### Summary

| 항목 | v1.4.x | v2.0.0 | 변화 |
|------|--------|--------|------|
| 에이전트 | 23개 | 15개 | -35% |
| 스킬 | 34개 | 32개 | -6% |
| 외부 의존성 | Gemini CLI | 없음 | 제거 |
| 워크플로우 | 암묵적 | 명시적 6단계 | 개선 |
| Plan 검증 | 외부 (Gemini) | 자체 검증 | 개선 |
| 구현 검증 | 선택적 | 필수 | 개선 |

---

## [1.4.3] - 2026-01-31

### Fixed

- **문서 정확성 개선** (docs-reviewer 리뷰 반영)
  - README.md 예시 출력 카운트 수정 (21/28 → 23/34)
  - README.md 디렉토리 구조 실제와 일치하도록 수정
  - marketplace.json (2개) 버전 및 설명 업데이트
  - LICENSE 저작권 연도 수정 (2025 → 2025-2026)
  - boundary-protocol.md "Domain Boundaries" → "Scope Boundaries" 통일
  - agent-template.md deprecated `color` 필드 제거
  - hooks.json `/git_issue` 스킬 추가

---

## [1.4.2] - 2026-01-31

### Fixed

- **리뷰 에이전트 트리거 개선**
  - CLAUDE.md와 hooks.json 간 불일치 해결
  - 리뷰 타입별 명확한 구분

---

## [1.4.1] - 2026-01-31

### Fixed

- **hooks.json 정확성 개선**
  - 에이전트 카운트 수정: 21개 → 23개
  - 스킬 카운트 수정: 28개 → 34개

---

## [1.4.0] - 2026-01-31

### Added

- **Boundary Protocol System**
- **Agent Boundary Definitions** (23개 에이전트 전체)
- **Skill Boundary Definitions** (5개 핵심 스킬)

---

## [1.3.0] - 2026-01-31

### Added

- **Superpowers-Inspired Workflow Skills** (6개 신규)
- **New Agents**: brainstorm-facilitator, debug-specialist

---

## [1.2.0] - 2026-01-31

### Added

- **SessionStart Hook**: 세션 시작 시 자동으로 에이전트/스킬 소개

---

## [1.1.0] - 2026-01-31

### Fixed

- 스킬 frontmatter에서 지원되지 않는 `color` 필드 제거

---

## [1.0.0] - 2026-01-31

### Added

- Initial release as Claude Code plugin
- **21 Specialized Agents**
- **28 Skills**
