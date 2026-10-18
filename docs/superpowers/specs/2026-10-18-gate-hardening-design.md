# Conductor Gate Hardening — Design

Date: 2026-10-18
Status: approved (design)
Parent: `2026-10-12-herdr-conductor-setup-design.md`

## Goal

Close the gaps in `claude/hooks/conductor-gate.sh` that let the conductor pull
source content into its context or mutate the repository/branch state. The
gate remains a token-economy and delegation-forcing mechanism, not a security
boundary against an adversary.

## Changes

### 1. `gh` becomes an allowlist

Replace the current denylist (`api`, `pr diff`, `alias`, `extension`) with an
allowlist. A `gh` segment is allowed only when its subcommand pair is listed:

| group | allowed subcommands |
|-------|--------------------|
| `pr` | `create`, `view`, `list`, `status`, `checks`, `comment`, `edit`, `merge` |
| `issue` | `view`, `list`, `create`, `comment` |
| `run` | `list`, `view` |
| `repo` | `view` |
| `auth` | `status` |
| `browse` | (no subcommand) |

Additional rules:

- Global flags (`-R`/`--repo <x>`, `--hostname <x>`) may precede the group;
  the parser skips them and their value before matching.
- The token `api` anywhere in the segment → deny.
- `gh run view` with `--log` or `--log-failed` → deny.
- Anything not listed (including `gist`, `repo clone`, `pr checkout`,
  `pr diff`, `run download`, `release`, `search`, `alias`, `extension`) → deny.

### 2. `git branch` is list-only

Allowed: bare `git branch`, and the options `-a`, `-r`, `-v`, `-vv`,
`--list`, `--all`, `--remotes`, `--show-current`, `--merged`, `--no-merged`,
`--contains`, `--no-contains`, `--points-at`, `--sort=<k>`. (`--format` is
not allowed; output shaping is unnecessary.) A positional argument is
allowed only when one of `--list`, `--merged`, `--no-merged`, `--contains`,
`--no-contains`, `--points-at` appears earlier in the segment. Any other
option (`-f`, `-d`, `-D`, `-m`, `-M`, `-c`, `-C`, `-u`, `--force`,
`--delete`, `--move`, `--copy`, `--set-upstream-to`, `--unset-upstream`,
`--edit-description`, `--track`, …) or an unqualified positional → deny.

### 3. `ls` without recursion

`-R`, `--recursive`, and any short-option cluster containing `R` (e.g. `-laR`)
→ deny. Applies to bare `ls` and to `ls` under `.harness/`/`docs/`.

### 4. Symlink-resolved path checks

For file tools (`Read`, `Grep`, `Glob`, `Edit`, `Write`, `NotebookEdit`,
filesystem MCP), after the existing lexical check passes, resolve the path's
real location and re-apply the same rule to the resolved repo-relative path.

- Resolution must work on macOS `/bin/bash` 3.2 without GNU coreutils:
  `cd -P` + `pwd -P` for the directory part, plus a bounded `readlink` loop
  (max 16 hops) for a symlinked final component.
- A path that does not exist yet (a new file under `docs/` or `.harness/`)
  resolves via its nearest existing ancestor directory.
- Resolved path outside `cwd`, or a loop/hop limit hit → deny with the
  existing fixed deny reason for that tool.

### 5. `jq` missing fails closed

If `jq` is not on `PATH` and the role is not `worker`, emit a deny with the
fixed reason `Conductor gate requires jq. Install jq, or run a worker session.`
The JSON must be emitted without `jq` (static `printf`). Unparseable stdin
keeps the current fail-open behaviour (allow + one stderr line).

## Non-goals

- WebFetch / non-filesystem MCP gating (needed for research).
- herdr agent-name collisions across projects (separate harness fix).
- Protecting `.harness/panes` from conductor writes.
- Changing the rule that any `*.md` in `cwd` is readable.

## Testing

TDD in `tests/gate.test.sh` (bash 3.2):

- New deny cases, written first and seen failing: `gh run view 1 --log`,
  `gh run view 1 --log-failed`, `gh gist view x`, `gh repo clone o/r`,
  `gh pr checkout 1`, `gh -R o/r api repos`, `gh --repo o/r pr diff 1`,
  `gh search code foo`, `gh release download v1`, `git branch tmpx`,
  `git branch -f tmpx HEAD`, `git branch -D x`, `git branch -m a b`,
  `ls -R`, `ls -laR docs`, `ls --recursive .harness`, Read of a symlink under
  `docs/` pointing to a source file, Write through a symlinked directory under
  `.harness/` pointing outside, jq missing (PATH without jq).
- Regression allow cases: `gh pr create --title 't' --body-file .harness/pr.md`,
  `gh -R o/r pr view 1`, `gh pr list`, `gh run view 1`, `gh run list`,
  `gh issue view 3`, `gh auth status`, `git branch`, `git branch -a`,
  `git branch --list 'feat*'` (if quoting allowed by existing rules, else
  `git branch --list feat`), `git branch --contains HEAD`, `ls`, `ls -la docs`,
  Write of a new file `docs/x.md`, Read of a real `docs/*.md`.
- `./install.sh --test` passes in full.

## Docs

Update the gate table in the parent spec, the README gate section, and the
`You may run directly` list in `claude/agents/conductor.md` to match.
