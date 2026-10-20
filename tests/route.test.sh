#!/bin/bash
# Tests for `harness route-log` and claude/hooks/conductor-route.sh.
# Run: /bin/bash tests/route.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
HARNESS="$REPO/bin/harness"
HOOK="$REPO/claude/hooks/conductor-route.sh"
pass=0
fail=0
OUT=""
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT" >&2; fi; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
BIN="$ROOT/bin"; mkdir -p "$BIN"; ln -s "$HARNESS" "$BIN/harness"
P="$ROOT/proj"; mkdir -p "$P/.harness"
RJ="$P/.harness/routing.jsonl"
nlines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
last() { tail -n 1 "$RJ" 2>/dev/null | jq -r "$1"; }

# rl ARGS... -> run `harness route-log ARGS` in $P without herdr on PATH; sets OUT, RC
rl() {
  OUT=$(cd "$P" && env -u HERDR_ENV PATH="$BIN:$PATH" /bin/bash "$HARNESS" route-log "$@" 2>&1); RC=$?
}

# --- harness route-log ---------------------------------------------------------
rl '{"ts":"2026-10-20T00:00:00Z","event":"prompt","session":"s1","prompt":"hi","skill":null}'
check "route-log: rc 0" [ "$RC" -eq 0 ]
check "route-log: silent" [ -z "$OUT" ]
check "route-log: one line" [ "$(nlines "$RJ")" -eq 1 ]
check "route-log: event" [ "$(last .event)" = prompt ]
check "route-log: session" [ "$(last .session)" = s1 ]
check "route-log: valid json line" jq -e . "$RJ" >/dev/null

rl 'not json'
check "route-log: garbage rc 0" [ "$RC" -eq 0 ]
check "route-log: garbage warns" grep -q 'route-log' <<<"$OUT"
check "route-log: garbage not appended" [ "$(nlines "$RJ")" -eq 1 ]

rl '[1,2]'
check "route-log: non-object not appended" [ "$(nlines "$RJ")" -eq 1 ]

rl '{"a":1} {"b":2}'
check "route-log: two objects refused" [ "$(nlines "$RJ")" -eq 1 ]
rl '{"c":1} junk'
check "route-log: object plus junk refused" [ "$(nlines "$RJ")" -eq 1 ]

rl ''
check "route-log: empty rc 0" [ "$RC" -eq 0 ]
check "route-log: empty not appended" [ "$(nlines "$RJ")" -eq 1 ]
check "route-log: empty warns" grep -q 'route-log' <<<"$OUT"

OUT=$(cd "$P" && HARNESS_ROUTE_LOG=0 env -u HERDR_ENV PATH="$BIN:$PATH" /bin/bash "$HARNESS" route-log '{"event":"x"}' 2>&1); RC=$?
check "route-log: disabled rc 0" [ "$RC" -eq 0 ]
check "route-log: disabled not appended" [ "$(nlines "$RJ")" -eq 1 ]

# rotation: file over HARNESS_JSONL_MAX is gzipped away before the append
head -c 200 /dev/zero | tr '\0' 'x' > "$RJ"; printf '\n' >> "$RJ"
OUT=$(cd "$P" && HARNESS_JSONL_MAX=100 env -u HERDR_ENV PATH="$BIN:$PATH" /bin/bash "$HARNESS" route-log '{"event":"after"}' 2>&1); RC=$?
check "route-log: rotate rc 0" [ "$RC" -eq 0 ]
check "route-log: rotated gz exists" ls "$P"/.harness/routing.jsonl.*.gz >/dev/null 2>&1
check "route-log: fresh file has one line" [ "$(nlines "$RJ")" -eq 1 ]
check "route-log: fresh file has new event" [ "$(last .event)" = after ]
check "route-log: rotated content kept" [ "$(gzip -dc "$P"/.harness/routing.jsonl.*.gz | tr -cd x | wc -c | tr -d ' ')" -eq 200 ]
rm -f "$P"/.harness/routing.jsonl.*.gz

# no .harness/ in cwd: created, not an error (harness ask relies on this)
E="$ROOT/empty"; mkdir -p "$E"
OUT=$(cd "$E" && env -u HERDR_ENV PATH="$BIN:$PATH" /bin/bash "$HARNESS" route-log '{"event":"mk"}' 2>&1); RC=$?
check "route-log: creates .harness" [ -f "$E/.harness/routing.jsonl" ]

# --- conductor-route.sh (UserPromptSubmit) ---------------------------------------
rm -f "$RJ"
# payload CWD PROMPT [SESSION]
payload() {
  jq -n -c --arg c "$1" --arg p "$2" --arg s "${3:-s1}" \
    '{session_id:$s, transcript_path:"/t.jsonl", cwd:$c, permission_mode:"default", hook_event_name:"UserPromptSubmit", prompt:$p, prompt_id:"p-1"}'
}
# hook PAYLOAD [ENV=VAL...] -> OUT (stdout+stderr), RC; HARNESS_ROLE unset, cwd elsewhere on purpose
hook() {
  local pl=$1; shift
  OUT=$(cd "$ROOT" && printf '%s' "$pl" | env -u HARNESS_ROLE "$@" PATH="$BIN:$PATH" /bin/bash "$HOOK" 2>&1); RC=$?
}

check "hook: executable" [ -x "$HOOK" ]

hook "$(payload "$P" 'what does install.sh do?')"
check "hook: rc 0" [ "$RC" -eq 0 ]
check "hook: no output" [ -z "$OUT" ]
check "hook: one line" [ "$(nlines "$RJ")" -eq 1 ]
check "hook: event prompt" [ "$(last .event)" = prompt ]
check "hook: session" [ "$(last .session)" = s1 ]
check "hook: prompt_id" [ "$(last .prompt_id)" = p-1 ]
check "hook: prompt text" [ "$(last .prompt)" = 'what does install.sh do?' ]
check "hook: skill null" [ "$(last .skill)" = null ]
check "hook: ts shape" [ "$(last '.ts|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")')" = true ]

hook "$(payload "$P" '/implement add a flag')"
check "hook: skill implement" [ "$(last .skill)" = /implement ]
hook "$(payload "$P" '/review')"
check "hook: bare skill" [ "$(last .skill)" = /review ]
hook "$(payload "$P" '/implementation notes')"
check "hook: prefix only is not a skill" [ "$(last .skill)" = null ]
hook "$(payload "$P" '/analyze
multi line')"
check "hook: skill before newline" [ "$(last .skill)" = /analyze ]

long=$(head -c 4001 /dev/zero | tr '\0' 'y')
hook "$(payload "$P" "$long")"
check "hook: prompt capped at 4000" [ "$(last '.prompt|length')" -eq 4000 ]

n=$(nlines "$RJ")
hook "$(payload "$P" 'x')" HARNESS_ROLE=worker
check "hook: worker rc 0" [ "$RC" -eq 0 ]
check "hook: worker silent" [ -z "$OUT" ]
check "hook: worker writes nothing" [ "$(nlines "$RJ")" -eq "$n" ]

E2="$ROOT/noharness"; mkdir -p "$E2"
hook "$(payload "$E2" 'x')"
check "hook: no .harness dir -> rc 0" [ "$RC" -eq 0 ]
check "hook: no .harness dir -> nothing" [ ! -e "$E2/.harness/routing.jsonl" ]

hook 'not json at all'
check "hook: garbage rc 0" [ "$RC" -eq 0 ]
check "hook: garbage silent" [ -z "$OUT" ]
check "hook: garbage writes nothing" [ "$(nlines "$RJ")" -eq "$n" ]

OUT=$(cd "$ROOT" && printf '%s' "$(payload "$P" 'x')" | env -u HARNESS_ROLE PATH=/usr/bin:/bin /bin/bash "$HOOK" 2>&1); RC=$?
check "hook: no jq/harness on PATH -> rc 0" [ "$RC" -eq 0 ]
check "hook: no jq/harness -> silent" [ -z "$OUT" ]

OUT=$(cd "$ROOT" && printf '%s' "$(payload "$P" 'x')" | env -u HARNESS_ROLE PATH="/usr/bin:/bin:$(dirname "$(command -v jq)")" /bin/bash "$HOOK" 2>&1); RC=$?
check "hook: harness missing (jq present) -> rc 0" [ "$RC" -eq 0 ]
check "hook: harness missing -> nothing" [ "$(nlines "$RJ")" -eq "$n" ]

hook "$(payload "$P" 'x')" HARNESS_ROUTE_LOG=0
check "hook: HARNESS_ROUTE_LOG=0 writes nothing" [ "$(nlines "$RJ")" -eq "$n" ]

OUT=$(cd "$ROOT" && env -u HARNESS_ROLE PATH="$BIN:$PATH" /bin/bash "$HOOK" </dev/null 2>&1); RC=$?
check "hook: empty stdin rc 0" [ "$RC" -eq 0 ]
check "hook: empty stdin writes nothing" [ "$(nlines "$RJ")" -eq "$n" ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
