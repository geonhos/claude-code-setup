# claude-code-setup

Claude Code의 메인 세션을 **conductor(지휘 세션)** 로 쓰는 사용자 단위 설정입니다. 소스를 읽거나 고치거나 검증하는 일은 conductor가 직접 하지 않고, 백그라운드에서 도는 headless Claude 워커 셋에게 맡깁니다.

## 무엇인가

- **conductor**: 사용자와 대화하고 issue·PR을 다룬다. 게이트(PreToolUse 훅)가 소스 읽기·수정을 막아서 워커 리포트만 읽을 수 있습니다.
- **워커**: `analyst`(조사·계획, opus), `implementer`(구현·테스트·커밋, sonnet), `reviewer`(diff 검토, opus). 각각 detached headless 세션(`claude -p`)이고, `/analyze` `/implement` `/review` 스킬이 `harness ask`로 띄웁니다.
- **검증**: implementer가 끝내려 하면 Stop 훅이 `harness-verify`(format, lint, test)를 돌리고, 실패하면 되돌려 보냅니다. reviewer는 리포트를 `VERDICT: PASS|FAIL`로 끝냅니다.
- **이유**: conductor 컨텍스트에 소스가 올라가지 않아 긴 세션에서도 토큰과 맥락이 유지되고, 구현한 쪽과 검토하는 쪽이 다른 세션이라 리뷰가 독립적입니다.

구조와 데이터 흐름은 [docs/architecture.md](docs/architecture.md), 설정·게이트 상세는 [docs/reference.md](docs/reference.md).

## 설치

요구 사항: macOS의 `/bin/bash` 3.2, `jq`, `gh`, Claude Code(`claude`) ≥ 2.1.277, `PATH`에 `~/.local/bin`.

```bash
git clone https://github.com/geonhos/claude-code-setup ~/workspace/claude-code-setup
cd ~/workspace/claude-code-setup
./install.sh        # 여러 번 실행해도 결과가 같습니다
```

`install.sh`가 하는 일:
- `claude/agents/*.md`와 `claude/skills/*/`(한국어 작성 스킬 `korean-writing` 포함)를 `~/.claude/`에 심링크합니다.
- `bin/*`(`harness`, `harness-verify`, `harness-run`, `harness-view`)를 `~/.local/bin`에 링크합니다.
- `~/.claude/settings.json`에 게이트·SessionStart·알림 훅과 환경변수를 병합합니다(백업을 남깁니다).

## 레포에 적용

harness를 쓸 저장소에서 한 번 실행합니다.

```bash
cd ~/workspace/<your-repo>
harness init            # 기본: 나만 씁니다
harness init --shared   # 팀 설정으로 커밋합니다
claude                  # 평소처럼 시작합니다
```

- 기본은 `.claude/settings.local.json`(사용자별, 추적 안 됨)에 `"agent": "conductor"`를 씁니다. `--shared`는 `agent` 키만 커밋되는 `.claude/settings.json`에 씁니다. `--no-agent`는 `agent` 키를 쓰지 않습니다.
- worker deny 규칙 아홉 개(`git reset *--hard*`, `git clean *`, force push 세 형태, `.env`·`.env.*`·`~/.ssh/**`·`~/.aws/**` 읽기 차단. 목록은 [docs/reference.md](docs/reference.md))를 옵션과 상관없이 항상 `.claude/settings.local.json`에 추가합니다. init을 실행한 체크아웃에만 생기고 끌 수 없습니다. 기존 `permissions` 항목은 유지하고 빠진 규칙만 덧붙입니다. 쓸 파일이 JSON이 아니거나 비어 있거나 최상위·`permissions`가 객체가 아니거나 `permissions.deny`가 배열이 아니면 init은 아무것도 만들지 않고 파일을 그대로 둔 채 이유를 stderr에 출력하고 실패합니다.
- 이 규칙은 안전벨트이지 샌드박스가 아닙니다. `git -C`, `sh -c`, `+refspec` 푸시는 걸리지 않고 `git restore`·`git checkout -- <file>`도 막지 않습니다. `Read(.env.*)`는 `.env.example` 편집도 막습니다. `&&`로 이은 명령은 한 부분만 걸려도 통째로 거부됩니다.
- `.harness/`(리포트, 로그, 진행 기록, 설정)는 git에 들어가지 않습니다. `harness init`이 git 제외 목록에 추가합니다.
- init하지 않은 저장소에서는 게이트와 훅이 아무것도 하지 않고 `harness ask`는 거부됩니다.
- 되돌리기: `.harness/asks/`를 지우고, `agent` 키를 지웁니다. deny 규칙 아홉 개는 `.claude/settings.local.json`에 남으므로 직접 지웁니다. 이 규칙은 그 체크아웃에서 도는 모든 Claude Code 세션(conductor와 `--agent solo` 포함)에 적용됩니다. 세션 하나만 끄려면 `HARNESS_ROLE=worker claude --agent solo`.

## 최신화

harness 체크아웃에서 한 번 실행합니다.

```bash
cd ~/workspace/claude-code-setup
git pull --ff-only
./install.sh
```

agents, skills, bin, 훅은 이 체크아웃에서 심링크되고 기본값은 코드에 있으므로, 이 한 번의 갱신이 모든 저장소에 반영됩니다. `./install.sh`는 새로 추가된 파일과 settings 병합에 필요하며 반복 실행해도 안전합니다.

- 새 저장소는 `harness init`을 실행합니다(위 "레포에 적용" 참고).
- 기존 저장소는 `harness init`을 다시 실행하지 않아도 됩니다. 다시 실행해도 안전합니다. 기존 `.harness/config.json`, 진행 기록, 리포트, 로그는 건드리지 않고, `agent`가 이미 `conductor`이고 deny 규칙이 모두 있으면 settings에 아무것도 쓰지 않습니다.
- 다시 실행하면 도움이 되는 경우는 셋이며 필수는 아닙니다.
  - 2026-11-13 이전에 init한 저장소: git 제외 목록에 `.harness/`만 있습니다. 다시 실행하면 빠진 항목(`.claude/settings.local.json`, `.claude/settings.local.json.bak`, `.claude/agent-memory/`, `docs/superpowers/`)이 추가됩니다. 없으면 `git status`에 나타날 수 있습니다.
  - settings 파일에 `"agent": "conductor"`가 없는 경우.
  - #165 이전에 init한 저장소: deny 규칙이 없습니다. 다시 실행하면 추가되고, 그 전에는 `harness ask`가 경고합니다.
- `harness lane`이 만든 작업 폴더는 주 폴더의 제외 목록을 공유하고 새로 만들 때 `harness init`이 함께 돕니다. #165 이전에 만든 작업 폴더는 `harness -C <lane> ask`가 그 폴더 자신의 `settings.local.json`을 확인하므로 그 폴더에서 `harness init`을 실행할 때까지 경고합니다(주 폴더에서 다시 실행해도 소용없습니다).
- 열려 있는 conductor 세션은 시작할 때의 프롬프트를 유지합니다. 갱신 후 `claude`를 다시 시작합니다. worker가 도는 동안에는 갱신하지 않습니다(`harness status`로 확인). 이유는 [실행 중 스크립트를 제자리에서 고치면 깨진다](docs/wiki/troubleshooting/in-place-edit-breaks-running-scripts.md)에 있습니다.

## 작업 흐름

1. 사용자가 대화로 요청하면 conductor가 GitHub issue를 만들거나 연결합니다.
2. 큰 작업(동작·설계 변경, 보안·권한·훅 같은 위험 영역, 예상 비용 $5 이상)은 `/analyze`로 계획을 세워 issue에 올리고 사용자 승인을 기다립니다. 작은 작업은 승인 없이 진행합니다.
3. `harness lane <issue#>`가 작업 폴더를 만듭니다. 저장소 옆 `../<repo>-<issue#>`의 git worktree이고 브랜치는 `feat|fix|docs/<issue#>-<slug>`입니다. 코드 변경은 항상 여기서 합니다. 기본 폴더에서 `harness ask implementer`는 거부됩니다.
4. `harness -C <폴더> ask implementer '...'`로 구현합니다. lint·test를 통과해야 리포트가 나옵니다.
5. 큰 작업만 `/review`를 거칩니다. Critical/Major가 있으면 FAIL이고, Minor는 issue로 남깁니다.
6. conductor가 PR을 만듭니다(본문에 `Fixes #N`). merge는 사용자가 합니다.
7. merge 뒤 `harness lane rm <issue#>`가 폴더와 브랜치를 지웁니다. PR이 merge 또는 close되고 미푸시 커밋이 없을 때만 지워집니다.

겹치지 않는 파일을 건드리는 작업은 폴더를 나눠 병렬로 돌립니다. 상태(`.harness/`)가 폴더마다 따로라 implementer 여럿이 동시에 돕니다. 자세한 규칙은 [docs/wiki/how-to/work-folders.md](docs/wiki/how-to/work-folders.md).

워커 한 번의 실행 상한은 `headless_max_minutes`(기본 60분, implementer 90분)입니다. 상한이 와도 run을 죽이지 않고 exit 4로 돌려줍니다. 재시작·compaction 뒤에는 `harness wait <worker>`로 다시 붙습니다.

## 진행 보기

- `/watch <role>`: 워커 대시보드를 herdr/tmux 패널이나 Ghostty·Terminal 창에 엽니다. 열 수 없으면 실행할 명령을 출력합니다(`harness open-watch`).
- `harness watch <role>`: 아무 터미널에서 직접 봅니다. 사람 터미널 전용입니다.
- 데스크톱 알림: conductor가 사용자 입력을 기다리면 macOS 알림이 뜹니다(`osascript` 필요).
- `needs-decision`: 사용자 결정이 필요하면 conductor가 질문을 issue에 댓글로 달고 이 라벨을 붙입니다. 답이 오면 뗍니다.
- `harness status`와 `.harness/progress.md`로 워커 상태와 최근 ask를 봅니다.

## 주요 명령

| 명령 | 용도 |
|------|------|
| `harness ask <agent> '<instruction>'` | 워커에게 맡깁니다(보통 스킬이 호출). `--timeout MS`, `--keep` |
| `harness wait <agent>` | 실행 중인 워커가 끝날 때까지 기다립니다 |
| `harness report <agent>` | 리포트를 다시 봅니다 |
| `harness status` | 워커 상태 |
| `harness lane <issue#> [slug]`, `lane ls`, `lane rm` | 작업 폴더 생성·목록·삭제 |
| `harness open-watch <agent>` | 대시보드를 새 패널·창에 엽니다 |
| `harness watch <agent>` | 실행 스트림을 터미널에서 봅니다 |
| `harness close <agent>` | 실행을 멈춥니다(`--force`) |
| `harness metrics` | ask·종료·소요 시간 통계와 wiki 상태 |
| `harness wiki-lint` | wiki 형식 검사 |
| `harness -C <폴더> <명령>` | 다른 작업 폴더에서 실행합니다 |

exit code, 설정 키, 전체 CLI는 [docs/reference.md](docs/reference.md).

## 규칙과 지식이 있는 곳

- [AGENTS.md](AGENTS.md): 모든 에이전트가 따르는 프로젝트 규칙(언어, 브랜치, 테스트, wiki 규칙)과 Claude Code 전용 메모(역할, 게이트, 완료 판정). `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`를 만들면 Claude Code가 `AGENTS.md`를 읽지 않으므로 만들지 않습니다(`tests/install.test.sh`가 검사합니다, [wiki](docs/wiki/troubleshooting/agents-md-ignored-when-claude-md-exists.md)).
- [claude/agents/conductor.md](claude/agents/conductor.md): conductor의 동작 지침.
- [docs/wiki/index.md](docs/wiki/index.md): 함정(troubleshooting), 절차(how-to), 결정(decisions). 리포트의 Notes는 `wiki` 라벨 issue가 되고, 검토를 거친 PR로 wiki 페이지가 됩니다.
- `docs/research/`: 실험과 조사 기록.

## 테스트

```bash
./install.sh --test    # tests/*.test.sh를 병렬로 돌립니다(약 70초)
bash tests/<x>.test.sh # 스위트 하나만
```

가짜 `tests/fake-claude`를 쓰므로 Claude 없이 돕니다.
