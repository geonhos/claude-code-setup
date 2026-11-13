# harness 레퍼런스

설치가 바꾸는 것, `harness init`, CLI 전체, 워커 상한, 설정 키, 검증 루프, conductor 게이트, 테스트, 디렉터리 구성. 개요와 빠른 시작은 [README](../README.md), 구조는 [architecture.md](architecture.md), 함정과 결정은 [wiki/index.md](wiki/index.md).

## 요구 사항과 설치

- macOS, `/bin/bash` 3.2면 충분 · `jq` · Claude Code ≥ 2.1.248 · `PATH`에 `~/.local/bin`

```bash
git clone https://github.com/geonhos/claude-code-setup ~/workspace/claude-code-setup
cd ~/workspace/claude-code-setup
./install.sh
```

`install.sh`는 여러 번 실행해도 결과가 같다.

- `claude/agents/*.md`를 `~/.claude/agents/`에, `claude/skills/*/`를 `~/.claude/skills/`에 심링크한다(이미 있던 다른 스킬은 `~/.claude/skills.bak/`으로 옮긴다).
- `bin/*`(`harness`, `harness-verify`, `harness-run`, `harness-view`)를 `~/.local/bin`에 링크한다. `lib/`는 링크 없이 실제 경로로 찾는다.
- `~/.claude/settings.json`에 PreToolUse 게이트 훅, SessionStart 훅(`conductor-resume.sh`), `env.BASH_DEFAULT_TIMEOUT_MS`/`BASH_MAX_TIMEOUT_MS`, `promptCacheTtl`/`subagentPromptCacheTtl: 1h`를 병합한다(백업을 남긴다). 전역 `agent` 키는 쓰지 않는다. 이전 설치가 남긴 `agent: conductor`는 한 번 제거한다.
- 전역 gitignore에 `.harness/`를 추가한다.

## 저장소마다 `harness init`

harness를 쓰려는 저장소에서 한 번 실행한다. `.harness/asks/`(체크아웃 표시), 기본 설정 `.harness/config.json`, 그리고 `.claude/settings.local.json`(사용자별, 추적 안 됨)에 `"agent": "conductor"`를 만든다.

- `--shared`: 커밋되는 `.claude/settings.json`에 쓴다. 이미 다른 `agent`가 있으면 그대로 두고 알린다. 기존 파일은 `.bak`을 한 번 남기고 심링크는 유지한다.
- `--no-agent`: settings를 건드리지 않는다.
- init하지 않은 저장소에서는 게이트·resume 훅이 아무것도 하지 않고 `harness ask`는 거부된다.
- 되돌리기: `.harness/asks/`를 지우고, `agent` 키를 만든 settings 파일에서 지운다. 세션 하나만 끄려면 `HARNESS_ROLE=worker claude --agent solo`.

## conductor 루프

1. init한 저장소에서 평소처럼 `claude`를 시작한다. 터미널이면 충분하다.
2. 일반 질문은 conductor가 바로 답한다. 소스를 읽거나 고치려 하면 게이트가 호출을 거부하고(사유에 쓸 스킬 이름이 있다), conductor가 `/analyze` 조사 · `/implement` 변경 · `/review` 검토를 호출한다. 직접 `/implement …`처럼 쳐도 된다.
3. 스킬이 `harness ask <worker> '<instruction>'`을 백그라운드(`run_in_background: true`)로 `timeout: 7200000`과 함께 돌린다. Bash 기본 제한이 10분이라 이 값을 주지 않으면 끊긴다. 기본 대기 시간이 워커의 실행 상한과 같아서 run이 끝나는 순간 ask가 돌아오고 완료 알림이 conductor를 깨운다. 리포트(`.harness/reports/<worker>.md`, 40줄 이하)가 출력된다.
4. 재시작·compaction 뒤에는 `harness wait <worker>`로 다시 붙는다. 워커가 리포트 없이 멈추려 하면 Stop hook이 ask당 최대 2번 막고 리포트를 쓰게 한다(지시문에 `[no-report]`가 있으면 제외). 노트북 절전으로 시계가 크게 건너뛰면 마감도 그만큼 늦춘다.
5. 진행은 `harness status`로 본다. 매 ask는 `.harness/log/`와 `progress.jsonl`에 기록되고, SessionStart 훅이 `progress.md`를 conductor 컨텍스트에 넣는다. goal 줄은 한 문단짜리 `.harness/goal.md`로 정한다.

## CLI

```
harness init   [--no-agent] [--shared]                       # 이 저장소를 체크아웃으로 만든다
harness ask    <agent> '<instruction>' [--timeout MS] [--keep]
harness wait   <agent> [--timeout MS]                        # run이 끝날 때까지 block, 수집은 안 함
harness watch  <agent> [-n N]                                # 사람용 터미널 뷰어(tty 필요, 게이트가 거부)
harness report <agent>                                       # 기존 리포트 출력 (ask와 같은 exit code)
harness status
harness metrics [--since YYYY-MM-DD] [--json]                # progress.jsonl·위키 기반 지표 (최근 28일 vs 직전 28일)
harness wiki-lint [DIR]                                      # docs/wiki 형식·한도 검사
harness close  <agent> [--force]                             # 실행 중이면 exit 4 (--force가 run을 죽임)
```

exit code는 `bin/harness` 머리 주석에 있다(`ask`/`report` 0-5, `wait` 0·3·4).

## 워커, 모델, 상한

워커는 항상 headless다: `harness-run`이 `claude -p`를 detached로 돌리고, 완료는 `.harness/asks/<role>.exit.json`(프로세스 종료)이다. 마감 시간에 run을 죽이지 않고 exit 4로 돌려준다. 한 번의 실행 상한은 `headless_max_minutes`(기본 60, implementer 90)이고, 이 키는 `.harness/config.json`에 두며 설정하면 implementer를 포함한 모든 역할에 적용되고 환경변수 `HARNESS_HL_MAX_S`(초)가 이를 덮어쓴다. `--keep`이 아니면 매번 새 세션이다. 원본 스트림 `.harness/log/*.jsonl`은 게이트가 conductor의 읽기를 막는다.

implementer(결정 0009)는 `--permission-mode auto --permission-prompts none`으로 고정된다. 거부된 도구 호출은 `exit.json`의 `denied[]`에 남고, 리포트 없이 거부만 있으면 exit 2다. 워커 세션(`HARNESS_ROLE=worker`)에서는 `harness ask`가 exit 1로 거부된다(중첩 위임 방지).

## 설정

- `.harness/config.json`의 최상위 키 `headless_max_minutes`(분; 모든 역할의 실행 상한, `HARNESS_HL_MAX_S` 초 단위 환경변수가 우선). run은 항상 백그라운드(로그 `.harness/asks/<role>.runner.log`)이고, 진행은 `harness watch <role>`로 본다.
- 로그 정리(ask가 끝날 때마다): `HARNESS_LOG_KEEP`(기본 200개), `HARNESS_LOG_DAYS`(14일), `HARNESS_JSONL_MAX`(`progress.jsonl` 압축 기준, 바이트, 기본 1 MB).
- 검증 명령은 명시적인 설정에서만 가져오고, 키마다 먼저 찾은 쪽이 이긴다: `.harness/verify.local.json` > `.claude/harness.json`. 언어는 감지하지 않는다. 없는 키(또는 `null`)는 그 단계를 건너뛴다. 이 저장소는 `{"test": "./install.sh --test"}`를 쓴다. `harness-verify detect`가 해석된 설정을 출력한다.

```json
{ "format": "prettier --write {files}", "lint": "eslint {files}", "test": "npm test",
  "app": { "start": "npm run dev", "url": "http://localhost:3000" }, "maxAttempts": 3 }
```

## 검증 루프

흐름과 exit 매핑은 [architecture.md](architecture.md) §4. 설정은 위 "설정"의 검증 명령 항목. jq, git, 설정 중 무엇이 없어도 워커를 막지 않는다.

## conductor가 직접 할 수 있는 일, 한계

Bash는 호출마다 명령 하나만 허용된다(`;` `&&` `||` `|` `&`, 리디렉션, 백틱, `$(`는 거부; 독립된 명령은 병렬 호출).

- `harness`, `gh pr create|view|list|checks|comment|edit|merge`(`api`, `merge -d` 금지; `--body-file`은 `.harness/`·`docs/` 아래만)
- `git status|log|diff --stat|branch`(목록만; patch·output·삭제 플래그 금지)
- `ls`(재귀 금지)와 `.harness/`·`docs/` 아래 `cat`/`ls`(인자에 따옴표, glob, `$` 금지)
- `docs/` 아래 Markdown과 `.harness/` 아래 모든 파일 쓰기

그 밖의 호출은 거부된다. 한계: 게이트는 기본 파일/셸 도구만 막고, 파일을 읽는 다른 MCP 서버는 막지 못한다. 판단은 훅 입력의 `agent_type`으로 하고, `agent_type`이 없거나 서브에이전트(`agent_id` 있음)일 때만 `HARNESS_ROLE=worker`가 게이트를 끈다([결정 0010](wiki/decisions/0010-herdr-optional-gate-by-checkout.md)). instruction에 백틱이나 `$(`가 들어가면 작은따옴표로 감싼다. conductor 에이전트의 본문은 기본 시스템 프롬프트를 대체하므로(`--agent`의 동작) 동작 지침은 `claude/agents/conductor.md`에 있다.
