#!/bin/bash
# UserPromptSubmit hook for the conductor. Appends one `prompt` line to
# .harness/routing.jsonl through `harness route-log`, so prompts can later be
# joined with the `delegate` lines that `harness ask` writes (routing labels
# for a decision model). Silent for workers (HARNESS_ROLE=worker), without jq
# or harness on PATH, outside a harness checkout (no .harness/asks/ between the
# prompt's cwd and the repo top; decision 0010), and on any error. Logs under the
# checkout root, whatever subdir the session runs in. Never writes to stdout and always exits 0: this hook
# must not block or alter the prompt.
# Spec: docs/superpowers/specs/2026-10-20-skill-routing-design.md §6.4
[ "${HARNESS_ROLE:-}" = worker ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v harness >/dev/null 2>&1 || exit 0
[ -t 0 ] && exit 0

# harness_root DIR -> prints the harness checkout root and returns 0, or returns 1.
# DIR is resolved physically (pwd -P) first, like enter_root.
# The root is the nearest dir at or above DIR with .harness/asks/, searched up to
# the dir holding .git (file or dir) inclusive; outside git only DIR counts. Same
# rule as enter_root in bin/harness-verify. This body is copied byte-for-byte into
# conductor-gate, -route and -resume (tests/gate.test.sh checks it).
harness_root() {
  local start d hit=""
  start=$(cd "${1:-/}" 2>/dev/null && pwd -P) || return 1
  d=$start
  while :; do
    if [ -z "$hit" ] && [ -d "$d/.harness/asks" ]; then hit=$d; fi
    if [ -e "$d/.git" ]; then
      [ -n "$hit" ] || return 1
      printf '%s' "$hit"
      return 0
    fi
    [ "$d" = / ] && break
    d=${d%/*}
    [ -n "$d" ] || d=/
  done
  [ -d "$start/.harness/asks" ] || return 1
  printf '%s' "$start"
}

input=$(cat 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

dir=$(printf '%s' "$input" | jq -r 'if type == "object" then (.cwd // empty) else empty end' 2>/dev/null)
[ -n "$dir" ] && [ -d "$dir" ] || exit 0
root=$(harness_root "$dir") || exit 0
cd "$root" 2>/dev/null || exit 0

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
