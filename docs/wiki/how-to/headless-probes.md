---
type: how-to
status: active
updated: 2026-11-22
sources: [ask 1795053727-6527-491, ask 1795069451-73146-26789, "#164", "#182", .harness/perm-pin-experiment-detail.md, .harness/169-experiment/gen.sh]
verified_by: human (read both scripts and logs)
---
# Probing Claude Code headlessly: permissions and clean generation calls

**Permission probes.** Do not use `--agent analyst` or any other harness role: its prompt makes it refuse writes outside `.harness/` by itself, which hides what the permission layer does (first run of perm-pin-experiment-detail.md). Define a neutral agent with `--agents '{"p":{...}}' --agent p` whose body holds only the rule under test. The deny-bypass runs used implementer.md with one line swapped.

**Clean generation call.** From a fresh `mktemp -d` cwd (no AGENTS.md, no project settings, no memory):
`claude -p --tools "" --setting-sources "" --no-session-persistence --disable-slash-commands --output-format json < prompt`. Read the cost from the JSON `total_cost_usd`.

**Cost.** On fable a 1-6k-token Korean output cost about 0.14-0.38 USD (24 calls, 6.10 USD in total, 169-experiment gen.sh). The permission-probe runs on haiku cost 0.14 USD in total. Set a budget before running a matrix.

**Timeout.** macOS has no `timeout`; use `perl -e 'alarm N; exec @ARGV' claude ...`.

**Transcripts.** Without `--no-session-persistence` a probe writes a transcript under the real `~/.claude/projects`.
