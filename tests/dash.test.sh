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
eval "$(sed -n '/^file_mtime() {/,/^}/p' "$HARNESS")"
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
# elapsed is wall-clock (date +%s - start): allow a few seconds of drift so a second boundary cannot flake it
check "header" bash -c 'case "$1" in "implementer  ask-1  ⏱ 12m0"[4-9]"s  turns 2  ctx 82k  sonnet") true;; *) false;; esac' _ "$(sed -n 1p <<<"$OUT")"
check "brief title" [ "$(sed -n 2p <<<"$OUT")" = "── Brief ── Implement the thing" ]
GOLD_MID=$(cat <<'EOG'
── Now ──
  → Say hi
    echo hi
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
check "Now from tool_use (description preferred)" bash -c 'grep -qF "  → Say hi" <<<"$1" && grep -qF "    echo hi" <<<"$1"' _ "$OUT"
sed 's/,"description":"Say hi"//' .harness/log/tool.jsonl > .harness/log/tool2.jsonl
frame 30 70 implementer .harness/log/tool2.jsonl
check "Now from tool_use (command fallback)" bash -c 'grep -qF "  → Bash echo hi" <<<"$1" && grep -qF "    echo hi" <<<"$1"' _ "$OUT"

# Now = whichever is later in the stream (text after tool_use, and tool_use after text)
{ grep -v '"type":"text"' $RAW | sed -n 1,2p; echo '{"type":"assistant","message":{"id":"m3","content":[{"type":"text","text":"Final words"}]}}'; } > .harness/log/order1.jsonl
frame 30 70 implementer .harness/log/order1.jsonl
printf '%s\n' '{"type":"assistant","message":{"id":"m4","content":[{"type":"text","text":"l1\nl2\nl3\nl4"}]}}' >> .harness/log/order1.jsonl
frame 30 70 implementer .harness/log/order1.jsonl
check "Now: text later than tool_use wins, shown wrapped (no summary line)" bash -c 'N=$(sed -n "/── Now/,/── Steps/p" <<<"$1"); grep -qF "  l3" <<<"$N" && grep -qF "  l4" <<<"$N" && ! grep -qF "→" <<<"$N"' _ "$OUT"
frame 30 70 implementer $RAW
check "Now: tool_use later than text wins" bash -c 'grep -qF "  → Say hi" <<<"$1" && ! sed -n "/── Now/,/── Steps/p" <<<"$1" | grep -qF "Starting work"' _ "$OUT"

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

# --- Now = summary + full command wrapped; height priority; idle timer ---
now_sec() { sed -En '/── Now/,/── (Steps|Verify)/p'; }
# widths hard-coded (Hangul/emoji = 2 cols), not taken from the lib's table
maxw() { jq -R 'explode | map(if . >= 44032 and . <= 55203 or . >= 126976 and . <= 129791 then 2 else 1 end) | add // 0' | sort -n | tail -n 1; }
export -f now_sec maxw
tool_stream() { # <file> <preceding text or ""> <tool> <input json>
  { echo '{"type":"system","subtype":"init","model":"sonnet","session_id":"s1"}'
    [ -z "$2" ] || printf '{"type":"assistant","message":{"id":"p1","content":[{"type":"text","text":"%s"}]}}\n' "$2"
    printf '{"type":"assistant","message":{"id":"p2","content":[{"type":"tool_use","name":"%s","input":%s}]}}\n' "$3" "$4"; } > "$1"
}
tool_stream .harness/log/s1.jsonl "Checking the config\nmore words" Bash '{"command":"ls -la"}'
frame 30 70 implementer .harness/log/s1.jsonl
check "summary from the preceding assistant text's first line" bash -c 'grep -qF "  → Checking the config" <<<"$1" && grep -qF "    ls -la" <<<"$1" && ! now_sec <<<"$1" | grep -qF "more words"' _ "$OUT"
tool_stream .harness/log/s2.jsonl "" Read '{"file_path":"/a/b.txt"}'
frame 30 70 implementer .harness/log/s2.jsonl
check "summary fallback: <Tool> <file_path>, path not repeated as detail" bash -c 'grep -qF "  → Read /a/b.txt" <<<"$1" && ! grep -qF "    /a/b.txt" <<<"$1"' _ "$OUT"
tool_stream .harness/log/s3.jsonl "" Grep '{"pattern":"foo.*bar"}'
frame 30 70 implementer .harness/log/s3.jsonl
check "summary fallback: <Tool> <pattern>" has "  → Grep foo.*bar"

CMD="START$(printf 'x%.0s' $(seq 1 60))MIDDLE$(printf 'y%.0s' $(seq 1 60))END"
tool_stream .harness/log/long1.jsonl "" Bash "{\"command\":\"$CMD\",\"description\":\"긴 명령 실행\"}"
frame 30 40 implementer .harness/log/long1.jsonl
check "long command wraps: every line <= 39 cols, rest continues on later lines" bash -c 'D=$(now_sec <<<"$1" | grep "^    " | tr -d " \n"); [ "$D" = "$2" ] && [ "$(maxw <<<"$1")" -le 39 ]' _ "$OUT" "$CMD"
BIG=$(printf 'abcdefghij%.0s' $(seq 1 40))END
tool_stream .harness/log/long2.jsonl "" Bash "{\"command\":\"$BIG\",\"description\":\"d\"}"
frame 30 40 implementer .harness/log/long2.jsonl
check "more than 6 lines: 6 detail lines, last ends with …, tail not shown" bash -c 'D=$(now_sec <<<"$1" | grep "^    "); [ "$(wc -l <<<"$D")" -eq 6 ] && [ "$(tail -n 1 <<<"$D" | grep -o ".$")" = "…" ] && ! grep -qF "END" <<<"$D" && [ "$(maxw <<<"$D")" -le 39 ]' _ "$OUT"
KO=$(printf '한글🟢abc%.0s' $(seq 1 12))
tool_stream .harness/log/long3.jsonl "" Bash "{\"command\":\"$KO\",\"description\":\"d\"}"
frame 30 30 implementer .harness/log/long3.jsonl
check "Korean/emoji wrap: <= 29 cols per line, nothing lost" bash -c 'D=$(now_sec <<<"$1" | grep "^    " | tr -d " \n"); [ "$D" = "$2" ] && [ "$(maxw <<<"$1")" -le 29 ]' _ "$OUT" "$KO"
printf '%s\n' '{"type":"assistant","message":{"id":"t9","content":[{"type":"text","text":"한글 문장이 아주 길어서 줄이 바뀌어야 합니다 🟢 계속 이어지는 문장입니다 끝"}]}}' > .harness/log/long4.jsonl
frame 30 30 implementer .harness/log/long4.jsonl
check "text Now wraps by display width and keeps the end" bash -c '[ "$(maxw <<<"$1")" -le 29 ] && grep -qF "끝" <<<"$1" && [ "$(now_sec <<<"$1" | grep -c "^  [^ ]")" -ge 2 ]' _ "$OUT"

# height priority: Recent shrinks first, then Now detail lines (down to 1), then Diff
tool_stream .harness/log/long5.jsonl "" Bash "{\"command\":\"$(printf 'abcdefghij%.0s' $(seq 1 25))\",\"description\":\"d\"}"
for H in 30 24 20 18 16 14 12 10 9 8; do
  frame $H 40 implementer .harness/log/long5.jsonl
  nd=$(now_sec <<<"$OUT" | grep -c "^    ")
  check "height $H: <= $H lines" [ "$(wc -l <<<"$OUT" | tr -d ' ')" -le $H ]
  check "height $H: Recent present => 6 detail lines + Diff" bash -c '! grep -qF "── Recent" <<<"$1" || { [ "$2" -eq 6 ] && grep -qF "── Diff" <<<"$1"; }' _ "$OUT" "$nd"
  check "height $H: fewer than 6 detail lines => no Recent" bash -c '[ "$2" -ge 6 ] || ! grep -qF "── Recent" <<<"$1"' _ "$OUT" "$nd"
  check "height $H: Diff present => Now keeps >= 1 detail, Steps, Verify" bash -c '! grep -qF "── Diff" <<<"$1" || { [ "$2" -ge 1 ] && grep -qF "── Steps" <<<"$1" && grep -qF "── Verify" <<<"$1"; }' _ "$OUT" "$nd"
  check "height $H: Diff absent => no Recent" bash -c 'grep -qF "── Diff" <<<"$1" || ! grep -qF "── Recent" <<<"$1"' _ "$OUT"
done
frame 16 40 implementer .harness/log/long5.jsonl
check "height 16: detail shrinks to make room (Diff + Steps + Verify kept, < 6 detail)" bash -c 'grep -qF "── Diff" <<<"$1" && grep -qF "── Verify" <<<"$1" && [ "$(now_sec <<<"$1" | grep -c "^    ")" -lt 6 ] && [ "$(now_sec <<<"$1" | grep -c "^    ")" -ge 1 ]' _ "$OUT"

# idle timer: from 10 s since the last stream line, only while live
ago() { date -v-"$1"S +%Y%m%d%H%M.%S 2>/dev/null || date -d "-$1 sec" +%Y%m%d%H%M.%S; }
touch .harness/log/long5.jsonl
frame 30 80 implementer .harness/log/long5.jsonl
check "idle hidden when the stream is fresh" bash -c '! grep -qF "idle" <<<"$1"' _ "$OUT"
touch -t "$(ago 5)" .harness/log/long5.jsonl
frame 30 80 implementer .harness/log/long5.jsonl
check "idle hidden below 10 s" bash -c '! grep -qF "idle" <<<"$1"' _ "$OUT"
touch -t "$(ago 45)" .harness/log/long5.jsonl
frame 30 80 implementer .harness/log/long5.jsonl
check "idle shown at >= 10 s (· idle 45s)" bash -c 'sed -n 1p <<<"$1" | grep -qE "⏱ 12m[0-5][0-9]s · idle (4[5-9]|5[0-9])s  turns"' _ "$OUT"

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

# cut at W-1: an ASCII-only line wider than W is cut to exactly W-1 columns (the trailing erase-to-EOL never hits glyph W)
printf '# %s\n' abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz > .harness/task-implementer.md
frame 30 20
check "W-1: header line is exactly 19 cols at W=20" [ "$(sed -n 1p <<<"$OUT" | jq -R length)" -eq 19 ]
check "W-1: no line reaches 20 cols" [ "$(jq -R length <<<"$OUT" | sort -n | tail -n 1)" -le 19 ]

# redraw: no full clear; home, clear line ends, clear below
PAINT=$(dash_paint $'one\ntwo' | od -c | tr -d ' \n')
check "paint: home + per-line clear + clear below, no 2J" bash -c 'case "$1" in *033[H*one033[K*two033[K*033[J*) ! case "$1" in *2J*) true;; *) false;; esac;; *) false;; esac' _ "$PAINT"

# full frame: exactly H lines -> H-1 newlines (a trailing newline would scroll the pane every tick)
FULL=$(printf 'l%s\n' 1 2 3 4 5 | sed '$d')$'\nl5'
check "paint: H-line frame prints H-1 newlines" [ "$(dash_paint "$FULL" | tr -cd '\n' | wc -c | tr -d ' ')" = 4 ]

# wide emoji/symbols count 2 columns; tabs expand. Widths are hard-coded, not taken from the lib's table:
# every sample emoji is 2 cols, so a line "  " + k emoji is 2 + 2k cols; ASCII-only lines are width = length.
printf '%s\n' '{"type":"assistant","message":{"id":"w1","content":[{"type":"text","text":"✅🚀❌⚡ ✅🚀❌⚡ ✅🚀❌⚡ ✅🚀❌⚡ ✅🚀❌⚡\n\tx\ty\tz\tabcdefghijklmnop"}]}}' > .harness/log/emoji.jsonl
printf '%s\n' '{"type":"assistant","message":{"id":"w2","content":[{"type":"text","text":"🟢🟡🟠🟢🟡🟠🟢🟡🟠🟢🟡🟠🟢🟡🟠🟢🟡🟠\n🀄🃏🆎🆑🆚🈁🈯🟠🟡🟢 〈x〉 ﹐﹑﹒"}]}}' > .harness/log/circles.jsonl
for w in 20 33; do
  frame 30 $w implementer .harness/log/emoji.jsonl
  check "emoji width: Now present, emoji line kept" bash -c 'grep -qF "── Now" <<<"$1" && grep -qF "  ✅" <<<"$1"' _ "$OUT"
  check "tabs: none left, ASCII tab line width <= $w" bash -c '! grep -q "$(printf "\t")" <<<"$1" && grep -qF "  x  y" <<<"$1" && [ "$(grep "x  y" <<<"$1" | jq -R "length" | sort -n | tail -n 1)" -le "$2" ]' _ "$OUT" $w
  frame 30 $w implementer .harness/log/circles.jsonl
  check "🟢🟡🟠 line fits $w cols (2 cols each, hard-coded)" bash -c 'l=$(grep "🟢" <<<"$1" | head -n 1); k=$(printf "%s" "$l" | grep -o "[🟢🟡🟠]" | wc -l | tr -d " "); [ "$k" -ge 1 ] && [ $((2 + 2 * k)) -le "$2" ]' _ "$OUT" $w
done
# conservative: the rest of the 1F000 block and the listed misses count 2 cols too (hard-coded: 3 chars = 6 cols)
for c in 🀄 🃏 🆎 🆑 🈁 🟠 〈 "$(printf '\xe2\x8c\xa9')" "$(printf '\xe2\x8c\xaa')" "$(printf '\xef\xb9\x90')" "$(printf '\xef\xb9\xab')"; do
  W=7; printf '{"type":"assistant","message":{"id":"c","content":[{"type":"text","text":"%s%s%s%s%s%s%s"}]}}\n' $c $c $c $c $c $c $c > .harness/log/one.jsonl
  frame 30 $W implementer .harness/log/one.jsonl
  check "width of $c counts 2 (2 + 2k <= 7 -> k <= 2)" bash -c 'k=$(grep -F "$2" <<<"$1" | while read -r l; do printf "%s" "$l" | grep -o "$2" | wc -l; done | sort -n | tail -n 1 | tr -d " "); [ "${k:-0}" -ge 1 ] && [ "$k" -le 2 ]' _ "$OUT" "$c"
done

# one size var set: that one is honoured, the other comes from the terminal/default
OUT=$(HARNESS_DASH_LINES=5 PATH="$HERE/../bin:$PATH" hl_dash_frame implementer "$RAW")
check "only LINES set: <= 5 lines" [ "$(wc -l <<<"$OUT" | tr -d ' ')" -le 5 ]
OUT=$(HARNESS_DASH_COLS=25 PATH="$HERE/../bin:$PATH" hl_dash_frame implementer "$RAW")
check "only COLS set: ASCII header line <= 25 cols" [ "$(sed -n 1p <<<"$OUT" | jq -R length)" -le 25 ]

# autowrap off while drawing, restored on exit with a newline
check "begin: cursor hidden + autowrap off" bash -c '[ "$1" = "$(printf "\033[?25l\033[?7l")" ]' _ "$(dash_begin)"
dash_begin >/dev/null
dash_end > .harness/log/end1.out   # main shell (not $(...)): the idempotence flag must persist
END=$(od -An -c < .harness/log/end1.out | tr -d ' \n')
check "end: autowrap on + cursor shown + newline" bash -c 'case "$1" in *033[?7h033[?25h\\n) true;; *) false;; esac' _ "$END"
dash_end > .harness/log/end2.out
check "end: idempotent (second call prints nothing)" [ ! -s .harness/log/end2.out ]
SRC=$(cat "$HERE/../lib/harness-headless.sh")
check "watch: traps cover INT TERM HUP QUIT EXIT" bash -c 'grep -qF "trap '"'"'dash_end; exit 129'"'"' HUP" <<<"$1" && grep -qF "trap '"'"'dash_end; exit 131'"'"' QUIT" <<<"$1" && grep -qF "trap dash_end EXIT" <<<"$1"' _ "$SRC"
check "watch: trap and normal exit both use dash_begin/dash_end" bash -c 'grep -qF "trap '"'"'dash_end; exit 130'"'"' INT TERM" <<<"$1" && grep -q "^  dash_begin" <<<"$1" && grep -q "^  dash_end" <<<"$1"' _ "$SRC"

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

# control chars never reach the frame raw (CR, ESC sequences, DEL); tools without a known arg key get a compact input
printf 'ask-1 %s\n' $((NOW - 5)) > $ASK_DIR/implementer.current
hl_alive() { return 0; }
RAWC=.harness/log/ctl-implementer.jsonl
printf '%s\n' '{"type":"assistant","message":{"id":"c1","content":[{"type":"tool_use","name":"Bash","input":{"command":"echo a\rEVIL\u001b[2Jb\u007fc"}}]}}' > $RAWC
frame 30 70 implementer $RAWC
check "ctl: no raw CR/ESC/DEL in the frame" bash -c '! printf "%s" "$1" | LC_ALL=C grep -q "[[:cntrl:]]" ' _ "$OUT"
check "ctl: replaced by a placeholder" has "echo a·EVIL·[2Jb·c"
check "ctl: header+detail wrap path too (Now has the text)" has "→ Bash echo a·EVIL"
printf '%s\n' '{"type":"assistant","message":{"id":"c2","content":[{"type":"tool_use","name":"WebSearch","input":{"query":"harness dash","limit":3}}]}}' > $RAWC
frame 30 70 implementer $RAWC
check "fallback: tool without known key shows compact input" has '→ WebSearch {"query":"harness dash","limit":3}'
check "fallback: detail line carries the input too" bash -c '[ "$(sed -n "/── Now/,/── Verify/p" <<<"$1" | grep -cF "\"query\"")" -eq 2 ]' _ "$OUT"
printf '%s\n' '{"type":"assistant","message":{"id":"c3","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/some/file.txt"}}]}}' > $RAWC
frame 30 70 implementer $RAWC
check "Read: path shown once (summary only)" bash -c '[ "$(sed -n "/── Now/,/── Verify/p" <<<"$1" | grep -cF "/tmp/some/file.txt")" -eq 1 ]' _ "$OUT"
printf '%s\n' '{"type":"assistant","message":{"id":"c4","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/some/file.txt","description":"look at it"}}]}}' > $RAWC
frame 30 70 implementer $RAWC
check "Read with description: path kept as detail" bash -c 'grep -qF "→ look at it" <<<"$1" && grep -qF "    /tmp/some/file.txt" <<<"$1"' _ "$OUT"

echo "dash: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
