---
type: troubleshooting
status: active
updated: 2026-11-26
sources: [ask 1795397876-20643-21846, ask 1795400331-67567-6009, "#212", "#222", a31c751, cf9f8c8, 7262979, "#258", ask 1795684662-94791-269, a6167d5]
verified_by: human (git show 7262979:AGENTS.md vs cf9f8c8:AGENTS.md)
---
# A doc rewrite says what its source does not: moved qualifiers, moved citations, copied suggestions

**Symptom.** A reviewed doc edit reads well and keeps every item, yet a rule changed: an item gained a condition it never had, or a citation vouches for a claim its source does not make. Or a sentence taken from an audit's suggested fix is false.

**Cause.** Three shapes, from compressing, rewording or copying:
1. A numbered list compressed into one line with a shared qualifier extends the qualifier to every item. Base 7262979 AGENTS.md:62 said "Promotions happen only through a human-approved PR"; cf9f8c8 AGENTS.md:34 wrote "each step only through a human-approved PR", which also covered step 1 (filing a `wiki` issue, done without a PR). Now fixed as "Promotions (steps 2-5)".
2. A parenthetical citing a prompt line was put on the neighbouring sentence. At a31c751 the base-worktree page said a guard failure listing only `.../base` from your own `mktemp` "is not a finding (claude/agents/reviewer.md:33 says so since #173)"; at that commit reviewer.md:33 only ordered the base worktree after the suite, and :28 said a suite failure is "a Major finding at least". The exemption existed only in the page.
3. A suggested wording copied from an audit carries the audit's errors. The pre-release audit for #256 proposed "`harness lane new/rm/ls`" (row D4) and "(spawn removed in prune step 4)" (row W/decisions/0010:19); the branch copied both. `cmd_lane` has no `new` subcommand (`lib/harness-lane.sh:186-191` dispatches `ls`, `rm`, and everything else to `lane_new` as an issue number) and spawn went in prune step 3 (`log.md:41`). Two of the three Majors in the review (ask 1795684662-94791-269); fixed before a6167d5.

**Fix.** After a compression or reword, check each item and each cited claim against its source line, not the paragraph as a whole. A citation goes on the sentence that line states. An audit's or plan's suggested text is not a source: check it against the code or the decision log like any new sentence. Promoted to `claude/agents/reviewer.md` and `implementer.md`, #268.

**Evidence.** Reviews of #176 (ask 1795400331-67567-6009) and #173 (ask 1795397876-20643-21846); issues #212, #222; #256 review (ask 1795684662-94791-269), issue #258.
