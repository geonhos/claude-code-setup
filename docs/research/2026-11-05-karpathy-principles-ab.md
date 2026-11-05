# Karpathy의 4원칙을 에이전트 하네스에 넣으면 나아질까? 24회 A/B 실험

> 블로그 원고 초안. 모든 수치는 `docs/research/karpathy-ab/runs.csv`와 `grades.csv`에서 계산했다.

AI 코딩 에이전트의 지침 파일에 "Andrej Karpathy가 지적한 LLM 코딩 실수를 줄이는 4원칙"을 붙이는 것이
유행이다. 우리는 그대로 붙이는 대신, 우리 하네스에서 같은 작업을 24번 돌려 보고 결정하기로 했다.
결론부터 말하면 **사전에 정한 기준으로는 "기각"** 이다. 품질 차이는 0.06점(5점 만점)이었고 비용은 1.9% 늘었다.
다만 가장 모호한 과제에서는 눈에 띄는 차이가 있었다.

## 1. 배경

**하네스.** 이 저장소(`claude-code-setup`)는 Claude Code용 conductor/worker 하네스다. 기본 세션인
conductor는 소스를 읽거나 고칠 수 없고(훅이 막는다), `/analyze`, `/implement`, `/review`로
analyst, implementer, reviewer 세 worker에게 일을 맡긴 뒤 worker가 남긴 보고서만 읽는다.
worker는 `claude -p`로 띄운 분리된 헤드리스 세션이다. 모든 에이전트는 저장소의 `AGENTS.md`(프로젝트 공통 규칙)를 읽는다.

**4원칙.** 출처는 `multica-ai/andrej-karpathy-skills`의 `CLAUDE.md`(커밋 `2c60614`)다.

1. Think Before Coding: 가정을 드러내고, 해석이 여럿이면 조용히 고르지 말고 제시한다.
2. Simplicity First: 요청한 것만, 최소한의 코드로. 투기적 추상화와 옵션 금지.
3. Surgical Changes: 요청과 직접 관련된 줄만 건드린다. 인접 코드를 "개선"하지 않는다.
4. Goal-Driven Execution: 성공 기준을 검증 가능한 형태로 바꾸고, 확인될 때까지 반복한다.

**왜 그냥 넣지 않고 실험했나.** `AGENTS.md`는 모든 에이전트가 매번 로드한다. 거기에 붙인 한 줄은 모든 실행에서
토큰으로 청구된다. 또 이 하네스의 프롬프트에는 이미 비슷한 규칙(최소 변경, 테스트 우선)이 있어서 중복일 수 있다.
"좋은 말"이 실제 diff를 바꾸는지, 바꾼다면 비용을 정당화하는지를 확인하고 싶었다.

## 2. 실험 설계

**조건 두 개.**

| 조건 | 차이 |
|------|------|
| baseline | 과제의 base 커밋 그대로 |
| karpathy | 같은 커밋 + `AGENTS.md` 끝에 `## Working principles` 섹션(4원칙 원문, 제목만 한 단계 낮춤) |

두 조건의 차이는 `exp: karpathy principles` 커밋 하나이고, 실행 스크립트가 그 커밋이 `AGENTS.md`만 건드렸는지 확인한다.
모든 base의 `CLAUDE.md`는 `@AGENTS.md`로 시작하므로 이 섹션은 세션에 그대로 로드된다.

**과제 4개.** 이 저장소의 실제 과거 implementer 요청(brief 원문)에서 유형별로 하나씩 골랐다(`tasks.md`).

| 과제 | 유형 | 고른 이유 |
|------|------|-----------|
| T1 | 버그 수정 | 원인이 명확한 TDD brief. 원인 확인 전 수정과 주변 코드 손대기가 드러난다 |
| T2 | 작은 기능 | 설계 선택이 있는 다부분 brief(스위트 병렬 실행, 프롬프트 문구). 과잉 구현이 드러난다 |
| T3 | 리팩터 | 코드 이동만 하는 작업. diff로 객관적 확인이 가능하다 |
| T4 | 애매한 요구 | 오래된 줄 번호를 다시 찾아야 하고, 이미 끝난 항목을 건너뛰어야 한다. 과잉 구현이 주된 실패 |

**재생(replay) 방식.** 실행마다 새 `git clone --local --no-hardlinks`로 과제의 base 커밋을 체크아웃하고,
`origin`을 제거하고 이후 히스토리를 가지치기(`gc --prune`)해서 에이전트가 정답 커밋을 볼 수 없게 했다.
원래 brief에서 원격이 필요한 문장(`git pull`, `git push`)만 뺐고, 양쪽에 같은 접미 문장
`Do not push. Local commits are fine.`을 붙였다. implementer의 Stop 훅(`harness-verify`)은 PATH 앞에 둔 빈 shim으로
**양쪽 모두** 끄고 같은 에이전트 정의(`claude -p --agent implementer`)를 썼다. 사용한 모델은 implementer 기본값(Sonnet)이다.

**반복과 순서.** 과제×조건당 n=3, 총 4×2×3=24회. 한 과제의 두 조건은 동시에 돌렸고(5초 간격),
반복마다 시작 순서를 번갈았다(홀수 반복은 baseline 먼저, 짝수는 karpathy 먼저). 실행 타임아웃은 30분이었고 시간 초과는 없었다.
24회 모두 exit 0이다.

**블라인드 채점.** 24개 실행에 무작위 ID(R01–R24)를 붙이고 순서를 섞었다(매핑은 채점이 끝날 때까지 별도 보관).
채점자는 opus 모델의 reviewer 에이전트이며, 도구 없이 텍스트만 보고 판단한다. 입력은 brief, 과제별 맥락 한 줄,
정답 커밋 범위의 diff, 실행의 diff, 실행의 최종 메시지다. 최종 메시지에서 원칙·`AGENTS.md`를 언급하는 줄은 지웠다
(redaction 수는 `grades.csv`의 `redactions`). 항목은 1–5점이다: 정확성(correctness), 범위 준수(scope),
단순성(simplicity), 검증(verification). 점수마다 한 줄 근거를 받는다. 채점 비용은 $6.49, 실행 비용은 $7.39였다.

**사전 등록한 판정 기준**(설계 문서 그대로):

> - 채택: 품질 평균 점수가 0.5 이상 높고 토큰(비용)이 15% 이하로 늘거나, 품질이 같고 비용이 줄 때
> - 기각: 품질 차이 0.5 미만이고 비용이 늘 때, 또는 품질이 떨어질 때
> - 그 사이: 원칙별 부분 채택을 결과 문서에서 논의

여기서 품질은 실행별 4개 점수의 평균을 조건 내에서 다시 평균낸 값, 비용은 `cost_usd` 합계로 정의했다.

## 3. 결과

계산은 `runs.csv`와 `grades.csv`를 (task, cond, n)으로 조인하는 작은 awk 스크립트로 했다(7절 참고).
표의 형식은 `평균 [최소–최대]`이고 조건당 12회 기준이다.

### 3.1 조건별 전체

| 지표 | baseline | karpathy |
|------|----------|----------|
| input 토큰 | 26.2 [16–42] | 25.3 [14–48] |
| output 토큰 | 6,414 [3,216–11,190] | 6,119 [3,213–11,392] |
| cache_read 토큰 | 616,194 [325,607–1,221,067] | 608,217 [276,277–1,533,645] |
| cache_creation 토큰 | 44,766 [10,008–73,138] | 47,184 [35,087–74,910] |
| 비용 (USD/회) | 0.305 [0.122–0.527] | 0.311 [0.216–0.567] |
| 턴 수 | 13.3 [8–21] | 12.8 [7–24] |
| 시간 (초) | 563 [214–967] | 527 [261–815] |
| diff 추가 줄 | 125.8 [46–326] | 116.8 [29–326] |
| diff 삭제 줄 | 99.8 [14–322] | 91.6 [3–322] |
| 수정 파일 수 | 6.75 [5–9] | 6.50 [5–9] |
| 범위 밖 파일 수 | 0.92 [0–2] | 0.75 [0–2] |
| 정확성 | 4.58 [4–5] | 4.33 [3–5] |
| 범위 준수 | 4.42 [3–5] | 4.67 [4–5] |
| 단순성 | 4.17 [3–5] | 4.33 [4–5] |
| 검증 | 3.00 [2–4] | 3.08 [2–5] |
| **품질(4개 평균)** | **4.04** [3.25–4.50] | **4.10** [3.50–5.00] |

"범위 밖 파일"은 실행이 수정했지만 정답 커밋 범위(`.harness/` 제외)에는 없는 파일의 수다.

### 3.2 비용 합계

| | baseline | karpathy | 차이 |
|---|---|---|---|
| 24회 중 12회 `cost_usd` 합 | $3.6584 | $3.7295 | +$0.0711 (**+1.94%**) |
| output 토큰 합 | 76,962 | 73,425 | −4.6% |
| cache_creation 토큰 합 | 537,189 | 566,204 | +5.4% |
| 시간 합 | 6,762초 | 6,319초 | −6.6% |

output 토큰과 시간은 줄었지만 cache_creation이 늘어서 비용은 약간 올랐다. 추가된 섹션이 컨텍스트에 한 번 더
기록되는 비용이 반영된 것으로 보인다(이 해석은 가설이며 따로 검증하지 않았다).
비용 차이는 한 과제의 반복 간 편차(예: T4 baseline 0.493–0.527, karpathy 0.423–0.567)보다 작다.

### 3.3 과제별 (평균, n=3)

| 과제 | 조건 | 비용 합계 | 추가/삭제 줄 | 파일 | 범위 밖 파일 합 | 정확성 | 범위 | 단순성 | 검증 | 품질 |
|------|------|-----------|--------------|------|-----------------|--------|------|--------|------|------|
| T1 버그 | baseline | $0.788 | 65.7 / 19.7 | 5.0 | 6 | 5.00 | 5.00 | 4.00 | 4.00 | 4.50 |
| T1 버그 | karpathy | $0.756 | 57.7 / 7.7 | 5.0 | 6 | 4.33 | 4.67 | 4.00 | 3.33 | 4.08 |
| T2 기능 | baseline | $0.725 | 49.3 / 15.7 | 7.0 | 0 | 4.33 | 4.33 | 4.00 | 2.00 | 3.67 |
| T2 기능 | karpathy | $0.762 | 42.0 / 14.0 | 7.0 | 0 | 3.67 | 4.67 | 4.00 | 2.00 | 3.58 |
| T3 리팩터 | baseline | $0.627 | 325.7 / 321.7 | 6.0 | 0 | 5.00 | 5.00 | 5.00 | 3.00 | 4.50 |
| T3 리팩터 | karpathy | $0.711 | 325.7 / 321.7 | 6.0 | 0 | 5.00 | 5.00 | 5.00 | 3.67 | 4.67 |
| T4 모호 | baseline | $1.518 | 62.3 / 42.0 | 9.0 | 5 | 4.00 | 3.33 | 3.67 | 3.00 | 3.50 |
| T4 모호 | karpathy | $1.500 | 41.7 / 23.0 | 8.0 | 3 | 4.33 | 4.33 | 4.33 | 3.33 | 4.08 |

과제별 품질 차이(karpathy − baseline): T1 −0.42, T2 −0.08, T3 +0.17, T4 **+0.58**.
T1의 "범위 밖 파일"이 양쪽 모두 6인 것은 brief가 요구한 inbox 노트 두 개가 정답 범위에서 제외된 파일이기 때문으로 보인다.
T4의 모호한 brief에서만 차이가 컸고, 이 과제의 diff 크기는 baseline의 평균 +62/−42에서 karpathy +42/−23으로 줄었다.

## 4. 사례: T4 반복 2

조건 간 차이가 가장 컸던 쌍이다(같은 brief, 같은 base `77252a8`).
brief는 "gate 정책 표 이동, allowlist 정리, ADR 0012 작성" 등을 요구하지만, 분석에 따르면 계획의 대부분은
base에 이미 반영되어 있었다. 좋은 실행은 이를 확인하고 건너뛴 뒤 남은 일(`--via` 제거, ADR)만 한다.

| | baseline (R17) | karpathy (R16) |
|---|---|---|
| diff | +92 / −63, 9개 파일, 범위 밖 2개 | +29 / −22, 7개 파일, 범위 밖 0개 |
| 건드린 파일 | `bin/harness`, `claude/agents/conductor.md`, `claude/hooks/conductor-gate.sh`, ADR 0011/0012, 위키 index/log, gate·progress 테스트 | `bin/harness`, ADR 0011/0012, 위키 index/log, gate·progress 테스트 |
| 점수 (정확/범위/단순/검증) | 4 / 3 / 3 / 3 | 5 / 5 / 5 / 4 |
| 소요 | $0.527, 20턴, 690초 | $0.423, 14턴, 441초 |

**채점자 근거(원문 번역).** baseline: "`--via` 제거와 거부 테스트는 추가했지만, brief에 필요 없던 `conductor.md` 문구 변경과
중복된 allow 테스트를 넣었고 0005 페이지는 수정하지 않았다." karpathy: "참조 답과 매우 가깝다. `--via` arm을 제거하고
usage-error 테스트를 추가했으며, 이미 반영된 gate 커밋은 올바르게 건너뛰었다. ADR도 간결하다. 검증은 `install.sh --test`
통과 진술에 의존한다."

**diff 발췌 — gate 테스트.** baseline은 `--via` 테스트를 지우는 것 외에 "You may run directly" 형태별 허용 테스트
11줄을 새로 넣었다(brief가 "없으면 gate 테스트를 추가"하라고 한 항목을 문자 그대로 따른 것이다).

```diff
 # baseline: tests/gate.test.sh
-expect allow $C "bash harness ask --via"  "$(bcmd "harness ask implementer 'x' --via skill")"
...
+# --- Bash: every form under "You may run directly" in claude/agents/conductor.md ---
+expect allow $C "direct: harness status"          "$(bcmd 'harness status')"
+expect allow $C "direct: gh pr view 1"            "$(bcmd 'gh pr view 1')"
+... (총 11줄)
```
```diff
 # karpathy: tests/gate.test.sh
-expect allow $C "bash harness ask --via"  "$(bcmd "harness ask implementer 'x' --via skill")"
```

**diff 발췌 — ADR 0012.** 두 실행 모두 20줄짜리 ADR을 썼다. karpathy는 "정책 표는 이미 한 블록에 있어 이동이 필요 없었다"고
기록하고 `conductor-gate.sh`를 건드리지 않았다. baseline은 gate 상단에 `POLICY TABLES` 블록을 새로 만들어 gate가 513줄에서 518줄이 됐다고 ADR에 적었고,
`conductor.md`의 문장도 고쳤다.

```diff
 # baseline: claude/hooks/conductor-gate.sh (정답 커밋에는 없는 변경)
+# === POLICY TABLES ===========================================================
+# Everything the conductor may do or is told lives in this block: deny messages,
+# the Bash allowlist, the gh subcommand list and the git option denials. ...
+MSG_WRITE="Conductor cannot edit source. Delegate with the /implement skill ..."
```

이 한 쌍이 전체를 대표하지는 않는다. 같은 과제의 반복 1과 3에서는 차이가 훨씬 작았다(품질 3.75 대 3.75, 3.50 대 3.75,
`grades.csv`). 그래도 "요청에 없는 곳을 건드리는 정도"가 줄어드는 방향은 T4 세 번 모두에서 보였다(범위 점수 baseline 4/3/3, karpathy 4/5/4).

## 5. 한계

- **표본이 작다.** 과제 4개, 조건당 3회. 품질 평균의 0.06점 차이는 잡음 범위 안이다. 통계적 검정은 하지 않았다.
- **모델과 채점자가 하나다.** implementer는 Sonnet 한 모델이고, 채점자는 LLM(opus) 한 모델이다. 채점자는 도구 없이 텍스트만 보며,
  자신의 취향(예: 짧은 diff 선호)이 단순성·범위 점수에 섞였을 수 있다. 사람 채점과의 일치는 확인하지 않았다.
- **검증 점수의 근거가 약하다.** 실행의 최종 보고서(`.harness/reports/implementer.md`)를 보존하지 않아서, 최종 메시지는
  보고서 위치를 가리키는 한 줄(`REPORT: ...`)뿐이었다. 그래서 검증 점수는 사실상 diff에 테스트가 있는지만 본 것이다.
  T2의 검증이 양쪽 모두 2.00인 것도 이 때문이다. **다음에는 보고서와 실행 로그를 함께 저장해야 한다.**
- **스위트가 동시 실행에서 실패했다.** 한 과제의 두 실행이 같은 머신에서 동시에 스위트를 돌리자 T2·T4의 12회 전부가 `suites_pass=0`이었다.
  원인은 HUP 관련 테스트였고, 변경을 적용한 새 클론에서 스위트를 하나씩 단독 실행하면 12회 모두 통과했다
  (`suites_pass_alone=1`, 방법은 `suite-reference.md`). 즉 `suites_pass`는 이 비교에서 정보가 없다.
- **오늘의 프롬프트와 옛 트리.** 과제는 과거 base 커밋에서 재생했으므로 에이전트는 그 시점의 프롬프트·훅이 아니라 현재 설치된
  agent 정의(`--agent implementer`)로 옛 트리를 작업했다. 당시 실행과 정확히 같은 환경이 아니다.
- **토큰 집계가 일부를 놓칠 수 있다.** `usage` 필드는 최상위 에이전트 기준이라 서브에이전트나 advisor 호출의 토큰이 빠졌을 수 있다. 비용(`total_cost_usd`)이 이를 포함하는지는 확인하지 않았다.
- **원칙이 기존 규칙과 겹친다.** 이 하네스의 implementer 프롬프트와 `AGENTS.md`에는 이미 최소 변경·테스트 우선 규칙이 있다.
  효과가 작게 나온 이유일 수 있지만, 겹침의 정도는 측정하지 않았다.
- T2 정답 커밋에는 나중에 고쳐진 결함이 있었고, 채점자에게 그 점을 맥락으로 알려 정답과 다르다는 이유로 감점하지 않게 했다.
  이 맥락 문장도 채점 결과에 영향을 줬을 수 있다.

## 6. 결론과 권고

**사전 기준을 기계적으로 적용한다.**

| 항목 | 값 |
|------|----|
| 품질 평균 | baseline 4.042, karpathy 4.104 → **+0.062** (기준 0.5 미만) |
| 비용 합계 | baseline $3.6584, karpathy $3.7295 → **+1.94%** (비용 증가) |
| 채택 조건 | (품질 +0.5 이상 그리고 비용 +15% 이하) 또는 (품질 동일 그리고 비용 감소). 둘 다 불충족 |
| 기각 조건 | 품질 차이 0.5 미만 그리고 비용 증가. **충족** |

**판정: 기각.** 4원칙을 `AGENTS.md`에 그대로 추가하지 않는다. 품질은 사실상 같고(+0.06), 비용은 소폭 늘었다(+1.94%).

**부분 채택은 어떨까.** 기준상 "그 사이" 구간은 아니므로 판정은 바뀌지 않는다. 다만 데이터에는 읽을 거리가 있다.

- 범위 준수와 단순성은 모호한 T4에서 가장 크게 좋아졌다(범위 3.33→4.33, 단순성 3.67→4.33, diff 크기 약 1/3 감소).
  전체로도 범위 4.42→4.67, 단순성 4.17→4.33이다. Surgical Changes와 Simplicity First는 과잉 구현이 주된 실패인 작업에서 도움이 될 수 있다.
- 반대로 정확성은 T1(5.00→4.33)과 T2(4.33→3.67)에서 떨어졌다. 채점 근거를 보면 T1의 한 실행은 brief에 없는 예외(중첩 `.harness`)를 넣어 brief와 다르게 동작했고, T2의 두 실행은 `set -e` 아래에서 실패한 스위트를 처리하지 못했다(같은 결함이 정답 커밋에도 있었다). 원칙이 이 하락을 일으켰다는
  증거는 없고, n=3에서는 우연일 수도 있다.
- 명확한 과제(T3)에서는 차이가 없었다(품질 4.50 대 4.67, 비용은 +$0.084).

따라서 **후속 실험의 제안**일 뿐 결정은 아니다: 2번(Simplicity First)과 3번(Surgical Changes)만 넣은 조건을 모호한 과제 위주로
더 많이 반복해 볼 만하다. 그때는 보고서와 로그를 보존하고, 채점 결과를 사람이 일부 표본 검수하고, 스위트는 동시 실행 없이 돌려야 한다.
이번 결정은 사전 기준에 따른 기각이다.

## 7. 재현 방법

스크립트는 저장소에 커밋하지 않았다(하네스에 일회성 도구를 더하지 않는다는 규칙). 아래는 핵심 부분이다.

**실행 한 번: `run-ab.sh <T1..T4> <baseline|karpathy> <n>`**

```bash
# 새 클론, base 체크아웃, origin 제거, 이후 히스토리 제거
git clone --local --no-hardlinks -q "$REPO" "$CLONE" && cd "$CLONE"
git checkout -q -B main "$BASE"
git remote remove origin
for b in $(git for-each-ref --format='%(refname:short)' refs/heads | grep -vx main); do git branch -q -D "$b"; done
for t in $(git tag); do git tag -d "$t" >/dev/null; done
git reflog expire --expire=now --all; git gc --prune=now -q

# karpathy 조건: 섹션을 AGENTS.md에 덧붙여 한 커밋으로 (AGENTS.md만 바뀌어야 함)
cat karpathy-section.md >> AGENTS.md && git add AGENTS.md && git commit -q -m 'exp: karpathy principles'
DIFFBASE=$(git rev-parse HEAD)

# 실행: Stop 훅은 shim(`exit 0`)으로 끔, 30분 타임아웃, brief는 표준입력
PATH="$SD/shim:$PATH" HARNESS_ROLE=worker perl -e 'alarm shift; exec @ARGV' 1800 \
  claude -p --agent implementer --output-format json --permission-mode auto \
  --permission-prompts none --disallowedTools=AskUserQuestion \
  < "$SD/briefs/$RUN.prompt" > "$OUT/runs/$RUN.json"

# diff와 범위 밖 파일 수
git add -N .
git diff "$DIFFBASE" -- . ':(exclude).harness' ':(exclude).claude/agent-memory' > "$OUT/runs/$RUN.diff"
git -C "$REPO" diff --name-only "$BASE..$ANS" | grep -v '^\.harness/' | sort > ans
git diff --numstat "$DIFFBASE" -- . ':(exclude).harness' ':(exclude).claude/agent-memory' | cut -f3- | sort > mine
OOS=$(comm -13 ans mine | wc -l)

# 과제의 스위트는 병렬로 (각 15분 제한)
( perl -e 'alarm shift; exec @ARGV' 900 bash "tests/$s.test.sh" ) &

# runs.csv 행: usage와 비용은 JSON에서
jq -r '.usage.input_tokens, .usage.output_tokens, .usage.cache_read_input_tokens,
       .usage.cache_creation_input_tokens, .total_cost_usd, .num_turns' "$J"
```

반복 `N`마다 T1–T4를 순서대로 돌리고, 과제마다 두 조건을 5초 간격으로 동시에 시작한다. 시작 순서는 `N`이 홀수면 baseline 먼저다.
누적 비용이 $50에 닿으면 멈추게 했다(이번에는 닿지 않았다).

**블라인드 채점: `prep.sh`와 `one.sh <Rxx>`**

```bash
# prep.sh: 실행 목록을 섞고 R01..R24 부여, mapping.csv는 채점 폴더 밖에서 보관
ls runs/*.json | sed 's#.*/##; s#\.json##' | awk 'BEGIN{srand()}{print rand()" "$0}' | sort | cut -d' ' -f2 > order.txt
# 입력: brief + 과제 맥락 한 줄 + 정답 범위 diff + 실행 diff + 최종 메시지(원칙/AGENTS.md 언급 줄은 삭제)
{ echo "## Task brief"; cat briefs/$run.prompt; echo "## Context"; ctx $t
  echo "## Answer diff"; git diff $b $a; echo "## Run's diff"; cat runs/$run.diff
  echo "## Run's final result text"; cat in/$id.res; } > in/$id.md

# one.sh: 채점자 한 번 (도구 없이 텍스트 판단, opus)
{ cat rubric.txt; echo "Run id: $id"; cat in/$id.md; } > work/$id.prompt
HARNESS_ROLE=worker claude -p --agent reviewer --model opus --output-format json \
  --permission-mode auto --disallowedTools=AskUserQuestion < work/$id.prompt > out/$id.json
```

채점자에게는 1–5점 정수 네 개와 근거 한 줄을 CSV 한 줄로만 답하게 했다(루브릭 전문은 위 `rubric.txt` 형식 그대로).

**요약 계산.** `runs.csv`와 `grades.csv`를 (task, cond, n)으로 조인한 뒤 조건·과제별로 합계, 평균, 최소, 최대를 구했다.

```bash
awk -F, 'FNR==NR{ if(FNR>1){k=$1","$2","$3; c[k]=$5; s[k]=$6; si[k]=$7; v[k]=$8} next }
         FNR>1 { k=$1","$2","$3; q=(c[k]+s[k]+si[k]+v[k])/4; sum[$2]+=q; cnt[$2]++ }
         END   { for (x in sum) printf "%s quality %.3f\n", x, sum[x]/cnt[x] }' grades.csv runs.csv
awk -F, 'NR>1{s[$2]+=$15} END{printf "%.4f %.4f %.2f%%\n", s["baseline"], s["karpathy"],
         (s["karpathy"]-s["baseline"])/s["baseline"]*100}' runs.csv
```

## 8. 부록: 원자료

모두 `docs/research/karpathy-ab/` 아래에 있다.

- [`runs.csv`](karpathy-ab/runs.csv): 실행 24회의 정량 지표(`suites_pass_alone` 포함)
- [`grades.csv`](karpathy-ab/grades.csv): 블라인드 채점 점수와 근거, 채점 비용
- [`grade-mapping.csv`](karpathy-ab/grade-mapping.csv): 채점 ID와 실행의 대응
- [`grades/`](karpathy-ab/grades): 채점자 원본 응답(JSON)
- [`runs/`](karpathy-ab/runs): 실행별 `*.diff`와 `*.json`(에이전트 출력, usage, 비용)
- [`tasks.md`](karpathy-ab/tasks.md): 과제 4개와 brief 원문, 원문에서 고친 부분
- [`principles.md`](karpathy-ab/principles.md): 4원칙 원문 출처, 커밋 SHA, 적용한 패치
- [`suite-reference.md`](karpathy-ab/suite-reference.md): 깨끗한 클론에서의 스위트 기준 결과와 `suites_pass_alone` 산출 방법
