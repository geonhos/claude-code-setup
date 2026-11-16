# Karpathy 4원칙 A/B 실험 설계

날짜: 2026-11-05 · 상태: 승인됨(설계) · 산출물: 블로그용 결과 문서

## 목적

현재 하네스(baseline)와, `AGENTS.md`에 Karpathy CLAUDE.md 4원칙
(Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven
Execution)을 추가한 하네스(karpathy)의 **결과물 품질**과 **토큰 사용량**을
비교해 채택 여부를 결정한다. 결과는 블로그 글로 옮길 수 있게 정리한다.

## 비목표

- 하네스에 영구 eval 기능(`harness eval` 등)을 추가하지 않는다(AGENTS.md
  "no new mechanism" 규칙). 실행 스크립트는 일회성이며 리포에 커밋하지 않는다.
- analyst/reviewer 역할에 대한 4원칙 효과는 측정하지 않는다(implementer만).
- 채택 시 실제 `AGENTS.md` 반영은 이 실험 이후 별도 PR로 한다.

## 조건

| 조건 | 차이 |
|------|------|
| baseline | 실험 base 커밋 그대로 |
| karpathy | 같은 커밋 + `AGENTS.md` 끝에 `## Working principles` 섹션으로 4원칙 추가 |

- 4원칙 원문: `forrestchang/andrej-karpathy-skills`의 `CLAUDE.md`를 그대로
  가져오되 출처 URL과 가져온 커밋 SHA를 결과 문서에 기록한다.
- 두 조건의 차이는 오직 이 섹션뿐이어야 한다(diff로 확인해 결과 문서에 첨부).

## 과제

analyst가 `.harness/log/`에서 과거 implementer ask 4개를 고른다.

| 유형 | 4원칙이 드러날 지점 |
|------|------------------|
| 버그 수정 | 원인 확인 전 수정, 주변 코드 손대기 |
| 작은 기능 | 과잉 구현, 요청 외 옵션 추가 |
| 리팩터(prune 단계 등) | 범위 밖 수정, 동작 변경 |
| 애매한 요구 | 가정 명시/질문 vs 추측해서 진행 |

과제마다 기록: ask-id, 원래 brief 원문, 당시 base 커밋, 머지된 정답 커밋,
선정 이유. 과제의 base 커밋이 다르면 과제별로 worktree를 만든다.

## 실행

- 과제별 base 커밋에서 조건마다 git worktree 생성(스크래치 디렉터리).
- 각 실행: worktree에서 `claude -p --agent implementer --output-format json`
  (하네스 worker와 같은 에이전트 정의, `HARNESS_ROLE=worker`), brief 원문 입력.
  커밋/푸시는 하지 않도록 brief 끝에 고정 문구 추가(양 조건 동일).
- 4 과제 × 2 조건 × 3회 = 24회. 조건 순서는 실행마다 교대한다.
- 한 실행이 끝나면 diff와 JSON 결과를 저장하고 worktree를 base로 리셋.
- 실행 타임아웃 30분. 타임아웃/실패도 결과로 기록(재시도 안 함).

## 측정

정량(실행별):
- 토큰: input, output, cache_read, cache_creation; 비용($); 턴 수; 시간
- 결과물: 해당 테스트 스위트 통과 여부, diff 추가/삭제 줄 수, 수정 파일 수,
  정답 커밋에 없는 파일 수정 수(범위 밖 수정)

정성(블라인드 채점):
- reviewer 에이전트(opus)에 diff, brief, 정답 커밋을 주고 조건은 숨긴다
  (diff 순서 무작위, 라벨 익명화).
- 항목별 1–5점: 정확성, 범위 준수, 단순성, 검증(테스트/확인 수행 여부).
  점수마다 한 줄 근거.

## 분석·산출물

`docs/research/2026-11-xx-karpathy-principles-ab.md` (블로그 원고용, 한국어):

1. 배경: 하네스 구조 한 단락, 4원칙 요약
2. 실험 설계: 조건, 과제 표, 실행·채점 방법
3. 결과: 조건별 평균/범위 표(토큰, 비용, 시간, diff 크기, 점수),
   과제별 표, 실행 24회 원자료는 부록
4. 사례: 차이가 가장 컸던 diff 1–2개 나란히 비교
5. 한계: n=3, 단일 모델, 기존 프롬프트와 원칙 중복, 채점자도 LLM
6. 결론과 권고: 채택 / 부분 채택(일부 원칙만) / 기각

원자료(JSON, diff, 채점 결과)는 `docs/research/karpathy-ab/`에 둔다.

## 판정 기준(사전 등록)

- 채택: 품질 평균 점수가 0.5 이상 높고 토큰(비용)이 15% 이하로 늘거나,
  품질이 같고 비용이 줄 때
- 기각: 품질 차이 0.5 미만이고 비용이 늘 때, 또는 품질이 떨어질 때
- 그 사이: 원칙별 부분 채택을 결과 문서에서 논의

## 예산

실행 약 $20 + 채점 약 $30 ≈ $50. $80을 넘기 전에 중단하고 보고한다.
