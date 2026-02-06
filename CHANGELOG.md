# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
