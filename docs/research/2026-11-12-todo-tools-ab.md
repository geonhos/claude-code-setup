# Task 도구(CLAUDE_CODE_ENABLE_TODO_TOOLS=1) 오버헤드 측정

CLI 2.1.322, 2026-11-12. 하네스는 바꾸지 않았다. 원자료와 스크립트: `todo-tools-ab/` (`runs.csv`, `runs/*.jsonl|diff`, `s1/*.jsonl`, `run.sh`, `suites.sh`).
총 지출 **$6.86** (stage 1 $2.16 + stage 2 $4.70, 예산 $15).

## 설정
- Stage 1: 임시 디렉터리에서 `claude -p --output-format stream-json --verbose --permission-mode auto`. 모델은 implementer 기본 `sonnet`(=claude-sonnet-5-5)과 analyst 기본 `opus`(=claude-opus-5-5).
- Stage 2: karpathy A/B와 같은 재생(fresh `git clone --local`, origin 제거, 이후 히스토리 제거, `claude -p --agent implementer`, Stop 훅 shim으로 끔). 과제 T1(버그 수정, 작음, base `2b30519`)과 T4(애매한 요구, 큼, base `77252a8`), brief는 `karpathy-ab/tasks.md` 그대로.
- 조건: `base`(현행), `todo`(`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`), 그리고 추가 조건 `nudge`(todo + brief 끝에 "TaskCreate/TaskUpdate로 진행을 추적하라" 한 문단; 아래 이유 참고). 셀당 n=2, 총 12회. 12회를 동시에 돌려서 **시간은 서로 간섭**한다.

## Stage 1: 도구 노출과 사용
| 조건 | init `tools`에 있는 Task/Todo 도구 | 3단계 파일 만들기, sonnet / opus |
|---|---|---|
| 없음 | `Task`(서브에이전트), `TaskStop`만 | Task 도구 호출 0 / 0 |
| `ENABLE_TODO_TOOLS=1` | + `TaskCreate TaskGet TaskList TaskUpdate` | 0 / 0 |
| `ENABLE_TODO_TOOLS=1 ENABLE_TASKS=0` | + `TodoWrite` (TaskCreate 등은 없음) | 0 / 0 |

- 두 변형 모두 도구는 노출되지만, 모델은 **지시 없이는 부르지 않았다**. 6단계 CLI 만들기(sonnet/opus x todo/todowrite, 4회)와 `--agent implementer` 6단계(todo, 1회)도 호출 0.
- `--agent implementer`에서는 Task 도구가 init `tools`에는 있지만 지연(deferred) 도구라 `ToolSearch select:TaskCreate,TaskUpdate`를 한 번 거쳐야 쓸 수 있다.
- 지시("task list로 추적")를 주면 사용: TaskCreate 6 + TaskUpdate 9, 총 22턴 $0.153(같은 brief 무지시는 6턴 $0.115).
- 입력 모양: `TaskCreate {subject, description}` (activeForm 없음), `TaskUpdate {taskId:"1", status:"in_progress|completed"}`.
- 결과: TaskCreate의 `tool_use_result` = `{"task":{"id":"1","subject":...,"description":...}}`; TaskUpdate = `{"success":true,"taskId":"1","updatedFields":["status"],"statusChange":{"from":"pending","to":"completed"}}`. id는 문자열 "1","2",... 순번. TodoWrite 경로는 이번에 한 번도 불리지 않아 모양을 못 봤다.
- 게이트 통과(도구는 노출됨). 다만 "도구를 켜면 Steps 체크리스트가 저절로 생긴다"는 전제는 **성립하지 않았다**: 모델이 지시 없이 쓰지 않기 때문. 그래서 stage 2에 `nudge` 조건을 추가했다.

## Stage 2: A/B (n=2, 평균 [두 값])
| 과제/조건 | 총 토큰* | 출력 토큰 | 비용 $ | 시간 s | 턴 | Task 호출 |
|---|---|---|---|---|---|---|
| T1 base | 743.7k [406k, 1082k] | 8.5k | 0.333 [0.249, 0.416] | 676 [206, 1145] | 15.0 | 0 |
| T1 todo | 581.0k [450k, 712k] | 7.6k | 0.293 [0.261, 0.324] | 948 [686, 1209] | 12.5 | 0 |
| T1 nudge | 494.1k [411k, 577k] | 5.1k | 0.261 [0.241, 0.281] | 450 [252, 649] | 13.0 | 2.0 (4, 0) |
| T4 base | 1223.1k [1150k, 1297k] | 10.1k | 0.481 [0.455, 0.507] | 998 [949, 1048] | 20.5 | 0 |
| T4 todo | 1256.5k [1053k, 1460k] | 9.5k | 0.481 [0.445, 0.517] | 1040 [922, 1159] | 21.5 | 0 |
| T4 nudge | 1285.6k [1116k, 1455k] | 9.5k | 0.505 [0.462, 0.548] | 1182 [872, 1494] | 23.5 | 2.5 (5, 0) |

*input + output + cache read + cache creation. 전 12회 exit 0, 영향 스위트 전부 통과(T1: verify, harness; T4: progress, gate, harness, metrics, headless, wiki, 각각 단독 실행 결과 포함). T4-nudge-2의 headless는 동시 실행 중 tty 테스트 1건이 실패했고, 단독 재실행에서는 통과(120/0; 기존에 알려진 HUP 계열 불안정).

조건 전체 평균(과제 합산, n=4): base 비용 $0.407 / 토큰 983k / 턴 17.8; todo $0.387 (-5%) / 919k (-7%) / 17.0; nudge $0.383 (-6%) / 890k (-10%) / 18.2. 시간 base 837 s, todo 994 s(+19%), nudge 816 s(-2%).
diff 크기는 조건 간 차이가 노이즈 수준(T1 추가 64-70줄 / T4 37-103줄; T1-base-1은 삭제 144줄로 이상치, 나머지 18-24줄). 품질은 스위트 통과 외에는 채점하지 않았다.

### 과제 목록이 일과 맞았나 (nudge, Task를 쓴 2회)
- T1-nudge-1: 2개 생성, 2개 모두 completed(in_progress 없음). 맞음.
- T4-nudge-1: 4개 생성(커밋 1-4), completed 1건뿐, **3개가 pending으로 stale**(커밋 4개 모두 만들었다). nudge-2와 T1-nudge-2는 ToolSearch로 도구를 불러오고도 Task를 한 번도 안 불렀다.
- 이벤트 열(T4-nudge-1): `ToolSearch select:TaskCreate,TaskUpdate` -> `TaskCreate "Commit 1: remove --via"` -> `TaskCreate "Commit 2: policy tables at top"` -> `TaskCreate "Commit 3: trim allowlist"` -> `TaskCreate "Commit 4: ADR 0012 docs"` -> `TaskUpdate {taskId:"1",status:"completed"}`. 이후 갱신 없음.

## 판정
- **오버헤드는 측정되지 않을 만큼 작다**: Task 호출은 실행당 0-5회(전체 턴의 0-약 15%), 비용·토큰 차이는 n=2의 실행 간 편차(T1 base 한 쌍 안에서도 토큰 2.7배)보다 작다. todo/nudge가 base보다 싸 보이는 것은 노이즈다. 확실히 말할 수 있는 건 "눈에 띄는 비용 증가는 없었다"까지다.
- **정작 문제는 사용률**: 환경 변수만으로는 사용 0%(8회 중 0회 + stage 1의 다수), 지시를 붙여도 4회 중 2회만 호출, 그중 1회는 목록이 stale. 즉 Task 이벤트로 Steps 체크리스트를 만들면 대부분 비어 있거나 틀린다. 쓰려면 implementer 프롬프트에 "작업 시작 때 TaskCreate, 단계마다 TaskUpdate" 같은 강제 문구가 필요하고, 그래도 순응은 보장되지 않는다.
- 주의: n=2, 동시 실행(시간 신뢰 낮음), 품질 채점 없음(스위트 통과만), sonnet만 stage 2에서 사용, TodoWrite 경로는 stage 2에서 측정 안 함, `nudge` 문구는 한 가지뿐이라 다른 문구의 순응률은 모른다.
