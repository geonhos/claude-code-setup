# harness 레퍼런스

설치가 바꾸는 것, `harness init`, CLI 전체, 워커 상한, 설정 키, conductor 게이트. 개요와 빠른 시작은 [README](../README.md), 구조는 [architecture.md](architecture.md), 함정과 결정은 [wiki/index.md](wiki/index.md).

## 요구 사항과 설치

- macOS, `/bin/bash` 3.2면 충분 · `jq` · `gh` · Claude Code ≥ 2.1.277 · `PATH`에 `~/.local/bin`
- `install.sh`는 `jq`만 확인합니다. Claude Code 버전과 `gh`는 직접 확인하세요.

```bash
git clone https://github.com/geonhos/my-claude-harness ~/workspace/my-claude-harness
cd ~/workspace/my-claude-harness
./install.sh
```

`install.sh`는 여러 번 실행해도 결과가 같습니다.

- `claude/agents/*.md`를 `~/.claude/agents/`에, `claude/skills/*/`를 `~/.claude/skills/`에 심링크합니다(이미 있던 다른 스킬은 `~/.claude/skills.bak/`으로 옮깁니다).
- `claude/skills/korean-writing/`은 conductor와 워커가 모두 쓰는 한국어 작성 스킬입니다(결정 0015). 나머지 스킬 넷은 conductor 전용입니다.
- `bin/*`(`harness`, `harness-verify`, `harness-run`, `harness-view`)를 `~/.local/bin`에 링크합니다. `lib/`는 링크 없이 실제 경로로 찾습니다.
- `~/.claude/settings.json`에 PreToolUse 게이트 훅, SessionStart 훅(`conductor-resume.sh`), Notification 훅(`notify-decision.sh`), `env.BASH_DEFAULT_TIMEOUT_MS`/`BASH_MAX_TIMEOUT_MS`, `promptCacheTtl`/`subagentPromptCacheTtl: 1h`, `attribution.commit`/`attribution.pr`(빈 문자열)과 `attribution.sessionUrl: false`(커밋 trailer, PR 꼬리말, 세션 링크를 붙이지 않음)를 병합합니다. 이미 값이 있으면 남기고 경고하며, 객체가 아닌 `attribution`은 건드리지 않습니다(백업을 남깁니다). 전역 `agent` 키는 쓰지 않습니다.

### 제거: `./install.sh --uninstall [--dry-run] [--force]`

이 체크아웃이 설치한 것만 지웁니다(링크, 훅 세 개, 키 네 개). 백업(`*.bak.<ts>`)은 남깁니다.

- `--dry-run`: 아무것도 바꾸지 않고 live-run 검사도 하지 않습니다. 실제 실행과 같은 `remove …` 줄, 경고, `keep key …` 줄, 백업 목록, 힌트 두 줄을 출력하고 `dry run: nothing was changed`로 끝납니다.
- `--force`: 살아 있는 `harness-run`이 있어도 지웁니다. 없으면 거부합니다(워커가 `harness-verify`를 잃습니다). 거부는 프로세스 목록에서 명령의 첫 두 단어 중 하나의 basename이 `harness-run`인지로 판단합니다.
- 인자가 틀리거나 `settings.json`이 객체 JSON이 아니면 아무것도 바꾸지 않고 실패합니다. `settings.json`이 없으면 링크만 처리합니다.
- 지울 것이 없으면 `nothing to remove`를 출력하고 끝납니다.

소유 규칙(`install.sh`의 install 정리와 `--uninstall`이 같은 함수를 씁니다):

- U1: `agents/`, `skills/`, `~/.local/bin`의 심링크 중 대상이 `$REPO/`로 시작하는 것을 지웁니다(저장소에서 지워진 이름도 포함).
- U2: 끊어진 링크는 그 이름이 이 체크아웃에 있고 대상 끝이 `/claude/agents/<n>.md`, `/claude/skills/<n>`, `/bin/<n>`으로 같을 때만 지웁니다. 다른 dotfiles 저장소를 가리키는 끊어진 링크는 남습니다.
- U3: 이 체크아웃 밖의 존재하는 경로를 가리키는 링크(작업 폴더, 다른 클론)는 남기고 `installed from <path>; run its install.sh --uninstall`로 경고합니다. 일반 파일과 디렉터리는 건드리지 않습니다.
- U4: 훅 항목은 `.command`가 `$REPO/claude/hooks/<b>`와 같거나, 같은 세 이름으로 끝나는 절대 경로인데 파일이 없을 때만 지웁니다. 존재하는 다른 체크아웃의 경로는 경고하고 남깁니다. 인자·따옴표가 있거나 이름이 다른 명령은 건드리지 않습니다. 항목이 비면 그 항목과 빈 이벤트 배열도 지웁니다. `$REPO`와 정확히 같은 명령은 경로에 어떤 문자가 있어도 지웁니다. 옛 경로에 공백이나 셸 특수문자가 있던 오래된 훅은 래퍼 명령과 구별되지 않아 남습니다. 직접 지웁니다.
- U5: 키 네 개는 값이 install 값과 같을 때만 지웁니다. 다르면 남기고 알립니다. `env`는 `{}`가 될 때만 지웁니다.

install도 같은 규칙으로 정리합니다. 끊어진 harness 링크(U2 모양)는 백업 없이 바꾸고, U4의 오래된 훅 항목은 지우고, 다른 존재하는 체크아웃의 훅은 경고만 합니다. 그래서 `mv` 뒤 `./install.sh`만으로 옮길 수 있습니다([wiki](wiki/how-to/move-checkout.md)).

## 저장소마다 `harness init`

harness를 쓰려는 저장소에서 한 번 실행합니다. `.harness/asks/`(체크아웃 표시)와 `.claude/settings.local.json`(사용자별, 추적 안 됨)에 `"agent": "conductor"`, `"autoCompactWindow": 400000`, worker deny 규칙을 만듭니다.

- `--shared`: `agent` 키를 커밋되는 `.claude/settings.json`에 씁니다(deny 규칙은 아래대로 로컬에 남습니다). 이미 다른 `agent`가 있으면 그대로 두고 알립니다. 기존 파일은 `.bak`을 한 번 남기고 심링크는 유지합니다.
- `--no-agent`: `agent`와 `autoCompactWindow` 키를 쓰지 않습니다. deny 규칙은 그래도 씁니다.
- `autoCompactWindow`(결정 0018, #276). conductor 세션이 자동 압축을 시작하는 컨텍스트 크기(토큰)입니다. 값은 400000이고 `agent`와 같은 파일(기본은 `.claude/settings.local.json`, `--shared`면 `.claude/settings.json`)에 씁니다. conductor 세션 전용이라, 그 파일이 다른 `agent`를 두고 있으면 쓰지 않고 이유를 한 줄 출력합니다. 그 파일에 이미 값이 있으면 그대로 두고 "autoCompactWindow already N"만 출력하며, 다시 실행해도 바뀌는 것이 없습니다. 추적되는 `.claude/settings.json`에 값이 있으면(팀 값) 로컬 설정이 그것을 덮어쓰므로 로컬 파일에는 쓰지 않고 `.claude/settings.json: autoCompactWindow already N`만 출력합니다. 작업 폴더(`harness lane`)는 git에 보이는 변경을 만들지 않으므로, 주 폴더가 `--shared`여도 거기서는 추적되는 `settings.json`이 아니라 `.claude/settings.local.json`에 씁니다(추적되는 `settings.json`에 이미 값이 있거나 거기에 다른 `agent`가 있으면 쓰지 않습니다). 로컬 설정이 프로젝트 설정보다 우선합니다. worker는 `lib/harness-headless.sh`가 설정하는 환경 변수 `CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000`을 그대로 쓰며, 환경 변수가 설정 키보다 우선합니다. 상수는 `bin/harness`의 `HARNESS_ACW`입니다.
- worker deny 규칙(결정 0014, #165). 항상 `.claude/settings.local.json`의 `permissions.deny`에 쓰고 `--shared`여도 커밋하지 않습니다. 끄는 플래그는 없고 init을 실행할 때마다 빠진 규칙을 다시 채웁니다. 순서대로: `Bash(git reset *--hard*)`, `Bash(git clean *)`, `Bash(git push *--force*)`, `Bash(git push -f*)`, `Bash(git push * -f*)`, `Read(.env)`, `Read(.env.*)`, `Read(~/.ssh/**)`, `Read(~/.aws/**)`. `rm -rf` 규칙은 `/tmp` 정리를 막으므로 없습니다. 상수는 `bin/harness`의 `HARNESS_DENY_RULES` 하나입니다.
- 병합: 기존 `permissions.deny`·`allow` 항목은 유지하고 빠진 규칙만 덧붙입니다. 바꿀 것이 없으면 쓰지 않고 "deny rules present"만 출력합니다. 쓸 때는 `.bak`을 한 번만 남깁니다. 쓸 파일이 병합 불가(JSON이 아님, 비어 있음, 최상위가 객체가 아님, `permissions`가 객체가 아님, `permissions.deny`가 배열이 아님)이면 init은 아무것도 만들지 않고 파일을 그대로 둔 채(`.bak` 없음) 파일 이름과 원인을 stderr에 출력하고 exit 1로 실패합니다. `--shared`면 두 파일을 모두 먼저 검사합니다. 다른 `agent` 값은 오류가 아닙니다(그대로 두고 알립니다).
- `harness ask`는 `.claude/settings.local.json`에 규칙이 하나라도 없으면 stderr에 한 줄 경고하고 계속 진행합니다(`harness init`을 다시 실행하라는 안내, 경고에 체크아웃 경로가 들어갑니다. `-C <lane>`이면 그 폴더의 파일을 봅니다). 규칙은 접두사 매칭이라 우회할 수 있습니다(`git -C`, `sh -c`, `+refspec`).
- 작업 규칙 블록(결정 0016, #243). `AGENTS.md`에 `harness:rules` 블록을 씁니다(마커는 `<!-- harness:rules begin -->`, `<!-- harness:rules end -->`). 내용은 `claude/templates/agents-rules.md`입니다. 파일이 없으면 만들고 git 제외 목록에 넣으며, `--shared`면 제외하지 않습니다. 파일이 있으면 마커 밖의 글은 한 글자도 바꾸지 않고 블록만 덧붙이거나 갱신합니다. 마커가 깨져 있으면 init은 아무것도 바꾸지 않고 실패합니다. 작업 폴더(`harness lane`)에서는 git에 보이는 변경을 만들지 않습니다. `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`가 있으면 Claude Code가 `AGENTS.md`를 읽지 않으므로, 그 파일에 `@AGENTS.md` 줄을 넣으라고 stderr로 안내할 뿐 고치지 않습니다. 되돌리려면 블록을 지웁니다(init이 만든 파일이면 파일과 제외 목록의 `AGENTS.md` 줄도 지웁니다).
- init하지 않은 저장소에서는 게이트·resume 훅이 아무것도 하지 않고 `harness ask`는 거부됩니다.
- 되돌리기(저장소별, `--uninstall`은 하지 않습니다): `.harness/asks/`를 지우고, `agent` 키를 만든 settings 파일에서 지웁니다. deny 규칙 아홉 개는 `.claude/settings.local.json`에 남으므로 직접 지웁니다. 이 규칙은 그 체크아웃의 모든 Claude Code 세션(conductor와 `--agent solo` 포함)에 적용됩니다. 세션 하나만 끄려면 `HARNESS_ROLE=worker claude --agent solo`.

## conductor 루프

1. init한 저장소에서 평소처럼 `claude`를 시작합니다. 터미널이면 충분합니다.
2. 일반 질문은 conductor가 바로 답합니다. 소스를 읽거나 고치려 하면 게이트가 호출을 거부하고(사유에 쓸 스킬 이름이 있습니다), conductor가 `/analyze` 조사 · `/implement` 변경 · `/review` 검토를 호출합니다. 직접 `/implement …`처럼 쳐도 됩니다.
3. 스킬이 `harness ask <worker> '<instruction>'`을 백그라운드(`run_in_background: true`)로 `timeout: 7200000`과 함께 돌립니다. Bash 기본 제한이 10분이라 이 값을 주지 않으면 끊깁니다. 기본 대기 시간이 워커의 실행 상한과 같아서 run이 끝나는 순간 ask가 돌아오고 완료 알림이 conductor를 깨웁니다. 리포트(`.harness/reports/<worker>.md`, 40줄 이하)가 출력됩니다.
4. 재시작·compaction 뒤에는 `harness wait <worker>`로 다시 붙습니다. Stop hook의 리포트 강제와 검증 루프는 [architecture.md](architecture.md) §4. 노트북 절전으로 시계가 크게 건너뛰면 마감도 그만큼 늦춥니다.
5. 진행은 `harness status`로 봅니다. 인자 오류를 빼면 매 ask는 `.harness/log/`와 `progress.jsonl`에 기록되고, SessionStart 훅이 `progress.md`를 conductor 컨텍스트에 넣습니다. goal 줄은 한 문단짜리 `.harness/goal.md`로 정합니다.

## CLI

`harness help`, `--help`, `-h`는 usage를 stdout에 출력하고 exit 0입니다(`-C <dir>` 뒤에서도 같습니다). `harness`를 인자 없이 실행하거나 모르는 명령을 주면 usage를 stderr에 출력하고 exit 1입니다. 전체 usage는 다음 명령을 보여 줍니다(`init`, `ask`, `wait`, `watch`, `open-watch`, `report`, `status`, `metrics`, `wiki-lint`, `close`, `lane`). exit code는 `bin/harness` 머리 주석에 있습니다(`ask`/`report` 0-5, `wait` 0·3·4). 작업 폴더에서 한 ask와 close도 주 폴더에 `.harness/asks`가 있으면 그 `progress.jsonl`에 `lane` 필드를 달고 함께 기록됩니다. `lane` 값은 브랜치가 `feat|fix|docs/<n>-*` 꼴이면(`<n>`은 숫자로 시작하고 뒤에 `-`가 하나라도 있어야 합니다) 접두사와 첫 `-` 사이의 글자입니다. `feat/12abc-x`면 `12abc`입니다. 그 밖의 브랜치나 detached HEAD면 폴더 이름입니다. 그래서 `harness lane rm` 뒤에도 `harness metrics`에 남습니다.

## 워커, 모델, 상한

워커는 항상 headless입니다: `harness-run`이 `claude -p`를 detached로 돌리고, 완료는 `.harness/asks/<role>.exit.json`(프로세스 종료)입니다. 마감 시간에 run을 죽이지 않고 exit 4로 돌려줍니다. 한 번의 실행 상한은 `headless_max_minutes`(기본 60, implementer 90)이고, 이 키는 직접 만든 `.harness/config.json`에 두며(파일이 없으면 기본값) 설정하면 implementer를 포함한 모든 역할에 적용되고 환경변수 `HARNESS_HL_MAX_S`(초)가 이를 덮어씁니다. `--keep`이 아니면 매번 새 세션입니다. 원본 스트림 `.harness/log/*.jsonl`은 게이트가 conductor의 읽기를 막습니다.

모든 역할(결정 0009, #166)의 러너는 `--permission-mode auto --permission-prompts none`으로 고정됩니다. 거부된 도구 호출은 `exit.json`의 `denied[]`에 남고, 리포트 없이 거부만 있으면 exit 2입니다. 워커 세션(`HARNESS_ROLE=worker`)에서는 `harness ask`가 exit 1로 거부됩니다(중첩 위임 방지).

## 설정

- `.harness/config.json`의 최상위 키 `headless_max_minutes`(분; 파일은 직접 만드는 선택 사항이고 없으면 기본값을 씁니다; 모든 역할의 실행 상한, `HARNESS_HL_MAX_S` 초 단위 환경변수가 우선). run은 항상 백그라운드(로그 `.harness/asks/<role>.runner.log`)이고, 진행은 `harness watch <role>`로 봅니다.
- 로그 정리(ask가 끝날 때마다): `HARNESS_LOG_KEEP`(기본 200개), `HARNESS_LOG_DAYS`(14일), `HARNESS_JSONL_MAX`(`progress.jsonl` 압축 기준, 바이트, 기본 1 MB).
- 검증 명령은 명시적인 설정에서만 가져오고, 키마다 먼저 찾은 쪽이 이깁니다: `.harness/verify.local.json` > `.claude/harness.json`. 언어는 감지하지 않습니다. 없는 키(또는 `null`)는 그 단계를 건너뜁니다. 이 저장소는 `{"test": "./install.sh --test"}`를 씁니다. `harness-verify detect`가 해석된 설정을 출력합니다.

```json
{ "format": "prettier --write {files}", "lint": "eslint {files}", "test": "npm test",
  "app": { "start": "npm run dev", "url": "http://localhost:3000" }, "maxAttempts": 3 }
```

코드가 읽는 키는 아래가 전부입니다.

| 키 | 파일 | 읽는 곳 | 기본값 |
|---|---|---|---|
| `format`, `lint`, `test` | `.harness/verify.local.json` > `.claude/harness.json` | `harness-verify`(`resolve_step`) | 없음: 그 단계를 건너뜁니다. `null` 같은 문자열이 아닌 값은 그 단계를 끕니다. |
| `maxAttempts` | 위와 같음 | `harness-verify`(`max_attempts`) | 3 (양의 정수가 아니면 3) |
| `app` | 위와 같음 | `harness-verify detect`가 출력만 하고, 다른 단계는 읽지 않습니다. | `null` |
| `lane_setup` | `.claude/harness.json`만 | `harness lane`이 새 work folder에서 `sh -c`로 실행합니다(`lib/harness-lane.sh`). | 없음: 실행하지 않습니다. |
| `headless_max_minutes` | `.harness/config.json` | `hl_max_s`(`lib/harness-headless.sh`) | implementer 90분, 나머지 60분. 환경변수 `HARNESS_HL_MAX_S`(초)가 먼저입니다. |

## conductor가 직접 할 수 있는 일, 한계

허용 목록(쓰기는 `docs/**/*.md`와 `.harness/`, Bash는 호출마다 단순 명령 하나)은 [architecture.md](architecture.md) §3과 `claude/agents/conductor.md`의 "You may run directly"에 있습니다.

그 밖의 호출은 거부됩니다. 한계: 게이트는 기본 파일/셸 도구만 막고, 파일을 읽는 다른 MCP 서버는 막지 못합니다. 경로는 심링크를 푼 뒤 한 번 더 검사합니다. jq가 없거나 훅 입력을 파싱하지 못하면 게이트는 모든 호출을 거부합니다(fail closed). 판단은 훅 입력의 `agent_type`으로 하고, `agent_type`이 없거나 서브에이전트(`agent_id` 있음)일 때만 `HARNESS_ROLE=worker`가 게이트를 끕니다([결정 0010](wiki/decisions/0010-herdr-optional-gate-by-checkout.md)). instruction에 백틱이나 `$(`가 들어가면 작은따옴표로 감쌉니다. conductor 에이전트의 본문은 기본 시스템 프롬프트를 대체하므로(`--agent`의 동작) 동작 지침은 `claude/agents/conductor.md`에 있습니다.
