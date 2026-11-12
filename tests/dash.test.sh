#!/bin/bash
# Viewer dashboard render (lib/harness-dash.sh): golden frames from a fixture stream + brief at a
# fixed size. Run: /bin/bash tests/dash.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
LIB="$HERE/../lib/harness-dash.sh"

# digits_only comes from bin/harness; hl_alive is faked (the run is live unless FINAL=1)
DO_SRC=$(sed -n '/^digits_only() {/,/^}/p' "$HARNESS")
. "$LIB" 2>/dev/null || { echo "FAIL [load lib/harness-dash.sh]"; fail=$((fail + 1)); }
eval "$DO_SRC"
hl_alive() { return 0; }

setup
ASK_DIR=.harness/asks
mkdir -p .harness/log .harness/verify .harness/reports
NOW=$(date +%s)
printf 'ask-1 %s\n' $((NOW - 724)) > $ASK_DIR/implementer.current
cp $ASK_DIR/implementer.current $ASK_DIR/analyst.current
printf 'Read .harness/task-implementer.md and do it.\n' > $ASK_DIR/implementer.prompt
printf 'plain question about code\nsecond line\n' > $ASK_DIR/analyst.prompt
cat > .harness/task-implementer.md <<'EOB'
# Implement the thing

## Goal
words

## Steps
1. Branch from main
2. Tests first
3. Implement
- not numbered

## Done criteria
x
EOB
RAW=.harness/log/x-implementer.jsonl
cat > $RAW <<'EOS'
not json at all
{"type":"system","subtype":"init","model":"sonnet","session_id":"s1"}
{"type":"assistant","message":{"content":[{"type":"text","text":"Starting work\nsecond\nthird\nfourth"}],"usage":{"input_tokens":100,"cache_read_input_tokens":80000,"cache_creation_input_tokens":2000}}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo hi","description":"Say hi"}}],"usage":{"input_tokens":1,"cache_read_input_tokens":82000,"cache_creation_input_tokens":0}}}
EOS
frame() { OUT=$(HARNESS_DASH_LINES=${1:-30} HARNESS_DASH_COLS=${2:-70} PATH="$HERE/../bin:$PATH" hl_dash_frame "${3:-implementer}" "${4:-$RAW}"); }
has() { grep -qF -- "$1" <<<"$OUT"; }

# full frame, implementer, text Now, no verify yet, no baseline
frame
EXPECT_HEAD='implementer  ask-1  ⏱ 12m04s  turns 2  ctx 82k  sonnet'
check "header" [ "$(sed -n 1p <<<"$OUT")" = "$EXPECT_HEAD" ]
check "brief title" [ "$(sed -n 2p <<<"$OUT")" = "── Brief ── Implement the thing" ]
GOLD_MID=$(cat <<'EOG'
── Now ──
  Starting work
  second
  third
── Steps ──
  1. Branch from main
  2. Tests first
  3. Implement
── Verify ── not started
── Diff ──
  (no baseline)
── Recent ──
  ▶ sonnet · session s1 · perm ? · 
  Starting work
  second
  third
  fourth
  → Bash echo hi
EOG
)
check "golden body (Now text 3 lines, Steps from ## Steps, Verify, Diff, Recent)" [ "$(sed -n '3,$p' <<<"$OUT")" = "$GOLD_MID" ]

# Now from tool_use when no assistant text; Bash description preferred, then command
grep -v '"type":"text"' $RAW > .harness/log/tool.jsonl
frame 30 70 implementer .harness/log/tool.jsonl
check "Now from tool_use (description preferred)" has "  → Bash Say hi"
sed 's/,"description":"Say hi"//' .harness/log/tool.jsonl > .harness/log/tool2.jsonl
frame 30 70 implementer .harness/log/tool2.jsonl
check "Now from tool_use (command fallback)" has "  → Bash echo hi"

# heading fallback (no ## Steps)
sed -e '/^## Steps/,/^- not numbered/d' .harness/task-implementer.md > t.md && mv t.md .harness/task-implementer.md
frame
check "heading fallback" bash -c 'grep -qF "  1. Goal" <<<"$1" && grep -qF "  2. Done criteria" <<<"$1"' _ "$OUT"

# brief = prompt text when the prompt does not name the task file; no Diff for non-implementer
cp $RAW .harness/log/x-analyst.jsonl
frame 30 70 analyst .harness/log/x-analyst.jsonl
check "analyst: prompt title" has "── Brief ── plain question about code"
check "analyst: no Steps section" bash -c '! grep -qF "── Steps" <<<"$1"' _ "$OUT"
check "analyst: no Diff section" bash -c '! grep -qF "── Diff" <<<"$1"' _ "$OUT"

# verify states
printf '%s\n' '{"type":"system","subtype":"hook_started","hook_event":"Stop"}' >> $RAW
frame; check "verify running" has "── Verify ── verifying…"
printf '%s\n' '{"type":"system","subtype":"hook_response","hook_event":"Stop","exit_code":0,"stdout":""}' >> $RAW
frame; check "verify pass" has "── Verify ── pass"
printf '%s\n' '{"type":"system","subtype":"hook_started","hook_event":"Stop"}' '{"type":"system","subtype":"hook_response","hook_event":"Stop","exit_code":0,"stdout":"{\"decision\":\"block\",\"reason\":\"lint failed\"}"}' >> $RAW
echo '{"status":"fail","step":"tests","tail":"x"}' > .harness/verify/implementer.json
frame; check "verify fail (step)" has "── Verify ── fail (tests)"

# Diff against the base sha (implementer)
git init -q . && git add -A . 2>/dev/null; git -c user.email=a@b -c user.name=t commit -qm base --allow-empty
SHA=$(git rev-parse HEAD)
printf '%s\nxx\n' "$SHA" > .harness/verify/implementer.base
echo hello > newfile.txt; git add newfile.txt
frame; check "diff stat shown" bash -c 'grep -qF "── Diff" <<<"$1" && grep -qF "newfile.txt" <<<"$1"' _ "$OUT"

# truncation: width cuts by character, height never exceeded and Recent shrinks first
frame 30 20
check "width: no line over 20 chars" bash -c '[ "$(jq -R "length" <<<"$1" | sort -n | tail -n 1)" -le 20 ]' _ "$OUT"
frame 12 70
check "height 12: at most 12 lines" [ "$(wc -l <<<"$OUT")" -le 12 ]
check "height 12: header + Now + Steps + Verify kept" bash -c 'grep -qF "implementer" <<<"$1" && grep -qF "── Now" <<<"$1" && grep -qF "── Steps" <<<"$1" && grep -qF "── Verify" <<<"$1"' _ "$OUT"
check "height 12: Recent dropped before them" bash -c '! grep -qF "── Recent" <<<"$1"' _ "$OUT"
frame 3 70
check "height 3: header + brief + at most 1 more" [ "$(wc -l <<<"$OUT")" -le 3 ]
check "height 3: header first" [ "$(sed -n 1p <<<"$OUT" | cut -c1-11)" = implementer ]

# multibyte brief title is cut by character, not byte
printf '# 한글제목한글제목한글제목\n## Steps\n1. a\n' > .harness/task-implementer.md
frame 30 20
check "multibyte: title cut to 20 chars" [ "$(sed -n 2p <<<"$OUT" | jq -R 'length')" = 20 ]

# final frame: result line + report head
echo '{"ask_id":"ask-1","rc":0,"result":"success","num_turns":38,"cost_usd":1.5,"duration_ms":125000}' > $ASK_DIR/implementer.exit.json
printf '# implementer report\nstatus: done\n' > .harness/reports/implementer.md
hl_alive() { return 1; }
frame
check "final: result line" has "── Result ── ■ success · rc 0 · 38 turns · 125s · \$1.5"
check "final: report head" bash -c 'grep -qF "── Report" <<<"$1" && grep -qF "  # implementer report" <<<"$1"' _ "$OUT"
check "final: duration from exit.json" has "⏱ 2m05s"
check "final: no Now" bash -c '! grep -qF "── Now" <<<"$1"' _ "$OUT"

echo "dash: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
