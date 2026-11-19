---
type: decision
status: active
updated: 2026-11-19
sources: [issue #169, issue #183, https://github.com/geonhos/claude-code-setup/issues/169#issuecomment-7001880191]
verified_by: human
---
# 0015: Korean text for the user is written directly under six prompt rules

## Context
Korean output varied: long mixed sentences, translationese and passives, unstable terms,
and quality that changed with the session or the repository. The only rules were one Style
line in `AGENTS.md` (this repo only) and a memory note. Issue #169 started from the idea of
asking for "about 80% ASD-STE100" English; STE is English-only.

## Decision
- Six core rules sit in the conductor prompt (global, always loaded). A longer guide with
  examples, `claude/guides/korean-writing.md`, is read on demand before an issue, a PR
  summary or a Korean document. The implementer reads it before it edits a Korean document.
- Korean is written directly. Text is not drafted in STE English and translated.
- Register is 합니다체 for every surface. 한다체 has no natural question or request form;
  해요체 reads light in issues and documents.
- Rules come from six Korean guides (NIKL 2014 and 2019, Kakao Developers, Kakao
  Enterprise, Microsoft Korean style guide, MOLEG). From STE only the form is kept: a few
  numbered rules, numeric where possible.
- No hook enforces the rules yet (#183 measures real issues two weeks after merge).
- Worker reports are English; no STE line is added to worker prompts.
- No dedicated writer agent.

## Evidence
One experiment, 2026-11-19: 4 methods x 3 writing tasks x 2 runs, generator
`claude-fable-5-2`, blind judge `claude-sonnet-5-5`. Means over 6 outputs:

| method | judge (1-5) | mean sentence chars | over 60 chars | fact errors (sum) | cost per output |
|---|---|---|---|---|---|
| no rules | 2.98 | 45.9 | 23.8% | 5 | $0.17 |
| direct, with rules | 4.17 | 42.0 | 17.1% | 15 | $0.26 |
| STE then translate | 3.52 | 37.7 | 11.4% | 16 | $0.26 |
| STE then translate with rules | 4.10 | 40.6 | 14.0% | 22 | $0.32 |

- Direct and "STE then translate with rules" are not distinguishable on quality; the
  second costs 1.2x, takes 1.4x as long and had the most fact errors, most of them made in
  the English step.
- Rules raised fact errors (5 → 15): splitting sentences turned a conditional into a past
  fact and added inferences. Core rule 2 therefore says to keep facts, numbers and
  conditionals. Rules also raised inanimate subjects (2 → 8, "명령은 거부합니다"); core
  rule 3 therefore names people and programs as subjects.
- The banned phrases ("~에 대한", "~에 의해") appeared at most twice per output even
  without rules, and no output broke the register. A script check would mostly fire on
  sentence length, where paths and commands cause false positives.
- No guide gives a numeric sentence-length limit. 60 characters is our own number, taken
  from STE's 25 words.

## Consequences
- Limits of the evidence: 6 outputs per method, one judge pass, one fidelity pass. The two
  amended rules and the English wording of the rules were not measured.
- Existing issues in 한다체 stay as they are.
- A hook check is added only for a rule that real issues break repeatedly (#183).
- The raw outputs of the experiment are not in the repository; the issue comment holds the
  tables.
