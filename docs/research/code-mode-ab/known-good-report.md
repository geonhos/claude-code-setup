
# analyst report — #105 축소 목록: 기능 유지로 8,423줄 이하 가능 여부
status: done
## Findings / Decisions
- 현재 9,386줄(43fc5a7)이고 목표까지 963줄 남았다. 기능을 지우지 않는 후보를 모두 합치면 약 392줄(±30%)이다. 이를 적용하면 약 8,994줄이고 목표에 약 570줄 못 미친다.
- 배치 A (위험 L, 약 137줄): 죽은 코드, 레거시 분기, 제거된 동작의 테스트.
  - `last_ask_record`는 호출처가 없다(bin/harness:109-127, 19줄). 머리 주석은 usage를 반복한다(5-39, 15줄).
  - metrics의 `clear`/`late`/`pane` 잔재(harness-metrics.sh:110-168, 18줄): 이 필드를 쓰는 코드가 없다.
  - `## Learned`와 `inbox` 레거시 15줄, install.sh의 주석과 일회성 마이그레이션 24줄, gate 머리 주석 10줄.
  - 제거된 동작의 테스트: verify.test.sh:437-462 22줄, headless.test.sh:151-164 8줄.
- 배치 B (위험 L-M, 약 117줄): 테스트 헬퍼 통합.
  - 6개 스위트가 harness-lib.sh를 source하지 않고 pass/check/setup을 다시 정의한다(45줄).
  - hrun, jqt, live_runs 등이 4-5개 스위트에 복사돼 있다(35줄).
  - gate.test.sh의 17개 probe가 gate-denied.list와 겹친다(17줄). 4개의 비슷한 reason 헬퍼는 하나로 합칠 수 있다(15줄).
- 배치 C (위험 M, gate 부분은 H, 약 79줄): 소스 중복 제거.
  - headless.sh의 ask/wait grace와 deadline 루프(20줄).
  - harness-verify의 harness_bin 로더 중복(8줄).
  - install.sh의 jq 블록 3개와 링크 루프(13줄).
  - gate의 rel/physrel/physical 경로 정규화와 bodyfile_ok/git_show_ok(23줄, H).
- 배치 D (위험 L, 약 59줄): conductor.md 안의 중복 20줄, 스킬이 반복하는 timeout과 exit 설명 10줄, implementer.md 4줄, reference.md와 architecture.md의 중복 25줄.
- 표 합계: A 137 + B 117 + C 79 + D 59 = 392줄. 순서는 A, B, D, C를 권한다(위험 낮은 순; 배치 C의 gate 부분은 따로 PR).
- 목표에 닿으려면 기능 하나를 빼야 한다.
  - 대시보드를 빼고 `harness watch`를 harness-view 스트림으로 되돌리면 약 660줄이 줄어 약 8,335줄로 목표에 닿는다.
  - 작업 폴더를 빼면 약 550줄이 줄어 약 8,445줄로 조금 모자란다.
  - open-watch(약 110줄)나 gate 단축 읽기(약 210줄)만으로는 부족하다.
- 남은 비기능 수단은 gate.test.sh의 중복 probe 삭제다(expect 468줄). probe 하나가 한 줄이라 probe를 지워야만 줄어든다. probe별 검토가 필요해 이번 추정에서 뺐다.
## Verification
- `git archive HEAD … | wc -l`: 9,386줄. `git diff --stat db418dc..HEAD`: +2097/−1134.
- 호출처 grep: `last_ask_record`를 부르는 곳이 없다. `.late`와 `.clear`는 bin/lib/harness-run 어디에도 쓰는 코드가 없고 읽는 코드만 있다.
- gate-denied.list의 명령을 gate.test.sh의 `bcmd` 줄과 대조했다: 17건이 겹친다.
- 읽은 파일: tests/harness-lib.sh, 각 스위트 머리말, conductor.md, 스킬 4개, implementer.md, reviewer.md, reference.md, architecture.md, install.test.sh:184-196. install.test는 스킬마다 `HARNESS_ROLE=worker` 문구를 확인하므로 이 문구는 지우면 안 된다.
- 전체 목록(항목, file:line, 절감 줄 수, 위험): `.harness/shrink2-inventory.md`
## Open questions
- 기능을 하나 빼서 목표를 맞출지, 약 8,994줄에서 멈출지는 사용자가 정해야 한다. 기능을 뺀다면 대시보드가 유일하게 단독으로 목표에 닿는다.
- 배치 C의 gate 경로 정규화 통합(H)을 이번 범위에 넣을지 정해야 한다.
## Notes
- 줄 수 축소는 테스트 쪽 여지가 크다. 6개 스위트가 harness-lib.sh를 쓰지 않고 헬퍼를 다시 정의한다(tests/metrics.test.sh:5-23, tests/progress.test.sh:5-38).

