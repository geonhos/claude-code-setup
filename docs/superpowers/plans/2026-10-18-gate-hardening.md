# Gate Hardening — Implementation Plan

Spec: `docs/superpowers/specs/2026-10-18-gate-hardening-design.md`
Branch: `feature/v7-herdr-conductor`

Each task is TDD: add the failing cases to `tests/gate.test.sh`, run
`bash tests/gate.test.sh` and see them fail, implement in
`claude/hooks/conductor-gate.sh`, see them pass, run `./install.sh --test`.
All code must run on macOS `/bin/bash` 3.2 (no `declare -A`, no GNU-only
flags; prefer awk).

1. **jq fail-closed** (spec §5). Test runs the gate with a PATH that has no
   `jq` (e.g. a temp dir with only `cat`/`awk` symlinks) and role unset →
   deny JSON with the fixed reason; role `worker` → allow.
2. **ls recursion** (spec §3).
3. **git branch list-only** (spec §2).
4. **gh allowlist** (spec §1). Replace the denylist; keep global-flag
   skipping; `api` token anywhere → deny; `run view --log*` → deny.
5. **Symlink resolution** (spec §4). Tests create a temp repo dir with
   `docs/link.md -> ../src/a.sh` and `.harness/out -> /tmp/…` symlinks.
6. **Docs**: parent spec gate table, README gate section,
   `claude/agents/conductor.md` "You may run directly" list.
7. **Commit** once, all tests green.
