# PoC: does a native subagent `model:` override the parent model?

Date: 2026-10-21. Premise under test: `claude/hooks/conductor-gate.sh` said "Native subagents inherit the Fable model".

## Setup
Scratch git repo outside the repo with `note.txt` and `.claude/agents/poc-reader.md`
(`name: poc-reader`, `tools: Read`, `model: sonnet` for run 1, `model: inherit` for run 2).
Parent model: `opus` (the conductor's `~/.claude/settings.json` model).

```
HARNESS_ROLE=worker claude --agent solo \
  -p 'Use the poc-reader subagent (Agent tool) to summarize note.txt. Reply with its answer only.' \
  --output-format json --model opus
```

## Raw `modelUsage` (trimmed)
Run 1 — subagent `model: sonnet` (num_turns 2, total_cost_usd 0.1755):
| model | in | out | cache read | cache create | cost USD |
|---|---|---|---|---|---|
| claude-opus-5-5 (parent) | 4 | 230 | 38541 | 17566 | 0.1529 |
| claude-sonnet-5-5 (subagent) | 4 | 243 | 4051 | 4952 | 0.0227 |

Run 2 — control, subagent `model: inherit` (num_turns 2, total_cost_usd 0.1823):
| model | in | out | cache read | cache create | cost USD |
|---|---|---|---|---|---|
| claude-opus-5-5 (only) | 8 | 466 | 44646 | 20499 | 0.1823 |

## Conclusion
Premise FALSE. `modelUsage` splits per model: with `model: sonnet` the subagent was billed
to Sonnet while the parent stayed on Opus; with `inherit` everything was billed to Opus.
Frontmatter `model:` overrides the parent, as the docs say.

## Implications
The gate message was factually wrong, so it now says native subagents are disabled for the
conductor and delegation goes through the skills (visibility in herdr panes, logging). The deny
is kept. The herdr layer cannot be justified by "subagents inherit the parent model"; its value
is visibility, per-pane logs and isolated worker sessions. No redesign here.
