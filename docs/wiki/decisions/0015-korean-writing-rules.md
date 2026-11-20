---
type: decision
status: active
updated: 2026-11-20
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
  examples, the `korean-writing` skill (`claude/skills/korean-writing/SKILL.md`), is loaded
  with the Skill tool on demand before an issue, a PR summary or a Korean document, by the
  conductor and by the implementer.
- The guide is a skill, not a file under `~/.claude` read by path: the conductor gate
  denies every Read outside the working directory. A gate exception for that one path was
  built and dropped in review: it needed a second, lexical path check next to `canon()`,
  and its unguarded `$HOME` under `set -u` made the gate exit 1 with HOME unset, which
  Claude Code treats as allow.
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
  rule 3 therefore names people and programs as subjects (amended again after experiment 3, below).
- The banned phrases ("~에 대한", "~에 의해") appeared at most twice per output even
  without rules, and no output broke the register. A script check would mostly fire on
  sentence length, where paths and commands cause false positives.
- No guide gives a numeric sentence-length limit. 60 characters is our own number, taken
  from STE's 25 words.

Two follow-up experiments (2026-11-19 and 11-20), same generator, two blind fidelity
auditors (sonnet / opus):

- Experiment 2, same inputs. Fact errors, sums over 6 outputs: no rules 6/7, first rule
  text 13/15, rules 2 and 3 amended (Korean wording, old guide) 13/17, the shipped English
  text with the skill body 8/7. The first finding held under re-audit. The skill quotes two
  sentences of those inputs, so part of the last gain may be copied.
- Experiment 3, fresh inputs. Chat (core rules only, 4 outputs): fact errors no rules 2/1,
  shipped rule 3 1/5, amended rule 3 4/4; the excess of the amended case is the report's
  status and topic line, dropped. Document (core rules + skill, 2 outputs): no rules 2/5,
  shipped 2/4, amended 0/2.
- Sentences that name a doer the source does not name (non-blind tally): chat 13 with the
  shipped rule 3, 0 with the amended one; document 4 and 0. Rule 3 therefore says the
  subject is whoever acts in the source, and a rule or a file stays the subject when it is
  what the source describes.
- Chat judge score 3.64 (shipped) and 3.25 (amended), inside the run spread of 0.57, one
  judge pass.

## Consequences
- Limits of the evidence: 2 to 6 outputs per case, one judge pass, auditors agree fully on
  about a third to two thirds of the outputs. Core rules alone did not bring chat fact
  errors below "no rules"; in chat about a third of the sentences still pass 60 characters
  and the report's status line tends to be dropped.
- Existing issues in 한다체 stay as they are.
- The skill's listing line (about 60 tokens) is in every conductor and worker session.
- A hook check is added only for a rule that real issues break repeatedly (#183).
- The raw outputs of the experiment are not in the repository; the issue comment holds the
  tables.
