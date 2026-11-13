# claude-code-setup: conductor

메인 세션을 **conductor(지휘 세션)** 로 쓰는 사용자 단위 Claude Code 설정. 평범한 질의는 conductor가 직접 답하고, 소스를 읽거나 고치거나 검증해야 하는 일은 `/analyze` `/implement` `/review` 스킬로 백그라운드에서 도는 headless Claude 워커(`claude -p`)에게 맡긴다. conductor는 워커 리포트만 읽는다.
이유: 메인 세션 토큰이 비싸다. conductor는 소스를 컨텍스트에 올리지 않고, 워커(`analyst` opus · `implementer` sonnet · `reviewer` opus)가 일을 한다. analyst와 implementer는 프로젝트 메모리를 가져서 코드베이스를 매번 다시 파악하지 않는다. reviewer는 일부러 메모리를 두지 않아 리뷰마다 선입견 없이 시작한다.
구조와 다이어그램은 [docs/architecture.md](docs/architecture.md), 명령·설정·게이트 상세는 [docs/reference.md](docs/reference.md), 함정과 결정은 [docs/wiki/index.md](docs/wiki/index.md).

## 빠른 시작

요구 사항: macOS, `/bin/bash` 3.2 · `jq` · Claude Code ≥ 2.1.248 · `PATH`에 `~/.local/bin`.

```bash
git clone https://github.com/geonhos/claude-code-setup ~/workspace/claude-code-setup
cd ~/workspace/claude-code-setup
./install.sh                 # 여러 번 실행해도 결과가 같다

cd ~/workspace/<your-repo>
harness init                 # 이 저장소를 harness 체크아웃으로 만든다
claude                       # 평소처럼 시작한다
```

`install.sh`는 에이전트·스킬 심링크, `bin/*` 링크, `~/.claude/settings.json`의 훅·환경변수 병합을 한다(백업을 남긴다). `harness init`은 `.harness/asks/`와 기본 설정, `.claude/settings.local.json`의 `"agent": "conductor"`를 만든다. 둘이 바꾸는 항목 전체와 `--shared` `--no-agent` 옵션은 [docs/reference.md](docs/reference.md)에 있다.

되돌리기: `.harness/asks/`를 지우고, `agent` 키를 만든 settings 파일에서 지운다. 세션 하나만 끄려면 `HARNESS_ROLE=worker claude --agent solo`.

## 어떻게 도는가

1. 일반 질문은 conductor가 바로 답한다. 소스를 읽거나 고치려 하면 게이트가 호출을 거부하고(사유에 쓸 스킬 이름이 있다), conductor가 `/analyze` 조사 · `/implement` 변경 · `/review` 검토를 호출한다. 직접 `/implement …`처럼 쳐도 된다.
2. 스킬이 `harness ask <worker> '<instruction>'`을 백그라운드로 돌린다. 워커는 detached headless 세션(`claude -p`)이고 실행 상한은 `headless_max_minutes`(기본 60, implementer 90)다. 마감이 와도 run을 죽이지 않고 exit 4로 돌려준다.
3. 워커가 끝나면 리포트(`.harness/reports/<worker>.md`, 40줄 이하)가 출력된다. implementer는 `harness-verify` 루프(format → lint → test, 최대 3회)를 통과해야 하고, reviewer는 `VERDICT: PASS|FAIL`로 끝낸다. 리포트 없이 멈추려 하면 Stop hook이 막고 쓰게 한다.
4. 재시작·compaction 뒤에는 `harness wait <worker>`로 다시 붙는다. 진행은 `harness status`로 보고, SessionStart 훅이 `.harness/progress.md`를 conductor 컨텍스트에 넣는다.

자주 쓰는 명령:

```
harness ask    <agent> '<instruction>'    # 워커에게 맡긴다 (스킬이 대신 호출한다)
harness wait   <agent>                    # run이 끝날 때까지 기다린다
harness report <agent>                    # 리포트를 다시 본다
harness status                            # 워커 상태
```

전체 CLI와 exit code, 설정 키, conductor가 직접 할 수 있는 명령의 허용 목록, 검증 루프 상세는 [docs/reference.md](docs/reference.md).

## 테스트

`./install.sh --test`가 `tests/*.test.sh`를 병렬로 돌린다. 가짜 `tests/fake-claude`를 쓰므로 Claude가 필요 없다.
