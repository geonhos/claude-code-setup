# multi-agent-system — Claude Code Plugin

**v5.0.0 — Harness Slim Edition.** A composable harness that orchestrates pipelines (`/ship`), captures feedback signals automatically, and proposes its own improvements via a weekly learning loop. v5 strips the commodity skills (TDD, debug, test, review, commit, PR, best-practices) and delegates them to better-maintained community plugins. What stays is what we do better than anyone else: the pipeline, the learning loop, and 6 slim agents with a 10-point plan-validation gate.

## Install

```
/plugin marketplace add geonhos/claude-code-setup
/plugin install multi-agent-system@geonhos-plugins
```

Optional but recommended companion plugins (see [Companion plugins](#companion-plugins-recommended)).

## What you get

```
┌──────────────────────────────────────────────────────────────┐
│  This plugin: harness + pipeline + learning loop             │
├──────────────────────────────────────────────────────────────┤
│  /ship    one-prompt: plan → issue → branch → exec → review  │
│           → test → PR                                        │
│  /plan    explore approaches + score (≥8 required)           │
│  /retro   weekly retrospective from auto-captured signals    │
│  /retro-review  human gate for retro's draft memos           │
│  best_practices  context-aware stub → delegates to context7  │
│  7 hooks  startup, feedback capture, pre-commit, stop-verify,│
│           subagent progress                                  │
│  6 agents plan-architect, code-reviewer, qa-executor,        │
│           backend-dev, frontend-dev, ai-expert               │
└──────────────────────────────────────────────────────────────┘
            │           │                  │
            ▼           ▼                  ▼
        ┌───────┐  ┌────────────┐  ┌──────────────┐
        │ Claude│  │ anthropics │  │  wshobson    │
        │  Code │  │  /plugins  │  │  /agents     │
        │ builtin│ │ /official  │  │              │
        └───────┘  └────────────┘  └──────────────┘
        /review,    /code-review,   /tdd-cycle,
        /security-  /commit, /pr,   /smart-debug,
        review, ... /context7, ...  /unit-testing, ...
```

The harness is the orchestrator; commodity work goes to specialized plugins. You install once, and your `/ship` pipeline can call out to the best-of-breed skill for each stage.

## Companion plugins (recommended)

These ship *better* commodity skills than what we removed in v5. Install whichever match your stack:

| Plugin source | Install | Provides |
|---------------|---------|----------|
| `anthropics/claude-plugins-official` | `/plugin marketplace add anthropics/claude-plugins-official` then `/plugin install code-review@claude-plugins-official` | `code-review`, `commit-commands`, `context7`, `code-simplifier`, `pr-review-toolkit` |
| `wshobson/agents` | `/plugin marketplace add wshobson/agents` then `/plugin install tdd-workflows@wshobson-agents` | `tdd-workflows`, `debugging-toolkit`, `unit-testing`, `comprehensive-review`, `git-pr-workflows` |
| Built into Claude Code | (already installed) | `/review`, `/security-review`, `/simplify`, `/init` |

> **Why not auto-install via `dependencies`?** Claude Code v2.1.110+ supports declaring plugin dependencies that auto-install on user install, but it requires the upstream marketplace to publish `{plugin-name}--v{version}` git tags and the user's root marketplace to whitelist cross-marketplace deps in `allowCrossMarketplaceDependenciesOn`. Both upstreams haven't been verified for tag compliance. We'll add formal `dependencies` declarations in v5.1 once the upstream tagging is confirmed — until then, manual install is the safe path.

### Recommended mapping (what v4 used to do → what to use now)

| v4 skill (removed) | v5 replacement |
|--------------------|----------------|
| `/tdd` | `wshobson:tdd-workflows` (`/tdd-cycle`, `/tdd-red`, `/tdd-green`, `/tdd-refactor`) |
| `/test` | `wshobson:unit-testing`, `wshobson:performance-testing-review` |
| `/debug` | `wshobson:debugging-toolkit` (`/smart-debug` + `debugger` agent) |
| `/review` | Built-in `/review` or `anthropics:code-review` |
| `/commit` | `anthropics:commit-commands` (built-in commit behavior also covers most cases) |
| `/pr` | `anthropics:commit-commands` `/pr-create` |
| `react/spring/python_best_practices` | `best_practices` skill (this plugin) — delegates to context7 MCP |

## /ship — the harness pipeline

```
/ship "Add JWT-based user authentication"
   │
   ├─ Stage 1: PLAN     plan-architect agent (auto-scored ≥ 8)
   ├─ Stage 2: ISSUE    gh issue create
   ├─ Stage 3: BRANCH   feature/issue-N-slug
   ├─ Stage 4: EXECUTE  domain agents (backend / frontend / ai), parallel where possible
   ├─ Stage 5: REVIEW   code-reviewer agent (Critical = 0 required)
   ├─ Stage 6: TEST     qa-executor agent (full suite)
   └─ Stage 7: PR       gh pr create
```

Each stage is a gate. If PLAN scores < 8, the user is asked before continuing; if a Critical review issue lands, the pipeline pauses with a fix list; if tests fail, qa-executor classifies (true failure / test bug / flaky / environment / dependency) and proposes a fix before retry.

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

## Agents (6)

All slim — average 85 lines each, down from ~340 in v4. Behavior unchanged; noise removed.

| Trigger | Agent | Role |
|---------|-------|------|
| Complex multi-task feature | [`plan-architect`](agents/pipeline/plan-architect.md) | Plan + score (≥ 8 to ship) |
| Java / Spring / API | [`backend-dev`](agents/execution/backend-dev.md) | DDD + JPA + tests in same commit |
| React / TS / UI | [`frontend-dev`](agents/execution/frontend-dev.md) | MVVM + FSD + tests in same commit |
| Python / ML / LLM | [`ai-expert`](agents/execution/ai-expert.md) | ML/LLM with metrics, reproducibility |
| Code or doc review | [`code-reviewer`](agents/quality/code-reviewer.md) | Severity-tiered findings, no auto-fix |
| Test execution | [`qa-executor`](agents/quality/qa-executor.md) | Run + classify failures + suggest fixes |

For language-specific patterns, every execution agent consults the `best_practices` skill, which queries context7 for current upstream docs — no baked-in stale rules.

## Skills (5)

| Skill | Description |
|-------|-------------|
| [`/ship`](skills/ship/SKILL.md) | Full pipeline harness |
| [`/plan`](skills/plan/SKILL.md) | Explore approaches + scored execution plan (kept because the score-gated rubric has no equivalent in surveyed plugins) |
| [`/retro`](skills/retro/SKILL.md) | Weekly retrospective + draft memo generation |
| [`/retro-review`](skills/retro-review/SKILL.md) | Human approval gate for retro drafts |
| `best_practices` | Context-aware stub (Claude invokes it when relevant, not via formal file-glob trigger) that calls context7 MCP for current React / Spring / Python guidance |

> v5 removed: `/tdd`, `/test`, `/debug`, `/review`, `/commit`, `/pr`, `react_best_practices`, `spring_best_practices`, `python_best_practices`. See [Companion plugins](#companion-plugins-recommended) for replacements.

## Workflow guide ("3-file rule")

| Files touched | Recommended flow |
|---------------|------------------|
| 1–2 | Direct work → `git commit` (pre-commit hook auto-validates) |
| 3–5 | `/plan` → approve → implement (TDD via `/tdd-cycle` from wshobson) → commit |
| 6+ or cross-domain | `/ship "..."` (full pipeline) |

## Hooks (7)

| Hook | Purpose |
|------|---------|
| `SessionStart` | Slim banner + pending draft-memo count |
| `UserPromptSubmit` | Frustration keyword → `feedback-signals.jsonl` |
| `PreToolUse(Bash)` | Detect `git commit` → run `pre-commit.sh` (compile/typecheck by default) |
| `PostToolUse(Edit/Write/Bash)` | Post-ship rework / `git revert` detection → `feedback-signals.jsonl` |
| `Stop` | Conditional verification nudge (only if changes present) |
| `SubagentStart` | Agent activity logging |
| `SubagentStop` | Agent completion + transcript analysis → `agent-progress.jsonl` |

### Environment variables (kill switches)

| Variable | Default | Effect |
|----------|---------|--------|
| `HARNESS_AUTO_FEEDBACK` | `1` | `0` = disable all signal capture |
| `HARNESS_SKIP_PRECOMMIT` | `0` | `1` = skip pre-commit validation entirely |
| `HARNESS_RUN_TESTS` | `0` | `1` = run full tests on pre-commit (default is compile-only) |

## Directory layout

```
plugin.json               # manifest (v5.0.0)

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

agents/
├── pipeline/plan-architect.md
├── execution/{backend-dev,frontend-dev,ai-expert}.md
└── quality/{code-reviewer,qa-executor}.md

skills/
├── ship/             # harness pipeline
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

## What changed in v5.0.0

This is a **breaking** release. Removed skills are not coming back — use the companion plugins documented above.

- **Skills removed (9)**: `/tdd`, `/test`, `/debug`, `/review`, `/commit`, `/pr`, `react_best_practices`, `spring_best_practices`, `python_best_practices`. 3,027 lines deleted across all SKILL.md, metadata.json, and `rules/` files in those trees.
- **Skill added (1)**: `best_practices` — 48-line context-aware stub (Claude invokes it when relevant) that delegates to context7 MCP. Replaces 2,476 lines of stale curated rules across the three former `*_best_practices` trees with always-fresh upstream docs.
- **Agents slimmed**: 6 agents went from 2,171 lines total → 511 lines (76% reduction). Dead frontmatter references (`task_breakdown`, `verify_complete`, `test_runner`, `coverage_report`, `jpa_entity`, `component_generator`, `rag_setup`) removed. Behavior unchanged.
- **Companion plugin guidance** added to this README.
- **Hooks, /ship, /plan, /retro, /retro-review** unchanged.

See [CHANGELOG.md](CHANGELOG.md) for full history.

## License

MIT
