# claude-code-setup: conductor

메인 세션을 conductor(지휘 세션)로 쓰는 Claude Code 설정이다. 메인 세션은 질문에 답하고 일을 나눠 주기만 하고, 소스를 읽거나 고치거나 검토하는 일은 백그라운드의 headless 워커 세션(`claude -p`)이 맡는다. conductor는 워커가 돌려주는 40줄 이하의 리포트만 읽는다.

A Claude Code setup where the main session only conducts: headless worker sessions read, change and review the code and send back short reports.

```mermaid
flowchart LR
  U([사용자]) <--> C["conductor<br/>메인 세션 · 소스를 읽지 않는다"]
  C -- "harness ask" --> A["analyst<br/>opus · 조사 · 계획"]
  C -- "harness ask" --> I["implementer<br/>sonnet · 변경 · 테스트 · 커밋"]
  C -- "harness ask" --> R["reviewer<br/>opus · 심사"]
  A & I & R -- "리포트 ≤ 40줄" --> C
  I -. "format → lint → test 루프" .-> V[harness-verify]
```

## 이렇게 만든 이유

메인 세션의 토큰이 비싸다. 파일을 한 번 읽으면 그 내용이 세션이 끝날 때까지 컨텍스트에 남고, 긴 세션일수록 이런 덤프가 쌓여서 비용과 compaction 횟수가 같이 는다. 그래서 conductor는 소스를 아예 읽지 못하게 훅 게이트로 막아 두고, 읽고 고치는 일은 더 싼 모델의 워커가 하게 했다.

워커 셋 중 analyst와 implementer는 프로젝트 메모리를 가진다. 코드베이스를 매번 처음부터 파악하지 않게 하려는 것이다. reviewer에는 일부러 메모리를 두지 않았다. 지난 리뷰의 판단이 다음 리뷰에 묻어나지 않게 하고 싶었다.

## 이렇게 보인다

세션 하나를 줄여서 옮긴 것이다. 게이트 거부 메시지와 리포트 형식은 실제와 같다.

```
> bin/harness의 exit code 설명을 README에 맞춰 고쳐줘

  Edit README.md
  ✗ Conductor cannot edit source. Delegate with the /implement skill (implementer worker).

> /implement README의 exit code 설명을 bin/harness의 실제 값에 맞춘다. 커밋은 하지 않는다.

  harness ask implementer 'Read .harness/task-implementer.md and do it.'   (백그라운드, 4분 48초)

  # implementer report — align README exit codes with bin/harness
  status: done
  ## Changed files
  - README.md — exit code 설명 (0-5)
  ## Verification
  - ./install.sh --test → 11 suites, FAIL 0
  ## Open questions
  - none
```

conductor는 이 리포트를 읽고 사용자에게 요약해 준다. 사소하지 않은 변경이면 뒤이어 `/review`를 부르고, reviewer는 리포트 끝에 `VERDICT: PASS` 또는 `FAIL`을 적는다.

## 빠른 시작

macOS에서 `/bin/bash` 3.2, `jq`, Claude Code 2.1.248 이상이면 된다. `~/.local/bin`이 `PATH`에 있어야 한다. [herdr](https://herdr.dev) 0.9 이상은 선택 사항으로, 워커 화면을 옆에 띄워 보고 싶을 때만 필요하다.

```bash
git clone https://github.com/geonhos/claude-code-setup ~/workspace/claude-code-setup
cd ~/workspace/claude-code-setup
./install.sh                 # 여러 번 실행해도 결과가 같다

cd ~/workspace/<your-repo>
harness init                 # 이 저장소를 harness 체크아웃으로 만든다
claude                       # 평소처럼 시작한다
```

`install.sh`는 에이전트와 스킬을 `~/.claude`에 심링크하고, `bin/*`를 `~/.local/bin`에 링크하고, `~/.claude/settings.json`에 훅을 병합한다(백업을 남긴다). `harness init`은 저장소에 `.harness/asks/`와 기본 설정을 만들고 `.claude/settings.local.json`에 `"agent": "conductor"`를 쓴다.

되돌리려면 `.harness/asks/`를 지우고 settings 파일의 `agent` 키를 지우면 된다. 세션 하나만 conductor 없이 쓰려면 `HARNESS_ROLE=worker claude --agent solo`.

## 어떻게 도는가

일반 질문은 conductor가 그냥 답한다. 소스를 읽거나 고치려는 도구 호출은 게이트가 거부하는데, 거부 사유에 어떤 스킬을 쓰면 되는지 적혀 있어서 conductor가 `/analyze`(조사), `/implement`(변경), `/review`(검토)를 호출한다. 사용자가 직접 `/implement …`라고 쳐도 된다.

스킬은 `harness ask <worker>`를 백그라운드로 돌린다. 워커는 detached headless 세션이고, 실행 상한은 `headless_max_minutes`(기본 60, implementer 90)다. 상한이 지나도 run을 죽이지는 않고 exit 4로 돌려주며, 나중에 `harness report`로 수집한다. implementer는 format → lint → test 루프를 통과해야 리포트를 낼 수 있고, 리포트 없이 끝내려 하면 Stop hook이 돌려보낸다. 재시작이나 compaction 뒤에는 `harness wait <worker>`로 다시 붙고, SessionStart 훅이 `.harness/progress.md`의 진행 요약을 conductor에 넣어 준다.

| 역할 | 모델 | 메모리 | 하는 일 |
|---|---|---|---|
| conductor | 메인 세션 | 진행 요약만 | 질의 응답, 위임, 리포트 읽기, PR |
| analyst | opus | 프로젝트 메모리 | 조사, 설계, 계획. `docs/` 밖은 고치지 않는다 |
| implementer | sonnet | 프로젝트 메모리 | 변경, 테스트, 커밋, 푸시 |
| reviewer | opus | 없음 | diff 심사, `VERDICT: PASS\|FAIL` |

자주 쓰는 명령은 이 정도다.

```
harness ask    <agent> '<instruction>'    # 워커에게 맡긴다 (보통은 스킬이 호출한다)
harness wait   <agent>                    # run이 끝날 때까지 기다린다
harness report <agent>                    # 리포트를 다시 본다
harness status                            # 워커 상태
harness metrics                           # 최근 28일 ask 수, 실패율, 소요 시간
```

## 실제 사용량

이 저장소 자체를 이 루프로 개발하고 있다. `harness metrics`로 본 최근 28일(2026-10-08 ~ 11-05) 수치다.

| 지표 | 값 |
|---|---|
| ask | 250회 (analyst 42, implementer 135, reviewer 73) |
| 워커 소요 중앙값 | analyst 4분, implementer 5분, reviewer 3분 |
| reviewer FAIL 비율 | 36% |
| implementer 검증 실패율 | 0.7% |

## 테스트

`./install.sh --test`가 `tests/*.test.sh` 11개 스위트를 병렬로 돌린다. 가짜 `tests/fake-herdr`와 `tests/fake-claude`를 쓰기 때문에 herdr나 Claude 없이도 돈다.

## 더 읽기

- [docs/reference.md](docs/reference.md): 설치 상세, `harness init` 옵션, CLI 전체와 exit code, 설정 키, 검증 루프, conductor 게이트 허용 목록, 디렉터리 구성
- [docs/architecture.md](docs/architecture.md): 런타임 데이터 흐름, ask 시퀀스, 게이트 판정 흐름
- [docs/wiki/index.md](docs/wiki/index.md): 함정, 절차, 결정 기록

MIT License.
