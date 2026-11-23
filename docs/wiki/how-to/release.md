---
type: how-to
status: active
updated: 2026-11-23
sources: ["#236", b098b2b, 9de83c6, "git tag -l", claude/hooks/conductor-gate.sh:64, claude/agents/conductor.md]
verified_by: human
---
# Releasing: semver from v3.0.0, the tag is the version

Tags stop at `v2.1.0`; the only GitHub release is `v2.0.0`. The plugin versions 3.0.0-6.0.0 live only in removed files (`git show b098b2b~1:CHANGELOG.md`), were never tagged and do not count. The first release is `v3.0.0`.

## Rules (decided by the user, 2026-11-23, #236)
- Semantic versioning. The git tag is the only source of the version: no VERSION file, no version string in code, no CHANGELOG file. The GitHub release note is the change record.
- **Major**: install method, commands or folder layout break for an existing user. **Minor**: a command, role or hook behaviour is added or changed. **Patch**: fixes and docs.
- Every tag gets a Korean release note (합니다체, `claude/skills/korean-writing/SKILL.md`). Sections in this order: Breaking Changes (major only), New Features, Changed, Removed, Known issues, Installation / Update. Write it under `.harness/` and pass it with `--notes-file`.
- Release condition: main is synced; `./install.sh --test` passes on main with no other worker running (a parallel run from another checkout can fail `dash` or worktree-guard: [base-worktree-during-suite](../troubleshooting/base-worktree-during-suite.md), #232); no open issue describes a behaviour defect.
- The user decides the version and approves the note. Nobody tags or publishes without that approval.

## Who runs what
The conductor's shell allows `git log`, `git status`, `gh pr list` and `gh issue ...`, but not `git describe`, `git tag`, `git push` or `gh release` (`claude/hooks/conductor-gate.sh:64`, "You may run directly" in `claude/agents/conductor.md`). So the conductor reads the history (`git log`, `gh pr list`), writes the note and gets the user's approval (steps 2-3), and delegates the rest (steps 1, 4-6, plus `git describe`) to the implementer: `harness ask implementer '...' --no-lane` (it changes no repo file, so no work folder).

## Steps
1. Sync and test: `git fetch origin --prune`, `git pull --ff-only`, then `./install.sh --test` once.
2. List changes since the last tag: `git describe --tags --abbrev=0`, `git log --oneline <last-tag>..HEAD`, `gh pr list --state merged`.
3. Pick the number by the bump rule, write the note to `.harness/release-vX.Y.Z.md`, get the user's approval of both.
4. Tag and push: `git tag -a vX.Y.Z -m "vX.Y.Z" <commit>`, then `git push origin vX.Y.Z`.
5. Publish: `gh release create vX.Y.Z --title "vX.Y.Z: <one line>" --notes-file .harness/release-vX.Y.Z.md --verify-tag`. `--verify-tag` aborts when the tag is not on the remote (present in the installed gh; check `gh release create --help`).
6. Check: `gh release view vX.Y.Z` and `git tag --list`.
