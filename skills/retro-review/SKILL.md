---
name: retro-review
description: "Human gate for the learning loop — reviews draft memos in memory/_draft/ produced by /retro, lets the user approve/reject/edit each, and moves approved memos into memory/ with MEMORY.md index updated. Use when: startup banner reports 'N retro drafts pending', after /retro runs, weekly on Monday."
model: inherit
allowed-tools: Read, Write, Edit, Bash, Glob
---

# /retro-review — Approve Retro Drafts

The human gate of the learning loop. `/retro` collects signals and
drafts memos; `/retro-review` decides which drafts actually change
Claude's behavior going forward.

## When to Use

- Startup banner shows `N retro drafts pending`
- After running `/retro`
- Weekly (Monday, ~5 min)

## Process

### 1. List pending drafts

```bash
ls -1 memory/_draft/*.md 2>/dev/null
```

If the directory is empty or absent, announce:
```
No retro drafts pending. Nothing to review.
```
and exit.

### 2. For each draft — present to the user

Show, in order:
1. Filename (relative path)
2. Full content (frontmatter + body)
3. Source retro report (from `source_retro` field)
4. Signal count (from `signal_count` field)

Then ask: **Approve / Reject / Edit / Defer?**

### 3. Handle the decision

| Decision | Action |
|----------|--------|
| **Approve** | Move file from `memory/_draft/` to `memory/feedback_{slug}.md`. Strip `status: draft` from frontmatter. Update `memory/MEMORY.md` index with a one-line entry. |
| **Reject** | Delete the draft file. Log decision. |
| **Edit** | Display content; accept the user's edits; then re-ask Approve/Reject. |
| **Defer** | Leave in `memory/_draft/` for next week. Log decision with reason. |

### 4. Approve — concrete steps

```bash
SLUG={slug from filename}
mv "memory/_draft/feedback_${SLUG}.md" "memory/feedback_${SLUG}.md"
```

Edit the promoted file:
- Remove `status: draft` from frontmatter
- Keep `source_retro` and `signal_count` as provenance

Update `memory/MEMORY.md`:
- Append a single line under the appropriate section:
  ```
  - [Title](feedback_{slug}.md) — one-line hook
  ```
- Keep MEMORY.md ≤ 200 lines. If near limit, warn the user and suggest consolidation.

### 5. Log decisions

Append to `logs/retro-decisions.jsonl` (create if missing):

```json
{"time":"...","draft":"feedback_xxx","decision":"approved","session":"..."}
{"time":"...","draft":"feedback_yyy","decision":"rejected","reason":"too specific","session":"..."}
```

This log itself is retro-input — patterns of rejection teach the system
that /retro is drafting too aggressively.

### 6. Check for duplicates

Before approving, scan existing `memory/*.md` for similar content. If
found:
```
This draft overlaps with memory/feedback_existing.md.
Options: [Merge] [Replace] [Approve as separate] [Cancel]
```

### 7. Summary

At the end:
```
Reviewed N drafts:
  Approved: A (→ memory/)
  Rejected: R
  Edited: E
  Deferred: D

Decisions logged: logs/retro-decisions.jsonl
```

## Rules

- **Never auto-approve.** Every draft needs an explicit human decision.
- **Never delete `memory/` entries.** This skill only promotes from `_draft/`.
- **Never rewrite draft content silently.** If editing, show the diff before applying.
- **If unsure on a draft, defer it.** Deferred drafts stay in `_draft/` and re-appear next week — that's fine.
- **Respect MEMORY.md size.** If the index would exceed 200 lines after adding, prompt the user to consolidate or archive.
- **Rejection is as valuable as approval.** A lot of rejections this week = /retro's pattern detection is too sensitive. Surface that in the final summary.

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Batch-approve all, they look fine" | One at a time. The whole point is deliberate review. |
| "I'll edit the draft later" | Edit now or reject. Draft rot is worse than rejection. |
| "Approving this is probably safe" | If you have to say "probably," defer. |
| "I'll skip /retro-review this week" | Skipping for 2+ weeks means /retro's work was wasted. Either do it or disable the loop. |
