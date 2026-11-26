# Code Mode(CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1)를 analyst에 켰을 때의 비용과 시간

**결과/결정:** 판정은 FAIL입니다. Code Mode를 켠 analyst는 turn이 24% 줄었지만 비용 중앙값은 27% 높았고 시간은 같았습니다. harness에는 넣지 않습니다. 비용을 가른 것은 Code Mode가 아니라 subagent 사용이었습니다.

CLI 2.1.332, 2026-11-25, 이슈 #239. harness는 바꾸지 않았습니다. 데이터와 스크립트: `code-mode-ab/` (`runs.csv`, `brief.md`, `known-good-report.md`, `run.sh`, `reports/`). 원본 스트림(`*.jsonl` 4개, 약 6.5 MB)은 용량 때문에 뺐고 branch `research/code-mode-ab`에 있습니다.
총 지출 **$20.05** (probe $0.03 + A/B $20.02, 예산 $15-20, 한도 $25).

## Code Mode가 무엇인지
- Claude Code의 실험 기능입니다(https://code.claude.com/docs/en/code-mode.md, 2.1.323 이상). Claude가 JavaScript를 쓰고 `REPL` tool이 그 script를 실행합니다. script 안에서 Bash, Read, Glob, Edit, Write를 부르므로 tool call 여러 개가 모델 turn 한 번에 끝납니다.
- 환경 변수 `CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1`로 켭니다. `--permission-mode`의 값이 아닙니다(`claude --help`: acceptEdits, auto, bypassPermissions, manual, dontAsk, plan).
- Code Mode에서는 Read, Bash, Glob, Grep, Edit, Write를 REPL 안에서만 부를 수 있습니다. 직접 부르면 "No such tool available: Glob. Glob is only available inside REPL."이 나옵니다.
- auto mode에서는 classifier가 호출 하나가 아니라 script 전체를 심사합니다.

## Stage 1: headless에서 켜지는지, 통제가 유지되는지 (haiku probe 7회, $0.032)
| Run | 설정 | 결과 |
|---|---|---|
| 1 | shell 환경 변수만 | Code Mode 꺼짐 |
| 2 | `--tools ""` | 정보 없음 |
| 3 | `--settings '{"env":{...}}'` | 켜짐. 안쪽 Bash 호출의 id가 `toolu_cc_*`, hook과 Stop 실행 |
| 4 | deny hook + deny rule | classifier가 script 전체를 거부 |
| 5 | 중립 프롬프트 | hook이 f3을 거부, deny rule이 f4를 가림, 전체 거부 1회, 직접 Glob 호출은 거부 |
| 6 | `write()` | Write의 PreToolUse를 거침 |
| 7 | 실제 conductor gate | `docs` 읽기와 `git status`는 허용, `src` 읽기와 복합 명령은 거부 |

- **headless(`claude -p`)는 `--settings`로 넘긴 환경 변수만 받습니다.** shell이나 사용자 설정의 환경 변수는 무시합니다. 문서에 없는 동작입니다. `bin/harness-run:70-71`은 `--settings`를 넘기지 않으므로 지금 worker에는 켜지지 않습니다.
- **gate는 뚫리지 않습니다.** script 안의 호출마다 PreToolUse와 PostToolUse가 원래 tool 이름으로 실행됩니다. hook의 거부와 deny rule은 호출마다 적용되고 script는 계속 실행됩니다. Stop hook도 실행됩니다.
- **전체 거부 오탐**: auto mode 5회 중 2회, 해롭지 않은 script가 통째로 거부됐습니다(haiku). 이 거부는 `denied[]`에 입력이 빈 Bash로 실립니다(`bin/harness-run:140-176`).
- Code Mode 세션은 Code Mode를 켠 채로만 resume됩니다(문서). `--keep`을 쓰려면 같은 `--settings`를 넘겨야 합니다.

## Stage 2: A/B (analyst, opus, n=2)
- 과제: 2026-11-16의 analyst ask "#105 shrink inventory"(base `43fc5a7`). 원래 실행은 $2.53, 245 s, 34 turn, subagent 없음(CLI 2.1.325). 읽기가 많고 git만 쓰며 `gh`와 네트워크가 필요 없습니다.
- 재생: 실행마다 새 `git clone`을 임시 폴더에 만들고 `43fc5a7`에서 `claude -p --agent analyst --permission-mode auto --permission-prompts none --include-hook-events --no-session-persistence`를 직접 실행했습니다. clone에는 `.harness/asks/`가 없어 Stop hook(`harness-verify done analyst`)이 바로 돌아옵니다. 두 조건이 같습니다.
- 조건: `A`(지금의 실행 줄), `B`(A + `--settings '{"env":{"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"1"}}'`).
- 계획은 조건마다 3회였습니다. 2라운드 뒤 지출이 $20.02였고 3라운드는 한도 $25를 넘기므로 **조건마다 2회에서 멈췄습니다.** 라운드마다 A와 B를 동시에 시작했습니다.
- 통과 기준(실행 전에 고정): B의 비용 또는 시간의 중앙값이 A보다 25% 이상 낮고, B의 report가 A만큼 결론을 맞게 내고, B에서 script 전체 거부가 0건.

| Run | 비용 $ | 시간 s | turn | cache read | main tool call (안쪽) | subagent tool call | Agent 실행 | 거부 |
|---|---|---|---|---|---|---|---|---|
| A1 | 2.906 | 339 | 44 | 3,066k | 42 (0) | 0 | 0 | 0 |
| B1 | 5.025 | 254 | 32 | 1,216k | 206 (206) | 38 | 2 | 0 |
| A2 | 5.901 | 415 | 43 | 3,301k | 40 (0) | 28 | 1 | 0 |
| B2 | 6.186 | 490 | 34 | 1,423k | 339 (339) | 70 | 2 | 0 |

조건별(n=2, 중앙값 [두 값]): 비용 A $4.40 [2.91, 5.90], B $5.61 [5.03, 6.19] → **B가 27% 높음**. 시간 A 377 s [339, 415], B 372 s [254, 490] → B가 1% 낮음. turn A 43.5, B 33 → B가 24% 낮음.

- 측정의 한계 2건(판정은 그대로): A2는 background Agent를 기다렸다가 깨어난 구간의 비용이 result에 잡히지 않은 것으로 보입니다. 보정하면 A의 중앙값은 약 $4.55이고 B는 약 23% 높습니다. 시간을 runner의 wall time으로 재면 A 408 s, B 374 s로 B가 8% 낮습니다.
- B의 main 세션은 cache read가 약 58% 줄었습니다. script 하나가 읽기와 검색 여러 건을 묶기 때문입니다. B의 script는 실행당 약 15개였습니다(추정: 스트림에 REPL 호출이 없어 모델 메시지 사이의 안쪽 호출 묶음을 셌습니다).
- **비용을 가른 것은 subagent입니다.** B는 두 번 모두 Agent를 2회 실행했고 A는 한 번만 1회 실행했습니다. subagent의 토큰이 비용의 대부분을 차지했습니다. A 안에서도 subagent가 없는 A1($2.91)과 있는 A2($5.90)가 2배 차이입니다.
- 거부와 hook: 4회 모두 거부 0건, script 전체 거부 0건. PreToolUse는 안쪽 호출마다 실행됐습니다(B1: 호출 244건 중 242건. 빠진 2건은 gate의 matcher 밖인 Agent). subagent의 안쪽 호출에도 실행됐습니다.
- `--agent analyst`와 opus 조합에서는 init의 `tools`에 `REPL`이 없고 스트림에 REPL 호출도 없습니다. Code Mode가 켜졌는지는 호출 id `toolu_cc_*`로만 알 수 있습니다. haiku probe에서는 REPL이 보였습니다. 원인은 모릅니다.

### 품질 (원래 report의 결론 11개와 대조)
| Run | 빠졌거나 어긋난 결론 | 점수 |
|---|---|---|
| A1 | K9 없음, K7 일부, K10이 lane 삭제로 "겨우 된다"고 함 | 9.5/11 |
| A2 | K9 일부 | 10.5/11 |
| B1 | K4 없음 | 10/11 |
| B2 | K4 일부, **K10이 어긋남**: dashboard 대신 `harness metrics` 삭제를 권함 | 9.5/11 |

4회 모두 머리 결론(약 9,386줄, 기능을 지우지 않으면 목표에 못 미침, `last_ask_record`는 죽은 코드, `gate-denied.list`와 겹치는 테스트)은 같았습니다. 줄일 수 있는 줄 수의 합계는 크게 달랐습니다(A 430과 582, B 580과 674, 원래 392). 결론 K1-K11의 정의는 `code-mode-ab/known-good-report.md`에 있습니다.

## 판정
- **FAIL.** 비용 중앙값은 B가 27% 높고(25% 이상 낮아야 통과), 시간 중앙값은 1% 낮습니다. 품질 조건(B 9.5-10, A 9.5-10.5)과 거부 조건(0건)은 채웠습니다.
- n=2로 말할 수 있는 것: B는 25% 이상 아끼는 모습을 보이지 않았습니다. B의 가장 싼 실행($5.03)이 A의 중앙값($4.40)보다 비쌉니다. 시간은 두 조건의 범위가 겹쳐서 차이를 말할 수 없습니다.
- Code Mode 자체는 기대대로 동작했습니다(turn 24% 감소, main cache read 58% 감소). 다만 analyst의 비용은 subagent를 띄우는지가 정했고, 두 조건 모두 이를 통제하지 않았습니다.
- 결정: harness에 넣지 않습니다(선택지 0). 역할별로 켜는 안(`bin/harness-run`이 `--settings`를 넘김, 요구 버전 2.1.329)은 근거가 없어 만들지 않습니다.
- 다시 잴 때의 조건: 두 조건 모두 `--disallowedTools Agent`로 subagent를 막아야 Code Mode의 효과만 볼 수 있습니다. reviewer 역할은 재지 않았습니다.
- 따로 나온 발견: analyst가 subagent를 띄우면 같은 작업의 비용이 약 2배가 됩니다(A1과 A2). analyst의 Agent 사용을 막거나 제한할지는 별도로 재야 합니다.
- 주의: n=2, 과제 하나, opus만, 라운드 안에서 A와 B가 동시에 돌았음, 품질은 analyst 한 세션이 채점함, headless에서 `--settings`로만 켜지는 동작은 문서에 없어 버전이 바뀌면 달라질 수 있음.
