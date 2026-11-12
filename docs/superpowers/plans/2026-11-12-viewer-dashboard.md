# Viewer dashboard (phase 1) — plan

Spec: `docs/superpowers/specs/2026-11-12-viewer-dashboard-design.md`.
Branch: `feat/viewer-dashboard` from `origin/main`. One implementer ask, TDD, then `/review`, then PR.

## Steps
1. Branch `feat/viewer-dashboard` from `origin/main`; bring the spec and this plan (untracked in the conductor checkout) into the first commit. Do not commit `docs/wiki/inbox/*` notes.
2. Tests first: add a render golden test (fixture stream jsonl + brief + `.current` + fixed size via env) covering header, `## Steps`, heading fallback, Now from text / from tool_use (Bash description preferred), Verify states (none / running / pass / fail step), Diff section only for implementer, truncation at small height and width. Watch them fail.
3. Implement the render function (lib/harness-headless.sh or a new lib file sourced from the explicit list in bin/harness; follow existing patterns; bash 3.2; jq). Reuse `bin/harness-view` for Recent.
4. Replace the live `tail -F | harness-view` branch of `cmd_watch` with a 2 s redraw loop that calls the renderer; final frame on run end with result line and report head. Keep finished-run branch and `hl_view_tail` unchanged.
5. Update existing watch assertions in affected suites; run affected suites singly, then `./install.sh --test` once.
6. Skills: add "brief contains a `## Steps` numbered list" to `/analyze`, `/implement`, `/review` SKILL.md (source under `claude/skills/`).
7. Wiki: only if a trap was hit (inbox note via report Notes); append one line to `docs/wiki/log.md` only if a wiki page changes.
8. Commit(s) with conventional messages ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; push the branch.
