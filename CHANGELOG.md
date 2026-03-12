# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
