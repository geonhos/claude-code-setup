# Architecture

The harness is a **conductor** Claude session, gated by a PreToolUse hook so it can only read reports and run `harness`, plus three worker Claude sessions (analyst, implementer, reviewer) in [herdr](https://herdr.dev) panes. `.harness/` in the project directory is the shared store for reports, logs, verification state and the progress summary.

These diagrams describe the code on `main` as of commit `583e0e5`, not the specs. Mermaid sources live in [`diagrams/`](diagrams/README.md).

## Contents

1. [Runtime data flow](#1-runtime-data-flow)
2. [Config and hook wiring](#2-config-and-hook-wiring)
3. [harness ask sequence](#3-harness-ask-sequence)
4. [Conductor gate decision flow (conductor-gate.sh)](#4-conductor-gate-decision-flow-conductor-gatesh)
5. [Verification loop](#5-verification-loop)
6. [Progress log and context reset](#6-progress-log-and-context-reset)
7. [Install layout (install.sh)](#7-install-layout-installsh)
8. [Exit codes](#exit-codes)

## 1. Runtime data flow

![Runtime data flow](diagrams/01-runtime-data-flow.svg)

<details><summary>Mermaid source</summary>

```mermaid
flowchart LR
  user([User])
  subgraph herdr["herdr (terminal multiplexer)"]
    cond["Conductor session<br/>claude, settings.agent = conductor"]
    an["analyst pane<br/>opus"]
    im["implementer pane<br/>sonnet"]
    rv["reviewer pane<br/>opus"]
  end
  hcli["harness CLI<br/>bin/harness"]
  hv["harness-verify<br/>bin/harness-verify"]
  subgraph store[".harness/ (cwd of conductor)"]
    rep[("reports/&lt;agent&gt;.md")]
    log[("log/*.md · progress.jsonl<br/>progress.md · goal.md")]
    vst[("verify/&lt;agent&gt;.json .base .attempts")]
  end
  tx[("~/.claude/projects/.../session.jsonl")]
  gh[(git / GitHub)]

  user -- "request, answers" --> cond
  cond -- "summary, questions" --> user
  cond -- "harness ask/report/status (Bash)" --> hcli
  hcli -- "stdout report + exit 0-5" --> cond
  hcli -- "pane split, agent start/prompt/get" --> herdr
  herdr -- "status, session id, screen text" --> hcli
  an & im & rv -- "write report" --> rep
  rep -- "read" --> hcli
  hcli -- "log + jsonl + regen md" --> log
  tx -- "ctx tokens (last usage)" --> hcli
  im -- "Stop hook" --> hv
  rv -- "run all --base" --> hv
  hv -- "state, block reason" --> vst
  hcli -- "baseline, read status" --> vst
  im & rv -- "commit / diff" --> gh
  cond -- "gh pr create/view" --> gh
```

</details>

The conductor never touches source: it talks to the user, runs `harness` (gated Bash), and reads only reports. Workers write reports into `.harness/`; `harness` reads them, logs every ask and returns an exit code. Context size comes from the worker's transcript under `~/.claude/projects`.

## 2. Config and hook wiring

![Config and hook wiring](diagrams/02-config-wiring.svg)

<details><summary>Mermaid source</summary>

```mermaid
flowchart LR
  cond["Conductor session"]
  workers["analyst / implementer / reviewer panes"]
  hcli["harness CLI"]
  subgraph claudehome["~/.claude"]
    set[("settings.json<br/>agent, hooks, env, TTLs")]
    hooks["hooks: conductor-gate.sh<br/>conductor-resume.sh"]
    agents[("agents/*.md")]
  end
  prog[("progress.md")]

  set -. "configures" .-> cond
  agents -. "claude --agent: prompt + hooks" .-> workers
  cond -- "PreToolUse hook JSON" --> hooks
  hooks -- "deny JSON / allow" --> cond
  prog -- "read by" --> hooks
  hooks -- "SessionStart: progress.md" --> cond
  hcli -. "starts with --agent X" .-> workers
```

</details>

`~/.claude/settings.json` makes every plain `claude` session the conductor and registers the PreToolUse gate and the SessionStart resume hook. Worker prompts and their hooks come from `agents/*.md` via `claude --agent`.

## 3. `harness ask` sequence

![`harness ask` sequence](diagrams/03-ask-sequence.svg)

<details><summary>Mermaid source</summary>

```mermaid
sequenceDiagram
  autonumber
  participant C as Conductor
  participant H as harness ask
  participant D as herdr
  participant W as Worker
  participant V as harness-verify
  participant S as .harness store

  C->>H: harness ask agent 'instr' [--timeout] [--fresh|--keep]
  H->>H: ctx_before from transcript, head_before, fork ask_inner (stdout buffered)
  opt implementer and harness-verify not on PATH
    H-->>C: exit 1
  end
  H->>D: agent get (live?) else pane split + agent start --agent X
  alt status = working
    H-->>C: screen, exit 4 (nothing sent)
  end
  Note over H,D: maybe_reset (live worker only, not --keep)<br/>need = implementer always, else ctx > 120000, or --fresh<br/>skip unless --fresh when last ask exit not 0 (reviewer: not 0/5)<br/>status idle|done → /clear, poll new session id (≤10 s) → else close + respawn
  H->>S: archive leftover report as late (jsonl exit null), rm report
  opt implementer
    H->>V: baseline (state id → verify/implementer.base, attempts=0)
  end
  alt status = blocked
    H-->>C: screen, exit 2
  end
  H->>D: agent prompt 'instr' --wait --timeout 600000
  D->>W: instruction
  W->>S: reports/agent.md
  opt implementer Stop hook
    W->>V: stop → lint+test, may block and retry
    V->>S: verify/implementer.json
  end
  D-->>H: settled (or prompt failed)
  H->>D: agent get status
  alt blocked
    H-->>C: exit 2
  else idle/done and report present
    H->>S: read report (+ verify json / VERDICT line)
    H-->>C: report, exit 0 or 5 (reviewer w/o VERDICT → 3)
  else idle/done, only .pending (hook killed)
    H-->>C: restore report + "verify: INTERRUPTED", exit 5
  else idle/done, no report
    H-->>C: exit 4 if prompt failed, else exit 3
  else working/unknown
    H-->>C: diag + screen, exit 4
  end
  H->>S: log/ts-agent.md, progress.jsonl line, rotate, progress.md
```

</details>

The context reset runs after the "still working" check and before the old report is removed and the prompt is sent; a freshly spawned worker is never reset. Whatever the outcome (including SIGTERM/INT/HUP of the wrapper → exit 143/130/129), `ask_finish` replays the buffered stdout and writes the log.

## 4. Conductor gate decision flow (`conductor-gate.sh`)

![Conductor gate decision flow (`conductor-gate.sh`)](diagrams/04-gate-decision-flow.svg)

<details><summary>Mermaid source</summary>

```mermaid
flowchart TD
  A["PreToolUse hook JSON on stdin"] --> R{"HARNESS_ROLE = worker?"}
  R -- yes --> OK([allow: no output])
  R -- no --> J{"jq on PATH?"}
  J -- no --> DJ([deny: static JSON, fail closed])
  J -- yes --> P{"tool_name parsed?"}
  P -- no --> OK
  P -- yes --> T{"tool_name"}
  T -- "Agent, Workflow" --> DA([deny MSG_AGENT])
  T -- Monitor --> DB([deny MSG_BASH])
  T -- "Edit, Write, NotebookEdit,<br/>mcp fs write/edit/mkdir/move" --> WR{"writable? lexical + symlink-resolved<br/>.harness/* or docs/*.md"}
  WR -- yes --> OK
  WR -- no --> DW([deny MSG_WRITE])
  T -- "Read, Grep, mcp fs read/list" --> RD{"readable? lexical + resolved<br/>.harness, docs, *.md inside cwd"}
  RD -- yes --> OK
  RD -- no --> DR([deny MSG_READ])
  T -- Glob --> GL{"no .., /, ~ in pattern<br/>base + static prefix under .harness or docs"}
  GL -- yes --> OK
  GL -- no --> DR
  T -- Bash --> S1{"split into segments<br/>reject quotes unterminated, &lt; &gt; #, backtick, $( $' $quote"}
  S1 -- "fail or no segments" --> DB
  S1 -- ok --> S2{"each segment: character allowlist<br/>and no .. path component"}
  S2 -- fail --> DB
  S2 -- "jq segment" --> JQ{"jq: not first segment, 1 filter<br/>no -f/-L/env/paths/expansion"}
  JQ -- "ok (skips regex)" --> NX(["next segment"])
  JQ -- fail --> DB
  S2 -- "other" --> S3{"per-command check<br/>git: no patch/output/delete flags, no rev:path, branch list-only<br/>gh: subcommand allowlist, body-file under .harness/docs<br/>cat/ls: no quotes/globs, path in .harness/docs, no -R"}
  S3 -- fail --> DB
  S3 -- ok --> S4{"matches BASH_ALLOW regex?<br/>harness, herdr read-only, gh, git read-only, cat, ls"}
  S4 -- yes --> NX
  NX -- "all segments ok" --> OK
  S4 -- no --> DB
  T -- other tools --> OK
```

</details>

Default role is conductor; only `HARNESS_ROLE=worker` turns the gate off. Missing jq fails closed, but unparseable input fails open. Every deny reason is a fixed string naming the worker to use (stable prompt cache). A Bash command is allowed only when every `; & |`-separated segment passes; `jq` segments are checked by `jq_segment_ok` alone and never hit the `BASH_ALLOW` regex.

## 5. Verification loop

![Verification loop](diagrams/05-verification-loop.svg)

<details><summary>Mermaid source</summary>

```mermaid
flowchart TD
  CFG["config per key, first hit wins:<br/>.harness/verify.local.json → .claude/harness.json<br/>(no detection; null/missing key = step skipped; maxAttempts default 3)"]
  subgraph impl["implementer (frontmatter hooks)"]
    E["Edit / Write / MultiEdit"] --> PT["PostToolUse: harness-verify format<br/>format file, lint {files} on it"]
    PT -- "lint fails" --> FB["decision: block + lint output<br/>(feedback, edit already done)"]
    PT -- ok --> E
    FB --> E
    ST["Stop: harness-verify stop"] --> NG{"git repo?"}
    NG -- no --> PASS0([allow stop])
    NG -- yes --> SAME{"state id = baseline?"}
    SAME -- yes --> SK(["result skipped, allow"])
    SAME -- no --> HIDE["hide report → .pending"] --> LT{"lint then test<br/>over changed files"}
    LT -- pass --> OKR(["restore report<br/>result pass or skipped"])
    LT -- fail --> CAP{"attempts &lt; max?"}
    CAP -- yes --> BLK["attempts+1, delete .pending<br/>result fail, decision: block + tail 40"]
    BLK --> E
    CAP -- no --> GIVE(["restore report, result fail, allow stop"])
  end
  subgraph rev["reviewer"]
    RR["harness-verify run all --base ref<br/>(merge-base main, else master)"] --> RX{"exit"}
    RX -- "0 pass / 1 fail / 2 bad base" --> VD["report ends VERDICT: PASS|FAIL"]
  end
  CFG -.-> PT & LT & RR
  OKR & GIVE --> MAP{"harness ask maps"}
  VD --> MAP
  MAP -- "implementer.json status fail" --> X5([exit 5 + verify: FAIL line])
  MAP -- "VERDICT: FAIL" --> X5
  MAP -- "reviewer, no VERDICT last line" --> X3([exit 3])
  MAP -- otherwise --> X0([exit 0])
```

</details>

`harness ask implementer` first calls `harness-verify baseline` (state id = HEAD + hash of working-tree changes; the base is kept after a fail). The Stop hook hides the report while checking, so `harness` never sees an unverified one; at the attempt cap it keeps the report and `harness` exits 5.

## 6. Progress log and context reset

![Progress log and context reset](diagrams/06-progress-and-reset.svg)

<details><summary>Mermaid source</summary>

```mermaid
flowchart TD
  ASK["any harness ask ends<br/>(any exit, incl. signal)"] --> LOGF["log/YYYYmmdd-HHMMSS-agent.md<br/>instruction, brief task-*.md, report or screen"]
  LOGF --> ROT1{"progress.jsonl &gt; 1 MB?"}
  ROT1 -- yes --> GZ["roll to progress.jsonl.ts.gz"] --> JL
  ROT1 -- no --> JL["append jsonl: ts agent session instr exit verify<br/>dur head_before/after ctx_before/after status summary report_sha"]
  JL --> ROT2["rotate logs: keep newest 200, drop &gt; 14 days"]
  ROT2 --> MD["regenerate progress.md ≤ 60 lines<br/>goal, last 15 asks, newest open questions, workers + ctx"]
  LATE["leftover report at next ask"] --> LA["log/…-late.md + jsonl exit null, late true"] --> MD
  MD --> RES["SessionStart hook (startup|clear|compact)<br/>conductor only, adds progress.md as additionalContext"]
  RES --> COND["Conductor resumes"]
  TX[("~/.claude/projects/enc-cwd/session.jsonl<br/>last main-thread assistant usage")] --> CTX["ctx = input + cache_creation + cache_read"]
  CTX --> JL
  CTX --> RS{"reset before ask?<br/>live and not --keep"}
  RS -- "implementer: always<br/>analyst/reviewer: ctx &gt; 120000 or --fresh" --> LE{"last ask exit 0?<br/>(reviewer also 5) or --fresh"}
  LE -- no --> KEEP(["keep context"])
  LE -- yes --> CLR["/clear, poll for new session id + idle"]
  CLR -- timeout --> RSP["close pane + respawn"]
```

</details>

Every ask writes a log file and a jsonl line and rebuilds `progress.md`; logging failures only warn. The conductor's SessionStart hook feeds `progress.md` back after a restart, `/clear` or compaction. Knobs: `HARNESS_LOG_KEEP`, `HARNESS_LOG_DAYS`, `HARNESS_JSONL_MAX`, `HARNESS_CTX_RESET`.

## 7. Install layout (`install.sh`)

![Install layout (`install.sh`)](diagrams/07-install-layout.svg)

<details><summary>Mermaid source</summary>

```mermaid
flowchart LR
  subgraph repo["repo"]
    RA["claude/agents/*.md"]
    RB["bin/harness, bin/harness-verify"]
    RG["claude/hooks/conductor-gate.sh"]
    RR["claude/hooks/conductor-resume.sh"]
  end
  HI["herdr integration install claude<br/>(runs first)"]
  A2["~/.claude/agents/*.md<br/>symlinks, foreign files backed up"]
  B2["~/.local/bin/harness, harness-verify<br/>symlinks"]
  ST["~/.claude/settings.json (backup .bak.ts)<br/>agent = conductor<br/>promptCacheTtl, subagentPromptCacheTtl = 1h<br/>env BASH_DEFAULT/MAX_TIMEOUT_MS<br/>hooks.PreToolUse: one gate entry<br/>hooks.SessionStart: one resume entry"]
  GI["~/.config/git/ignore<br/>+ .harness/"]
  RA -- "ln -sfn" --> A2
  RB -- "ln -sfn" --> B2
  RG -- "jq merge (path)" --> ST
  RR -- "jq merge (path)" --> ST
  HI --> ST
  repo -. "./install.sh" .-> GI
```

</details>

Idempotent: re-running replaces the gate/resume entries instead of adding duplicates. Hooks are referenced by absolute repo path, not copied. The gate matcher is `Edit|Write|NotebookEdit|Read|Grep|Glob|Bash|Agent|Workflow|Monitor|mcp__filesystem__.*`.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Report returned, verification passed (or not applicable) |
| 1 | Setup error (e.g. implementer asked but `harness-verify` not on PATH) |
| 2 | Worker blocked, waiting for input; screen returned |
| 3 | No report produced (or reviewer report without a final `VERDICT:` line) |
| 4 | Worker still working / not ready, or prompt failed; nothing usable returned |
| 5 | Report returned but verification failed or was interrupted (`VERDICT: FAIL`, `verify: FAIL`/`INTERRUPTED`) |
| 129 / 130 / 143 | Wrapper received SIGHUP / SIGINT / SIGTERM; log still written |
