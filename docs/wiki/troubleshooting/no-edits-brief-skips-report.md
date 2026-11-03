---
type: troubleshooting
status: active
updated: 2026-11-03
sources: [ask 1793322003-39187-11720, lib/harness-headless.sh:187, claude/agents/implementer.md:70, bin/harness-verify:377]
verified_by: ask 1793322003-39187-11720 (no check; wording trap)
---
# A "no file edits" brief makes the implementer skip the report

**Symptom.** A git-housekeeping ask (cherry-pick, push, branch delete) finished the work in 18 s, then exited 3 with "finished without a report". The worker's last reply said the reply was the report.

**Cause.** The brief said "Git housekeeping only, no file edits". The worker read it as also forbidding the mandatory report file. The Stop hook never requires a report (`bin/harness-verify:377` only hides and restores it); the missing report is caught only by the runner (`lib/harness-headless.sh:187`, exit 3). A similar brief in an earlier ask did get a report, so it is a judgment slip that wording can trigger, not a harness bug.

**Fix.** Briefs that forbid edits say "no source edits (report still required)". Not yet encoded anywhere: candidate for one line in `claude/skills/implement/SKILL.md`, or for making the report contract in `claude/agents/implementer.md:70` override brief wording.

**Evidence.** Ask 1793322003-39187-11720.
