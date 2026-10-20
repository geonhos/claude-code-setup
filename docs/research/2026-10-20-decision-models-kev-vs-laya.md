# 결정 모델 조사: Jev, Kev, Laya

작성일: 2026-10-20
목적: conductor가 사용자 입력을 받았을 때 "직접 답한다 / analyst / implementer / reviewer에게 넘긴다"를 **LLM 호출 없이** 수십~수백 ms 안에 가르는 결정 계층을 두기 위해, Jev 계열 오픈소스 결정 모델을 비교한 기록이다. 결론은 [§6](#6-결론과-선택-근거)에 있다.

## 1. 왜 결정 모델인가

현재 harness는 conductor 시스템 프롬프트가 **모든 요청을 워커에게 위임**하도록 되어 있다. "이 옵션이 뭐야?" 수준의 질문도 opus analyst pane 기동 → 프롬프트 전송 → 최대 600 s 대기 경로를 탄다. 첫 질의는 pane split + agent start 비용이 더해져 더 느리다.

위임 여부를 가르는 방법은 셋이다.

| 방법 | 지연 | 비용 | 일관성 | 비고 |
|---|---|---|---|---|
| conductor(Claude)가 스스로 판단 | 0 | 토큰 약간 | 프롬프트 의존, 흔들림 | 가장 단순. "무조건 위임" 규칙만 빼면 됨 |
| 사용자가 스킬(`/implement` 등)로 명시 | 0 | 0 | 완전 | 매번 지정해야 함 |
| 결정 모델이 힌트 제공 (UserPromptSubmit 훅) | 30~700 ms | 로컬 RAM 2~13 GB | 높고, 로그로 남음 | 훅은 힌트만 주입. 강제 라우팅은 불가 |

세 번째 방법에 쓸 수 있는 모델이 Jev와 그 호환 구현들이다.

## 2. Jev란

[TypeSafe](https://typesafe.ai)의 "System One" 결정 모델. 텍스트/JSON state와 **타입이 있는 질문**을 받아, 텍스트를 생성하지 않고 한 번의 forward pass로 답과 확률을 돌려준다.

| 질문 타입 | 반환 | 용도 |
|---|---|---|
| `choice` | 선택지 중 하나 + 선택지별 확률 + confidence | 라우팅, 분류 |
| `score` | 순서가 있는 척도 위의 기대값 + 분포 | 심각도, 관련도 |
| `noul` | 명제가 참일 확률 P(true) | 게이트, 플래그 |

API는 `POST /v1/systemone` 하나다. 요청은 `state`, `model`, `questions{id: {type, instructions, criteria}}`, 응답은 `answers{id: {type, choice|score|probability, probabilities, confidence}}`.

**Jev 자체는 오픈소스가 아니다.** 가중치·학습 데이터 미공개, 호스팅 API만 제공, 웨이트리스트. 가격은 입력 1M 토큰당 US$0.042, 출력 무료. 공개 벤치마크(multi-turn RAG 라우팅 100건)에서 Jev 1.13은 decision-correct 61.4 %, p50 749 ms로, 정확도보다 **지연이 안정적**인 것이 장점으로 꼽힌다.

따라서 우리가 로컬에서 쓸 수 있는 것은 Jev **호환 재구현**이다.

## 3. 후보 한눈에 보기

| 프로젝트 | 라이선스 | 크기 / 백본 | 학습 방식 | Apple Silicon | 지연 (맥) | `/v1/systemone` | 제로샷 |
|---|---|---|---|---|---|---|---|
| [Kev](https://github.com/jaredpalmer/kev) | Apache-2.0 | 0.8B / 4B / 9B (Qwen3.5-Base + LoRA r16 + pointer head), 27B (full) | 결정 데이터로 LoRA 학습 | MLX 자동 | 0.8B ~150 ms, 4B ~500~720 ms | ✅ (SDK 호환) | 중간~좋음 (영어) |
| [Laya](https://github.com/NandhaKishorM/laya) | Apache-2.0 (코드 MIT) | 421M ModernBERT-large / 322M mmBERT(다국어) | 인코더 + decision head, RLCD | MPS, CPU | ~40 ms (1질문), CPU 4질문 ~450 ms | ✅ (`laya-serve`) | **약함**, 파인튜닝 전제 |
| [SemIf](https://github.com/TheoLeeCJ/SemIf-OpenJev) | MIT | 임의 Qwen (예: 3.5-4B) 로짓 직독 | 학습 없음 | MLX / MPS / llama.cpp | 3090에서 ~1 s | ❌ (CLI, JSONL) | 0.81 (저자 데이터) |
| [Von](https://github.com/wfzyx/von) | 미표기 | 395M ModernBERT | 미상 | CPU/MPS | 미보고 | ✅ | 미보고 |
| [NanoJev](https://github.com/TianyuCodings/NanoJev) | MIT | 0.6B Qwen3 + heads | 게임 환경 학습 | **CUDA만** | — | ❌ | 게임 4종만 |
| [jevlike](https://github.com/vinnylarouge/jevlike) | MIT | 트레이너 (모델 아님) | 자기 라벨로 학습 | CPU/MPS | — | ❌ | 해당 없음 |

SemIf는 느리고 HTTP 서버가 없어 훅에 넣기 부담스럽다. Von·NanoJev·jevlike는 문서·벤치·맥 지원 중 하나 이상이 빠진다. **실질적 후보는 Kev와 Laya 둘**이고, 아래에서 깊이 본다.

## 4. Kev 심층

### 4.1 구조

- 베이스: Qwen3.5-Base (0.8B/4B/9B), Qwen3.8-27B (post-trained). 베이스는 **동결**.
- 어댑터: LoRA rank 16, α 32, attention·MLP·DeltaNet projection에 적용. 0.8B 기준 11.3M 파라미터.
- 헤드: pointer head. 각 선택지 끝 토큰 `</opt>`의 hidden state를 질문의 `<decide>` state와 내적해 점수화하고 softmax. 선택지 수(1~255)에 무관하게 같은 헤드를 쓰므로 **재학습 없이 선택지를 바꿀 수 있다**.
- Qwen3.5/3.8의 Gated DeltaNet 층은 attention mask를 무시하므로, 질문마다 "state + 질문" 한 행씩 돌리고 서버가 state를 캐시한다. 같은 state에 질문을 여럿 보내면 둘째부터 빠르다(0.8B: 149 ms → 28 ms).
- 캘리브레이션: 체크포인트마다 temperature 하나(0.8B T=2.35). confidence 정의는 `(p_max − 1/K) / (1 − 1/K)`로, **측정된 정답률이 아니다**.

### 4.2 모델 표

| 모델 | 베이스 | 맥 요구 | 검증 컨텍스트 | held-out 지수 | 비고 |
|---|---|---|---|---|---|
| Kev-0.8B | Qwen3.5-0.8B-Base | 아무 Apple Silicon, MLX 가중치 ~1.5 GB, 피크 3.8 GB | 8,192 | 23.3 | 영어 전용 |
| Kev-4B | Qwen3.5-4B-Base | 32 GB 맥, 피크 13 GB | 8,192 | 38.0 | |
| Kev-9B | Qwen3.5-9B-Base | 32 GB 맥 (미측정) | 8,192 | 41.0 | |
| Kev-27B | Qwen3.8-27B | 96~128 GB 맥 (미측정), 가중치 51 GB | 65,536 | 52.3 | 베이스 학습 데이터 미상 |
| Jev (hosted) | — | — | — | 54.0 | 비교 기준 |

### 4.3 학습 데이터

- `decision-v7`: 공개 분류 데이터셋 10종 × 1,000 + 생성한 policy minimal pair 896 + 규칙 구조 60종에서 생성한 1,680 = 12,576.
- 날짜·결측 증거 1,425, 문서/스킬 16,539 (CFPB 소비자 금융 민원 5,219, 프로그램 생성 `hard-v1` 6,000, `devtools-v1` 5,320 — CodeReviewer, CommitPackFT, FlakeFlagger, Aegis).
- Jev 출력은 학습에 쓰지 않았다고 명시. 어댑터·헤드·베이스 모두 Apache-2.0.

`devtools-v1`에 코드 리뷰·커밋 메시지 데이터가 들어 있는 점은 우리 용도(개발 대화 라우팅)에 유리한 신호다.

### 4.4 평가

Kev-0.8B 모델 카드 기준:

| 패널 | Kev-0.8B | Jev |
|---|---|---|
| transfer-v4 locked test (학습에 없던 출처) | 0.697 | — |
| decision-v7 locked test | 0.838 | — |
| breadth-v1 test (14 held-out 데이터셋) | 0.586 | 0.757 |
| devtools-v1 test | 0.637 | — |
| MMLU-Pro 10지선다 | 0.230 | 0.840 |
| **When2Call (tool-call 라우팅)** | **0.133 (우연 이하)** | — |
| 날짜 계산 | 0.35 | 0.95 |

Kev-4B/9B는 "new sources" 정확도 0.817/0.820(dev), 0.838/0.852(test)로 Jev 0.857에 근접한다.

### 4.5 한계 (우리 용도 관점)

1. **When2Call(tool-call 라우팅)이 우연 이하.** 모델 카드가 "tool-call routing에 쓰지 말 것"이라고 명시한다. 우리 과제("직접 답변 vs 어떤 워커")는 분류 문제지만 성격이 tool-call 라우팅과 비슷하다. **제로샷으로 믿을 수 없고, 우리 프롬프트 로그로 파인튜닝해야 한다.**
2. **영어 전용.** 어댑터 학습 데이터가 전부 영어. 베이스 Qwen3.5는 한국어를 이해하지만 결정 헤드가 한국어 state에서 어떻게 동작하는지 측정값이 없다.
3. 선택지 순서를 바꾸면 답이 바뀔 수 있다. `/v1/systemone/permute`로 민감도를 재볼 수 있다.
4. 캘리브레이션 temperature가 하나라 confidence 순서를 못 바꾼다. 임계값을 쓰려면 자기 데이터로 다시 맞춰야 한다.
5. 맥에서 수백 ms. 0.8B는 150 ms 내외, 4B는 500~700 ms(state 캐시 시 136 ms).

### 4.6 설치·운영

```bash
git clone https://github.com/jaredpalmer/kev.git && cd kev
uv sync --extra serve                       # Apple Silicon이면 MLX 포함
uv run --extra serve python -m kev.serve --run jaredpalmer/kev-0.8b --port 8009
curl -s localhost:8009/v1/systemone -d '{
  "state": "install.sh 가 settings.json 을 덮어쓰나?",
  "model": "kev-latest",
  "questions": {"route": {"type": "choice",
    "instructions": "Who should handle this?",
    "criteria": {"direct": "...", "analyst": "...", "implementer": "...", "reviewer": "..."}}}}'
```

- Python 3.12/3.13 + `uv`. **`pip install kev`는 다른 패키지**다.
- 파인튜닝: 요청 JSON 한 줄 + 각 질문에 `label`을 붙인 JSONL. `kev.train --init_from jaredpalmer/kev-0.8b` 권장. 10~20 % 홀드아웃.
- 환경 변수: `KEV_TEMPERATURE`, `KEV_TRUNCATE_STATES`, `KEV_API_KEY` 등.

## 5. Laya 심층

### 5.1 구조

- 인코더(ModernBERT-large 421M, 또는 mmBERT-base 322M 다국어) 위에 decision head. 생성이 없는 순수 인코더라 **가장 작고 빠르다**.
- 학습: RLCD. 체크포인트 `laya`(영어), `laya-multilingual`, `laya-typed-decisions`(파인튜닝 예시), `laya-browser`(브라우저 에이전트용).
- 캘리브레이션: 타입별(`choice`/`score`/`noul`) temperature를 [0.5, 5.0]으로 클램프. 피팅 후 ECE 0.466 → 0.081(영어), 0.314 → 0.106(다국어). **`laya-multilingual`은 temperature가 없어 confidence를 그대로 쓰면 안 된다.**
- 런타임: Python(`pip install laya`, CUDA→MPS→XPU→CPU 자동), Node/ONNX(`@receptron/laya`, 1.7 GB fp32, RAM ~2 GB). HTTP: `laya-serve` → `/v1/systemone`, 그리고 MCP 서버.

### 5.2 벤치마크

| 벤치마크 | `laya` (영어) | `laya-multilingual` |
|---|---|---|
| MASSIVE intent, 영어 | 0.783 | 0.657 |
| MASSIVE intent, 13개 타언어 | 0.306 | 0.451 |
| XNLI, 영어 | 0.860 | 0.843 |
| XNLI, 14개 타언어 | 0.521 | 0.731 |
| 사용 가능 언어 (>3× random) | 23 / 51 | 48 / 51 |
| 1질문 지연 (T4) | 39.5 ms | 32.8 ms |
| typed-decisions 2,000건 | **0.362** (파인튜닝 후 0.766) | — |
| Banking77 | 0.425 (Jev 0.870) | — |
| Jev Benchmark (RAG 라우팅 100건) | — | **decision-correct 0 %**, p50 189 ms |

### 5.3 한계

1. README가 스스로 "typed-decisions에서 제로샷은 우연 수준"이라고 적는다. 외부 벤치(Jev Benchmark)에서도 0 %. **파인튜닝 없이는 쓸 수 없다.**
2. 과신(over-confident) 경향, 부정문(negation) 취약, boolean 단어 라벨에 민감, 다국어 체크포인트의 `score` 위치 편향.
3. state 예산이 `max_len − head_len − 1`로 줄어들어 선택지가 많으면 state가 잘린다. 기본 512 토큰(영어), 1,024(다국어, `max_len=8192` 가능).
4. 한국어는 "100+ 언어" 주장에 포함될 것으로 보이지만(mmBERT), 문서에 명시되지 않았고 측정값이 없다.
5. 영어 체크포인트는 영어 밖에서 급격히 나빠진다.

### 5.4 설치·파인튜닝

```bash
pip install "laya[serve]"
laya-serve            # POST /v1/systemone
```

파인튜닝 경로: Kaggle 2×T4 노트북(데이터 빌드 → RLCD → temperature 피팅 → 평가 → Hub push, ~30k 질문 4 epoch에 4~5시간) 또는 Apple Silicon MPS 스크립트(`--micro-batch 1 --grad-accum 32`). `laya.train.finetune(TrainConfig(option_layout="parallel"))`.

## 6. 결론과 선택 근거

### 6.1 우리 과제에 대한 평가

과제: `state` = 사용자 프롬프트 1~3문장(주로 **한국어**, 코드 식별자 혼재), `choice` = {direct, analyst, implementer, reviewer}. 선택지 설명은 자연어로 쓴다.

| 기준 | Kev-0.8B | Kev-4B | Laya-multilingual |
|---|---|---|---|
| 제로샷으로 바로 쓸 수 있나 | 아니오 (tool-call 라우팅 우연 이하, 영어 전용) | 가능성 있음, 미검증 | 아니오 (0 %) |
| 한국어 | 베이스는 이해, 헤드는 미학습 | 같음 | 설계상 지원, 미측정 |
| 파인튜닝 난이도 | JSONL + `kev.train`, 맥에서 가능 | 같음, 32 GB 맥 | Kaggle/MPS 스크립트, 더 느림 |
| 훅 안 지연 | ~150 ms (캐시 28 ms) | ~500~700 ms | ~40~190 ms |
| RAM | ~4 GB | ~13 GB | ~2 GB |
| 교체 가능성 | `/v1/systemone` 그대로 → 4B/9B/진짜 Jev로 URL만 바꿈 | 같음 | 같음 |
| 개발 도메인 사전 노출 | `devtools-v1` 포함 | 포함 | 없음 |

### 6.2 선택: Kev, 단 파인튜닝 전제

**Kev를 고른 이유**

1. **Jev와 같은 계약.** `/v1/systemone`를 그대로 구현해 TypeSafe SDK가 바로 붙는다. 0.8B로 시작해 정확도가 모자라면 4B, 나중에 진짜 Jev로 바꿔도 훅 코드는 URL 한 줄만 바뀐다.
2. **파인튜닝 결과의 상한이 높다.** Kev-4B/9B는 학습에 없던 출처에서 0.82~0.85로 Jev에 근접한다. Laya는 파인튜닝해도 0.77(자체 벤치)이고 외부 벤치 0 %에서 출발한다.
3. **베이스가 한국어를 이해한다.** Qwen3.5-Base는 다국어 LLM이므로 한국어 state에 대한 파인튜닝이 통할 여지가 있다. Laya 영어 체크포인트는 구조적으로 불가능하고, 다국어 체크포인트는 더 작고 약하다.
4. **개발 도메인 데이터가 이미 들어 있다.** `devtools-v1`(코드 리뷰, 커밋 메시지, flaky 테스트)은 우리 입력 분포에 가깝다.
5. 선택지·설명을 요청마다 바꿀 수 있어 워커가 늘거나 역할이 바뀌어도 재학습이 필요 없다.

**Laya를 고르지 않은 이유**

- 제로샷이 우연 수준이고 외부 벤치마크에서 0 %. 지연 40 ms라는 장점이 정확도 앞에서 의미가 없다.
- 과신 경향 + 다국어 체크포인트 temperature 부재 → confidence 임계값을 쓰기 어렵다.
- 다만 **RAM 2 GB, Node/ONNX 단일 바이너리**라는 배포 편의는 Kev가 못 따라온다. 메모리가 빡빡한 환경이거나, 나중에 우리 로그가 수천 건 쌓여 Laya 파인튜닝만으로 충분해지면 재검토할 가치는 있다.

**전제와 리스크**

- Kev-0.8B의 **제로샷은 믿지 않는다.** 모델 카드가 tool-call 라우팅에 쓰지 말라고 명시한다. 도입 순서는 ① 스킬 기반 위임 + conductor 직접 답변으로 먼저 전환, ② 훅이 프롬프트와 conductor의 실제 선택(직접 답변 / 어떤 스킬)을 JSONL로 기록, ③ 수백 건 쌓이면 `kev.train --init_from jaredpalmer/kev-0.8b`로 파인튜닝, ④ 홀드아웃 정확도가 임계값(예: 0.85)을 넘을 때만 훅에서 힌트를 켠다.
- 한국어 성능은 측정값이 없다. ③ 단계에서 반드시 확인한다.
- 훅은 힌트만 준다. Kev 서버가 내려가 있으면 훅이 조용히 빠지고 스킬 방식만 남아야 한다.
- 4B가 필요해지면 32 GB 맥과 500 ms 지연을 감수해야 한다.

## 7. 출처

- Jev: [OpenRouter: What Is Jev?](https://openrouter.ai/blog/insights/what-is-jev/), [Firecrawl: What Is Jev?](https://www.firecrawl.dev/blog/what-is-jev), [LargitData: Jev System One, Open Source and Benchmarks](https://www.largitdata.com/en/blog/jev-system-one-model-open-source-benchmark/), [Jev MCP server](https://mcpmarket.com/server/jev-2), [wavect: Jev AI Review](https://wavect.io/blog/jev-ai-decision-model-review/)
- Kev: [github.com/jaredpalmer/kev](https://github.com/jaredpalmer/kev), [HF jaredpalmer/kev-0.8b 모델 카드](https://huggingface.co/jaredpalmer/kev-0.8b)
- Laya: [github.com/NandhaKishorM/laya](https://github.com/NandhaKishorM/laya), [github.com/receptron/laya (Node/ONNX)](https://github.com/receptron/laya), [HF convaiinnovations/laya](https://huggingface.co/convaiinnovations/laya)
- 비교 기사: [DataCamp: Top 7 Open-Source Jev Alternatives](https://www.datacamp.com/blog/top-open-source-jev-alternatives), [Pinggy: Best Open Source Jev Alternatives](https://pinggy.io/blog/best_open_source_jev_alternatives_self_hosted_decision_models/)
- 기타 라우터: [Arch-Router 1.5B](https://huggingface.co/katanemo/arch-router-1.5b), [RouteLLM](https://github.com/lm-sys/RouteLLM), [semantic-router](https://github.com/aurelio-labs/semantic-router), [SemIf](https://github.com/TheoLeeCJ/SemIf-OpenJev)
- Claude Code 훅: [Claude Code Hooks Explained](https://blakecrosley.com/blog/claude-code-hooks-explained), [additionalContext 이슈 #49063](https://github.com/anthropics/claude-code/issues/49063)

벤치마크 수치는 모두 각 프로젝트의 자체 보고이며, 이 문서를 쓰는 시점에 독립 검증은 하지 않았다.
