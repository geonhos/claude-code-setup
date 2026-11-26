---
type: decision
status: active
updated: 2026-11-26
sources: ["#243", bin/harness:rules_apply, claude/templates/agents-rules.md]
verified_by: tests/harness.test.sh, tests/lane.test.sh, tests/install.test.sh
---
# 0016: `harness init` writes the harness rules block into AGENTS.md

**Context.** The working rules (language, issue per task, branch and commit form) lived only in this repo's `AGENTS.md`, so a repo set up with `harness init` had none of them. Probes for #243: `git worktree remove` refuses a folder with an untracked or modified tracked file and removes one with only ignored files; `.git/info/exclude` is shared by all worktrees; an ignored file that a later merge tracks is silently replaced.

**Decision.** (user, 2026-11-26)
- `harness init` creates or updates a block in `AGENTS.md` between `<!-- harness:rules begin -->` and `<!-- harness:rules end -->`, text from `claude/templates/agents-rules.md` (one source; this repo's own block is tested equal to it).
- Text outside the markers is never changed. A broken block (a begin without an end, an end without a begin, an end before the begin, two or more begins, two or more ends) fails init with nothing changed.
- A file init creates is added to `.git/info/exclude` unless `--shared`; an existing file is never excluded. A tracked file gets the block uncommitted, with a note.
- Work folder rule: in a lane init never leaves a git-visible change. It writes only a file git already ignores (local mode recreates it from the template); a tracked or not-ignored case prints a note and changes nothing. `lane_ignored_diff` skips `AGENTS.md`.
- `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md` are never edited; init warns to add `@AGENTS.md` (see troubleshooting/agents-md-ignored-when-claude-md-exists).
- Line endings (checked in a scratch repo, #257): in a CRLF `AGENTS.md` that has a block, init writes the block body with LF and leaves the marker lines and all text outside them as they are (CRLF), so the file ends up mixed. A block appended to a CRLF file without one is all LF, markers included; the existing text keeps CRLF. A file converted wholesale to CRLF gets one "updated the harness rules block" run (the body goes back to LF) and "up to date" after that.
- No opt-out flag. `lane_copy` was removed in exchange (no reader since #63; `"lane_setup": "cp ../<repo>/.env ."` covers the `.env` case).

**Status.** Active.

**Consequences.**
- Undo: delete the block; delete the file and its `.git/info/exclude` line if init created it. The next init adds the block again.
- A repo where the rules do not fit (team, English) gets the block on every init and lane; file an issue when one needs an opt-out.
- An excluded AGENTS.md that upstream later tracks is replaced by a merge; only init text is lost unless the user edited it.
- Cost in a target repo: ≈ 765 bytes of context per request.
