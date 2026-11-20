---
name: korean-writing
description: Korean writing guide for text people read. Load before writing an issue, a PR body or a Korean document (README.md); not needed for code or English text.
---

# Korean writing guide

Use this before you write an issue, a PR body or a Korean document
(README.md and the like). The six core rules are in the conductor prompt; this skill adds
the detail and the examples. It applies to the conductor and to workers alike. Sources:
NIKL public-language guides (2014, 2019), Kakao Developers documentation guideline, Kakao
Enterprise "테크니컬 라이팅 10계명", Microsoft Korean style guide, MOLEG 「알기 쉬운 법령
정비기준」; see wiki decision 0015.

## Register
- 합니다체 everywhere: chat, questions, issues, PR bodies, documents. No 해요체, no 한다체.
- Questions: "~합니까?", "~할까요?". Requests: "~해 주십시오". Instructions in a document:
  "~해야 합니다", not "~하세요" / "~하십시오".
- Fragments without a verb ending are fine inside tables and lists.
- In a PR body these stay English: the headings `## Summary` and `## Test plan` and the `Fixes #N` line (GitHub parses `Fixes`). The PR title and commit messages are English too.
- Do not rewrite existing issues or documents only to change the register.

## Sentences
- One point per sentence; split above 60 characters. A sentence that is long only because
  of a path or a command may stay.
- When you split or shorten, keep every fact, number and conditional. "would have caught"
  is "걸렀을 것입니다", not "걸렀습니다". Add no inference the source does not state.
- The subject is whoever does the action in the source. Name a person or a program when it is the one that acts ("명령은 삭제를 거부합니다" → "harness가 삭제를 거부합니다"). Never swap in an actor the source does not name: "deny rule이 우회 경로를 막지 못합니다" stays, it does not become "harness는 …"; "`/watch`가 … 을 실행합니다" does not become "Claude가 … 을 실행합니다".
- Passive only when the subject is a thing that cannot act ("파일이 저장됩니다"), the
  actor does not matter or the source names no actor. No double passive: "보여지다" → "보이다", "쓰여진" → "쓰인".
- Subject and predicate must agree: "이유는 … 비슷하다" → "이유는 … 비슷하기 때문이다".
- Double negation becomes a positive: "포함이 안 되지는 않습니다" → "포함됩니다".
- State what is certain plainly: "~할 수 있을 것으로 보입니다" → "~합니다" or "~할 수 있습니다".
- End an action with a verb: "실행할 예정입니다" → "실행합니다", "완료된 상태입니다" →
  "마쳤습니다", "수정이 필요합니다" → "수정해야 합니다". "입니다" is for definitions, values
  and states ("`main`은 `1f0095b`입니다").
- Joined items share one structure: "평화 수호와 인권을 보장하는 것" → "평화를 수호하고 인권을
  보장하는 것".
- A noun chain of three or more nouns may stay only when it contains a proper name, a code, command or file name, or a harness term (conductor, worker, analyst, gate, brief, work folder).

## Translationese (bad → rewrite)
- 버튼이 클릭되어야 → 버튼을 클릭해야
- 호환성 제고를 위하여 → 호환성을 높이기 위하여
- 이 앱에 대한 사용 권한 설정 → 이 앱의 사용 권한 설정
- 이성계에 의해 건국되었다 → 이성계가 건국했다
- 품질에 있어서 → 품질 면에서
- 이 결과는 …을 말해 주고 있다 → …을 이 결과에서 알 수 있다
- 구체화시켜 → 구체화해
- 새로 고침 수행에 실패했습니다 → 새로 고치지 못했습니다
- 현장에서 필요로 하는 → 현장에서 필요한
- 권한을 가지고 있지 않습니다 → 권한이 없습니다
- 현장 방문을 통한 → 현장 방문으로
- 진행 중에 있습니다 → 진행하고 있습니다
- 충족하는지 여부 → 충족하는지
- 계속하기를 원하십니까? → 계속하시겠습니까?

## Words
- Plain words: 제고 → 높이기, 향후 → 앞으로, 금년 → 올해, 실시하다 → 하다.
- Product, language and harness names stay in English (Android, Java, conductor, worker,
  analyst, gate, brief). Do not translate them ("분석가" is wrong for analyst).
- Other English terms: Korean with the original once at first mention, "메서드(Method)",
  then the Korean form only.
- Loanword spelling: 애플리케이션, 콘텐츠, 디렉터리, 메시지, 메서드, 릴리스, 라이선스.
- "최신", "기존", "새로운" need a version or a date. "많은", "곧", "잠시" become numbers.
- Do not close a list with "등" or "기타": name every item or link the full list.

## Structure
- First sentence of a paragraph is its conclusion. One topic per paragraph, at most five
  sentences.
- Numbered list for steps, bullets for unordered items, a table when items share three or
  more attributes.

## Checklist
- Is any sentence long or wordy?
- Can any word or sentence be read two ways?
- Do subject and predicate agree?
- Is there a needless passive, causative or translated phrase?
- Is each thing named by one term?
- Does the conclusion come first?
- Is every fact, number, conditional and actor of the source unchanged?

## Do not write
"좋은 질문입니다", "핵심은", "살펴보겠습니다", "seamless", "robust", metaphors, emoji
decoration, closing pleasantries.
