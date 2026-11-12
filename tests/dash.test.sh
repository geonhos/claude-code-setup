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
{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"Starting work\nsecond\nthird\nfourth"}],"usage":{"input_tokens":100,"cache_read_input_tokens":80000,"cache_creation_input_tokens":2000}}}
{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","name":"Bash","input":{"command":"echo hi","description":"Say hi"}}],"usage":{"input_tokens":1,"cache_read_input_tokens":82000,"cache_creation_input_tokens":0}}}
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
  → Bash Say hi
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
check "golden body (Now = later tool_use, Steps from ## Steps, Verify, Diff, Recent)" [ "$(sed -n '3,$p' <<<"$OUT")" = "$GOLD_MID" ]

# Now from tool_use when no assistant text; Bash description preferred, then command
grep -v '"type":"text"' $RAW > .harness/log/tool.jsonl
frame 30 70 implementer .harness/log/tool.jsonl
check "Now from tool_use (description preferred)" has "  → Bash Say hi"
sed 's/,"description":"Say hi"//' .harness/log/tool.jsonl > .harness/log/tool2.jsonl
frame 30 70 implementer .harness/log/tool2.jsonl
check "Now from tool_use (command fallback)" has "  → Bash echo hi"

# Now = whichever is later in the stream (text after tool_use, and tool_use after text)
{ grep -v '"type":"text"' $RAW | sed -n 1,2p; echo '{"type":"assistant","message":{"id":"m3","content":[{"type":"text","text":"Final words"}]}}'; } > .harness/log/order1.jsonl
frame 30 70 implementer .harness/log/order1.jsonl
printf '%s\n' '{"type":"assistant","message":{"id":"m4","content":[{"type":"text","text":"l1\nl2\nl3\nl4"}]}}' >> .harness/log/order1.jsonl
frame 30 70 implementer .harness/log/order1.jsonl
check "Now: text later than tool_use wins, 3 lines max" bash -c 'N=$(sed -n "/── Now/,/── Steps/p" <<<"$1"); grep -qF "  l3" <<<"$N" && ! grep -qF "  l4" <<<"$N" && ! grep -qF "→ Bash" <<<"$N"' _ "$OUT"
frame 30 70 implementer $RAW
check "Now: tool_use later than text wins" bash -c 'grep -qF "  → Bash Say hi" <<<"$1" && ! sed -n "/── Now/,/── Steps/p" <<<"$1" | grep -qF "Starting work"' _ "$OUT"

# turns count unique message ids: one message streamed as several content-block events is one turn
cat > .harness/log/blocks.jsonl <<'EOS'
{"type":"system","subtype":"init","model":"sonnet","session_id":"s1"}
{"type":"assistant","message":{"id":"mA","content":[{"type":"text","text":"a"}]}}
{"type":"assistant","message":{"id":"mA","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x"}}]}}
{"type":"assistant","message":{"id":"mA","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/y"}}]}}
{"type":"assistant","message":{"id":"mB","content":[{"type":"text","text":"b"}]}}
EOS
frame 30 70 implementer .harness/log/blocks.jsonl
check "turns: unique message ids (4 events, 2 messages)" bash -c 'grep -qF "turns 2  " <<<"$1" && grep -qF "sonnet" <<<"$1"' _ "$OUT"

# long stream: init line and turns survive more than 2000 events
{ sed -n 1,2p .harness/log/blocks.jsonl | sed -n 1p; i=0; while [ $i -lt 2500 ]; do echo "{\"type\":\"assistant\",\"message\":{\"id\":\"L$i\",\"content\":[{\"type\":\"text\",\"text\":\"t\"}]}}"; i=$((i + 1)); done; } > .harness/log/long.jsonl
frame 30 70 implementer .harness/log/long.jsonl
check "long stream: model from init and turns over the whole stream" bash -c 'grep -qF "turns 2500  " <<<"$1" && grep -qF "  sonnet" <<<"$1"' _ "$OUT"

# heading fallback (no ## Steps)
sed -e '/^## Steps/,/^- not numbered/d' .harness/task-implementer.md > t.md && mv t.md .harness/task-implementer.md
frame
check "heading fallback" bash -c 'grep -qF "  1. Goal" <<<"$1" && grep -qF "  2. Done criteria" <<<"$1"' _ "$OUT"

# brief = prompt text when the prompt does not name the task file; no Diff for non-implementer
cp $RAW .harness/log/x-analyst.jsonl
frame 30 70 analyst .harness/log/x-analyst.jsonl
check "analyst: prompt title" has "── Brief ── plain question about code"
check "analyst: no Steps section (Verify present)" bash -c 'grep -qF "── Verify" <<<"$1" && ! grep -qF "── Steps" <<<"$1"' _ "$OUT"
check "analyst: no Diff section (Verify present)" bash -c 'grep -qF "── Verify" <<<"$1" && ! grep -qF "── Diff" <<<"$1"' _ "$OUT"

# verify states
printf '%s\n' '{"type":"system","subtype":"hook_started","hook_event":"Stop"}' >> $RAW
frame; check "verify running" has "── Verify ── verifying…"
printf '%s\n' '{"type":"system","subtype":"hook_response","hook_event":"Stop","exit_code":0,"stdout":""}' >> $RAW
frame; check "verify pass" has "── Verify ── pass"
printf '%s\n' '{"type":"system","subtype":"hook_started","hook_event":"Stop"}' '{"type":"system","subtype":"hook_response","hook_event":"Stop","exit_code":0,"stdout":"{\"decision\":\"block\",\"reason\":\"lint failed\"}"}' >> $RAW
echo '{"status":"fail","step":"tests","tail":"x"}' > .harness/verify/implementer.json
frame; check "verify fail (step)" has "── Verify ── fail (tests)"
# stale verify json (older than .current) gives no step
touch -t 200001010000 .harness/verify/implementer.json
frame; check "verify fail: stale verify json -> no step" bash -c 'grep -qF "── Verify ── fail" <<<"$1" && ! grep -qF "(tests)" <<<"$1"' _ "$OUT"
touch .harness/verify/implementer.json
# report_gate block is not a verify failure
printf '%s\n' '{"type":"system","subtype":"hook_started","hook_event":"Stop"}' '{"type":"system","subtype":"hook_response","hook_event":"Stop","exit_code":0,"stdout":"{\"decision\":\"block\",\"reason\":\"write .harness/reports/implementer.md for this ask, then stop\"}"}' >> $RAW
frame; check "verify: report_gate block -> waiting for report" bash -c 'grep -qF "── Verify ── waiting for report" <<<"$1" && ! grep -qF "── Verify ── fail" <<<"$1"' _ "$OUT"
printf '%s\n' '{"type":"system","subtype":"hook_started","hook_event":"Stop"}' '{"type":"system","subtype":"hook_response","hook_event":"Stop","exit_code":0,"stdout":"{\"decision\":\"block\",\"reason\":\"lint failed\"}"}' >> $RAW

# Diff against the base sha (implementer)
git init -q . && git add -A . 2>/dev/null; git -c user.email=a@b -c user.name=t commit -qm base --allow-empty
SHA=$(git rev-parse HEAD)
printf '%s\nxx\n' "$SHA" > .harness/verify/implementer.base
echo hello > newfile.txt; git add newfile.txt
frame; check "diff stat shown" bash -c 'grep -qF "── Diff" <<<"$1" && grep -qF "newfile.txt" <<<"$1"' _ "$OUT"

# truncation: width cuts by character, height never exceeded and Recent shrinks first
frame 30 20
check "width: no line over 20 chars (header and Steps present)" bash -c 'grep -qF "implementer" <<<"$1" && grep -qF "── Steps" <<<"$1" && [ "$(jq -R "length" <<<"$1" | sort -n | tail -n 1)" -le 20 ]' _ "$OUT"
frame 12 70
check "height 12: at most 12 lines (header present)" bash -c 'grep -qF "implementer" <<<"$1" && [ "$(wc -l <<<"$1")" -le 12 ]' _ "$OUT"
check "height 12: header + Now + Steps + Verify kept" bash -c 'grep -qF "implementer" <<<"$1" && grep -qF "── Now" <<<"$1" && grep -qF "── Steps" <<<"$1" && grep -qF "── Verify" <<<"$1"' _ "$OUT"
check "height 12: Recent dropped before them" bash -c 'grep -qF "── Verify" <<<"$1" && ! grep -qF "── Recent" <<<"$1"' _ "$OUT"
frame 3 70
check "height 3: header + brief + at most 1 more" bash -c 'grep -qF "── Brief" <<<"$1" && [ "$(wc -l <<<"$1")" -le 3 ]' _ "$OUT"
check "height 3: header first" [ "$(sed -n 1p <<<"$OUT" | cut -c1-11)" = implementer ]

# multibyte brief title is cut by character, not byte
printf '# 한글제목한글제목한글제목\n## Steps\n1. a\n' > .harness/task-implementer.md
frame 30 20
check "multibyte: title cut by width (Brief prefix kept, <= 20 cols)" bash -c '[ "$(sed -n 2p <<<"$1" | cut -c1-5)" = "── Br" ] && [ "$(sed -n 2p <<<"$1" | jq -R "explode | map(if . >= 44032 and . <= 55203 then 2 else 1 end) | add")" -le 20 ]' _ "$OUT"
# Korean text everywhere: no line wider than W display columns (Hangul = 2), at several widths
cat > .harness/log/ko.jsonl <<'EOS'
{"type":"system","subtype":"init","model":"sonnet","session_id":"s1"}
{"type":"assistant","message":{"id":"k1","content":[{"type":"text","text":"한글 진행 상황을 계속 길게 써서 폭을 넘기는 줄\n두번째 줄입니다 한글한글한글한글"}]}}
EOS
for w in 20 33 61; do
  frame 30 $w implementer .harness/log/ko.jsonl
  check "display width: Korean frame <= $w cols (Now + header present)" bash -c 'grep -qF "── Now" <<<"$1" && grep -qF "  한글" <<<"$1" && [ "$(jq -R "explode | map(if . >= 44032 and . <= 55203 then 2 else 1 end) | add // 0" <<<"$1" | sort -n | tail -n 1)" -le "$2" ]' _ "$OUT" $w
done

# redraw: no full clear; home, clear line ends, clear below
PAINT=$(dash_paint $'one\ntwo' | od -c | tr -d ' \n')
check "paint: home + per-line clear + clear below, no 2J" bash -c 'case "$1" in *033[H*one033[K*two033[K*033[J*) ! case "$1" in *2J*) true;; *) false;; esac;; *) false;; esac' _ "$PAINT"

# full frame: exactly H lines -> H-1 newlines (a trailing newline would scroll the pane every tick)
FULL=$(printf 'l%s\n' 1 2 3 4 5 | sed '$d')$'\nl5'
check "paint: H-line frame prints H-1 newlines" [ "$(dash_paint "$FULL" | tr -cd '\n' | wc -c | tr -d ' ')" = 4 ]

# wide emoji/symbols count 2 columns; tabs expand
printf '%s\n' '{"type":"assistant","message":{"id":"w1","content":[{"type":"text","text":"✅🚀❌⚡ ✅🚀❌⚡ ✅🚀❌⚡ ✅🚀❌⚡ ✅🚀❌⚡\n\tx\ty\tz\tabcdefghijklmnop"}]}}' > .harness/log/emoji.jsonl
for w in 20 33; do
  frame 30 $w implementer .harness/log/emoji.jsonl
  check "emoji width: lines <= $w cols (Now present)" bash -c 'grep -qF "── Now" <<<"$1" && grep -qF "  ✅" <<<"$1" && [ "$(jq -R "explode | map(if (. >= 9989 and . <= 9989) or . == 10060 or . == 9889 or (. >= 127744 and . <= 128767) then 2 else 1 end) | add // 0" <<<"$1" | sort -n | tail -n 1)" -le "$2" ]' _ "$OUT" $w
  check "tabs: none left, width <= $w" bash -c '! grep -q "$(printf "\t")" <<<"$1" && grep -qF "  x  y" <<<"$1" && [ "$(jq -R "length" <<<"$1" | sort -n | tail -n 1)" -le "$2" ]' _ "$OUT" $w
done

# final frame: result line + report head
printf '%s\n' '# stale report' > .harness/reports/implementer.md; touch -t 200001010000 .harness/reports/implementer.md
echo '{"ask_id":"ask-0","rc":0,"result":"success","num_turns":99,"cost_usd":9,"duration_ms":999000}' > $ASK_DIR/implementer.exit.json
hl_alive() { return 1; }
frame
check "final: stale exit.json (other ask) -> no result" bash -c 'grep -qF "── Result ── ■ ended (no result)" <<<"$1" && ! grep -qF "99 turns" <<<"$1" && grep -qF "ask-1" <<<"$1"' _ "$OUT"
check "final: stale report -> no report head" bash -c 'grep -qF "── Report" <<<"$1" && grep -qF "(no report)" <<<"$1" && ! grep -qF "stale report" <<<"$1"' _ "$OUT"
echo '{"ask_id":"ask-1","rc":0,"result":"success","num_turns":38,"cost_usd":1.5,"duration_ms":125000}' > $ASK_DIR/implementer.exit.json
printf '# implementer report\nstatus: done\n' > .harness/reports/implementer.md
hl_alive() { return 1; }
frame
check "final: result line" has "── Result ── ■ success · rc 0 · 38 turns · 125s · \$1.5"
check "final: report head" bash -c 'grep -qF "── Report" <<<"$1" && grep -qF "  # implementer report" <<<"$1"' _ "$OUT"
check "final: duration from exit.json" has "⏱ 2m05s"
check "final: no Now (Result present)" bash -c 'grep -qF "── Result" <<<"$1" && ! grep -qF "── Now" <<<"$1"' _ "$OUT"

echo "dash: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
