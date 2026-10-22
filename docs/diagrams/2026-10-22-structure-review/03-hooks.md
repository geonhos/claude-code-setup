# 03 Hooks

Conductor hooks are registered by `install.sh` in `~/.claude/settings.json`; worker hooks
live in each agent file's frontmatter, so a hook change needs a worker respawn.

```mermaid
flowchart LR
  subgraph CS[Conductor session · settings.json]
    SS([SessionStart]) --> RES[conductor-resume<br/>inject progress.md + active wiki lines]
    UP([UserPromptSubmit]) --> RT[conductor-route<br/>log to routing.jsonl only]
    PT([PreToolUse]) --> G{conductor-gate}
    G -- worker or HERDR_ENV≠1 --> AL[allow]
    G -- Read/Grep/Glob --> RG[.harness · docs · *.md only]
    G -- Edit/Write --> EW[.harness/* · docs/*.md only]
    G -- Agent/Workflow/Monitor --> DN[deny]
    G -- Bash --> BS[split segments → char allowlist → BASH_ALLOW]
    G -- no jq / bad input --> DN
  end
  subgraph WS[Worker session · agent frontmatter]
    PTU([PostToolUse Edit/Write]) --> FMT[verify format<br/>implementer, block on lint fail]
    ST([Stop]) --> K{role}
    K -- analyst/reviewer --> DM[write done marker]
    K -- implementer --> VS[report → .pending<br/>lint → test]
    VS -- pass --> RS[restore report + marker]
    VS -- fail, < 3 tries --> BL[decision: block<br/>worker keeps fixing]
    VS -- fail, 3rd try --> FL[restore + fail + marker]
    BL --> ST
  end
```

| Hook | On failure |
|---|---|
| conductor-gate | fail closed: no jq or unparseable input → deny (decision 0005) |
| conductor-route, conductor-resume | never fail, stay silent |
| verify done | no marker → harness waits 30 s grace, exit 3 |
| verify stop | hook killed → stale `.pending` → ask waits full timeout, exit 5 INTERRUPTED |
| verify format | no jq → exit 0 (silent pass) |
