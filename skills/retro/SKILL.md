---
name: retro
description: "Weekly harness retrospective — analyzes logs/feedback-signals.jsonl and logs/agent-progress.jsonl from the past N days, produces a retro report, and drafts feedback memos in memory/_draft/ for human approval via /retro-review. Use when: weekly review, investigating recurring failures, before changing skills/hooks."
model: sonnet
allowed-tools: Read, Write, Bash, Grep, Glob
argument-hint: "[days=7]"
---

# /retro — Weekly Harness Retrospective

Turn raw activity logs into actionable insights. Draft memos go to
`memory/_draft/` for human approval in `/retro-review`; nothing is
auto-applied to the harness.

## When to Use

- Weekly (Monday morning is a natural cadence; cron via `/schedule` works too)
- When startup banner reports "N retro drafts pending"
- Investigating why /ship keeps failing at the same stage
- Before changing a skill or hook (so you have baseline signals to compare against after)

## Inputs

| File | Purpose |
|------|---------|
| `logs/feedback-signals.jsonl` | Implicit bad signals (frustration, post-ship rework, git undo) |
| `logs/agent-progress.jsonl` | Per-agent activity, duration, tool counts |
| `logs/ship-outcomes.jsonl` | Per-ship pipeline outcomes (optional, present if /ship writes it) |
| `harness/progress.md` | Latest /ship state |

Missing files are fine — just note them in the report.

## Process

### 1. Select the window

Default: last 7 days. Argument overrides (e.g. `/retro 14`).

```bash
DAYS="${1:-7}"
SINCE=$(date -u -v-${DAYS}d +"%Y-%m-%d" 2>/dev/null || date -u -d "${DAYS} days ago" +"%Y-%m-%d")
```

### 2. Count & categorize signals

Read `logs/feedback-signals.jsonl`. Filter entries whose `time` ≥ `SINCE`.
Bucket by `signal`:
- `frustration_keyword` — user pushed back verbally
- `post_ship_rework` — user edited a file shortly after /ship
- `strong_bad_git_undo` — git revert / reset --hard on recent commit

Per bucket: count, unique sessions, top 3 detail snippets.

### 3. Agent health metrics

Read `logs/agent-progress.jsonl`. For each agent:
- Total runs in window
- Median & max duration
- Avg tool count
- Outlier runs (duration > 2× median, or tool_count > 2× avg)

Flag an agent if its retry rate (same agent spawned >1× in one session) is high.

### 4. Pattern detection

Look for repetition, not one-offs. A signal counts as a pattern only if it
has **≥3 occurrences across ≥2 sessions** in the window.

Examples of patterns worth drafting memos for:
- "Rework keeps hitting `src/auth/*.ts`" → candidate best-practice rule
- "code-reviewer never flags N+1 on Spring code" → update to agent instructions
- "frustration keyword right after plan-architect output" → plan quality issue

### 5. Write the retro report

Path: `logs/retro-YYYY-WW.md` (where WW is ISO week).

```markdown
# Retro Week WW (YYYY-MM-DD ~ YYYY-MM-DD)

## Summary
- Bad signals: N total (frustration: A, rework: B, git-undo: C)
- Ships detected: N
- Agent runs: N

## Top patterns (≥3 occurrences)
1. {pattern} — {count} / {sessions}
2. ...

## Agent health
| Agent | Runs | Median dur | Outliers |
|-------|------|------------|----------|

## Recommended drafts
- `memory/_draft/feedback_{slug}.md`
- ...

## Window
DAYS=N, SINCE=YYYY-MM-DD, generated YYYY-MM-DDTHH:MM:SSZ
```

### 6. Produce draft memos

For each detected pattern, create `memory/_draft/feedback_{slug}.md`:

```markdown
---
name: {short name}
description: {one line — what this would teach Claude}
type: feedback
status: draft
source_retro: YYYY-WW
signal_count: N
detected_at: YYYY-MM-DDTHH:MM:SSZ
---

{The rule being proposed.}

**Why:** Observed {N} times across {M} sessions in week WW.
Example signals: {1-2 concrete snippets}.

**How to apply:** {When this guidance should trigger in future work.}

---
*Draft — requires /retro-review approval before activation.*
```

### 7. Announce

Print a compact summary to the user:

```
Retro week WW complete.
  Report: logs/retro-YYYY-WW.md
  Drafts: N in memory/_draft/
Run /retro-review to approve/reject.
```

## Rules

- **Never auto-approve** drafts. Drafts are inert until `/retro-review`.
- **Never modify** existing `memory/` entries.
- **Pattern threshold is non-negotiable**: require ≥3 occurrences + ≥2 sessions before drafting. Single-session spikes are noise.
- **Write the report even on a quiet week.** "Nothing to learn this week" is itself useful signal — it means the harness is stable.
- **Respect `HARNESS_AUTO_FEEDBACK=0`.** If signal capture is off, the retro still runs but must prefix the report with a warning that the window has no fresh signals.
- **Archive policy:** After a retro completes, the old `logs/feedback-signals.jsonl` entries within the window stay — they become the next retro's "ignore before SINCE" boundary. Don't truncate.

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "I'll approve drafts inline to save a step" | That's exactly the human gate you're bypassing. Stop. |
| "One signal is enough, it's obviously a pattern" | One signal is a datum. Wait for three. |
| "The report is boring this week, skip it" | Boring weeks are proof the system is working. Write it. |
