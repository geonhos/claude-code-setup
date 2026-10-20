# 스킬 기반 위임 + conductor 직접 답변 + 라우팅 로그 — 설계

작성일: 2026-10-20
상태: 승인됨 (구현 계획 작성 전)
관련 조사: [`docs/research/2026-10-20-decision-models-kev-vs-laya.md`](../../research/2026-10-20-decision-models-kev-vs-laya.md)

## 1. 문제

conductor 시스템 프롬프트(`claude/agents/conductor.md`)가 **모든 요청을 세 워커 중 하나로 분류해 위임**하도록 강제한다. "이 옵션이 뭐야?" 수준의 질문도 opus analyst pane 기동 → 프롬프트 전송 → 최대 600 s 대기 경로를 타고, 첫 질의는 pane split + agent start 비용이 더해져 더 느리다.

위임 여부를 결정 모델(Kev 등)에 맡기는 방안을 조사했으나, 제로샷으로는 신뢰할 수 없고 자체 프롬프트 로그로 파인튜닝해야 한다는 결론이 났다. 따라서 도입 순서를 넷으로 나누고, **이 스펙은 1·2단계**를 다룬다.

1. 스킬 기반 위임 + conductor 직접 답변 ← 이 스펙
2. 라우팅 로그 기록 (학습 라벨) ← 이 스펙
3. 로그로 Kev 파인튜닝, 한국어 정확도 측정 (다음 스펙)
4. 정확도가 임계값을 넘으면 UserPromptSubmit 훅에서 힌트 주입 (다음 스펙)

## 2. 목표와 비목표

**목표**

- 평범한 질의(일반 질문, 리포트 설명, 이미 아는 내용의 계획, `docs/`·`.harness/` 파일)는 conductor가 **직접** 답한다.
- 워커 위임은 `/analyze`, `/implement`, `/review` 스킬을 통해서만 일어난다. 사용자가 직접 부르거나, conductor가 코드 접근이 필요하다고 판단해 `Skill` 도구로 부른다.
- 모든 프롬프트와 모든 위임을 `.harness/routing.jsonl`에 기록해, 나중에 "이 프롬프트는 직접 답변/어느 워커"라는 라벨을 도출할 수 있게 한다.
- 게이트(소스 Read/Edit 차단, Agent 차단)는 그대로 유지한다.

**비목표**

- 결정 모델 설치·호출·힌트 주입 (3·4단계).
- 학습 데이터 export 스크립트 (3단계에서 로그 스키마가 확정된 뒤).
- 게이트 deny 메시지 문구 변경 (고정 문자열 = 프롬프트 캐시 안정성 유지).

## 3. 구성 요소

```
claude/
  agents/conductor.md          수정  직접 답변 기본, 위임은 Skill 경유
  skills/
    analyze/SKILL.md           신규
    implement/SKILL.md         신규
    review/SKILL.md            신규
  hooks/conductor-route.sh     신규  UserPromptSubmit 훅 → harness route-log
bin/harness                    수정  `ask --via`, `route-log` 서브커맨드, delegate 줄 기록
install.sh                     수정  skills 디렉터리 심링크, UserPromptSubmit 훅 등록
tests/route.test.sh            신규
tests/install.test.sh          수정
tests/progress.test.sh         수정
tests/gate.test.sh             수정  (--via 세그먼트 allow 고정)
docs/architecture.md           수정  "8. 라우팅과 스킬" 섹션
README.md                      수정  스킬 소개, 직접 답변 한 줄
```

## 4. conductor 프롬프트 (`claude/agents/conductor.md`)

바꾸는 곳 (현재 줄 번호는 analyst 조사 시점 기준):

| 위치 | 현재 | 변경 |
|---|---|---|
| L3 description | "Delegates all analysis and implementation to herdr-hosted Claude workers via the harness CLI; reads only their reports." | "Default session role. Answers directly when no code access is needed; delegates code reading, changes and reviews to herdr workers through the /analyze, /implement, /review skills." |
| L7-11 역할 문단 | "Your job is to understand what the user wants, delegate the work to herdr-hosted Claude workers, …" | "Your job is to answer the user directly when you can, and to delegate through a skill when the answer needs source code read, changed or reviewed. You still cannot read or edit source or spawn native subagents; the gate denies those." |
| Loop 앞 | (없음) | 새 절 **When to delegate** (아래) |
| L42-44 Loop 1단계 | "Classify the request: understand → analyst; change → implementer; verify → reviewer." | "Pick: answer directly, or /analyze (understand), /implement (change), /review (verify). Big requests: /analyze plans, then /implement per task, then /review." |
| L98-100 superpowers 절 | "use `harness ask analyst`" 등 | "use the /analyze (/implement, /review) skill" |
| L113-114 | "Everything else goes through a worker." | "Everything else goes through a skill." |

새 절 **When to delegate**:

1. 사용자가 `/analyze`, `/implement`, `/review`를 호출했으면 그 스킬을 따른다.
2. 답에 소스 읽기·실행·변경·검증이 필요하다고 판단하면 `Skill` 도구로 해당 스킬을 호출한다. **`harness ask`를 직접 치지 않는다.** 스킬이 `--via skill`을 붙여 출처를 기록한다.
3. 그 외에는 직접 답한다. 짧게.
4. `Skill` 도구가 없는 세션(스킬 미설치)이면 `harness ask <worker> …`를 직접 쓴다. 이때 `--via`는 생략한다(기본 `conductor`).

유지하는 곳: escape hatch, How to work, 워커 표, `harness ask` 작성법(타임아웃 660000, 따옴표 규칙, `.harness/task-<worker>.md`, `--fresh`/`--keep`), 진행/재개, exit code 표, 허용 목록, opt-out. 스킬 본문은 이 절들을 "conductor.md의 해당 절을 따른다"로 참조한다.

## 5. 스킬 (`claude/skills/<name>/SKILL.md`)

### 5.1 공통

frontmatter:

```yaml
---
name: analyze            # 디렉터리명과 같아야 함
description: Conductor only. Delegate a read-only investigation (unknown code, design questions, plans) to the herdr analyst worker and relay its report.
argument-hint: <what to investigate>
---
```

- `context: fork`, `agent:`를 쓰지 않는다 (conductor는 `Agent` 도구가 막혀 있다).
- `` !`cmd` `` 동적 주입을 쓰지 않는다 (게이트 경유 여부 미검증).
- `disable-model-invocation`은 **쓰지 않는다** — conductor가 판단해 자동 호출해야 한다.

본문 구조:

1. "If you are a worker session (your system prompt says HARNESS_ROLE=worker or names you analyst/implementer/reviewer), ignore this skill and do the task yourself." — 사용자 전역 스킬이라 워커 세션에도 보이기 때문.
2. `$ARGUMENTS`와 대화 맥락으로 **자기완결 브리프**를 `.harness/task-<worker>.md`에 쓴다: 목표, 파일/영역, 제약, 완료 기준, 커밋 여부와 메시지.
3. `harness ask --via skill <worker> 'Read .harness/task-<worker>.md and do it.'` — Bash timeout 660000, 또는 백그라운드. 작은따옴표 규칙은 conductor.md를 따른다.
4. exit code는 conductor.md의 표대로 처리한다. 리포트 요지만 사용자에게 전달한다.

### 5.2 워커별 차이

| 스킬 | 워커 | 브리프에 고정되는 제약 |
|---|---|---|
| `/analyze` | analyst | "파일 수정·커밋 금지. 리포트에 파일 경로+줄 범위 포함." |
| `/implement` | implementer | 커밋 여부와 정확한 커밋 메시지(attribution 포함). verify 실패(exit 5) 시 재시도 규칙. |
| `/review` | reviewer | 비교 기준(base ref 또는 커밋 범위)과 범위. 리포트 마지막 줄 `VERDICT: PASS|FAIL` 요구. FAIL이면 `/implement`로 넘기는 흐름 안내. |

## 6. 라우팅 로그

### 6.1 파일과 스키마

`.harness/routing.jsonl`, append-only, UTC `ts`. 줄 2종.

```json
{"ts":"2026-10-20T05:12:01Z","event":"prompt","session":"<session_id>","prompt":"<원문, 최대 4000자>","skill":"/implement"}
{"ts":"2026-10-20T05:12:40Z","event":"delegate","session":"<session_id>","worker":"implementer","source":"skill","exit":0}
```

| 필드 | prompt 줄 | delegate 줄 |
|---|---|---|
| `ts` | 훅 실행 시각 | ask 종료 시각 |
| `session` | 훅 stdin `session_id` | Bash 환경 `CLAUDE_CODE_SESSION_ID` (없으면 null) |
| `prompt` | 원문, 4000자 초과 시 잘림 | — |
| `skill` | prompt가 `/analyze`, `/implement`, `/review`로 시작하면 그 이름, 아니면 null | — |
| `worker` | — | analyst / implementer / reviewer |
| `source` | — | `skill` (스킬이 `--via skill`로 호출) / `conductor` (기본값) |
| `exit` | — | `harness ask`의 exit code |

"직접 답변"은 **기록하지 않는다.** 같은 `session`에서 다음 `prompt` 줄 전까지 `delegate` 줄이 없으면 직접 답변으로 **오프라인에서 도출**한다. 훅 시점에는 결정을 알 수 없고, 같은 줄 보강은 JSONL 재작성과 경합 문제가 있기 때문이다. export 스크립트는 3단계 스펙.

`prompt` 줄의 `skill`은 부가 정보다. ground truth는 `delegate` 줄의 `source`다. 슬래시 호출 시 훅에 들어오는 prompt가 원문이 아니어도 설계는 유지되고 `skill`만 null이 된다.

### 6.2 `harness route-log`

```
harness route-log '<json 한 줄>'
```

- `record_progress`와 같은 패턴: 쓰기 전 크기가 `HARNESS_JSONL_MAX`(기본 1 MiB) 초과면 `routing.jsonl.<stamp>`로 mv 후 gzip. jq로 유효성만 확인하고 append.
- 실패는 stderr 경고만, exit 0.
- `HARNESS_ROUTE_LOG=0`이면 아무것도 쓰지 않고 exit 0.
- 경로는 CWD 상대 `.harness/routing.jsonl` (progress.jsonl과 같은 규칙).

### 6.3 `harness ask --via`

- `harness ask [--via skill|conductor] [--fresh|--keep] <worker> '<instruction>'`. 기본 `conductor`. 다른 값은 exit 1.
- `ask_finish`에서 (어떤 exit든, 시그널 포함) `delegate` 줄을 `route-log`로 1개 append.
- 게이트: `harness( .*)?` 정규식이 이미 허용. `tests/gate.test.sh`에 `harness ask --via skill implementer 'x'` allow 케이스를 고정한다.
- `VAR=x harness …` 환경변수 접두는 게이트가 막으므로 플래그 방식을 쓴다.

### 6.4 `claude/hooks/conductor-route.sh` (UserPromptSubmit)

```
#!/bin/bash
[ "${HARNESS_ROLE:-}" = worker ] && exit 0
command -v jq >/dev/null || exit 0
command -v harness >/dev/null || exit 0
input=$(cat) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty') || exit 0
[ -n "$cwd" ] && [ -d "$cwd/.harness" ] || exit 0
cd "$cwd" || exit 0
line=$(printf '%s' "$input" | jq -c '{ts: (now|todate), event:"prompt",
  session: (.session_id // null),
  prompt: ((.prompt // "")[:4000]),
  skill: ((.prompt // "") | capture("^(?<s>/(analyze|implement|review))(\\s|$)").s // null)}') || exit 0
harness route-log "$line" >/dev/null 2>&1
exit 0
```

(의사코드. `now|todate`는 jq 1.6+에서 UTC ISO 8601을 돌려준다. 실제 구현에서 `date -u`로 대체해도 된다.)

- 어떤 경로로도 stdout에 쓰지 않고 exit 0 → 프롬프트를 막거나 컨텍스트를 주입하지 않는다.
- `.harness/`가 없는 디렉터리(harness 미사용 프로젝트)에서는 기록하지 않는다.
- bash 3.2 호환, BSD 유틸만 사용.

## 7. 설치 (`install.sh`)

- (a) `claude/skills/*/` → `~/.claude/skills/<name>` **디렉터리 심링크**(`ln -sfn`). 기존 항목이 심링크가 아니면 `.bak.<ts>`로 백업 후 교체. agents 루프와 같은 형태.
- (b) 기존 jq 필터에 `UserPromptSubmit` 3줄 추가: `//= []` → 우리 command 포함 엔트리에서 그 hook 제거, 빈 엔트리 삭제 → `{hooks:[{type:"command", command:$route}]}` append. **matcher 없음.** 같은 패턴이 세 번 반복되므로 jq `def` 함수로 묶는 리팩터는 선택.
- (c) `installed:` 출력에 skills와 UserPromptSubmit 줄 추가.
- 재실행 멱등: 심링크 교체, 훅 엔트리 정확히 1개 유지, 타 훅 보존.

## 8. 에러 처리

| 상황 | 동작 |
|---|---|
| 훅: jq/harness 없음, stdin 깨짐, `.harness/` 없음, 쓰기 실패 | 무출력, exit 0 |
| `route-log` 실패 | stderr 경고, `harness ask` 결과·exit code 불변 |
| `--via`에 허용되지 않은 값 | exit 1 (설정 오류 범주) |
| 스킬 미설치 세션 | conductor.md의 fallback(§4 4항)으로 `harness ask` 직접 사용 |
| 워커 세션에서 스킬이 호출됨 | 스킬 본문 1항에 따라 무시하고 직접 수행 |

## 9. 테스트

실행: `./install.sh --test` (`.claude/harness.json`의 test). 기존 자작 프레임워크(`check`/`pass`/`fail`, `mktemp -d`, `tests/fake-herdr`)를 따른다. 모든 스크립트 `/bin/bash`(3.2).

| 파일 | 케이스 |
|---|---|
| `tests/route.test.sh` (신규) | 샘플 stdin → `routing.jsonl` 1줄, 필드(`event`,`session`,`prompt`,`skill`) 검증 / `HARNESS_ROLE=worker` → 무출력·파일 미생성 / 깨진 JSON → exit 0, 파일 불변 / `PATH`에서 jq 제거 → exit 0 / `.harness/` 없는 cwd → 미기록 / 4001자 prompt → 4000자 / `/implement foo` → `skill:"/implement"`, `/implementation` → null / 크기 초과 → 로테이션 파일 생성 / `HARNESS_ROUTE_LOG=0` → 미기록 |
| `tests/install.test.sh` | UserPromptSubmit 엔트리 정확히 1개 / 재설치 후에도 1개 / 다른 UserPromptSubmit 훅 보존 / `~/.claude/skills/{analyze,implement,review}` 심링크 존재, 대상이 레포 디렉터리 / 기존 비심링크 디렉터리 백업 |
| `tests/progress.test.sh` | fake-herdr로 `harness ask --via skill analyst 'x'` → delegate 줄 `source:"skill"` / `--via` 생략 → `"conductor"` / `--via bogus` → exit 1 / `route-log` 쓰기 실패 시 ask exit 불변 |
| `tests/gate.test.sh` | `harness ask --via skill implementer 'x'` → allow / `harness route-log '{...}'` → allow |
| 스킬 정적 검사 (route.test.sh 또는 install.test.sh) | 3개 `SKILL.md` 존재, frontmatter `name` == 디렉터리명, 본문에 `--via skill` 포함, `context: fork` 미포함 |

**실측 과제** (구현 계획의 첫 태스크, 결과를 이 스펙에 추기):

1. UserPromptSubmit 훅의 `session_id`가 같은 세션 Bash 환경의 `CLAUDE_CODE_SESSION_ID`와 같은가.
2. `/analyze foo`로 호출했을 때 훅 stdin `prompt`가 원문 `/analyze foo`인가, 아니면 스킬 본문으로 치환된 뒤인가.

②가 "치환 뒤"면 §6.1의 `skill` 필드는 항상 null이 되고, 그 경우 필드를 제거한다. ①이 다르면 `delegate` 줄의 `session`을 훅이 남긴 `.harness/routing.last`(최근 prompt의 session)에서 읽는 대안을 쓴다.

## 10. 문서

- `docs/architecture.md`: "8. 라우팅과 스킬" 섹션 — 프롬프트 → (스킬 호출 | conductor 판단 | 직접 답변) 흐름도, `routing.jsonl` 스키마 표, 훅 등록 위치. 목차와 "2. 설정과 훅 연결", "7. 설치 구성" 다이어그램 텍스트에 UserPromptSubmit·skills 반영(Mermaid 원본만, SVG 재렌더는 별도).
- `README.md`: 스킬 3개 한 줄씩, "일반 질의는 conductor가 직접 답한다" 한 줄, `routing.jsonl` 언급.

## 11. 결정 기록

| 결정 | 선택 | 대안과 기각 이유 |
|---|---|---|
| 위임 진입점 | 워커별 스킬 3개 | `/delegate <worker>` 하나: 워커 선택 라벨이 conductor 판단에 섞임. 프롬프트만 수정: 명시/자동 위임 구분 불가 |
| 출처 표시 | `harness ask --via` 플래그 | 환경변수 접두: 게이트 `BASH_ALLOW`가 `harness`로 시작해야 해서 불가 |
| 직접 답변 기록 | 기록하지 않고 오프라인 조인 | 같은 줄 보강: JSONL 재작성·경합. 별도 "direct" 줄: 훅 시점엔 결정을 모름 |
| 로그 헬퍼 위치 | `harness route-log` 서브커맨드 | 훅 내 복제: 로테이션 로직 두 곳 |
| 훅 등록 위치 | `settings.json` + 스크립트 첫 줄 role 체크 | `conductor.md` frontmatter hooks: trusted dir에서만 발동, 기존 관행과 다름 |
| 게이트 deny 메시지 | 변경 없음 | 스킬명으로 바꾸기: 고정 문자열 규칙·캐시 안정성 우선. conductor.md가 스킬 경유를 우선하므로 충돌 없음 |
