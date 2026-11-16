# claude-code-setup

Claude Code의 메인 세션을 **conductor(지휘 세션)** 로 쓰는 사용자 단위 설정이다. 소스를 읽거나 고치거나 검증하는 일은 conductor가 직접 하지 않고, 백그라운드에서 도는 headless Claude 워커 셋에게 맡긴다.

## 무엇인가

- **conductor**: 사용자와 대화하고 issue·PR을 다룬다. 게이트(PreToolUse 훅)가 소스 읽기·수정을 막아서 워커 리포트만 읽을 수 있다.
- **워커**: `analyst`(조사·계획, opus), `implementer`(구현·테스트·커밋, sonnet), `reviewer`(diff 검토, opus). 각각 detached headless 세션(`claude -p`)이고, `/analyze` `/implement` `/review` 스킬이 `harness ask`로 띄운다.
- **검증**: implementer가 끝내려 하면 Stop 훅이 `harness-verify`(format, lint, test)를 돌리고, 실패하면 되돌려 보낸다. reviewer는 리포트를 `VERDICT: PASS|FAIL`로 끝낸다.
- **이유**: conductor 컨텍스트에 소스가 올라가지 않아 긴 세션에서도 토큰과 맥락이 유지되고, 구현한 쪽과 검토하는 쪽이 다른 세션이라 리뷰가 독립적이다.

구조와 데이터 흐름은 [docs/architecture.md](docs/architecture.md), 설정·게이트 상세는 [docs/reference.md](docs/reference.md).

## 설치

요구 사항: macOS의 `/bin/bash` 3.2, `jq`, `gh`, Claude Code(`claude`) ≥ 2.1.248, `PATH`에 `~/.local/bin`.

```bash
git clone https://github.com/geonhos/claude-code-setup ~/workspace/claude-code-setup
cd ~/workspace/claude-code-setup
./install.sh        # 여러 번 실행해도 결과가 같다
```

`install.sh`가 하는 일:
- `claude/agents/*.md`와 `claude/skills/*/`를 `~/.claude/`에 심링크한다.
- `bin/*`(`harness`, `harness-verify`, `harness-run`, `harness-view`)를 `~/.local/bin`에 링크한다.
- `~/.claude/settings.json`에 게이트·SessionStart·알림 훅과 환경변수를 병합한다(백업을 남긴다).
- 전역 gitignore에 `.harness/`를 추가한다.

## 레포에 적용

harness를 쓸 저장소에서 한 번 실행한다.

```bash
cd ~/workspace/<your-repo>
harness init            # 기본: 나만 쓴다
harness init --shared   # 팀 설정으로 커밋한다
claude                  # 평소처럼 시작한다
```

- 기본은 `.claude/settings.local.json`(사용자별, 추적 안 됨)에 `"agent": "conductor"`를 쓴다. `--shared`는 커밋되는 `.claude/settings.json`에 쓴다. `--no-agent`는 settings를 건드리지 않는다.
- `.harness/`(리포트, 로그, 진행 기록, 설정)는 git에 들어가지 않는다. `harness init`이 git 제외 목록에 추가한다.
- init하지 않은 저장소에서는 게이트와 훅이 아무것도 하지 않고 `harness ask`는 거부된다.
- 되돌리기: `.harness/asks/`를 지우고, `agent` 키를 지운다. 세션 하나만 끄려면 `HARNESS_ROLE=worker claude --agent solo`.

## 작업 흐름

1. 사용자가 대화로 요청하면 conductor가 GitHub issue를 만들거나 연결한다.
2. 큰 작업(동작·설계 변경, 보안·권한·훅 같은 위험 영역, 예상 비용 $5 이상)은 `/analyze`로 계획을 세워 issue에 올리고 사용자 승인을 기다린다. 작은 작업은 승인 없이 진행한다.
3. `harness lane <issue#>`가 작업 폴더를 만든다. 저장소 옆 `../<repo>-<issue#>`의 git worktree이고 브랜치는 `feat|fix|docs/<issue#>-<slug>`다. 코드 변경은 항상 여기서 한다. 기본 폴더에서 `harness ask implementer`는 거부된다.
4. `harness -C <폴더> ask implementer '...'`로 구현한다. lint·test를 통과해야 리포트가 나온다.
5. 큰 작업만 `/review`를 거친다. Critical/Major가 있으면 FAIL이고, Minor는 issue로 남긴다.
6. conductor가 PR을 만든다(본문에 `Fixes #N`). merge는 사용자가 한다.
7. merge 뒤 `harness lane rm <issue#>`가 폴더와 브랜치를 지운다. PR이 merge 또는 close되고 미푸시 커밋이 없을 때만 지워진다.

겹치지 않는 파일을 건드리는 작업은 폴더를 나눠 병렬로 돌린다. 상태(`.harness/`)가 폴더마다 따로라 implementer 여럿이 동시에 돈다. 자세한 규칙은 [docs/wiki/how-to/work-folders.md](docs/wiki/how-to/work-folders.md).

워커 한 번의 실행 상한은 `headless_max_minutes`(기본 60분, implementer 90분)다. 상한이 와도 run을 죽이지 않고 exit 4로 돌려준다. 재시작·compaction 뒤에는 `harness wait <worker>`로 다시 붙는다.

## 진행 보기

- `/watch <role>`: 워커 대시보드를 herdr/tmux 패널이나 Ghostty·Terminal 창에 연다. 열 수 없으면 실행할 명령을 출력한다(`harness open-watch`).
- `harness watch <role>`: 아무 터미널에서 직접 본다. 사람 터미널 전용이다.
- 데스크톱 알림: conductor가 사용자 입력을 기다리면 macOS 알림이 뜬다(`osascript` 필요).
- `needs-decision`: 사용자 결정이 필요하면 conductor가 질문을 issue에 댓글로 달고 이 라벨을 붙인다. 답이 오면 뗀다.
- `harness status`와 `.harness/progress.md`로 워커 상태와 최근 ask를 본다.

## 주요 명령

| 명령 | 용도 |
|------|------|
| `harness ask <agent> '<instruction>'` | 워커에게 맡긴다(보통 스킬이 호출). `--timeout MS`, `--keep` |
| `harness wait <agent>` | 실행 중인 워커가 끝날 때까지 기다린다 |
| `harness report <agent>` | 리포트를 다시 본다 |
| `harness status` | 워커 상태 |
| `harness lane <issue#> [slug]`, `lane ls`, `lane rm` | 작업 폴더 생성·목록·삭제 |
| `harness open-watch <agent>` | 대시보드를 새 패널·창에 연다 |
| `harness watch <agent>` | 실행 스트림을 터미널에서 본다 |
| `harness close <agent>` | 실행을 멈춘다(`--force`) |
| `harness metrics` | ask·종료·소요 시간 통계와 wiki 상태 |
| `harness wiki-lint` | wiki 형식 검사 |
| `harness -C <폴더> <명령>` | 다른 작업 폴더에서 실행 |

exit code, 설정 키, 전체 CLI는 [docs/reference.md](docs/reference.md).

## 규칙과 지식이 있는 곳

- [AGENTS.md](AGENTS.md): 모든 에이전트가 따르는 프로젝트 규칙(언어, 브랜치, 테스트, wiki 규칙).
- [CLAUDE.md](CLAUDE.md): Claude 전용 메모(역할, 게이트, 완료 판정).
- [claude/agents/conductor.md](claude/agents/conductor.md): conductor의 동작 지침.
- [docs/wiki/index.md](docs/wiki/index.md): 함정(troubleshooting), 절차(how-to), 결정(decisions). 리포트의 Notes는 `wiki` 라벨 issue가 되고, 검토를 거친 PR로 wiki 페이지가 된다.
- `docs/research/`: 실험과 조사 기록.

## 테스트

```bash
./install.sh --test    # tests/*.test.sh를 병렬로 돌린다(약 70초)
bash tests/<x>.test.sh # 스위트 하나만
```

가짜 `tests/fake-claude`를 쓰므로 Claude 없이 돈다.
