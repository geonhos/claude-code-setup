# Wiki index

Read this first. Open a page only when it is relevant. Schema and promotion rules: the Wiki section of `AGENTS.md`. `wiki`-label issues go stale fast: check `git log` for a fix before triaging one.

## Troubleshooting: ask completion and timeouts
- [ask --timeout is ms](troubleshooting/ask-timeout-is-milliseconds.md): `--timeout 1200` = 1.2s; defaults are role-aware (active, 2026-10-27)
- [Serial suite loop](troubleshooting/serial-suite-loop.md): workers looping over suites cost 5x the parallel run; run singly or `./install.sh --test` once (active, 2026-11-26)
- [.harness root lookup](troubleshooting/harness-root-lookup.md): hook finds root by nearest `.harness/asks/`; one definition in lib/harness-root.sh; probe the gate from a checkout (active, 2026-11-16)
- [Docs-only skip scope](troubleshooting/docs-only-asks-skip-the-suite.md): Stop hook skips the suite only for `docs/`/`.harness/`; wiki runs wiki-lint only (active, 2026-11-03)

## Troubleshooting: workers and env
- [AGENTS.md is ignored when a CLAUDE.md exists](troubleshooting/agents-md-ignored-when-claude-md-exists.md): no CLAUDE.md on purpose; CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md hides AGENTS.md unless it imports it; init warns (active, 2026-11-26)
- [Live gate edit](troubleshooting/live-gate-edit.md): a syntax error denies everything, other gate failures fail open silently; bash -n + suite before each save (active, 2026-11-22)
- [In-place edit breaks running scripts](troubleshooting/in-place-edit-breaks-running-scripts.md): bin/ is live; bodies are brace-wrapped, edit via new inode; lib/ is safe while sourced eagerly (active, 2026-11-03)
- [cd "$VAR" deny false hit](troubleshooting/cd-var-deny-rule-false-hit.md): after an unresolvable cd, Claude Code tests relative reads against ~/.ssh/** rules; use absolute paths or git -C (active, 2026-11-23)
- [Doc rewrite moves scope](troubleshooting/doc-rewrite-moves-scope.md): a compressed list's shared qualifier, a moved citation or an audit's copied suggestion states what the source never said; check each sentence against code or decision log (active, 2026-11-26)

## Troubleshooting: conductor
- [zsh extendedglob in gate revs](troubleshooting/zsh-extendedglob-in-gate-revs.md): `^` in a git show rev globs to file names; gate denies `^`, allows only `~N` with --stat (active, 2026-11-16)
- [Conductor shell: one command](troubleshooting/conductor-shell-one-command.md): exactly one simple command: no `;`, `&&`, `|`, redirects (active, 2026-10-28)

## Troubleshooting: shell portability and tests
- [GNU stat -f](troubleshooting/gnu-stat-f.md): use `-nt`/`-ot` or `stat -c %Y` first (active, 2026-11-26)
- [bash signals and job control](troubleshooting/bash-signals-job-control.md): bg jobs ignore INT; `set -m` hands tty signals to children (active, 2026-11-26)
- [Global gitignore masks ignore gaps](troubleshooting/global-gitignore-masks-ignore-gaps.md): this machine's ~/.config/git/ignore hides missing excludes; check with core.excludesFile=/dev/null (active, 2026-11-26)
- [Temp worktree fails worktree-guard](troubleshooting/base-worktree-during-suite.md): the guard is per repo, so any session's temp worktree (not only your own base) fails every running suite; remove only yours, else wait and rerun once (active, 2026-11-26)
- [Tests inherit worker env](troubleshooting/tests-inherit-worker-env.md): suites run by a worker see `HARNESS_ROLE=worker`; unset it (active, 2026-11-26)
- [Half-assertion tests](troubleshooting/half-assertion-tests.md): `check [ a ] && [ b ]` asserts only a; prove fixes with a mutant; take expected values and inputs from outside the code under test; repeat items in every source a dedupe merges; count rows, not the tail row (active, 2026-11-26)
- [wiki-lint dangling sources](troubleshooting/wiki-lint-dangling-sources.md): lint checks only non-empty `sources`; grep the slug before deleting a suite or page (active, 2026-11-26)
- [No-edits brief skips report](troubleshooting/no-edits-brief-skips-report.md): say "no source edits (report still required)" or the implementer exits 3 (active, 2026-11-26)

## How-to
- [Transcript forensics](how-to/transcript-forensics.md): real Stop-hook time, did /clear run, what a worker was given, known model noise (active, 2026-11-26)
- [Headless probes](how-to/headless-probes.md): neutral --agents agent for permission probes; clean, cheap claude -p generation call (active, 2026-11-22)
- [Release](how-to/release.md): semver from v3.0.0, tag is the version, Korean release note, who runs git tag / gh release (active, 2026-11-23)
- [Per-issue work folders](how-to/work-folders.md): lane <issue#>/ls/rm, -C parallel asks, lane_setup, progress mirroring, risks (active, 2026-11-26)

## Decisions
- [0001 Keep herdr panes](decisions/0001-keep-herdr-panes-despite-subagent-model.md): subagent model works; panes kept; superseded by 0011 (superseded, 2026-11-01)
- [0002 Stop-hook completion](decisions/0002-completion-by-stop-hook-marker.md): pane marker; superseded by exit.json (superseded, 2026-11-02)
- [0003 Pane lifecycle](decisions/0003-pane-lifecycle-defaults.md): pane idle TTL and close rules; removed (superseded, 2026-11-02)
- [0004 Failure-only retros](decisions/0004-failure-only-batched-retros.md): removed in prune step 4 (superseded, 2026-11-02)
- [0005 Gate only inside herdr](decisions/0005-gate-only-inside-herdr.md): step 1 (HERDR_ENV) and the global conductor superseded, steps 2-3 scoped by 0010; agent_type keys the gate; 0012 supersedes the 4b consequence (active, 2026-11-26)
- [0006 Keep implementer pane](decisions/0006-keep-implementer-pane.md): implementer pane kept; no panes remain (superseded, 2026-11-02)
- [0007 Headless runner pilot](decisions/0007-headless-runner-pilot.md): `claude -p` detached; completion = exit file; `runner` key removed in step 3 (active, 2026-11-26)
- [0008 Worktree per ask](decisions/0008-worktree-per-ask.md): removed in prune step 4 (superseded, 2026-11-02)
- [0009 Headless implementer](decisions/0009-headless-implementer.md): headless implementer: all roles pinned to auto, exit 2 on denials, auto-resume removed (#72), 90 min cap (active, 2026-11-26)
- [0010 Harness acts only in a checkout](decisions/0010-herdr-optional-gate-by-checkout.md): gate/resume key on .harness/asks (made by `harness init`); per-repo conductor agent; no HERDR_ENV switch; `harness wait`/`watch`; doctor and `--worktree` removed in step 4 (active, 2026-11-26)
- [0011 One runner: headless](decisions/0011-single-runner-headless.md): headless is the only runner; herdr viewer removed by 0013; prune plan steps 1-7 done (active, 2026-11-03)
- [0012 Gate shrink](decisions/0012-gate-shrink.md): gate kept and trimmed to observed use (552 → 513 lines); permissions-rules and native-subagent options rejected (active, 2026-11-26)
- [0013 Remove herdr](decisions/0013-remove-herdr.md): herdr removed from runner/gate/install; `open-watch` may use a herdr pane first (amended 2026-11-26, #257); watch via `harness watch` in any terminal (active, 2026-11-26)
- [0014 init writes deny rules](decisions/0014-init-writes-deny-rules.md): `harness init` adds nine worker deny rules to settings.local.json; ask warns when missing; seatbelt, not a sandbox; `denied[]` partial-list note resolved (active, 2026-11-26)
- [0015 Korean writing rules](decisions/0015-korean-writing-rules.md): Korean for the user written directly under six conductor-prompt rules plus the on-demand `korean-writing` skill; no STE-style drafting (active, 2026-11-20)
- [0016 init writes AGENTS.md rules](decisions/0016-init-writes-agents-rules.md): `harness init` owns a marker block in AGENTS.md; lane never gets a git-visible change; CLAUDE.md only warned about (active, 2026-11-26)
