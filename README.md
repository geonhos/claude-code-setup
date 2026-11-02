# claude-code-setup: conductor

메인 세션(Fable)을 **conductor(지휘 세션)** 로 쓰는 사용자 단위 Claude Code 설정. 평범한 질의는 conductor가 직접 답하고, 소스를 읽거나 고치거나 검증해야 하는 일은 `/analyze` `/implement` `/review` 스킬로 백그라운드에서 도는 headless Claude 워커(`claude -p`)에게 맡긴다. [herdr](https://herdr.dev)는 선택 사항이고 워커 화면을 보여 주는 viewer일 뿐이다. conductor는 워커 리포트만 읽는다.
아키텍처 다이어그램은 [docs/architecture.md](docs/architecture.md)에 있다.

이렇게 하는 이유: Fable 토큰이 비싸다. conductor는 소스를 컨텍스트에 올리지 않고, 워커(`analyst` opus · `implementer` sonnet · `reviewer` opus)가 일을 한다. analyst와 implementer는 프로젝트 메모리를 가져서 코드베이스를 매번 다시 파악하지 않는다. reviewer는 일부러 메모리를 두지 않는다. 리뷰마다 선입견 없이 시작하게 하려는 것이다.

## 요구 사항

- macOS, `/bin/bash` 3.2면 충분
- `jq`, Claude Code ≥ 2.1.248
- `herdr` ≥ 0.9는 선택: `viewer: pane`(또는 `auto`로 viewer pane을 보려는 경우)에만 필요하다
- `PATH`에 `~/.local/bin`

## 설치

```bash
git clone https://github.com/geonhos/claude-code-setup ~/workspace/claude-code-setup
cd ~/workspace/claude-code-setup
./install.sh
```

`install.sh`는 여러 번 실행해도 결과가 같다. 하는 일:

- `claude/agents/*.md`를 `~/.claude/agents/`에 심링크
- `claude/skills/*/`를 `~/.claude/skills/`에 디렉터리 심링크 (이미 있던 다른 스킬은 `~/.claude/skills.bak/`으로 옮긴다)
- `bin/*`(`harness`, `harness-verify`, `harness-run`, `harness-view`)를 `~/.local/bin`에 링크 (`lib/`는 링크 없이 실제 경로로 찾음)
- `~/.claude/settings.json`에 아래 항목을 병합 (백업을 남긴다)
  - PreToolUse 훅 하나(게이트), SessionStart 훅 하나(`conductor-resume.sh`), UserPromptSubmit 훅 하나(`conductor-route.sh`)
  - `env.BASH_DEFAULT_TIMEOUT_MS`/`BASH_MAX_TIMEOUT_MS`
  - `promptCacheTtl`/`subagentPromptCacheTtl: 1h`
  - 전역 `agent` 키는 더 이상 쓰지 않는다. 이전 설치가 남긴 `agent: conductor`는 한 번 제거한다(다른 키는 건드리지 않는다). conductor 역할은 저장소 단위로 `harness init`이 정한다.
- 전역 gitignore에 `.harness/` 추가
- herdr가 설치돼 있으면 `herdr integration install claude` 실행 (없으면 건너뜀)

설치는 `./install.sh` 한 번, 그 뒤 harness를 쓰려는 저장소마다 `harness init`을 한 번 실행한다. herdr는 필요 없다. `.harness/asks/`(체크아웃 표시), 기본 설정, 그 저장소의 `.claude/settings.local.json`(사용자별, 추적 안 됨)에 `"agent": "conductor"`를 만든다(`--shared`는 커밋되는 `.claude/settings.json`에 쓴다. 이미 다른 `agent`가 있으면 그대로 두고 알린다. 기존 파일은 `.bak`을 한 번 남기고, 심링크는 유지한다. `--no-agent`는 settings를 건드리지 않는다). init하지 않은 저장소에서는 게이트·resume 훅·라우팅 로그가 모두 꺼지고 `harness ask`/`spawn`은 거부된다.

이전 버전이 남긴 오염(`asks/` 없는 `.harness/` 디렉터리, 전역 `agent: conductor`)은 `harness doctor`로 찾고 `harness doctor --fix`로 지운다. 아는 파일만 든 디렉터리만 지우고, 모르는 파일이 있으면 건너뛴다. 심링크 디렉터리와 심링크된 `.harness`는 따라가지 않고, 기본 범위가 `$HOME`이면 거부하며(DIR을 직접 지정), 워커(`HARNESS_ROLE=worker`)에서는 실행되지 않는다.

테스트는 `./install.sh --test`로 돌린다. 스위트는 병렬로 실행되고, 디버깅용으로 `HARNESS_TEST_SERIAL=1`을 주면 하나씩 돌린다.

## 사용법

1. 프로젝트(`harness init`을 한 저장소)에서 평소처럼 `claude`를 시작한다. 터미널이면 충분하고 herdr는 필요 없다.
2. 질문하거나 작업을 맡긴다. 일반 질문은 conductor가 바로 답한다. 소스를 읽거나 고치려 하면 게이트가 호출을 거부하고, conductor는 맞는 스킬(`/analyze` 조사 · `/implement` 변경 · `/review` 검토)을 호출한다. 직접 `/implement …`처럼 쳐도 된다.
3. 스킬이 `harness ask <worker> '<instruction>' --via skill`을 실행한다. 워커는 detached headless Claude 세션(`claude -p`)으로 백그라운드에서 돈다. 워커가 끝나면 리포트(`.harness/reports/<worker>.md`, 40줄 이하)가 출력된다. 설치 스크립트는 Bash 도구 상한을 `BASH_MAX_TIMEOUT_MS=7200000`으로 올려 두지만, 호출마다 `timeout`을 직접 주지 않으면 기본값(`BASH_DEFAULT_TIMEOUT_MS=600000`, 10분)에서 끊긴다. 그래서 스킬은 `harness ask`와 `harness wait`를 항상 `run_in_background: true`와 `timeout: 7200000`으로 돌린다: 기본 대기 시간이 워커의 headless 상한(analyst·reviewer 60분, implementer 90분)과 같아 실행이 끝나는 순간 ask가 돌아오고 Bash 완료 알림이 conductor를 깨운다. 재시작·compaction 뒤에는 `harness wait <worker>`로 다시 붙는다. 워커가 리포트 없이 멈추려 하면 Stop hook이 (ask당 최대 2번) 막고 리포트를 쓰게 한다(지시문에 `[no-report]`가 있으면 제외). 노트북 절전으로 시계가 크게 건너뛰면 마감도 그만큼 늦춘다.
4. 워커의 진행은 `harness status`로 보고, herdr를 쓰면 viewer pane에서도 볼 수 있다(읽기 전용). conductor가 보는 것은 리포트뿐이다.

```
harness init   [--no-agent] [--shared]                              # 이 저장소를 체크아웃으로 만든다 (asks/, 설정, .claude/settings.local.json agent)
harness doctor [--fix] [DIR...]                                    # 과거 오염(asks/ 없는 .harness/, 전역 agent 키)을 찾고 --fix로 지운다
harness ask    <agent> '<instruction>' [--timeout MS] [--fresh|--keep] [--via skill|conductor|retro]   # exit 2 tool call denied, no report · 3 no report · 4 still working · 5 verification failed
harness wait   <agent>|<ask-id> [--timeout MS]                       # run이 끝날 때까지 block(수집은 안 함): 0 done · 3 ask 없음/러너 죽음 · 4 timeout; 끝나면 `harness report`
harness watch  <agent>|<ask-id> [-n N]                              # 사람용 터미널 뷰어(tty 필요, conductor 게이트가 거부)
harness report <agent>|<ask-id>                                   # print existing report (same exit codes as ask): 3 none, 4 still working
harness ask    <analyst|reviewer> '<instruction>' --worktree [--base REF]   # headless 전용: ask마다 detached git worktree(~/.cache/harness/wt/<repo8>/<role>-<id8>), 병렬 ask 가능 (결정 0008)
harness status
harness retro  [--dry-run]                               # 실패한 ask의 후보(.harness/retro/)를 analyst 한 번에 묶어 회고하고 docs/wiki/inbox/에 남김
harness metrics [--since YYYY-MM-DD] [--json]            # progress.jsonl·위키 기반 지표 (최근 28일 vs 직전 28일)
harness close  <agent>|<ask-id>|--all [--force]          # run을 멈추거나 worktree를 지운다. exit 4: 실행 중이거나 리포트를 수집 안 함 (--force가 무시)
harness route-log '<json>'                               # append one line to .harness/routing.jsonl (used by the hook and by ask)
```

## 병렬 ask: `--worktree` (결정 0008)

analyst·reviewer는 `--worktree [--base REF]`로 ask마다 자기 작업 트리(`git worktree add --detach`, 브랜치·머지 없음)를 받는다. 경로는 `~/.cache/harness/wt/<repo8>/<role>-<id8>`(`.harness/` 밖). ask-id는 시작할 때 stderr에 찍히고 `harness report <ask-id>`·`harness close <ask-id> [--force]`·`harness status`에 쓴다. 진행 로그·routing·retro는 메인 루트에 그대로 쌓인다(progress.jsonl에 `wt`/`base`/`ask_id`). 리포트를 정상 수집(exit 0/5)했고 작업 트리가 깨끗하면 자동 제거, 아니면 유지. 패치가 저장된 작업 트리는 자동으로 절대 지워지지 않고(30분 고정 reap·LOG_DAYS 포함) `harness status`에 `kept`+패치 경로로 남아 `harness close <ask-id>`를 기다린다(저장된 패치 외 변경이 더 있을 때만 `--force`). 패치 파일은 close 뒤에도 남고 HARNESS_LOG_DAYS 후 정리된다. 패치 없는 깨끗한 kept는 30분 고정 reap으로 정리될 수 있다. 작업 트리 안에서 워커가 만든 커밋도 base 기준으로 패치(바이너리 포함)에 저장되고 그 트리는 깨끗하지 않은 것으로 보아 유지한다; 저장된 패치는 새 패치가 쓰일 때만 교체된다. 락은 소유 pid가 살아 있고 명령줄에 `harness`가 있을 때만 살아 있는 것으로 보며, `HARNESS_LOCK_MAX_S`(기본 120초)가 지나면 조용히 넘겨받는다. 동시에 `max_parallel`(기본 3, `HARNESS_MAX_PARALLEL`)개까지, 넘으면 exit 4. implementer에 쓰면 exit 1. 작업 트리 안의 `.harness/*.md` 산출물은 끝날 때 메인 `.harness/`로 복사되고(예약 이름 `goal.md`·`progress.md`·`task-*.md`와 심볼릭 링크는 제외; 메인 쪽이 그사이 바뀌었으면 `<name>.<id8>.md`), 그 밖의 변경은 `.harness/wt/<ask-id>.patch`로 저장되며 작업 트리는 유지된다. `HARNESS_WT_ROOT`는 저장소 밖 절대경로여야 하고, `--base`는 `--worktree`와 함께만 쓴다.

## 러너와 viewer

워커는 항상 headless다: `harness-run`이 `claude -p`를 detached로 돌린다(결정 0011). 완료 = `.harness/asks/<role>.exit.json`(프로세스 종료). 마감 시간에 죽이지 않고 exit 4(`harness report <role>`로 수집), `--keep`이 아니면 매번 새 세션. `headless_max_minutes`(기본 60, implementer 90)가 한 번의 실행 상한이다. implementer(결정 0009)는 `--permission-mode auto --permission-prompts none`으로 고정되고, 거부된 도구 호출은 `exit.json`의 `denied[]`에 기록되며 report 없이 거부만 있으면 exit 2, Stop hook 검증 중에 마감되면 exit 4 "still verifying", 직전 ask가 0이 아니었으면 다음 ask가 자동으로 `--resume`(`--fresh`로 끔). 원본 스트림(`.harness/log/*.jsonl`)은 conductor 게이트가 읽기를 막는다.
설정은 `.harness/config.json`(없으면 첫 실행 때 만든다)의 최상위 키 `viewer`(환경변수 `HARNESS_VIEWER`가 우선) 하나다: `auto`(기본)=herdr를 쓸 수 있으면 `harness watch <role>`을 돌리는 viewer pane(run이 끝나면 닫는다), 아니면(또는 pane split/run 실패 시) pane 없이 백그라운드(stderr에 한 줄 안내, 로그 `.harness/asks/<role>.runner.log`), `pane`=항상 pane(herdr 필요), `none`=항상 백그라운드. 옛 pane 러너의 키(`runner`, `close_after_ask`, `idle_ttl_minutes`)는 무시되고 처음 한 번 stderr에 안내가 나온다. 옛 기본 설정 파일은 자동으로 새 기본값으로 바뀐다.

## 진행 로그와 컨텍스트 리셋

`harness ask`는 exit code와 관계없이 매번 `.harness/log/<ts>-<agent>.md`(instruction, brief 파일 내용, 리포트 또는 화면 끝부분)를 쓰고, `.harness/progress.jsonl`에 JSON 한 줄(ts, agent, session, instr, exit, verify, dur_s, head_before/after, status, summary)을 덧붙인 뒤 `.harness/progress.md`를 다시 만든다. `progress.md`는 60줄 이하이고 goal, 최근 ask 15개, 미해결 질문, 워커 상태가 들어간다. goal 줄은 한 문단짜리 `.harness/goal.md`를 써서 정한다.
로그 작업에서 문제가 생겨도 stderr에 경고만 찍고 ask 결과는 바꾸지 않는다.

`SessionStart` 훅(`claude/hooks/conductor-resume.sh`, matcher `startup|clear|compact`, `install.sh`가 설치)이 `progress.md`를 conductor 컨텍스트에 넣어 준다. 워커 세션에서는 아무것도 출력하지 않는다.

ask가 끝날 때마다 로그를 정리한다. 최신 200개만 남기고, 14일이 지난 로그는 지우고, 1 MB를 넘은 `progress.jsonl`은 `progress.jsonl.<ts>.gz`로 압축해 옮긴다.
조절 변수: `HARNESS_LOG_KEEP`, `HARNESS_LOG_DAYS`, `HARNESS_JSONL_MAX`(바이트).

`harness status`의 `ctx` 열은 끝난 run의 `exit.json`에서 읽은 토큰 수이고, 알 수 없으면 `-`다. 늦게 도착한 리포트를 보관하는 archive는 없다: 끝난 뒤 `report <ask-id>`는 retro 후보만 큐에 넣는다. 0이 아닌 exit 뒤에는 role 세션을 시간 제한 없이 이어 쓰며(implementer는 자동 `--resume`), `--fresh`나 exit 0이 나올 때까지 계속된다.

프롬프트마다 UserPromptSubmit 훅이 `.harness/routing.jsonl`에 `prompt` 줄을, `harness ask`가 끝날 때마다 `delegate` 줄(`source`: 스킬 경유면 `skill`, 아니면 `conductor`)을 남긴다. 직접 답변은 "다음 프롬프트까지 delegate 줄 없음"으로 나중에 도출한다. 이 로그는 결정 모델을 학습시켜 라우팅 힌트를 주기 위한 데이터다, 배경은 [docs/research/2026-10-20-decision-models-kev-vs-laya.md](docs/research/2026-10-20-decision-models-kev-vs-laya.md). `HARNESS_ROUTE_LOG=0`으로 끈다.

## 검증 루프

`.harness/`(리포트, 패널, 검증 상태)는 `harness init`이 저장소 루트에 만든다(conductor를 시작한 디렉터리에는 만들어지지 않는다). 훅은 `cwd`에서 `.git`이 있는 디렉터리까지 올라가며 `.harness/asks/`가 있는 가장 가까운 디렉터리를 체크아웃 루트로 쓴다. 없으면 훅은 아무것도 하지 않는다(`harness init`이 만든다).

implementer는 자기 작업을 스스로 판정하지 않는다. `claude/agents/implementer.md`의 훅이 `harness-verify`를 루프 안에서 돌린다. `PostToolUse` 훅이 수정한 파일마다 포맷을 적용하고 파일 단위 lint 오류를 돌려주며, `Stop` 훅은 변경분 전체에 lint와 테스트를 돌려서 실패하면 실패 출력과 함께 워커를 되돌려 보낸다. 최대 `maxAttempts`회(기본 3)까지 반복하고, 검증하는 동안은 리포트를 숨기며 실패할 때마다 리포트를 지운다. 횟수를 다 쓰면 리포트를 그대로 둔다.
`harness ask implementer`는 `./install.sh`로 설치한 `harness-verify`가 있어야 하고(없으면 exit 1), 먼저 baseline을 기록한다. 재시도 상한까지 검증에 실패하면 exit **5**(리포트와 `verify: FAIL (<step>, <n> attempts)` 줄)로 종료한다. `harness report`도 같은 검사를 한다.
reviewer는 `harness-verify run all [--base <ref>]`(`main`과의 merge base 이후 바뀐 파일과 커밋하지 않은 파일)를 돌리고, 설정돼 있으면 앱을 스모크 체크한 뒤, 리포트 마지막에 `VERDICT: PASS` 또는 `VERDICT: FAIL`을 적는다(FAIL이면 exit 5, 없으면 exit 3).

명령은 명시적인 설정에서만 가져오고, 키마다 먼저 찾은 쪽이 이긴다. 순서는 `.harness/verify.local.json`, `.claude/harness.json`이다. 언어나 프로젝트 유형을 자동으로 감지하지 않는다. 없는 키는 그 단계를 건너뛰고, 설정이 아예 없으면 `skipped`(Stop 훅은 통과)다. conductor는 `.claude/harness.json`이 있는 디렉터리에서 실행해야 한다(`.harness/`와 같은 루트 기준이고, git toplevel이 아니다). 이 저장소는 `{"test": "./install.sh --test"}`를 쓴다.

```json
{ "format": "prettier --write {files}", "lint": "eslint {files}", "test": "npm test",
  "app": { "start": "npm run dev", "url": "http://localhost:3000" }, "maxAttempts": 3 }
```

`null`로 두면 그 단계를 끈다. `harness-verify detect`는 해석된 설정을 출력한다.
jq, git, 설정 중 무엇이 없어도 워커를 막지 않는다.

## conductor가 직접 할 수 있는 일

- `harness`
- `gh pr create|view|list|checks|comment|edit|merge`: `api`는 금지. `--body-file`은 `.harness/` 또는 `docs/` 아래 파일만 가능. `pr merge -d`는 금지.
- 읽기 전용 `herdr`: `pane get|current`
- 읽기 전용 `git`: `status`, `log`, `diff --stat`, `branch`(목록만: `-a -r -v --show-current`). patch, output, 삭제 플래그는 금지.
- `ls` (재귀 금지)
- `.harness/`와 `docs/` 아래의 `cat`/`ls` (인자에 따옴표, glob, `$` 금지)
- `docs/` 아래 Markdown 작성, `.harness/` 아래 모든 파일 작성
- Bash 호출 하나에 명령 하나만: `;` `&&` `||` `|` `&`, 리디렉션(`2>&1` 포함), 백틱, `$(`는 거부된다. 독립된 명령은 병렬 호출로 보낸다.

이 밖의 호출은 모두 거부되고, 거부 사유에 써야 할 스킬 이름이 들어 있다.

## 알려진 한계

게이트가 막는 것은 기본 파일/셸 도구다. 파일을 읽는 다른 MCP 서버는 막지 못한다. 파일 도구의 경로는 심링크를 풀고 나서 한 번 더 검사한다. jq가 없거나 훅 입력을 파싱하지 못하면 게이트는 워커를 포함해 모든 호출을 거부한다(fail closed). `harness init`을 하지 않은 저장소(`.harness/asks/`가 없음)에서는 게이트가 꺼진다([결정 0010](docs/wiki/decisions/0010-herdr-optional-gate-by-checkout.md), 0005를 대체). 워커에게 보내는 instruction에 백틱이나 `$(`가 들어가면 작은따옴표로 감싸야 한다.

워커 세션(`HARNESS_ROLE=worker`)에서는 `harness ask`가 exit 1로 거부된다. 스킬이 사용자 전역이라 워커에서 중첩 위임이 일어나는 것을 막기 위해서다.

conductor 에이전트의 본문은 Claude Code의 기본 시스템 프롬프트를 대체한다(`--agent`가 원래 그렇게 동작한다). 그래서 conductor는 동작 지침을 이 파일에 의존한다.

## 끄는 방법

- 저장소 단위: `harness init`을 하지 않으면 된다(이미 했다면 두 단계: `.harness/asks/`를 지우고, `.claude/settings.local.json`(`--shared`였다면 `settings.json`)에서 `agent` 키를 지운다).
- 세션 하나만: `HARNESS_ROLE=worker claude --agent solo`.

게이트는 훅 입력의 `agent_type`으로 판단한다. conductor 에이전트 세션은 `HARNESS_ROLE=worker`여도 게이트가 켜져 있고, `agent_type`이 없거나 서브에이전트(`agent_id` 있음)일 때만 `HARNESS_ROLE=worker`가 게이트를 끈다.

## 디렉터리 구성

```
bin/harness                      harness CLI (ask, report, status, init, ...; herdr is optional)
bin/harness-verify               format/lint/test checks used by worker hooks
lib/harness-defaults.sh         roles and default numbers (sourced by bin/harness, bin/harness-verify)
lib/harness-metrics.sh          harness metrics + wiki-lint (sourced eagerly by bin/harness)
lib/harness-worktree.sh         --worktree asks, the wt_* group (sourced eagerly by bin/harness)
lib/harness-headless.sh         headless runner glue, the hl_* group (sourced eagerly by bin/harness)
claude/hooks/conductor-gate.sh   PreToolUse gate
claude/hooks/conductor-resume.sh SessionStart hook: injects .harness/progress.md
claude/hooks/conductor-route.sh  UserPromptSubmit hook: logs each prompt to .harness/routing.jsonl
claude/skills/<name>/SKILL.md    /analyze /implement /review (symlinked to ~/.claude/skills/<name>)
claude/agents/{analyst,implementer,reviewer}.md  worker definitions (model, memory, cacheTtl, report contract)
claude/agents/conductor.md       conductor system prompt (settings.agent)
claude/agents/solo.md            escape-hatch agent (empty body = default prompt)
install.sh                       installer (--test runs tests/)
tests/                           gate, harness (against tests/fake-herdr), verify, progress, install, route
docs/superpowers/                spec and plan
```
