---
type: decision
status: active
updated: 2026-11-27
sources: ["#267"]
verified_by: tests/install.test.sh
---
# 0017: the conductor asks its questions together

**Context.** Complaint (#267): the conductor asks one question, works, then asks the next; the idle gaps between question, work and the next question cost the user time. Two measurements, both on real sessions:
- Ask batching (`ask-batching-savings.md`): 155 `AskUserQuestion` calls, 188 questions, 13 sessions. 133 calls (86 %) held one question; 10 calls repeated an earlier question. Batching would save at most 41.2-42.9 % of the 34,362,046 tokens re-read because of question calls. This is an upper bound: follow-up rounds cannot be batched.
- Decision-board pilot (`board-token-cost.md`): an Artifact board cost about 41.6k tokens to set up and 1.9x the bytes per question of `AskUserQuestion`.

**Decision.** (user, 2026-11-27)
- Keep `AskUserQuestion`; change only the question rule in `claude/agents/conductor.md`. No board, HTML page, skill, hook or queue file. The board was rejected for its token cost.
- Collect every question the conductor must ask for a piece of work, ask them in one call of up to 4 questions; a fifth goes in the next call with no work between.
- A question that does not block the work waits and is asked with the others at the next stop, and at the latest before the PR or the final report.
- Never ask a question twice: answer a counter-question and wait for the reply. When the user dismisses a question or replies without choosing, do what the reply says and, for what it leaves open, go on with the recommended option if that can be undone, and say so; plan approval, merge, release and deletion wait for an explicit answer (`AskUserQuestion` is synchronous: a reply or a dismissal, never silence).
- Answers are recorded on the issue in one comment.

**Status.** Active.

**Consequences.**
- Saving is at most the upper bound above; a decision that depends on an earlier answer still needs a later call.
- Removed: the `needs-decision` label rule (comment the question on the issue, label, remove when answered) and the "one topic at a time" rule. The label may still exist on old issues; nothing reads it (the gate tests only allow listing it).
- The review skill's "interview format" now says `AskUserQuestion`; README no longer lists the label.
- Undo: restore the two removed bullets from the commit that adds this page.
