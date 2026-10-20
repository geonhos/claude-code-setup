#!/bin/bash
# UserPromptSubmit hook for the conductor. Appends one `prompt` line to
# .harness/routing.jsonl through `harness route-log`, so prompts can later be
# joined with the `delegate` lines that `harness ask` writes (routing labels
# for a decision model). Silent for workers (HARNESS_ROLE=worker), without jq
# or harness on PATH, outside a harness project (no .harness/ in the prompt's
# cwd), and on any error. Never writes to stdout and always exits 0: this hook
# must not block or alter the prompt.
# Spec: docs/superpowers/specs/2026-10-20-skill-routing-design.md §6.4
[ "${HARNESS_ROLE:-}" = worker ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v harness >/dev/null 2>&1 || exit 0
[ -t 0 ] && exit 0
input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

dir=$(printf '%s' "$input" | jq -r 'if type == "object" then (.cwd // empty) else empty end' 2>/dev/null)
[ -n "$dir" ] && [ -d "$dir/.harness" ] || exit 0
cd "$dir" 2>/dev/null || exit 0

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# skill: the leading /analyze, /implement or /review token, else null
line=$(printf '%s' "$input" | jq -c --arg ts "$ts" '
  def nz: if . == "" then null else . end;
  ((.prompt // "") | tostring) as $p
  | {ts: $ts, event: "prompt",
     session: (((.session_id // "") | tostring) | nz),
     prompt_id: (((.prompt_id // "") | tostring) | nz),
     agent: (((.agent_type // "") | tostring) | nz),
     prompt: ($p | .[:4000]),
     skill: (if ($p | test("^/(analyze|implement|review)(\\s|$)"))
             then ($p | capture("^(?<s>/[a-z]+)") | .s) else null end)}' 2>/dev/null) || exit 0
[ -n "$line" ] || exit 0

harness route-log "$line" >/dev/null 2>&1
exit 0
