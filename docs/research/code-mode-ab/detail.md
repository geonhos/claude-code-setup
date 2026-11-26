# Claude Code "Code Mode" and the harness (issue #239) — detail

Date 2026-11-25, CC 2.1.332 installed (`claude --version`), main 89e0472.
Scratch evidence (left in place): docs/changelog/binary strings in
`<tmpdir>` (`code-mode.md`, `changelog.md`,
`cm.txt`, `cm2.txt`, `fn.txt`, `workflows.md`, `llms.txt`); probes in `.../tmp.bhUaPzegIj/` (run1-6)
and `.../tmp.wv6r91NfyS/` (run7, real conductor gate).

## Part 1 — What "code mode" is

### Candidate A (most likely): Claude Code "Code Mode (experimental)"
- Source: https://code.claude.com/docs/en/code-mode.md (saved as `code-mode.md`); embedded changelog
  entries 2.1.327-2.1.331 (`changelog.md`); binary strings (`cm.txt`).
- What: Claude writes JavaScript that a `REPL` tool runs; the script calls tools (`` $`cmd` `` for
  Bash, `tools.Glob(...)`, `write()`, `edit()`, Agent, Workflow, `searchTools`, `describeTool`).
  Many tool calls happen in one model turn. In Code Mode Read/Bash/Glob/Grep/Edit/Write are only
  callable inside REPL (direct call → "No such tool available: Glob. Glob is only available inside
  REPL.", probe run5).
- Not a `--permission-mode` value: `claude --help` lists acceptEdits, auto, bypassPermissions,
  manual, dontAsk, plan. It is "a mode" in the sense of a session-wide switch with a banner, which
  matches the user's "plan mode처럼" (inference: the user paraphrases).
- Enable: env `CLAUDE_CODE_EXPERIMENTAL_CODE_MODE=1` from shell, user settings `env`, or a
  `--settings` file; project settings ignored; `0` anywhere wins; managed `0` blocks (docs). First
  interactive use asks to accept caveats (`~/.claude.json` keys `codeModeCaveatsAcceptedV1`,
  `codeModeAutoModeCaveatAcceptedV1`, binary strings).
- Version: v2.1.323+ (docs); hook-failure semantics `"onFailure":"block"` 2.1.329; cloud
  providers + `--bare` fix 2.1.331 (changelog).
- Models: Opus 5.5, Sonnet 5.5, Haiku 5.5, Fable 5.2 (docs).
- Limits (docs): no Remote Control / Chrome, no background sessions, a Code Mode session resumes
  only with Code Mode on; scripts 10 min when Claude waits, up to 2 h in background (auto/bypass).
- Headless `claude -p` (probes, undocumented — docs name only "an interactive claude session"):
  - shell env only → Code Mode stays OFF (run1: init tools normal, no REPL).
  - `--settings '{"env":{"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"1"}}'` → ON (run3-7).
  - Cause in binary (`fn.txt`, function settleCodeModeOptInAtStartup):
    `P=M&&o.source!=="flagSettings"&&v!=="entrypoint"?"not_passed":v` — headless accepts only
    flagSettings. So user-settings env would turn it on for the interactive conductor, not workers
    (inference from code + run1).
- With `--agent`: worked with `--agents` JSON neutral agent (run3-7). With `--permission-mode auto`:
  works; the classifier reviews the whole script, not each call (docs; run4/5).
- PreToolUse hooks (docs + probes run3/5/6/7):
  - inner calls fire PreToolUse/PostToolUse under the usual tool name (Bash/Read/Glob/Write) with
    `agent_type`; `write()` goes through Write's PreToolUse (run6).
  - a `REPL` matcher fires for the script itself (`tool_input.code`); a `*` matcher did not log
    PreToolUse REPL in run3 (PostToolUse REPL did fire).
  - hook deny is honored per inner call, the script continues (run5: f3 denied); deny rules apply
    (run5: Glob hid denied f4.txt).
  - failing hook lets the call through unless `"onFailure":"block"` (docs, 2.1.329); after a hook
    rewrote a call (`updatedInput`) auto mode will not run it (binary string).
  - Stop hook fires (run3, run7).
- JS globals: `process`, `Bun`, `fetch`, `fs` undefined; `require` is a function, scope unprobed (run6).

### Candidate B: Workflow tool / dynamic workflows
- https://code.claude.com/docs/en/workflows.md (`workflows.md`): Claude writes a script that
  orchestrates many subagents. A delegation mechanism, not a session mode. Conductor disallows it
  (`claude/agents/conductor.md` frontmatter `disallowedTools: Agent, Workflow, Monitor, NotebookEdit`).

### Candidate C (from memory, NOT fetched — unverified): API "programmatic tool calling" / code
execution tool, and Cloudflare "Code Mode" (model writes code that calls MCP as an API). Same idea
as A but outside the CLI; not a Claude Code session mode, so they do not match "plan mode처럼".

Most likely: A — the only one that is a session-wide Claude Code switch, released recently
(2.1.323+), and literally named "Code Mode".

## Part 2 — Where it meets the harness

- Launch: `bin/harness-run:70-71` runs `claude -p --agent "$role" ... --permission-mode auto
  --permission-prompts none` with no `--settings`, so workers never get Code Mode today even if the
  user sets the env in `~/.claude/settings.json` (flagSettings-only rule above).
- Conductor gate: `install.sh:14` `MATCHER="Edit|Write|Read|Grep|Glob|Bash"` — REPL not matched;
  `claude/hooks/conductor-gate.sh:583-617` has no REPL case. Inner calls are still gated: run7
  with the real gate allowed `Read docs/x.md` and `git status --short`, denied `Read src/a.sh` and
  `ls src && cat src/a.sh`. So no gate bypass found, but the conductor's one-command rule
  (`MSG_BASH`, line 64) fights scripts' compound commands, and the conductor reads little anyway:
  little to gain there.
- Worker deny rules (`harness init`): enforced per inner call (run5).
- Stop-hook verification (`harness-verify`): Stop fires (run3/7); unaffected.
- Stream / dashboard: inner calls appear as ordinary `tool_use` blocks with ids `toolu_cc_*`
  (REPL call itself `toolu_01*`); `lib/harness-dash.sh:62-77` keys on `.type=="tool_use"` and
  `.name`, so it should render inner calls (inference; not run against the dashboard).
- Denial accounting: `bin/harness-run:140-176` builds `denied[]` from `permission_denied` events
  and `result.permission_denials`. A classifier whole-script refusal arrives as tool `Bash`, empty
  `command`, description "A step that was refused as a whole; nothing in it ran: …" (run4/5) →
  recorded as Bash with null input. `lib/harness-headless.sh:127-130` exits 2 only when there are
  denials AND no report, so a false positive costs a retry turn, not a failed ask, unless the
  worker gives up.
- Classifier false positives: 2 of 5 auto runs had a whole harmless script refused (run4
  "[Undermining Oversight]" on a Read script; run5 on `ls -1 f*.txt`). Haiku runs only; real
  role models untested.
- Resume: Code Mode sessions resume only with Code Mode on (docs) → `--keep`/`--resume` in
  `harness-run` must pass the same `--settings`.
- Version floor: README.md:16 says ≥ 2.1.277; Code Mode needs ≥ 2.1.323 (≥ 2.1.329 for
  onFailure). Would need a runtime version check or a README bump.
- Lanes / progress.jsonl: no change needed; cost/turns fields already recorded per ask.

### Metrics (jq over `.harness/progress.jsonl`, rows ts ≥ 2026-10-28; `harness` not run per worker rule)

| Role | Asks | Exits | Dur median/p95 | Cost total | Cost median | Turns median | ctx_after median | Denials |
|---|---|---|---|---|---|---|---|---|
| analyst | 49 | 0:45 1:1 3:2 4:1 | 294/884 s | $112.05 | $2.22 | 27 | 77k | 5 |
| implementer | 122 | 0:110 1:4 3:4 4:1 5:2 | 228/1740 s | $47.97 | $0.18 | 9 | 50k | 5 |
| reviewer | 55 | 0:32 5:22 | 215/824 s | $46.46 | $0.62 | 15 | 57k | 3 |

Where it can save (inference): the analyst is the cost centre ($112 of $206, 27 turns median);
batching reads/greps into one script cuts turns and repeated cache reads. Reviewer second.
Implementer is cheap (9 turns, $0.18) — little to gain. Conductor context: unchanged, it only reads
reports. Where it cannot: tokens of file contents the model must still read; model thinking time.

## Part 3 — Options (smallest first)

0. Do nothing / wait. Adds nothing, removes nothing. Right if: the feature is experimental, headless
   enabling is undocumented (flagSettings only, may change), and 2/5 classifier false positives.
   Cost 0.
1. **One-off experiment, no code change (recommended).** Run Part 4 by hand from a scratch dir.
   Changes no files; rollback n/a. Cost ~$15-20. Decides whether 2 is worth building.
2. Opt-in per role. `bin/harness-run` adds `--settings '{"env":{"CLAUDE_CODE_EXPERIMENTAL_CODE_MODE":"1"}}'`
   for roles listed in one config key (e.g. analyst, reviewer), also on resume; `denied[]` tags
   "refused as a whole" entries separately; version check ≥ 2.1.329 else skip. Must remove a
   mechanism per AGENTS.md (candidate: an unread metrics field or mode — pick via `harness
   metrics`). Files: `bin/harness-run`, `lib/harness-headless.sh`, `lib/harness-defaults.sh`,
   README, one test suite. Rollback: unset the key. Risk: undocumented flag path breaks on upgrade
   (fails closed: Code Mode just stays off).
3. Default on for all workers (+ add `REPL` to `install.sh:14` matcher and a REPL case in the
   gate for defence in depth). Largest blast radius: false positives on every role, version floor
   raised for everyone, implementer gains little. Not recommended now.

For candidate B (Workflow): the harness already is a conductor→worker orchestrator; letting
workers use Workflow would duplicate `harness ask` — a mechanism without removal. For C: not
applicable to CC sessions.

## Part 4 — First experiment

- Task: one fixed read-heavy analyst brief from the archive (`.harness/log/*.md`, a past analyst
  ask with a known-good report), replayed at its base commit in a `mktemp -d` clone.
- Arms: A = current launch line; B = same + `--settings` Code Mode env. Real role model (opus),
  `--agent analyst`, `--permission-mode auto`, `--include-hook-events`, stream-json saved.
- N = 3 per arm (6 runs), interleaved A/B.
- Measure from result JSON / stream: `total_cost_usd`, `duration_ms`, `num_turns`, count of
  `tool_use` blocks (split `toolu_cc_*`), `permission_denials` (and how many are "refused as a
  whole"), hook events fired (PreToolUse, Stop), report written and matches the known answer.
- Pass: median cost or wall time drops ≥ 25% in B, report quality equal (same findings), and 0
  whole-script false positives across the 3 B runs. Fail otherwise → option 0.
- Budget: ~$15-20 (analyst median $2.22 × 6 + margin); stop at $25.

## Probes run (all claude-haiku-5-5, `--permission-mode auto`, `--no-session-persistence`)

| Run | Setup | Result | Cost |
|---|---|---|---|
| 1 | shell env only | Code Mode off | $0.0040 |
| 2 | `--tools ""` debug | no info | $0.0019 |
| 3 | `--settings` env | on; inner Bash `toolu_cc`, hooks fired, Stop fired | $0.0057 |
| 4 | deny hook + deny rule | classifier refused whole script | $0.0040 |
| 5 | neutral prompt | hook deny f3, rule hid f4, 1 false positive, direct Glob refused | $0.0055 |
| 6 | `write()` + globals | `write()` → PreToolUse Write | $0.0048 |
| 7 | real conductor gate | allowed docs read + git status; denied src read + compound cmd | $0.0057 |

Total ≈ $0.032.
