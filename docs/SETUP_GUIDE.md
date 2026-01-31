# Multi-Agent System 설치 가이드

이 문서는 Multi-Agent System 플러그인의 설치 및 설정 방법을 설명합니다.

## 목차

- [빠른 시작](#빠른-시작)
- [설치 방법](#설치-방법)
- [에이전트 활성화](#에이전트-활성화)
- [버전 업데이트](#버전-업데이트)
- [문제 해결](#문제-해결)

---

## 빠른 시작

```bash
# 1. 플러그인 설치 (Claude Code에서)
/plugin marketplace add geonhos/claude-code-setup
/plugin add multi-agent-system

# 2. 프로젝트에 적용 (터미널에서)
bash <(cat ~/.claude/plugins/cache/geonhos-plugins/multi-agent-system/*/scripts/install-agents.sh)
```

설치 완료 후 프로젝트에 다음이 생성됩니다:

```
.claude/
├── agents/       # 21개 에이전트 (자동 감지)
├── skills/       # 28개 스킬 (자동 감지)
└── CLAUDE.md     # 개발 지침
```

---

## 설치 방법

### 1단계: 마켓플레이스 추가

Claude Code에서 다음 명령어를 실행합니다:

```
/plugin marketplace add geonhos/claude-code-setup
```

### 2단계: 플러그인 설치

```
/plugin add multi-agent-system
```

설치 범위를 선택할 수 있습니다:
- **User scope**: 모든 프로젝트에서 사용
- **Project scope**: 현재 프로젝트의 모든 협업자가 사용
- **Local scope**: 현재 프로젝트에서 나만 사용

### 3단계: 설치 확인

```
/plugin list
```

`multi-agent-system`이 목록에 표시되면 설치 완료입니다.

---

## 에이전트 활성화

### 왜 추가 설정이 필요한가?

Claude Code의 플러그인 에이전트는 자동 감지 우선순위가 가장 낮습니다:

| 우선순위 | 위치 | 자동 감지 |
|---------|------|----------|
| 1 | CLI 플래그 (`--agents`) | ✅ |
| 2 | 프로젝트 에이전트 (`.claude/agents/`) | ✅ |
| 3 | 사용자 에이전트 (`~/.claude/agents/`) | ✅ |
| 4 | 플러그인 에이전트 | ❌ |

에이전트가 자동으로 감지되려면 프로젝트의 `.claude/agents/` 디렉토리에 복사해야 합니다.

### 설치 스크립트 사용

#### 프로젝트에 스크립트 복사 (최초 1회)

```bash
# scripts 폴더를 프로젝트 루트에 복사
cp -r "$(find ~/.claude/plugins/cache/geonhos-plugins/multi-agent-system -maxdepth 1 -type d | tail -1)/scripts" ./

# 실행 권한 부여
chmod +x ./scripts/*.sh
```

#### 에이전트 설치

```bash
# 현재 프로젝트에 에이전트 설치
./scripts/install-agents.sh
```

#### 다른 프로젝트에 설치

```bash
./scripts/install-agents.sh /path/to/other/project
```

### 설치 결과

스크립트 실행 후 프로젝트 구조:

```
your-project/
├── scripts/                 # ← 설치/업데이트 스크립트
│   ├── install-agents.sh
│   └── check-update.sh
├── .claude/
│   ├── agents/              # ← 21개 에이전트 파일
│   │   ├── ai-expert.md
│   │   ├── backend-dev.md
│   │   ├── code-reviewer.md
│   │   ├── git-ops.md
│   │   └── ... (17개 더)
│   ├── .agent-version       # ← 설치된 버전 추적
│   └── CLAUDE.md            # ← 프로젝트 지침 (있는 경우)
└── ...
```

---

## 버전 업데이트

### 업데이트 확인

```bash
./scripts/check-update.sh
```

### 업데이트 방법

새 버전이 출시되면 다음 단계를 따릅니다:

```bash
# 1. 플러그인 업데이트
/plugin update multi-agent-system

# 2. 에이전트 재설치
./scripts/install-agents.sh
```

스크립트는 자동으로:
- 현재 설치된 버전을 확인
- 새 버전이 있으면 업데이트 제안
- 에이전트 파일 덮어쓰기

### 버전 파일

`.claude/.agent-version` 파일에 현재 설치된 버전이 기록됩니다:

```
1.0.0
```

이 파일을 Git에 커밋하면 팀원들이 동일한 버전을 사용하는지 확인할 수 있습니다.

---

## 문제 해결

### 에이전트가 자동으로 호출되지 않음

**원인**: 에이전트가 `.claude/agents/`에 없음

**해결**:
```bash
./scripts/install-agents.sh
```

### "Plugin not found" 오류

**원인**: 플러그인이 설치되지 않음

**해결**:
```
/plugin marketplace add geonhos/claude-code-setup
/plugin add multi-agent-system
```

### 스크립트가 없음

**원인**: scripts 폴더를 복사하지 않음

**해결**:
```bash
cp -r "$(find ~/.claude/plugins/cache/geonhos-plugins/multi-agent-system -maxdepth 1 -type d | tail -1)/scripts" ./
chmod +x ./scripts/*.sh
```

### 특정 에이전트만 사용하고 싶음

개별 에이전트를 수동으로 복사할 수 있습니다:

```bash
# 예: git-ops 에이전트만 복사
mkdir -p .claude/agents
PLUGIN_PATH=$(find ~/.claude/plugins/cache/geonhos-plugins/multi-agent-system -maxdepth 1 -type d | tail -1)
cp "$PLUGIN_PATH/agents/execution/git-ops.md" .claude/agents/
```

---

## 에이전트 목록

### Execution 에이전트 (8개)

| 에이전트 | 설명 | 트리거 키워드 |
|---------|------|--------------|
| `ai-expert` | AI/ML 개발 전문가 | ML, AI, LLM, RAG, PyTorch |
| `backend-dev` | Spring Boot 백엔드 개발 | Spring, Java, API, 백엔드 |
| `database-expert` | 데이터베이스 전문가 | DB, 스키마, 쿼리, 마이그레이션 |
| `devops-engineer` | DevOps/인프라 전문가 | Docker, K8s, CI/CD, 배포 |
| `docs-writer` | 문서 작성 전문가 | docs, 문서, README |
| `frontend-dev` | React 프론트엔드 개발 | React, 컴포넌트, UI |
| `git-ops` | Git 작업 전문가 | commit, branch, merge, PR |
| `refactoring-expert` | 리팩토링 전문가 | refactor, 리팩토링, 개선 |

### Pipeline 에이전트 (4개)

| 에이전트 | 설명 | 트리거 키워드 |
|---------|------|--------------|
| `orchestrator` | 작업 조율 및 분배 | (자동 파이프라인) |
| `plan-architect` | 계획 수립 전문가 | plan, 계획, 설계, 아키텍처 |
| `plan-feedback` | 계획 피드백 제공 | (Gemini CLI 통합) |
| `requirements-analyst` | 요구사항 분석 | requirements, 요구사항, 스펙 |

### Quality 에이전트 (9개)

| 에이전트 | 설명 | 트리거 키워드 |
|---------|------|--------------|
| `code-reviewer` | 코드 리뷰 전문가 | review, 코드리뷰, 검토 |
| `docs-reviewer` | 문서 리뷰 전문가 | 문서 리뷰, 스펙 리뷰 |
| `performance-analyst` | 성능 분석 전문가 | performance, 성능, 최적화 |
| `pr-reviewer` | PR 리뷰 전문가 | PR, pull request |
| `qa-executor` | 테스트 실행 | test, 테스트 |
| `qa-healer` | 테스트 복구 | (자동 복구) |
| `qa-planner` | 테스트 계획 수립 | test, QA, 커버리지 |
| `reporter` | 작업 리포트 생성 | (자동 로깅) |
| `security-analyst` | 보안 분석 전문가 | security, 보안, 취약점 |

---

## 추가 리소스

- [README](../README.md) - 프로젝트 개요
- [CHANGELOG](../CHANGELOG.md) - 버전 변경 내역
- [Skills 문서](./SKILLS.md) - 사용 가능한 스킬 목록
