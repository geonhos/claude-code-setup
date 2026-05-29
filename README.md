# multi-agent-system — Claude Code Plugin

**v6.0.0 — Harness Conductor Edition.** A thin harness that drives native Claude Code through *enforced gates* and improves itself via a weekly learning loop. v5 stopped competing on commodity *skills*; v6 stops competing on *implementation* — native Claude Code now plans, codes, and verifies well on its own. So this plugin no longer ships bundled domain agents. What remains is the part native CC doesn't give you: a one-prompt pipeline where the discipline (a scored plan, a clean review, green tests) is **enforced rather than optional**, plus a self-improving feedback loop.

> The product is no longer "we have agents." It's "the gates are enforced, and the harness learns from your sessions."

## Install

```
/plugin marketplace add geonhos/claude-code-setup
/plugin install multi-agent-system@geonhos-plugins
```

Companion plugins are optional but recommended (see [Companion plugins](#companion-plugins-recommended)).

## What you get

```
┌──────────────────────────────────────────────────────────────┐
│  This plugin: a gated conductor + a learning loop            │
├──────────────────────────────────────────────────────────────┤
│  /ship    one-prompt pipeline. Thin conductor — drives       │
│           native CC through gates:                           │
│           plan ≥8 → branch → implement → review → test → PR  │
│  /plan    explore approaches + score (≥8 required)           │
│  /retro   weekly retrospective from auto-captured signals    │
│  /retro-review  human gate for retro's draft memos           │
│  best_practices  context-aware stub → delegates to context7  │
│  7 hooks  startup, feedback capture, pre-commit, stop-verify,│
│           subagent progress                                  │
│  0 agents implementation/verification is delegated, not      │
│           bundled                                            │
└──────────────────────────────────────────────────────────────┘
        │                    │                  │
        ▼                    ▼                  ▼
   ┌──────────┐      ┌────────────┐    ┌──────────────┐
   │  native  │      │ anthropics │    │  wshobson    │
   │  Claude  │      │  /plugins  │    │  /agents     │
   │   Code   │      │ /official  │    │              │
   └──────────┘      └────────────┘    └──────────────┘
   plan mode,         /code-review,     /tdd-cycle,
   subagents,         /commit, /pr,     /smart-debug,
   /review, hooks     /context7, ...    /unit-testing, ...
```

The harness sequences and **gates**; the actual work goes to native Claude Code and best-of-breed plugins. You install once, and `/ship` enforces the same discipline on every feature regardless of which tools run each stage.

## /ship — the gated conductor

```
/ship "Add JWT-based user authentication"
   │
   ├─ 1 PLAN      /plan skill                       [GATE: score ≥ 8]
   ├─ 2 BRANCH    git checkout -b feature/...
   ├─ 3 IMPLEMENT native CC (TodoWrite + subagents)
   ├─ 4 REVIEW    built-in /review (+ /security-review)  [GATE: Critical = 0]
   ├─ 5 TEST      full suite via pre-commit / native     [GATE: all green]
   └─ 6 PR        gh pr create
```

Each stage is a gate. PLAN must score ≥ 8 (else it iterates, then asks you). REVIEW must land zero Critical findings (else it fixes and re-reviews, max 2 cycles). TEST must be all green (failures are classified — true failure / test bug / flaky / environment — then fixed and re-run). **`/ship` no longer implements with bundled agents** — it drives native Claude Code and calls out to companion plugins per stage when installed.

## Learning loop — the harness improves itself

```
[ daily ]  user calls /ship or individual skills
              │
              └──► hooks auto-capture:
                    • UserPromptSubmit  → frustration keywords
                    • PostToolUse        → post-ship rework
                    • PreToolUse         → git revert / reset --hard
                    → logs/feedback-signals.jsonl

[ weekly auto ]   /retro  (or /schedule "weekly mon 09:00" /retro)
                     │
                     ├──► logs/retro-YYYY-WW.md      report
                     └──► memory/_draft/*.md          draft memos

[ weekly manual 5 min ]  /retro-review
                            │
                            └──► approve / reject / edit / hold
                                 → approved memos move to memory/
                                   and update MEMORY.md
```

Layer 1 (capture) and Layer 2 (analysis) are automatic. **Layer 3 (apply) is always human-gated.** The harness never changes itself without your approval.

## Companion plugins (recommended)

Since v5, commodity skills live in better-maintained community plugins. v6 goes further and delegates *implementation* too. Install whichever match your stack — `/ship` will use them per stage when present:

| Plugin source | Install | Provides |
|---------------|---------|----------|
| `anthropics/claude-plugins-official` | `/plugin marketplace add anthropics/claude-plugins-official` then `/plugin install code-review@claude-plugins-official` | `code-review`, `commit-commands`, `context7`, `code-simplifier`, `pr-review-toolkit` |
| `wshobson/agents` | `/plugin marketplace add wshobson/agents` then `/plugin install tdd-workflows@wshobson-agents` | `tdd-workflows`, `debugging-toolkit`, `unit-testing`, `comprehensive-review`, `git-pr-workflows` |
| Built into Claude Code | (already installed) | `/review`, `/security-review`, `/simplify`, `/init`, plan mode, native subagents |

> **Why not auto-install via `dependencies`?** Claude Code supports declaring plugin dependencies that auto-install, but it requires the upstream marketplace to publish `{plugin-name}--v{version}` git tags and the root marketplace to whitelist cross-marketplace deps. Both upstreams aren't verified for tag compliance, so manual install stays the safe path for now.

### What used to be bundled → what to use now

| Was bundled (≤ v5) | v6 replacement |
|--------------------|----------------|
| `backend-dev` / `frontend-dev` / `ai-expert` agents | native Claude Code (plan mode + subagents); `wshobson:tdd-workflows` for a TDD loop |
| `code-reviewer` agent | built-in `/review` or `anthropics:code-review` |
| `qa-executor` agent | `pre-commit` hook + native test run; `wshobson:unit-testing` |
| `plan-architect` agent | the `/plan` skill (the scored rubric was always there) |
| `/tdd` `/test` `/debug` `/review` `/commit` `/pr` (removed in v5) | see the companion table above |

## Skills (5)

| Skill | Description |
|-------|-------------|
| [`/ship`](skills/ship/SKILL.md) | Thin conductor — drives native CC through enforced gates |
| [`/plan`](skills/plan/SKILL.md) | Explore approaches + scored execution plan (score-gated rubric has no equivalent in surveyed plugins) |
| [`/retro`](skills/retro/SKILL.md) | Weekly retrospective + draft memo generation |
| [`/retro-review`](skills/retro-review/SKILL.md) | Human approval gate for retro drafts |
| `best_practices` | Context-aware stub (Claude invokes it when relevant) that calls context7 MCP for current React / Spring / Python guidance |

## Workflow guide ("3-file rule")

| Files touched | Recommended flow |
|---------------|------------------|
| 1–2 | Direct work → `git commit` (pre-commit hook auto-validates) |
| 3–5 | `/plan` → approve → implement → commit |
| 6+ or cross-domain | `/ship "..."` (full gated pipeline) |

## Hooks (7)

| Hook | Purpose |
|------|---------|
| `SessionStart` | Slim banner + pending draft-memo count |
| `UserPromptSubmit` | Frustration keyword → `feedback-signals.jsonl` |
| `PreToolUse(Bash)` | Detect `git commit` → run `pre-commit.sh` (compile/typecheck by default) |
| `PostToolUse(Edit/Write/Bash)` | Post-ship rework / `git revert` detection → `feedback-signals.jsonl` |
| `Stop` | Conditional verification nudge (only if changes present, or an active `/ship`) |
| `SubagentStart` | Subagent activity logging → `agent-progress.jsonl` |
| `SubagentStop` | Subagent completion + transcript analysis → `agent-progress.jsonl` |

### Environment variables (kill switches)

| Variable | Default | Effect |
|----------|---------|--------|
| `HARNESS_AUTO_FEEDBACK` | `1` | `0` = disable all signal capture |
| `HARNESS_SKIP_PRECOMMIT` | `0` | `1` = skip pre-commit validation entirely |
| `HARNESS_RUN_TESTS` | `0` | `1` = run full tests on pre-commit (default is compile-only) |

## Directory layout

```
plugin.json               # manifest (v6.0.0, no agents array)

.claude-plugin/
└── marketplace.json      # marketplace entry

harness/
└── progress.md           # /ship cross-session state

hooks/
├── hooks.json
├── startup.sh
├── feedback-capture.sh
├── pre-commit-guard.sh
├── pre-commit.sh
├── stop-verify.sh
└── agent-progress.sh

skills/
├── ship/             # gated conductor
├── plan/             # scored planning
├── retro/            # weekly retro + draft memos
├── retro-review/     # human approval gate
└── best_practices/   # context7-delegating stub (Claude-invoked)

memory/
├── _draft/           # retro-generated drafts (awaiting approval)
└── MEMORY.md         # approved memo index

logs/
├── feedback-signals.jsonl
├── agent-progress.jsonl
├── agent-progress-summary.md
├── retro-YYYY-WW.md
└── retro-decisions.jsonl
```

## What changed in v6.0.0

**Breaking.** v6 delegates *implementation*, not just commodity skills.

- **All 6 bundled agents removed** (`plan-architect`, `backend-dev`, `frontend-dev`, `ai-expert`, `code-reviewer`, `qa-executor`); the `agents` array is gone from `plugin.json`. Roles fold into `/plan`, built-in `/review`, the `pre-commit` hook, and native Claude Code.
- **`/ship` rewritten** as a 106-line thin conductor (was 315). Same enforced gate sequence; bundled agents replaced by native CC + companion plugins per stage.
- **`/plan` de-agented**; rubric swaps "Agent Assignment" → "Scope / Right-sizing".
- **`/retro`, `startup.sh` banner, manifests, README** updated for the conductor positioning.
- Plugin **name kept** (`multi-agent-system`) for install-path stability despite being a slight misnomer now.

See [CHANGELOG.md](CHANGELOG.md) for full history.

## License

MIT
