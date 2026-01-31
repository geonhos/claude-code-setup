# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-01-31

### Added

- **Boundary Protocol System**
  - `.claude/protocols/boundary-protocol.md` - 경계 정의 마스터 프로토콜
  - Iron Law, DO NOT, Scope Boundaries, Rationalization Prevention, Red Flags 템플릿

- **Agent Boundary Definitions** (23개 에이전트 전체)
  - **Iron Laws**: 에이전트별 1개 비타협 규칙
    - `plan-architect`: "NO EXECUTION WITHOUT VALIDATED PLAN"
    - `backend-dev`: "NO CODE WITHOUT TESTS"
    - `git-ops`: "NO PUSH WITHOUT LOCAL VERIFICATION"
    - `debug-specialist`: "NO FIX WITHOUT REPRODUCTION AND HYPOTHESIS TESTING"
  - **DO NOT Lists**: 에이전트별 4-6개 명시적 금지사항
  - **Red Flags - STOP**: 즉시 중단해야 하는 경고 신호

- **Skill Boundary Definitions** (5개 핵심 스킬)
  - `brainstorm`, `checkpoint`, `verify_complete`, `debug_workflow`, `tdd_workflow`

- **CLAUDE.md Boundary Enforcement Section**
  - Universal DO NOT Rules
  - Gate Functions 테이블
  - Violation Response 절차

### Changed

- **Enhanced Protocol System**
  - `agent-template.md` - 경계 섹션 필수 항목으로 추가

- **Rationalization Prevention** (고위험 에이전트)
  - `git-ops`, `qa-executor`, `pr-reviewer`, `code-reviewer`, `debug-specialist`
  - Excuse vs Reality 테이블로 변명 방지

### Summary

| 항목 | v1.3.0 | v1.4.0 |
|------|--------|--------|
| Iron Laws | 0개 | 23개 (에이전트당 1개) |
| DO NOT Rules | 0개 | ~120개 (에이전트당 4-6개) |
| Red Flags | 0개 | ~70개 (에이전트당 3-4개) |
| Boundary Protocol | 없음 | 완전한 프로토콜 시스템 |

---

## [1.3.0] - 2026-01-31

### Added

- **Superpowers-Inspired Workflow Skills** (6개 신규)
  - `/brainstorm` - 최소 3개 접근법 탐색 후 결정
  - `/checkpoint` - 5개 태스크마다 검증 일시정지
  - `/task_breakdown` - 2-5분 단위 atomic 태스크 생성
  - `/debug_workflow` - 가설 기반 체계적 디버깅
  - `/verify_complete` - 태스크 완료 전 필수 검증
  - `/git_worktree` - 병렬 브랜치 개발 지원

- **New Agents** (2개 신규)
  - `brainstorm-facilitator` - 설계 탐색 및 의사결정 촉진
  - `debug-specialist` - 체계적 디버깅 (reproduce → hypothesize → test → fix → verify)

- **New Keywords for Auto-Trigger**
  - brainstorm, explore, alternatives, approaches, options → `brainstorm-facilitator`
  - debug, bug, issue, error, crash, not working → `debug-specialist`
  - worktree, parallel branch, multiple branches → `git-ops`

### Changed

- **Enhanced Agents** (3개 업데이트)
  - `git-ops` - Worktree 작업 섹션 추가
  - `plan-architect` - 2-5분 atomic 태스크 분해 규칙 추가
  - `orchestrator` - 체크포인트 실행 모드 추가 (기본 5개 태스크마다 검증)

- **Updated Pipeline**
  ```
  새 기능 구현:
    requirements-analyst → brainstorm-facilitator (복잡한 결정 시)
    → plan-architect (atomic task breakdown)
    → [execution agents with checkpoint every 5 tasks]
    → verify-complete → qa-planner → qa-executor
  ```

### Summary

| 항목 | 이전 | 이후 |
|------|------|------|
| 에이전트 | 21개 | 23개 |
| 스킬 | 28개 | 34개 |
| 워크플로우 패턴 | 0개 | 6개 |

---

## [1.2.0] - 2026-01-31

### Added

- **SessionStart Hook**: 세션 시작 시 자동으로 에이전트/스킬 소개
- `hooks/hooks.json` - 초기화 훅 설정

### Changed

- 플러그인 설치만으로 완전한 사용 가능
- 별도 스크립트 실행 불필요

### Removed

- `scripts/` 디렉토리 (불필요해짐)
- `docs/` 디렉토리 (README로 통합)

---

## [1.1.0] - 2026-01-31

### Fixed

- 스킬 frontmatter에서 지원되지 않는 `color` 필드 제거
- 중첩된 에이전트/스킬 디렉토리 경로 명시적 지정

### Changed

- plugin.json에 명시적 경로 목록 추가

---

## [1.0.0] - 2026-01-31

### Added

- Initial release as Claude Code plugin
- **21 Specialized Agents**
  - Pipeline: requirements-analyst, plan-architect, plan-feedback, orchestrator
  - Execution: backend-dev, frontend-dev, ai-expert, git-ops, devops-engineer, database-expert, refactoring-expert, docs-writer
  - Quality: qa-planner, qa-executor, qa-healer, security-analyst, pr-reviewer, docs-reviewer, reporter, code-reviewer, performance-analyst
- **28 Skills**
  - Git: git_commit, git_branch, git_pr, git_issue, git_analyze
  - Python: python_setup, fastapi_setup, api_test_setup, rag_setup, python_best_practices
  - Java: spring_boot_setup, gradle_setup, jpa_entity, spring_best_practices
  - React: react_setup, nextjs_setup, component_generator, react_best_practices
  - AI/ML: mlflow_setup, langchain_setup
  - Infrastructure: docker_setup, alembic_migration
  - Quality: test_plan_template, test_runner, coverage_report, execution_report
  - Base: project_init, tdd_workflow
- Plugin manifest (`.claude-plugin/plugin.json`)
- MIT License
- Comprehensive documentation

### Features

- Automated agent pipeline for software development workflows
- Keyword-based automatic agent triggering
- Cross-LLM validation with Gemini CLI integration
- Quality assurance automation (code review, security analysis, testing)
- Git Flow compliance with git-ops agent

[1.0.0]: https://github.com/geonho-yeom/claude-code-setup/releases/tag/v1.0.0
