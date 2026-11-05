# Karpathy 4원칙 A/B 실험 Implementation Plan

> **For agentic workers:** conductor가 `/analyze`, `/implement`, `/review`로 task 단위 위임. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** baseline 하네스와 `AGENTS.md`+Karpathy 4원칙 하네스의 implementer 품질·토큰을 24회 실행으로 비교하고, 블로그용 결과 문서와 실험 PR을 만든다.

**Architecture:** 과제별 base 커밋에서 조건당 git worktree를 만들고 `claude -p --agent implementer --output-format json`으로 실행한다. 실행·채점 스크립트는 스크래치에만 두고(커밋 금지), 원자료와 결과 문서만 `docs/research/`에 커밋한다. 실행은 ask 타임아웃(90분)을 넘기므로 detached로 띄우고 별도 ask로 수거한다.

**Tech Stack:** bash 3.2, git worktree, `claude -p` JSON 출력, jq/awk.

**Spec:** `docs/superpowers/specs/2026-11-05-karpathy-principles-ab-design.md`

---

## 파일

- Create: `docs/research/karpathy-ab/tasks.md` — 선정 과제 4개(ask-id, brief 원문, base 커밋, 정답 커밋, 선정 이유)
- Create: `docs/research/karpathy-ab/principles.md` — 4원칙 원문 + 출처 URL + 원 리포 커밋 SHA + `AGENTS.md`에 붙인 diff
- Create: `docs/research/karpathy-ab/runs/<task>-<cond>-<n>.json|.diff` — 실행 원자료 24쌍
- Create: `docs/research/karpathy-ab/runs.csv` — 실행별 지표 한 줄씩
- Create: `docs/research/karpathy-ab/grades.csv` — 블라인드 채점 결과
- Create: `docs/research/2026-11-05-karpathy-principles-ab.md` — 블로그 원고용 결과 문서
- 스크래치 전용(커밋 금지): `run-ab.sh`, `grade-ab.sh`, worktree들

---

### Task 0: 브랜치

- [ ] `main`에서 `research/karpathy-ab` 브랜치 생성
- [ ] spec + 이 plan 커밋: `docs(spec): karpathy principles A/B design` / `docs(plan): karpathy principles A/B plan`

### Task 1: 과제 선정 (analyst)

- [ ] `.harness/log/`와 `.harness/progress.jsonl`에서 implementer ask 후보를 훑고 유형별(버그 수정, 작은 기능, 리팩터, 애매한 요구) 1개씩 고른다. 조건: brief 원문이 남아 있음, 결과가 단일 커밋/소수 커밋으로 머지됨, 실행이 30분 안에 끝날 규모, 대응 테스트 스위트가 있음.
- [ ] 과제마다 ask-id, brief 원문, base 커밋(ask 직전 HEAD), 정답 커밋 범위, 관련 스위트, 선정 이유를 보고서에 표로 남긴다.
- [ ] 완료 기준: 4개 모두 base 커밋이 `git cat-file -e`로 존재 확인됨.

### Task 2: 하니스 준비와 스모크 (implementer)

- [ ] analyst 표를 `docs/research/karpathy-ab/tasks.md`로 저장.
- [ ] `forrestchang/andrej-karpathy-skills`의 `CLAUDE.md`에서 4원칙 원문을 가져와 `principles.md`에 출처 URL, SHA와 함께 저장. `AGENTS.md` 끝에 붙일 `## Working principles` 섹션 패치도 같은 파일에 기록.
- [ ] 스크래치에 `run-ab.sh <task> <cond> <n>` 작성:
  1. 과제 base 커밋에서 worktree 생성(이미 있으면 `git reset --hard <base>` + `git clean -fdx`)
  2. `cond=karpathy`면 패치 적용; 적용 후 `git diff`가 `AGENTS.md`의 해당 섹션뿐인지 확인
  3. brief 원문 + 고정 문구 "Do not commit or push." 로 `HARNESS_ROLE=worker claude -p --agent implementer --output-format json` 실행(30분 timeout), 시작/종료 시각 기록
  4. JSON과 `git diff base`(작업 트리 포함, 패치 섹션 제외)를 `runs/`에 저장
  5. 관련 스위트 실행 결과(pass/fail), diff 추가/삭제 줄 수, 수정 파일 수, 정답 커밋에 없는 파일 수, JSON의 usage(input/output/cache_read/cache_creation), total_cost_usd, num_turns, duration을 `runs.csv`에 한 줄 append
- [ ] 스모크: 가장 작은 과제로 baseline 1회 실행해 `runs.csv` 한 줄과 JSON/diff가 생기는지 확인. 확인되면 이 스모크 결과는 버린다.
- [ ] 확인 사항을 보고서에 기록: 워커 Stop 훅(`harness-verify`)이 worktree 실행에서도 도는지(양 조건 동일하면 그대로 둔다), 중첩 `claude -p`가 정상 동작하는지.
- [ ] 커밋: `tasks.md`, `principles.md`만. 메시지 `docs(research): karpathy A/B tasks and principles`

### Task 3: 24회 실행 시작 (implementer)

- [ ] 실행 순서 생성: 과제 4 × 반복 3, 각 쌍 안에서 조건 순서 교대(1회차 baseline 먼저, 2회차 karpathy 먼저, …).
- [ ] 전체 실행 루프를 `nohup`으로 detached 실행, 로그는 스크래치. 누적 `total_cost_usd`가 $50을 넘으면 루프 중단(채점 예산 $30 별도).
- [ ] 보고서: 시작 시각, 로그 경로, 실행 순서, 예상 종료 시각. 그리고 바로 종료.

### Task 4: 실행 수거 (implementer)

- [ ] 루프 완료 확인(로그 마지막 줄). 미완료면 진행 상황만 보고하고 종료.
- [ ] `runs.csv` 24줄, `runs/` 48개 파일 확인. 타임아웃/실패 행은 그대로 둔다.
- [ ] 커밋: `docs(research): karpathy A/B raw runs`

### Task 5: 블라인드 채점 (implementer)

- [ ] 스크래치에 `grade-ab.sh` 작성: 각 실행 diff에 무작위 ID 부여(매핑 파일은 스크래치, 채점 끝날 때까지 열지 않음), diff에서 `AGENTS.md` 변경 제거.
- [ ] 각 diff를 `claude -p --agent reviewer --model opus`에 brief 원문, 정답 커밋 diff, 루브릭과 함께 입력. 출력 형식 고정: `id,correctness,scope,simplicity,verification,notes`(각 1–5, notes는 한 줄 근거).
- [ ] 매핑으로 조건 복원 후 `grades.csv` 저장. 채점 비용 합계 기록($30 상한).
- [ ] 커밋: `docs(research): karpathy A/B blind grades`

### Task 6: 결과 문서 (implementer)

- [ ] `docs/research/2026-11-05-karpathy-principles-ab.md` 작성(한국어, 블로그 원고용). 구조는 spec의 "분석·산출물" 1–6절 그대로.
- [ ] 표: 조건별 평균과 범위(input/output/cache 토큰, 비용, 턴, 시간, diff 줄, 범위 밖 파일, 4개 점수), 과제별 표.
- [ ] 사례: 조건 간 차이가 가장 큰 과제의 diff 한 쌍을 발췌 비교.
- [ ] 판정: spec의 사전 등록 기준을 그대로 적용해 채택/부분 채택/기각 결론을 적고 근거 수치를 인용.
- [ ] 재현 방법 절: 스크립트는 커밋하지 않았으므로 `run-ab.sh`/`grade-ab.sh`의 핵심 명령을 문서에 코드 블록으로 남긴다.
- [ ] `harness wiki-lint`와 docs 관련 스위트 통과 확인. 커밋: `docs(research): karpathy principles A/B results`

### Task 7: 리뷰 (reviewer)

- [ ] `main..research/karpathy-ab` 리뷰: 결과 문서 수치가 `runs.csv`/`grades.csv`와 일치하는지, 판정이 사전 기준과 맞는지, 블라인드가 유지됐는지, 스크립트·worktree가 커밋되지 않았는지.
- [ ] FAIL이면 Task 6 수정 후 재리뷰(최대 2회).

### Task 8: 실험 PR

- [ ] implementer가 브랜치 push.
- [ ] conductor가 `.harness/pr.md` 작성 후 `gh pr create --title 'docs(research): Karpathy principles A/B experiment' --body-file .harness/pr.md`. 본문: 요약 표, 판정, 채택 시 후속 PR(`AGENTS.md` 변경) 예고.
