# Karpathy A/B: selected tasks

Four replayed `implementer` asks from this repo's own history, one per type. Each is replayed
from its base commit in a fresh `git clone --local` (origin removed, later history pruned),
with the listed seed files copied into `.harness/` (untracked, as in the original run).
Source: `.harness/karpathy-ab-tasks-detail.md` (analyst). Briefs below are what the agent
received: verbatim from the original `## Brief`, minus the exact edits listed per task, plus
the identical suffix `Do not push. Local commits are fine.` for both conditions.

| Task | Ask-id | Type | Base | Answer range | Suites | Why chosen | Replay risk |
|---|---|---|---|---|---|---|---|
| T1 | 20261022-213533-implementer | bug fix | `2b30519` | `2b30519..a4b57b7` (101fae0 = inbox notes, excluded) | verify, harness | Clear root cause, TDD brief, 2 commits | Two inbox notes must be seeded (from 101fae0); brief's second commit adds them |
| T2 | 20261022-130514-implementer | small feature | `8c2d881` | `8c2d881..32f2ac6` (review fixes ee92a03, f32ec70, 0dce2c7 not in the range) | install, harness, retro | Multi-part brief with design choices (parallel suites, prompt wording) | Heaviest suites (harness ~85 s); brief asks for 3 full runs + serial run, long |
| T3 | 20261028-122652-implementer | refactor | `a0cbd2d` | `a0cbd2d..458f640` | harness-split, headless, worktree | Pure move, objectively checkable (diff-purity) | Needs `.harness/harness-split-design.md` seed (mtime before ask) |
| T4 | 20261103-140822-implementer | ambiguous | `77252a8` | `77252a8..395690c` (bc13fa0 banner commit rejected by user, dropped) | progress, gate, harness, metrics, headless, wiki | Underspecified in places (re-derive stale line numbers, skip already-done items) | Largest: 4 commits, 6 suites; brief talks of live-file traps that do not apply in a clone |

Backups (not used): B1 `20261023-083436-implementer` (feature, base `1234beb`; part A depends on how the advisor tool is exposed, environment-specific), B2 `20261103-144825-implementer` (refactor, base `d5fd8b8`).

## Edits to the original briefs (remote-less clone)
- T1: removed `` `git checkout main && git pull --ff-only`, then `` (no remote; clone is already at base).
- T2: `, then push the branch with `-u`` removed from the commit line.
- T3: removed `` `git checkout main && git pull` `` from the setup sentence and the line `` `git push -u origin refactor/v22-split-c`. Do not open a PR. ``.
- T4: removed the parenthetical `run `git fetch` first and confirm local main == origin/main`.
- All: suffix `Do not push. Local commits are fine.` appended.

## Briefs as given to the agent

### T1 bug fix

`````markdown

# Task: v14 step 1 — Stop hooks must work from the repo root, whatever the worker's cwd

Read `docs/wiki/index.md` first. Bash 3.2 only. Use TDD: write the failing test first.

## Setup
PR #17 was just merged on GitHub. 
`git checkout -b feature/v14-speed-stability`. The two untracked files under
`docs/wiki/inbox/` (2026-10-22-analyst-1792671569-…, 2026-10-22-retro-1792643421-…) must
come along untouched.

## Bug (retro, see docs/wiki/inbox/2026-10-22-retro-1792643421-12588-9450.md)
When a worker ends its turn after `cd <repo>/<subdir>` (e.g. `.harness`), Claude Code keeps
that cwd and the Stop hook's input JSON carries cwd = the subdir. `enter_root`
(bin/harness-verify:32-34) cd's there, then `mark_done` (:243) reads the relative
`.harness/asks/<role>.current`, finds nothing and returns 0 silently → no done marker →
`harness ask` gives up after the 30 s idle grace with exit 3 although the report exists.
`cmd_stop` (implementer verify, enter_root at :274/:283) has the same problem.

## Fix
1. `enter_root`: after cd to the hook's cwd, move to `git rev-parse --show-toplevel` when
   inside a git repo (keep current behaviour outside git). Check nothing else relies on the
   old cwd (format subcommand uses file paths — make sure relative paths still resolve).
2. `mark_done`: when `.harness/asks/<role>.current` is missing in a worker session, print one
   warning line to stderr (still exit 0 — a Stop hook must not block on this).
3. `bin/harness` exit-3 message (~:1083) currently suggests respawning for a stale hook.
   Reword so it also names the other cause: "or the Stop hook ran from a directory without
   .harness (check the worker's cwd)". Keep it one or two lines.
4. Tests (tests/verify.test.sh and/or tests/harness.test.sh): `harness-verify done <role>`
   with hook input cwd = a repo subdir writes the marker at the repo root; same for `stop`
   (verify runs at root); missing `.current` warns on stderr.

Full `./install.sh --test` must pass (the Stop hook runs it).

## Commit (do not push)
```
fix(verify): run Stop hooks from the git toplevel, warn when no ask is current

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```
Then a second commit with the two inbox notes:
```
docs(wiki): inbox notes from the v13 retro

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```


Do not push. Local commits are fine.
`````

### T2 small feature

`````markdown

# Speed up verification: parallel suites, no clear sleep in tests, scoped worker runs

The analysis is in `.harness/verify-speed-detail.md` (read it first; raw timings are in
`.harness/verify-speed/`). Summary: the full suite takes ~195 s (harness 85 s, progress 39 s,
retro 37 s). The implementer runs it 2–3 times per ask on top of the Stop hook.

## Branch
You are on `main`, which is clean and up to date. Create `feature/v13-verify-speed` from it.

## A. Run the suites in parallel in `./install.sh --test`
- Start every `tests/*.test.sh` at the same time. Buffer each suite's output to a temp file,
  then print each suite's buffered output as one block in the order the suites finish, with
  a header line per suite. Exit non-zero if any suite failed, and list the failed suites at
  the end.
- The suites must be safe to run in parallel. Check for shared state: fixed paths under
  /tmp, `$HOME`/.harness, herdr pane names, ports, a fake-herdr state dir. Fix any collision
  in the tests, for example by giving each suite its own `mktemp -d`.
- Keep a way to run the suites serially (e.g. `HARNESS_TEST_SERIAL=1`) for debugging.
- macOS bash 3.2: `&` + `wait <pid>` per suite to collect each exit code. No `wait -n`
  (bash 4.3+) and no GNU-only tools.
- The analyst measured ~86 s in parallel. Report your own number.

## B. `HARNESS_CLEAR_INTERVAL=0` in the harness and retro tests
The 0.5 s `do_clear` sleep (bin/harness:~307) is not zeroed there. Set it in the tests' env
the same way the other suites already do; do not change the default in bin/harness. The
analyst measured harness.test 85 → 73 s.

## E. Implementer prompt: run only the affected suites while working
In `claude/agents/implementer.md`, add one or two lines: while iterating, run only the
suites the change affects (`bash tests/<x>.test.sh`); do not run the full
`./install.sh --test` yourself before stopping, because the Stop hook runs it. If that
contradicts existing text in the prompt or in AGENTS.md ("All must pass before a commit"),
keep the guarantee: the Stop hook's full run is the gate, and the commit happens after it
passes or is fixed after a hook block. Word it so nothing commits untested. Check how the
Stop hook and commit order work today, and describe in the report what you chose.

## Docs
- README or AGENTS.md: if either describes how tests run, update it for parallel runs and
  the serial switch.
- Add one line to `docs/wiki/log.md`. Leave the wiki inbox alone.

## Verify
- `./install.sh --test` (parallel) passes. Run it 3 times in a row to catch parallel-only
  flakiness. Also run `HARNESS_TEST_SERIAL=1 ./install.sh --test` once.
- `harness wiki-lint` must be clean.

## Commit
Up to three commits (A+B, E, docs, or fewer). Each message
ends with:
```

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```
Suggested subjects: `perf(tests): run suites in parallel, no clear sleep in harness/retro tests`,
`docs(agents): implementer runs affected suites, Stop hook runs all`.


Do not push. Local commits are fine.
`````

### T3 refactor

`````markdown

# Task: v22 PR C — move the headless group out of bin/harness into lib/harness-headless.sh (#8, stage 2)

## Setup
(PR #33 merged: lib/harness-{defaults,metrics,worktree}.sh,
loader with `# end loader` marker, tests/harness-split.test.sh), then
`git checkout -b refactor/v22-split-c`.
Design: `.harness/harness-split-design.md` §4. Bash 3.2. bin/* and lib/* are live: edit via
the Edit tool or tmp+mv only. Lib files: definitions only, sourced eagerly from the loader
list (add `headless` to `for m in …`; order: defaults metrics worktree headless, or as the
design orders dependencies). The split suite enforces the structure; keep it green.

## Move
`lib/harness-headless.sh`: the headless group (`hl_*`, runner glue: use_hl, hl_alive,
hl_done, hl_collect, hl_last_session, hl_start, the viewer/runner pid helpers; ≈317 lines
per the design). Pure move: identical bodies. Shared helpers that both headless and the ask
engine use stay in bin/harness (resolved at call time). Do not touch bin/harness-run or
bin/harness-view.

## Checks
- `bash tests/harness-split.test.sh` (it must pick up the new file automatically via
  all_listed), headless and worktree suites, then `./install.sh --test` once.
- Diff-verify purity: `git show main:bin/harness | sed -n '<a>,<b>p' | diff - lib/harness-headless.sh`
  (minus the header) and put the result in the report.
- Line counts before/after.

## Docs
README/AGENTS.md Layout (lib now lists headless too); docs/wiki/log.md one line.

## Commit and push
One commit `refactor(harness): headless group moves to lib/harness-headless.sh` (+ a docs
commit if separate), ending with a blank line then
`Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.


Do not push. Local commits are fine.
`````

### T4 ambiguous

`````markdown

# Prune step 5: remove the `--via` no-op and shrink the conductor gate (decision 0011)

Branch `chore/prune-5-gate-shrink` from `main` (77252a8). Commit in the order below; do **not** open the PR. Leave the untracked `docs/wiki/inbox/*.md` files alone (do not stage them). Read `docs/wiki/index.md` first and open `troubleshooting/live-gate-edit.md`, `troubleshooting/in-place-edit-breaks-running-scripts.md`, `troubleshooting/conductor-shell-one-command.md`.

## Context
- Step 4 (#43) left `--via` as a no-op arm in `ask_parse_args` (`bin/harness`) with a test ("--via no-op cases", commit bee6a4d). The skills and `conductor.md` no longer pass `--via`, so the arm can go now.
- The gate plan is `.harness/gate-shrink-detail.md` (analyst, 2026-10-28, written against a 552-line gate). Its line numbers are stale; **re-derive them from the current `claude/hooks/conductor-gate.sh` (~513 lines)**. Of its §7 plan, these are already done: (g) agent_type keying, step 2 `tests/gate-denied.list` + loop, (a) single-command scanner (gate v21; wiki page conductor-shell-one-command). Verify each by reading the gate and tests, then skip them.
- The B′ spike (native subagents) was rejected on 2026-11-03 (`.harness/spike-bprime/RESULTS.md`): the harness runner stays, so the gate stays and is trimmed as planned. Do not touch runner code.

## Live-file traps (important)
- `claude/hooks/conductor-gate.sh` and `bin/harness` are symlinked into `~/.claude` / `~/bin` and run **live** for the conductor that sent this ask. A syntax error in the gate denies every conductor tool call. Before every save of the gate: `bash -n`, then run `tests/gate.test.sh` singly. Write a new file and `mv` it over the old path (new inode); never edit in place.
- `bin/harness` is brace-wrapped: same new-inode rule.

## Work

### Commit 1 — `refactor(prune-5): remove the --via no-op`
- Remove the `--via` arm from `ask_parse_args` and any remaining `--via`/`ASK_VIA`/`via` writer in `bin/harness`, `lib/`, `install.sh`, tests, README, AGENTS.md, CLAUDE.md, skills, agent prompts (`grep -rn -- '--via\|ASK_VIA\|"via"' bin lib claude install.sh tests README.md AGENTS.md CLAUDE.md docs/wiki`).
- Keep metrics/progress readers tolerant of old rows that carry a `via` field (nothing should read it; confirm `lib/harness-metrics.sh` does not). Remove the no-op test; add one asserting `harness ask analyst --via x 'y'` is refused as an unknown option (exit 1) without starting a run.
- Suites: harness, progress, metrics, headless.

### Commit 2 — `refactor(prune-5): gate policy tables at the top` (option e, no behaviour change)
- Move `BASH_ALLOW`, the gh subcommand list, `GIT_DENY`, `JQ_DENY` (if still present) and the deny messages into one clearly labelled block near the top of the gate, after the prologue. Gate suite must pass **unchanged**.

### Commit 3 — `refactor(prune-5): trim the gate allowlist and dead tool cases` (options c, d, b)
- (c) gh: keep only `gh pr create|view|list|checks|comment|edit|merge` with the existing flag checks (`--body-file` only from `.harness/` or `docs/`; no `pr merge -d`; no `api`). Drop issue/run/repo/auth/browse/`pr status` handling.
- (d) git: drop `git show --stat` if allowed; replace `git_branch_ok` with a regex allowing only `git branch` followed by any of `-a -r -v --show-current` (list-only). herdr: keep only `herdr pane get|current`; drop status/pane list/layout/workspace/tab.
- (b) Remove the explicit Agent/Workflow/Monitor/NotebookEdit deny cases and the `mcp__filesystem__*` block **only if** `claude/agents/conductor.md` frontmatter `disallowedTools` already lists those tools (and `mcp__filesystem__*` if a prefix is accepted); if not, add them there in the same commit and note it in the report. Trim the hook MATCHER accordingly; update `install.sh`/`tests/install.test.sh` if they assert the matcher.
- Every line of `tests/gate-denied.list` must still deny and the 5 controls must still allow. Every form listed under "You may run directly" in `claude/agents/conductor.md` must still be allowed: add a gate test per form if missing (`harness status`, `gh pr view 1`, `git log --oneline -3`, `git diff --stat`, `git branch -a`, `git branch --show-current`, `herdr pane current`, `cat .harness/progress.md`, `ls docs`).
- Update the deny message text if a list changed, and `claude/agents/conductor.md` "You may run directly" so it matches the gate exactly.
- Suites: gate, install.

### Commit 4 — `docs(prune-5): ADR 0012 gate shrink; 0011 step 5 done`
- `docs/wiki/decisions/0012-gate-shrink.md` (type decision, status active, frontmatter per AGENTS.md, ≤150 lines): context (gate-shrink-detail §1-3 usage data: 754 allowed calls, what was never used), decision (what was removed / kept and why the path helpers and Bash allowlist stay; option f "permissions rules" rejected because user-scope rules bind workers), status, consequences. Cite `.harness/gate-shrink-detail.md`, `.harness/spike-bprime/RESULTS.md` (B′ rejected 2026-11-03: subagents die on conductor exit, "1 local agent couldn't be moved and was stopped") and the commits.
- `0011`: append "Step 5 done 2026-11-03: `--via` removed; gate trimmed (N → M lines), ADR 0012." `0005`: note in its index hook that 0012 supersedes the 4b consequence. Index lines for 0012 and 0011/0005 hooks; `docs/wiki/log.md` one line; `conductor-shell-one-command.md` only if the deny text changed. README: fix any gate line count or command list.
- Suite: wiki (`harness wiki-lint`).

Finish with `./install.sh --test` once (parallel). All suites green.


Do not push. Local commits are fine.
`````
