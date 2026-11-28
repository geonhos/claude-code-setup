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
frame() { OUT=$(HARNESS_DASH_NOW=$NOW HARNESS_DASH_LINES=${1:-30} HARNESS_DASH_COLS=${2:-70} PATH="$HERE/../bin:$PATH" hl_dash_frame "${3:-implementer}" "${4:-$RAW}"); }
has() { grep -qF -- "$1" <<<"$OUT"; }

# full frame, implementer, text Now, no verify yet, no baseline
frame
# the clock is pinned (HARNESS_DASH_NOW=$NOW in frame): elapsed is exactly 724 s
check "header" [ "$(sed -n 1p <<<"$OUT")" = "implementer  ask-1  ⏱ 12m04s  turns 2  ctx 82k  sonnet" ]
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
ago() { local t=$((NOW - $1)); date -r "$t" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$t" +%Y%m%d%H%M.%S; }   # relative to the pinned NOW
touch -t "$(ago 0)" .harness/log/long5.jsonl
frame 30 80 implementer .harness/log/long5.jsonl
check "idle hidden when the stream is fresh" bash -c '! grep -qF "idle" <<<"$1"' _ "$OUT"
touch -t "$(ago 5)" .harness/log/long5.jsonl
frame 30 80 implementer .harness/log/long5.jsonl
check "idle hidden below 10 s" bash -c '! grep -qF "idle" <<<"$1"' _ "$OUT"
touch -t "$(ago 45)" .harness/log/long5.jsonl
frame 30 80 implementer .harness/log/long5.jsonl
check "idle shown at >= 10 s (· idle 45s)" bash -c 'sed -n 1p <<<"$1" | grep -qF "⏱ 12m04s · idle 45s  turns"' _ "$OUT"

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

# brief path named in the prompt: absolute or relative, any .md under a .harness/ dir; nothing outside .harness/
mkdir -p .harness/other elsewhere
printf '# Abs brief\n## Steps\n1. one\n2. two\n' > .harness/other/task-67.md
printf '# Outside brief\n## Steps\n1. nope\n' > elsewhere/task-9.md
printf 'Read %s/.harness/other/task-67.md and do it.\n' "$PWD" > $ASK_DIR/implementer.prompt
check "brief: absolute path in the prompt is followed" [ "$(dash_brief implementer | head -n 1)" = "Abs brief" ]
check "brief: its steps are listed" [ "$(dash_brief implementer | grep -c '^S')" = 2 ]
printf 'Read .harness/other/task-67.md.\n' > $ASK_DIR/implementer.prompt
check "brief: relative path (trailing period) is followed" [ "$(dash_brief implementer | head -n 1)" = "Abs brief" ]
printf 'Read elsewhere/task-9.md and do it.\nsecond\n' > $ASK_DIR/implementer.prompt
check "brief: file outside .harness/ is not read (prompt line shown)" [ "$(dash_brief implementer)" = "Read elsewhere/task-9.md and do it." ]
printf 'Read .harness/../elsewhere/task-9.md\n' > $ASK_DIR/implementer.prompt
check "brief: .. escape is not followed" [ "$(dash_brief implementer | head -n 1)" = "Read .harness/../elsewhere/task-9.md" ]
printf 'Read .harness/task-implementer.md and do it.\n' > $ASK_DIR/implementer.prompt

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
dw() { jq -R "explode | map(if (. >= 44032 and . <= 55203) or (. >= 126976 and . <= 129791) then 2 else 1 end) | add // 0"; }   # display width: Hangul and emoji = 2
check "W-1: header line is exactly 19 cols at W=20" [ "$(sed -n 1p <<<"$OUT" | dw)" -eq 19 ]
check "W-1: no line reaches 20 cols" [ "$(dw <<<"$OUT" | sort -n | tail -n 1)" -le 19 ]
# wide characters: a 2-column glyph that would straddle column 19 is dropped, so the line is 18 or 19 columns, never 20
printf '# %s\n' 한한한한한한한한한한한한한한한한 > .harness/task-implementer.md
frame 30 20
check "W-1: Hangul Brief line is 18 or 19 display cols (not jq length), never 20" bash -c '[ "$1" -ge 18 ] && [ "$1" -le 19 ] && [ "$(sed -n 2p <<<"$2" | jq -R length)" -lt "$1" ]' _ "$(sed -n 2p <<<"$OUT" | dw)" "$OUT"
printf '# %s\n' 😀😀😀😀😀😀😀😀😀😀😀😀😀😀😀 > .harness/task-implementer.md
frame 30 20
check "W-1: emoji frame has no line over 19 display cols" [ "$(dw <<<"$OUT" | sort -n | tail -n 1)" -le 19 ]

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
SRC=$(cat "$HERE/../lib/harness-dash.sh")
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

# size is read on every frame, from the harness-only override names; an exported LINES/COLUMNS is ignored
sz() { HARNESS_DASH_LINES=$1 HARNESS_DASH_COLS=$2 PATH="$HERE/../bin:$PATH" dash_size; }
check "size: override read per call (1)" [ "$(sz 20 50)" = "20 50" ]
check "size: override read per call (2) differs" [ "$(sz 33 99)" = "33 99" ]
frame 30 40; W1=$(jq -R length <<<"$OUT" | sort -n | tail -n 1)
frame 30 90; W2=$(jq -R length <<<"$OUT" | sort -n | tail -n 1)
check "size: two frames, two widths" bash -c '[ "$1" -le 39 ] && [ "$2" -gt 39 ] && [ "$2" -le 89 ]' _ "$W1" "$W2"
check "size: LINES/COLUMNS env ignored" [ "$(LINES=7 COLUMNS=9 HARNESS_DASH_LINES=21 HARNESS_DASH_COLS=61 dash_size)" = "21 61" ]
OUT=$(unset HARNESS_DASH_LINES HARNESS_DASH_COLS; LINES=7 COLUMNS=9 PATH="$HERE/../bin:$PATH" dash_size)
check "size: no override + LINES/COLUMNS set -> not 7 9" [ "$OUT" != "7 9" ]

# dash_watch on a finished run: draws the final frame, stays alive, re-renders on WINCH (no polling needed) and on a
# polled size change, exits on HUP/INT/TERM with the terminal restored, and when the ask is removed
cat > .harness/log/hold.sh <<'EOH'
. "$LIB"
. "$HERE/../lib/harness-defaults.sh" 2>/dev/null
eval "$DO_SRC"
hl_alive() { return 1; }
hl_done() { return 0; }
dash_size() { cat .harness/log/size; }
ASK_DIR=.harness/asks
dash_watch implementer "$RAW" ask-1
EOH
# wait_until <tenths> CMD... — poll CMD every 0.1 s until it succeeds or the cap passes (the check after it decides)
wait_until() { local i=0 n=$1; shift; while [ $i -lt "$n" ] && ! "$@"; do sleep 0.1; i=$((i + 1)); done; return 0; }
nframes_is() { [ "$(nframes "$1")" = "$2" ]; }
dead() { ! kill -0 "$1" 2>/dev/null; }
hold_start() {   # hold_start <name> -> HP; output in .harness/log/<name>.out
  echo "30 40" > .harness/log/size; rm -f .harness/log/$1.out
  LIB="$LIB" HERE="$HERE" DO_SRC="$DO_SRC" RAW="$RAW" PATH="$HERE/../bin:$PATH" HARNESS_DASH_IDLE_SEC=${2:-30} \
    perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' /bin/bash .harness/log/hold.sh > .harness/log/$1.out 2>&1 </dev/null & HP=$!   # perl: a background job inherits SIGINT ignored, which no trap can undo
  wait_until 100 grep -q "── Result" .harness/log/$1.out   # first frame drawn (cold start can exceed a fixed sleep under load, #232)
}
nframes() { grep -c "── Result" .harness/log/$1.out; }
hold_start winch 30
check "hold: final frame drawn, still alive" bash -c 'kill -0 "$1" && [ "$(grep -c "── Result" "$2")" = 1 ]' _ "$HP" .harness/log/winch.out
echo "30 90" > .harness/log/size; kill -WINCH $HP; wait_until 100 nframes_is winch 2
check "hold: WINCH redraws at once (idle poll is 30 s)" [ "$(nframes winch)" = 2 ]
kill -WINCH $HP; sleep 0.7
check "hold: WINCH with an unchanged size does not repaint" [ "$(nframes winch)" = 2 ]
kill -HUP $HP; wait $HP 2>/dev/null; HRC=$?
check "hold: HUP exits 129, terminal restored" bash -c '[ "$1" = 129 ] && tail -c 20 "$2" | od -An -c | tr -d " \n" | grep -qF "$3"' _ "$HRC" .harness/log/winch.out '033[?7h033[?25h\n'
# live loop (the run is alive, not done): real HUP/INT/TERM while painting frames
cat > .harness/log/live.sh <<'EOH'
. "$LIB"
eval "$DO_SRC"
hl_alive() { return 0; }
hl_done() { return 1; }
dash_size() { echo "30 40"; }
hl_dash_frame() { echo "live frame"; }
ASK_DIR=.harness/asks
dash_watch implementer "$RAW" ask-1
EOH
for sg in HUP:129 INT:130 TERM:130; do
  n=${sg%%:*}; want=${sg##*:}
  rm -f .harness/log/live-$n.out
  LIB="$LIB" DO_SRC="$DO_SRC" RAW="$RAW" HARNESS_DASH_SEC=30 \
    perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' /bin/bash .harness/log/live.sh > .harness/log/live-$n.out 2>&1 </dev/null & HP=$!
  wait_until 100 grep -qF "live frame" .harness/log/live-$n.out   # traps are set before the first paint
  kill -$n $HP; wait $HP 2>/dev/null; HRC=$?
  check "live loop: $n exits $want, output ends with autowrap on + cursor shown + newline" bash -c '[ "$1" = "$2" ] && grep -qF "live frame" "$3" && [ "$(tail -c 20 "$3" | od -An -c | tr -d " \n" | grep -oF "$4" | wc -l | tr -d " ")" = 1 ] && tail -c 20 "$3" | od -An -c | tr -d " \n" | grep -qF "$4"' _ "$HRC" "$want" .harness/log/live-$n.out '033[?7h033[?25h\n'
done
hold_start poll 1
echo "30 90" > .harness/log/size; wait_until 100 nframes_is poll 2
check "hold: size change picked up by the idle poll (no signal)" [ "$(nframes poll)" = 2 ]
kill -INT $HP; wait $HP 2>/dev/null; HRC=$?
check "hold: INT exits 130" [ "$HRC" = 130 ]
hold_start gone 1
cp $ASK_DIR/implementer.current .harness/log/cur.bak; rm -f $ASK_DIR/implementer.current; wait_until 100 dead $HP
check "hold: exits when the ask is removed, terminal restored" bash -c '! kill -0 "$1" 2>/dev/null && tail -c 20 "$2" | od -An -c | tr -d " \n" | grep -qF "$3"' _ "$HP" .harness/log/gone.out '033[?7h033[?25h\n'
cp .harness/log/cur.bak $ASK_DIR/implementer.current

# ---- harness status --json [--all] (#305): machine-readable worker state, pure read ----
setup
SJ_BASE=$(mktemp -d); WORKS="$WORKS $SJ_BASE"
printf '#!/bin/bash\nsleep 60\n' > "$SJ_BASE/harness-run"; chmod +x "$SJ_BASE/harness-run"
"$SJ_BASE/harness-run" & SJ_LIVE=$!
"$SJ_BASE/harness-run" & SJ_LIVE2=$!
echo "$SJ_LIVE $SJ_LIVE2" > "$SJ_BASE/pids"
SJ_NOW=1795867512
git init -q -b main . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
# at_mtime EPOCH FILE — set a file's mtime to an epoch (UTC, portable BSD/GNU)
at_mtime() { TZ=UTC touch -t "$(TZ=UTC date -u -r "$1" +%Y%m%d%H%M.%S 2>/dev/null || date -u -d "@$1" +%Y%m%d%H%M.%S)" "$2"; }
# mkrun DIR ROLE ID START — .current + .prompt + a small stream (init, a Bash tool_use with quotes) + .stream
mkrun() {
  local d=$1 r=$2 id=$3 st=$4
  mkdir -p "$d/.harness/asks" "$d/.harness/log" "$d/.harness/verify" "$d/.harness/reports"
  printf '%s %s\n' "$id" "$st" > "$d/.harness/asks/$r.current"
  printf 'Read .harness/task-%s.md and do it.\n' "$r" > "$d/.harness/asks/$r.prompt"
  printf '%s .harness/log/s-%s.jsonl\n' "$id" "$r" > "$d/.harness/asks/$r.stream"
  cat > "$d/.harness/log/s-$r.jsonl" <<EOS
{"type":"system","subtype":"init","model":"sonnet","session_id":"s1"}
{"type":"assistant","message":{"id":"m1","content":[{"type":"text","text":"start"}],"usage":{"input_tokens":10,"cache_read_input_tokens":60000,"cache_creation_input_tokens":990}}}
{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","name":"Bash","input":{"command":"x","description":"Run the \"dash\" suite"}}],"usage":{"input_tokens":10,"cache_read_input_tokens":60000,"cache_creation_input_tokens":990}}}
EOS
}
mkexit() { printf '{"ask_id":"%s","rc":0,"result":"success","num_turns":5,"cost_usd":0.25,"duration_ms":220000,"ctx":61000,"stream_log":".harness/log/s-%s.jsonl"}\n' "$2" "$3" > "$1/.harness/asks/$3.exit.json"; }
sj() { OUT=$(HARNESS_DASH_NOW=$SJ_NOW env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>"$WORK/sj.err"); RC=$?; }
P=$(pwd -P)
# primary: analyst running (live pid), implementer exited (matching exit.json, brief with Steps, Stop hook pass),
# reviewer exited with a VERDICT line in its report
mkrun "$P" analyst a-1 $((SJ_NOW - 252))
printf '한국어 질문: 코드를 읽어 주세요\nsecond line\n' > $P/.harness/asks/analyst.prompt
printf 'a-1 %s %s\n' "$SJ_LIVE" "$SJ_LIVE" > $P/.harness/asks/analyst.pid
at_mtime $((SJ_NOW - 4)) $P/.harness/log/s-analyst.jsonl
mkrun "$P" implementer i-1 $((SJ_NOW - 300))
printf 'Title-ko: 상태 JSON에 한글 필드\n# 작업: 상태 JSON\n\n## Goal\nx\n\n## Steps\n1. Read AGENTS.md [ko: AGENTS.md 읽기]\n2) Add failing tests\n- not numbered\n\n## Done\ny\n' > $P/.harness/task-implementer.md
echo '{"type":"system","subtype":"hook_response","hook_event":"Stop","exit_code":0,"stdout":""}' >> $P/.harness/log/s-implementer.jsonl
mkexit "$P" i-1 implementer
mkrun "$P" reviewer r-1 $((SJ_NOW - 100))
printf '# reviewer report\nstatus: done\nVERDICT: PASS\n' > $P/.harness/reports/reviewer.md
mkexit "$P" r-1 reviewer
before=$(cd "$P" && find .harness -type f | sort | xargs cksum | cksum)
sj status --json
check "status --json: exit 0" [ "$RC" -eq 0 ]
check "status --json: stderr empty" [ ! -s "$WORK/sj.err" ]
check "status --json: one valid document, version 1" jqt '.version == 1 and (.generated_at == 1795867512) and (.folders | length == 1)' <<<"$OUT"
check "status --json: stdout is a single JSON value" [ "$(jq -c . <<<"$OUT" | wc -l | tr -d ' ')" = 1 ]
check "folder fields" jqt --arg p "$P" '.folders[0] | .path == $p and .primary == true and .lane == null and .branch == "main"' <<<"$OUT"
check "roles in order analyst, implementer, reviewer" jqt '[.folders[0].workers[].role] == ["analyst","implementer","reviewer"]' <<<"$OUT"
check "running worker: state, ids, times, facts" jqt '.folders[0].workers[0] | .state == "running" and .ask_id == "a-1" and .started_at == 1795867260 and .elapsed_s == 252 and .idle_s == 4 and .turns == 2 and .ctx == 61000 and .model == "sonnet" and .exit == null' <<<"$OUT"
check "running worker: Korean title kept, no brief steps" jqt '.folders[0].workers[0] | .brief_title == "한국어 질문: 코드를 읽어 주세요" and .steps == [] and .step == null' <<<"$OUT"
check "running worker: now keeps quotes (jq-escaped)" jqt '.folders[0].workers[0].now == "Run the \"dash\" suite"' <<<"$OUT"
check "exited worker (matching exit.json): state, exit, verify" jqt '.folders[0].workers[1] | .state == "exited" and .elapsed_s == 220 and .idle_s == null and .now == null and .verify == "pass" and .exit == {rc: 0, result: "success", cost_usd: 0.25, duration_s: 220, verdict: null}' <<<"$OUT"
check "brief with ## Steps: numbered list, Korean title" jqt '.folders[0].workers[1] | .brief_title == "작업: 상태 JSON" and .steps == [{n:1,text:"Read AGENTS.md",ko:"AGENTS.md 읽기"},{n:2,text:"Add failing tests",ko:null}]' <<<"$OUT"
check "brief with Title-ko and one [ko:] step: title_ko set, suffix not in text" jqt '.folders[0].workers[1] | .title_ko == "상태 JSON에 한글 필드" and (.steps | map(.text | contains("[ko") | not) | all)' <<<"$OUT"
check "reviewer: verdict from the report's VERDICT line" jqt '.folders[0].workers[2] | .state == "exited" and .exit.verdict == "PASS"' <<<"$OUT"
check "status --json writes and creates nothing" [ "$before" = "$(cd "$P" && find .harness -type f | sort | xargs cksum | cksum)" ]
# a brief without markers: both fields null; `[ko:` mid-line, an empty `[ko: ]` and a Title-ko below a heading are not Korean names
printf '# Plain\n\n## Steps\n1. Keep [ko: x] inside\n2. Empty [ko: ]\n3. Plain\n\n## Notes\nTitle-ko: late\n' > $P/.harness/task-implementer.md
sj status --json
check "brief: mid-line [ko:], empty [ko: ] and late Title-ko are ignored" jqt '.folders[0].workers[1] | .title_ko == null and .steps == [{n:1,text:"Keep [ko: x] inside",ko:null},{n:2,text:"Empty",ko:null},{n:3,text:"Plain",ko:null}]' <<<"$OUT"
# a brief with Steps and no Korean marker: title_ko and every ko are null on real steps
printf '# Plain\n\n## Steps\n1. Read it\n2. Do it\n' > $P/.harness/task-implementer.md
sj status --json
check "brief without Korean: title_ko null, ko null on real steps" jqt '.folders[0].workers[1] | .title_ko == null and (.steps | length == 2) and (.steps | map(.ko == null) | all)' <<<"$OUT"
# the English text without the suffix is what the dashboard Steps block shows
printf 'Title-ko: 한글\n# T\n\n## Steps\n1. Read it [ko: 읽기]\n2. Do it\n' > $P/.harness/task-implementer.md
frame 30 70 implementer "$P"
check "dash Steps: English text, no [ko:] suffix" bash -c 'sed -n "/── Steps/,/── Verify/p" <<<"$1" | tr "\n" "|" | grep -qF "── Steps ──|  1. Read it|  2. Do it|" && ! grep -qF "[ko" <<<"$1"' _ "$OUT"
printf 'Title-ko: 상태 JSON에 한글 필드\n# 작업: 상태 JSON\n\n## Steps\n1. Read AGENTS.md [ko: AGENTS.md 읽기]\n2) Add failing tests\n' > $P/.harness/task-implementer.md
# a role that never ran is omitted
rm -f $P/.harness/asks/reviewer.*
sj status --json
check "role that never ran is omitted" jqt '[.folders[0].workers[].role] == ["analyst","implementer"]' <<<"$OUT"
# --all needs --json; a bare status is untouched
sj status --all
check "--all without --json: usage error, exit 1" [ "$RC" -eq 1 ]
sj status
check "plain status: text lines, not JSON" bash -c '! jq -e . >/dev/null 2>&1 <<<"$1" && grep -q "^analyst  *running" <<<"$1"' _ "$OUT"
# dead (current ask, pid gone, no matching exit.json) and stale exit.json (other ask_id); corrupt exit.json; --all over worktrees
git worktree add -q "$P/wt1" -b feat/12-x && git worktree add -q "$P/wt2" -b scratch
W1=$(cd "$P/wt1" && pwd -P)
mkrun "$W1" implementer i-9 $((SJ_NOW - 60))
printf 'i-9 999999 999999\n' > $W1/.harness/asks/implementer.pid
mkexit "$W1" i-OLD implementer
mkrun "$W1" reviewer r-9 $((SJ_NOW - 30))
printf '{"ask_id":"r-9","rc":\n' > $W1/.harness/asks/reviewer.exit.json
printf 'garbage\n' > $W1/.harness/asks/analyst.current
sj status --json --all
check "--all: exit 0" [ "$RC" -eq 0 ]
check "--all: one document, version 1" jqt '.version == 1' <<<"$OUT"
check "--all: primary first, folder without .harness/asks skipped" jqt --arg p "$P" --arg w "$W1" '[.folders[].path] == [$p, $w]' <<<"$OUT"
check "--all: lane folder: primary false, lane 12, branch" jqt '.folders[1] | .primary == false and .lane == 12 and .branch == "feat/12-x"' <<<"$OUT"
check "dead worker: stale exit.json is ignored" jqt '.folders[1].workers[] | select(.role == "implementer") | .state == "dead" and .exit == null and .elapsed_s == null and .now == null' <<<"$OUT"
check "corrupt exit.json: exited, exit fields null" jqt '.folders[1].workers[] | select(.role == "reviewer") | .state == "exited" and .exit == {rc: null, result: null, cost_usd: null, duration_s: null, verdict: null}' <<<"$OUT"
check "garbage .current: worker emitted with null start" jqt '.folders[1].workers[] | select(.role == "analyst") | .state == "dead" and .started_at == null and .ask_id == "garbage"' <<<"$OUT"
# from a work folder: current folder only, even with --all it lists the whole repository
sj -C "$W1" status --json
check "from a work folder: only that folder" jqt --arg w "$W1" '[.folders[].path] == [$w] and .folders[0].primary == false' <<<"$OUT"
sj -C "$W1" status --json --all
check "--all from a work folder: same list, primary first" jqt --arg p "$P" '.folders[0].path == $p and (.folders | length) == 2' <<<"$OUT"
# a worker session may read status as it can today
OUT=$(HARNESS_ROLE=worker env /bin/bash "$HARNESS" status --json 2>&1); RC=$?
check "worker session: exit 0" [ "$RC" -eq 0 ]
check "worker session: status --json works" jqt '.version == 1' <<<"$OUT"
# empty ask dir / no git: emits the folder with no workers
NG=$(mktemp -d); WORKS="$WORKS $NG"; mkdir -p "$NG/.harness/asks"
sj -C "$NG" status --json --all
check "no git repo: exit 0" [ "$RC" -eq 0 ]
check "no git repo: the folder alone" jqt '(.folders | length == 1) and .folders[0].primary == true and .folders[0].workers == [] and .folders[0].branch == null' <<<"$OUT"
# verdict freshness: a reviewer report older than .current is a leftover of an earlier ask, so its VERDICT is not read
VT=$(mktemp -d); WORKS="$WORKS $VT"
mkrun "$VT" reviewer r-5 $((SJ_NOW - 100))
mkexit "$VT" r-5 reviewer
printf '# reviewer report\nstatus: done\nVERDICT: PASS\n' > $VT/.harness/reports/reviewer.md
at_mtime $((SJ_NOW - 5000)) $VT/.harness/reports/reviewer.md
at_mtime $((SJ_NOW - 100)) $VT/.harness/asks/reviewer.current
sj -C "$VT" status --json
check "stale reviewer report (older than .current): verdict null" jqt '.folders[0].workers[0] | .state == "exited" and .exit.rc == 0 and .exit.verdict == null' <<<"$OUT"
at_mtime $((SJ_NOW - 50)) $VT/.harness/reports/reviewer.md
sj -C "$VT" status --json
check "fresh reviewer report (newer than .current): verdict PASS" jqt '.folders[0].workers[0].exit.verdict == "PASS"' <<<"$OUT"
# start grace (pinned clock): just launched and no pid file for this ask yet counts as running
GT=$(mktemp -d); WORKS="$WORKS $GT"
mkrun "$GT" analyst g-1 $((SJ_NOW - 5))
sj -C "$GT" status --json
check "start grace: fresh .current, no .pid: running" jqt '.folders[0].workers[0].state == "running"' <<<"$OUT"
printf 'g-0 999999 999999\n' > $GT/.harness/asks/analyst.pid
sj -C "$GT" status --json
check "start grace: .pid of an older ask, within the grace: running" jqt '.folders[0].workers[0].state == "running"' <<<"$OUT"
mkrun "$GT" analyst g-1 $((SJ_NOW - 60))
sj -C "$GT" status --json
check "start grace: .pid of an older ask, past the grace: dead" jqt '.folders[0].workers[0].state == "dead"' <<<"$OUT"
mkrun "$GT" analyst g-2 $((SJ_NOW - 60))
rm -f $GT/.harness/asks/analyst.pid
sj -C "$GT" status --json
check "start grace: no .pid, past the grace: dead" jqt '.folders[0].workers[0].state == "dead"' <<<"$OUT"
# arguments: an unknown flag is a usage error, a plain extra word is ignored as before
sj status --bogus
check "status --bogus: usage error, exit 1" [ "$RC" -eq 1 ]
sj status extra
check "status extra: ignored, exit 0, text lines" [ "$RC" -eq 0 ]
check "status extra: same output as plain status" bash -c '[ "$1" = "$(HARNESS_DASH_NOW='"$SJ_NOW"' env -u HARNESS_ROLE /bin/bash "$2" status)" ]' _ "$OUT" "$HARNESS"
sj status --json extra
check "status --json extra: extra word ignored" jqt '.version == 1' <<<"$OUT"

# ---- step marker (#305 PR B): `STEP <n>` in an assistant text block -> .step ----
# The canonical instruction line lives in the three agent files; the test greps each for it verbatim.
STEP_LINE='- When you start a step of the brief'"'"'s `## Steps`, first write a text line on its own `STEP <n>` (n = the step number), then do the step; one marker per step, in order.'
for ag in analyst implementer reviewer; do
  check "agent $ag.md carries the STEP marker instruction verbatim" grep -qxF -- "$STEP_LINE" "$HERE/../claude/agents/$ag.md"
done
# evt_text ID TEXT — an assistant text event; evt_tool ID JSON-INPUT — a tool_use event
evt_text() { jq -n -c --arg id "$1" --arg t "$2" '{type:"assistant",message:{id:$id,content:[{type:"text",text:$t}]}}'; }
evt_tool() { jq -n -c --arg id "$1" --argjson i "$2" '{type:"assistant",message:{id:$id,content:[{type:"tool_use",name:"Bash",input:$i}]}}'; }
ST=$(mktemp -d); WORKS="$WORKS $ST"
mkrun "$ST" implementer s-1 $((SJ_NOW - 300))
printf '# Steps task\n\n## Steps\n1. one\n2. two\n3. three\n' > $ST/.harness/task-implementer.md
SR=.harness/log/s-implementer.jsonl
step_of() { sj -C "$ST" status --json; jq -c '.folders[0].workers[0].step' <<<"$OUT"; }
check "step: no marker -> null" [ "$(step_of)" = null ]
{ evt_text m3 'STEP 2'; } >> $ST/$SR
check "step: marker -> number" [ "$(step_of)" = 2 ]
sj -C "$ST" status --json
check "step: a number, not a string" jqt '.folders[0].workers[0].step | type == "number"' <<<"$OUT"
{ evt_text m4 'STEP 3'; } >> $ST/$SR
check "step: last marker wins" [ "$(step_of)" = 3 ]
{ evt_text m5 $'plain prose\nSTEP 1\nSTEP 2  \t\nmore'; } >> $ST/$SR
check "step: two markers in one block, trailing blanks: the last" [ "$(step_of)" = 2 ]
{ evt_text m6 'STEP 9'; } >> $ST/$SR
check "step: n above the step count ignored (previous valid stands)" [ "$(step_of)" = 2 ]
{ evt_text m7 'STEP 0'; evt_text m8 'STEP 03'; } >> $ST/$SR
check "step: n = 0 ignored, 03 is step 3" [ "$(step_of)" = 3 ]
{ evt_text m9 'STEP 2 done'; evt_text m10 'xSTEP 1'; evt_text m11 'step 1'; evt_text m12 'STEP'; evt_text m13 'STEP -1'; } >> $ST/$SR
check "step: near-miss lines are not markers" [ "$(step_of)" = 3 ]
# marker only inside a tool_use input, a tool_result, a user prompt, thinking: not a marker
mkrun "$ST" implementer s-2 $((SJ_NOW - 300))
{ evt_tool n1 '{"command":"echo","description":"x\nSTEP 2\ny"}'
  jq -n -c '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t",content:"STEP 2\nSTEP 1"}]}}'
  jq -n -c '{type:"user",message:{content:[{type:"text",text:"STEP 3"}]}}'
  jq -n -c '{type:"user",message:{content:"STEP 3"}}'
  jq -n -c '{type:"assistant",message:{id:"n2",content:[{type:"thinking",thinking:"STEP 2"}]}}'
  jq -n -c '{type:"system",subtype:"init",model:"STEP 2"}'
  printf 'STEP 2\n'; } >> $ST/$SR
check "step: marker only in tool input / tool_result / prompt / thinking / raw line -> null" [ "$(step_of)" = null ]
# brief without ## Steps -> null even with a marker
printf '# No steps\n\n## Goal\nx\n' > $ST/.harness/task-implementer.md
evt_text n3 'STEP 1' >> $ST/$SR
check "step: brief without Steps -> null" [ "$(step_of)" = null ]
sj -C "$ST" status --json
check "step: ... and steps is []" jqt '.folders[0].workers[0].steps == []' <<<"$OUT"
printf '# Steps task\n\n## Steps\n1. one\n2. two\n3. three\n' > $ST/.harness/task-implementer.md
check "step: Steps back -> number" [ "$(step_of)" = 1 ]
# .gz part: the stream only as <raw>.gz
gzip -c $ST/$SR > $ST/$SR.gz; rm -f $ST/$SR
check "step: read from a .gz stream" [ "$(step_of)" = 1 ]
rm -f $ST/$SR.gz
# exited worker keeps its step; a new ask (new log, even --keep) starts at null
mkrun "$ST" implementer s-3 $((SJ_NOW - 300)); evt_text n4 'STEP 2' >> $ST/$SR
mkexit "$ST" s-3 implementer
check "step: exited worker keeps the last marker" [ "$(step_of)" = 2 ]
sj -C "$ST" status --json
check "step: ... state is exited" jqt '.folders[0].workers[0].state == "exited"' <<<"$OUT"
mkrun "$ST" implementer s-4 $((SJ_NOW - 10))
# the window first: .stream still names the previous ask (s-3), whose log carries STEP 2
printf 's-3 .harness/log/s-new.jsonl\n' > $ST/.harness/asks/implementer.stream
cp $ST/$SR $ST/.harness/log/s-new.jsonl; evt_text n5 'STEP 2' >> $ST/.harness/log/s-new.jsonl
check "step: a new ask whose .stream is still the old ask's -> null" [ "$(step_of)" = null ]
printf 's-4 .harness/log/s-new.jsonl\n' > $ST/.harness/asks/implementer.stream
grep -v 'STEP' $ST/$SR > $ST/.harness/log/s-new.jsonl
check "step: a new ask (new log without a marker) -> null" [ "$(step_of)" = null ]
# the start window (#305 round 2): .current is the new ask, .stream still the old ask's -> every stream field null
mkrun "$ST" implementer x2 $((SJ_NOW - 3)); evt_text w1 'STEP 2' >> $ST/$SR
printf 'x1 %s\n' "$SR" > $ST/.harness/asks/implementer.stream
rm -f $ST/.harness/asks/implementer.exit.json
sj -C "$ST" status --json
check "start window: old .stream id -> state running, ask_id new" jqt '.folders[0].workers[0] | .state == "running" and .ask_id == "x2"' <<<"$OUT"
check "start window: step, turns, ctx, model, now, idle_s all null" jqt '.folders[0].workers[0] | .step == null and .turns == null and .ctx == null and .model == null and .now == null and .idle_s == null' <<<"$OUT"
printf 'x2 %s\n' "$SR" > $ST/.harness/asks/implementer.stream
sj -C "$ST" status --json
check "matching .stream id: values present" jqt '.folders[0].workers[0] | .step == 2 and .turns > 0 and .model == "sonnet" and .ctx > 0' <<<"$OUT"
# sub-agent (sidechain) messages do not move the step
mkrun "$ST" implementer x3 $((SJ_NOW - 3)); evt_text w2 'STEP 1' >> $ST/$SR
jq -n -c '{type:"assistant",parent_tool_use_id:"toolu_1",message:{id:"sc1",content:[{type:"text",text:"STEP 3"}]}}' >> $ST/$SR
check "step: a sub-agent message (parent_tool_use_id) is ignored" [ "$(step_of)" = 1 ]
jq -n -c '{type:"assistant",parent_tool_use_id:null,message:{id:"sc2",content:[{type:"text",text:"STEP 2"}]}}' >> $ST/$SR
check "step: parent_tool_use_id null still counts" [ "$(step_of)" = 2 ]
# dash Steps of a finished worker: rc 0 -> last step done (✓), other rc or no exit record -> ▶ stays
printf '# Steps task\n\n## Steps\n1. one\n2. two\n3. three\n' > $ST/.harness/task-implementer.md
mkrun "$ST" implementer x4 $((SJ_NOW - 300)); evt_text w3 'STEP 2' >> $ST/$SR
mkexit "$ST" x4 implementer
cd "$ST"; OUT=$(HARNESS_DASH_FINAL=1 HARNESS_DASH_NOW=$SJ_NOW HARNESS_DASH_LINES=30 HARNESS_DASH_COLS=70 PATH="$HERE/../bin:$PATH" hl_dash_frame implementer "$SR"); cd "$P"
check "dash Steps: exited rc 0 -> last marked step done" bash -c 'sed -n "/── Steps/,/── Verify/p" <<<"$1" | tr "\n" "|" | grep -qF "── Steps ──|  ✓ 1. one|  ✓ 2. two|    3. three|"' _ "$OUT"
sed -i.bak 's/"rc":0/"rc":1/' $ST/.harness/asks/implementer.exit.json; rm -f $ST/.harness/asks/implementer.exit.json.bak
cd "$ST"; OUT=$(HARNESS_DASH_FINAL=1 HARNESS_DASH_NOW=$SJ_NOW HARNESS_DASH_LINES=30 HARNESS_DASH_COLS=70 PATH="$HERE/../bin:$PATH" hl_dash_frame implementer "$SR"); cd "$P"
check "dash Steps: exited rc 1 -> ▶ stays" bash -c 'sed -n "/── Steps/,/── Verify/p" <<<"$1" | tr "\n" "|" | grep -qF "── Steps ──|  ✓ 1. one|  ▶ 2. two|    3. three|"' _ "$OUT"
rm -f $ST/.harness/asks/implementer.exit.json
cd "$ST"; OUT=$(HARNESS_DASH_FINAL=1 HARNESS_DASH_NOW=$SJ_NOW HARNESS_DASH_LINES=30 HARNESS_DASH_COLS=70 PATH="$HERE/../bin:$PATH" hl_dash_frame implementer "$SR"); cd "$P"
check "dash Steps: dead (no exit record) -> ▶ stays" bash -c 'sed -n "/── Steps/,/── Verify/p" <<<"$1" | tr "\n" "|" | grep -qF "  ▶ 2. two|"' _ "$OUT"
# Now: a bare marker is skipped as the summary of a tool call; marker + prose keeps the prose
mkrun "$ST" implementer s-5 $((SJ_NOW - 10))
{ evt_text p1 $'Reading the code now'; evt_text p2 'STEP 2'; evt_tool p3 '{"command":"ls"}'; } >> $ST/$SR
sj -C "$ST" status --json
check "now: bare marker skipped, previous text is the summary" jqt '.folders[0].workers[0].now == "Reading the code now"' <<<"$OUT"
mkrun "$ST" implementer s-6 $((SJ_NOW - 10))
{ evt_text q1 $'STEP 2\nDoing the second thing'; evt_tool q2 '{"command":"ls"}'; } >> $ST/$SR
sj -C "$ST" status --json
check "now: marker line stripped, prose kept" jqt '.folders[0].workers[0].now == "Doing the second thing"' <<<"$OUT"
mkrun "$ST" implementer s-7 $((SJ_NOW - 10))
{ evt_text r1 'STEP 1'; } >> $ST/$SR
sj -C "$ST" status --json
check "now: a bare marker as the last item falls back to the earlier item" jqt '.folders[0].workers[0].now == "Run the \"dash\" suite"' <<<"$OUT"
# the dashboard: Now never shows a bare marker; the marker line stays in Recent (harness-view prints texts as is)
cd "$ST"; frame 30 70 implementer "$SR"; cd "$P"
check "dash: Now has no bare marker line" bash -c '! sed -n "/── Now/,/── Steps/p" <<<"$1" | grep -q "STEP 1"' _ "$OUT"
check "dash: Recent keeps the marker line" bash -c 'sed -n "/── Recent/,\$p" <<<"$1" | grep -qx "  STEP 1"' _ "$OUT"

# dash: the Steps block marks done (✓) and current (▶) steps from the marker; no marker leaves it as it was
printf '# Steps task\n\n## Steps\n1. one\n2. two\n3. three\n' > $ST/.harness/task-implementer.md
mkrun "$ST" implementer s-8 $((SJ_NOW - 10)); evt_text u1 'STEP 2' >> $ST/$SR
cd "$ST"; frame 30 70 implementer "$SR"; cd "$P"
check "dash Steps: done ✓, current ▶, pending plain" bash -c 'sed -n "/── Steps/,/── Verify/p" <<<"$1" | tr "\n" "|" | grep -qF "── Steps ──|  ✓ 1. one|  ▶ 2. two|    3. three|"' _ "$OUT"
mkrun "$ST" implementer s-9 $((SJ_NOW - 10))
cd "$ST"; frame 30 70 implementer "$SR"; cd "$P"
check "dash Steps: no marker, no marks" bash -c 'sed -n "/── Steps/,/── Verify/p" <<<"$1" | tr "\n" "|" | grep -qF "── Steps ──|  1. one|  2. two|  3. three|"' _ "$OUT"
printf '# H task\n\n## Goal\nx\n\n## Done\ny\n' > $ST/.harness/task-implementer.md
evt_text u2 'STEP 1' >> $ST/$SR
cd "$ST"; frame 30 70 implementer "$SR"; cd "$P"
check "dash Steps: headings fallback is never marked" bash -c 'sed -n "/── Steps/,/── Verify/p" <<<"$1" | tr "\n" "|" | grep -qF "── Steps ──|  1. Goal|  2. Done|"' _ "$OUT"

# golden: the full document of the representative fixture (path normalised) is the checked-in file the mod reads too
GOLD="$HERE/fixtures/status-v1.json"
mkrun "$P" reviewer r-1 $((SJ_NOW - 100))
printf '# reviewer report\nstatus: done\nVERDICT: PASS\n' > $P/.harness/reports/reviewer.md
mkexit "$P" r-1 reviewer
# one golden worker carries a marker (same message id as m1: turns/ctx stay as they were)
evt_text m1 'STEP 2' >> $P/.harness/log/s-implementer.jsonl
sj status --json
jq -S --arg p "$P" '.folders[0].path = "/FIXTURE"' <<<"$OUT" > "$WORK/gold.out"
if [ -n "${GOLDEN_UPDATE:-}" ]; then cp "$WORK/gold.out" "$GOLD"; fi
check "golden: status --json equals tests/fixtures/status-v1.json" cmp -s "$WORK/gold.out" "$GOLD"
kill $SJ_LIVE $SJ_LIVE2 2>/dev/null; wait $SJ_LIVE $SJ_LIVE2 2>/dev/null

echo "dash: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
