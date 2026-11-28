# harness-dash.sh — the viewer dashboard frame for `harness watch <role>` (a live run).
# Sourced eagerly by bin/harness: definitions only, no side effects. hl_dash_frame is a pure
# render (inputs: .harness/asks/<role>.*, the stream, verify/<role>.*) -> text on stdout; the
# redraw loop lives in cmd_watch. bash 3.2 + jq; Recent reuses harness-view (PATH).

# dash_fmt_dur <seconds> — 45s | 12m04s | 1h02m
dash_fmt_dur() {
  local s=${1:-0}
  case "$s" in ''|*[!0-9]*) s=0 ;; esac
  if [ "$s" -ge 3600 ]; then printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  elif [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60))
  else printf '%ds' "$s"; fi
}

# dash_min A B
dash_min() { if [ "$1" -lt "$2" ]; then echo "$1"; else echo "$2"; fi; }

# dash_now — epoch seconds; HARNESS_DASH_NOW pins the clock (tests)
dash_now() { if [ -n "${HARNESS_DASH_NOW:-}" ]; then printf '%s' "$HARNESS_DASH_NOW"; else date +%s; fi; }

# dash_brief_file <prompt> — the first existing .md under a .harness/ directory that the prompt names
# (absolute or relative, e.g. "Read /abs/.harness/task-67.md"); nothing when none
dash_brief_file() {
  local tok
  for tok in $(grep -oE '[^[:space:]`"'"'"'()]*\.harness/[^[:space:]`"'"'"'()]*\.md' "$1" 2>/dev/null); do
    case "$tok" in */../*|*/..|../*) continue ;; esac
    case "$tok" in .harness/*|*/.harness/*) ;; *) continue ;; esac
    if [ -f "$tok" ]; then printf '%s\n' "$tok"; return 0; fi
  done
  return 1
}

# dash_brief <role> — title line, then "T<TAB>title-ko" (a `Title-ko:` line above the first `## `), then
# "S<TAB>step" / "H<TAB>heading" lines, then "K<TAB>n<TAB>ko" for each step that ends in `[ko: ...]` (the
# suffix is cut from the S line). The brief is the task
# file only when the ask's prompt names one under .harness/; otherwise the prompt text itself (first line, no steps).
dash_brief() {
  local role=$1 p="$ASK_DIR/$1.prompt" f
  if f=$(dash_brief_file "$p"); then
    awk '
      BEGIN { t = ""; sec = 0; tk = ""; top = 1 }
      top && tk == "" && /^Title-ko:/ { tk = $0; sub(/^Title-ko:[ \t]*/, "", tk); sub(/[ \t\r]+$/, "", tk); gsub(/\t/, " ", tk) }
      /^# / && t == "" { t = substr($0, 3); next }
      /^## / { top = 0; h[++nh] = substr($0, 4); sec = ($0 ~ /^## Steps[ \t]*$/); next }
      sec && /^[0-9]+[.)] / {
        s = $0; sub(/^[0-9]+[.)] +/, "", s); ++k
        if (match(s, /[ \t]*\[ko:[^]]*\][ \t]*$/)) {
          ko = substr(s, RSTART, RLENGTH); s = substr(s, 1, RSTART - 1)
          sub(/^[ \t]*\[ko:[ \t]*/, "", ko); sub(/[ \t]*\][ \t]*$/, "", ko); gsub(/\t/, " ", ko)
          if (ko != "") kos[k] = ko
        }
        st[++ns] = k ". " s
      }
      END {
        print (t == "" ? "(untitled brief)" : t)
        if (tk != "") print "T\t" tk
        if (ns > 0) { for (i = 1; i <= ns; i++) print "S\t" st[i] }
        else { for (i = 1; i <= nh; i++) print "H\t" h[i] }
        for (i = 1; i <= ns; i++) if (i in kos) print "K\t" i "\t" kos[i]
      }' "$f"
  else
    awk 'NR == 1 { print; exit }' "$p" 2>/dev/null
  fi
}

# dash_facts <raw> — one JSON object of what the stream says (model, turns, ctx, now, verify, markers).
# markers: the n of every `STEP <n>` line of an assistant text block, in order (workers write one when they
# start a step of the brief); status --json maps the last valid one to step. Texts that are only markers
# are dropped from now, marker lines are cut from the rest.
dash_facts() {
  local raw=$1
  { if [ -f "$raw" ]; then cat "$raw"; elif [ -f "$raw.gz" ]; then gzip -dc "$raw.gz"; fi; } 2>/dev/null | jq -R -n -c '
    def first_line: tostring | split("\n")[0];
    [inputs | fromjson? | select(type == "object")] as $e
    | ([$e[] | select(.type == "system" and .subtype == "init")] | first) as $i
    | [$e[] | select(.type == "assistant")] as $a
    | ([$a[] | .message.usage?] | map(select(. != null)) | last) as $u
    | [$a[] | select(.parent_tool_use_id == null) | (.message.content // [])[] | select(.type == "text") | (.text // "" | tostring) | scan("(?m)^STEP ([0-9]+)[ \t]*$") | .[0] | tonumber] as $mk
    | [$a[] | (.message.content // [])[]
       | if .type == "text" then .text = ((.text // "" | tostring) | split("\n") | map(select(test("^STEP [0-9]+[ \t]*$") | not)) | join("\n")) else . end
       | select((.type == "text" and (.text | test("\\S"))) or .type == "tool_use")] as $it
    | ($it | last) as $n | ($it | if length > 1 then .[-2] else null end) as $p
    | ([$e[] | select(.type == "system" and .hook_event == "Stop" and (.subtype == "hook_started" or .subtype == "hook_response"))] | last) as $h
    | {model: ($i.model // "?"),
       markers: $mk,
       turns: ([$a | to_entries[] | (.value.message.id // "n\(.key)")] | unique | length),
       ctx: (if $u then (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0)) else 0 end),
       now: (if $n == null then {sum: "", detail: ""}
             elif $n.type == "text" then {sum: "", detail: $n.text}
             else ($n.input // {}) as $in
               | ($in | (.command // .file_path // .pattern // .url // .path // "") | tostring) as $known
               | (if $known != "" then $known elif ($in | type) == "object" and ($in | length) > 0 then ($in | tojson) else "" end) as $arg
               | "\($n.name // "?") \($arg | first_line)" as $fb
               | {sum: (if ((($in.description // "") | tostring) | test("\\S")) then ($in.description | first_line)
                        elif ($p != null and $p.type == "text") then ($p.text | split("\n") | map(select(test("\\S"))) | .[0] // "")
                        else $fb end)} as $o
               | $o + {detail: (if $o.sum == $fb and (($n.name // "") | IN("Read", "Edit", "Write")) then "" else $arg end)} end),
       verify: (if $h == null then "none"
                elif $h.subtype == "hook_started" then "running"
                elif ([($h.stdout // "") | fromjson? | select(type == "object" and .decision == "block" and ((.reason // "") | test("\\.harness/reports/")))] | length > 0) then "report"
                elif (($h.exit_code // 0) != 0) or ([($h.stdout // "") | fromjson? | select(type == "object" and .decision == "block")] | length > 0) then "fail"
                else "pass" end)}'
}

# --- `harness status --json [--all]` (#305): machine-readable worker state, version 1 (docs/reference.md) ---
# Pure read of <folder>/.harness/ (cwd = the folder): writes, creates and locks nothing.

# st_starting <role> <id> <start> <now> — hl_starting on the pinned clock: just launched, no pid file for this ask yet
st_starting() {
  grep -q "^$2 " "$ASK_DIR/$1.pid" 2>/dev/null && return 1
  digits_only "${3:-}" && [ $(( $4 - $3 )) -lt "${HARNESS_HL_START_S:-15}" ]
}

# st_worker_json <role> — one compact worker object; nothing when the role has no .current here
st_worker_json() {
  local role=$1 a="$ASK_DIR/$1" id start state raw="" facts="" brief="" ej="" rep verdict="" now
  [ -f "$a.current" ] || return 0
  read -r id start _ < "$a.current" 2>/dev/null
  now=$(dash_now)
  if hl_alive "$role" || st_starting "$role" "${id:-}" "${start:-}" "$now"; then state=running
  elif hl_done "$role" "${id:-}"; then state=exited
  else state=dead; fi
  raw=$(hl_stream_of "$role")
  # a stream counts only when .stream names this ask: between `ask` writing .current and the runner writing
  # .stream, hl_stream_of falls back to the previous ask's log, and its values must not show under the new id
  [ "$(hl_stream_id "$role")" = "${id:-}" ] || raw=""
  if [ -n "$raw" ] && { [ -f "$raw" ] || [ -f "$raw.gz" ]; }; then facts=$(dash_facts "$raw"); else raw=""; fi
  brief=$(dash_brief "$role" 2>/dev/null)
  [ "$state" != exited ] || ej=$(cat "$a.exit.json" 2>/dev/null)
  rep=".harness/reports/$role.md"
  if [ "$state" = exited ] && [ "$role" = reviewer ] && [ -f "$rep" ] && ! [ "$rep" -ot "$a.current" ]; then
    verdict=$(awk 'NF { l = $0 } END { print l }' "$rep" 2>/dev/null)
  fi
  local idle=""
  if [ "$state" = running ] && [ -n "$raw" ] && [ -f "$raw" ] && idle=$(file_mtime "$raw"); then idle=$((now - idle)); else idle=""; fi
  jq -n -c --arg role "$role" --arg state "$state" --arg id "${id:-}" --argjson start "$(num_or_null "${start:-}")" \
    --argjson now "$now" --argjson idle "$(num_or_null "$idle")" --arg facts "$facts" --arg brief "$brief" \
    --arg ej "$ej" --arg verdict "$verdict" '
    def num: if type == "number" then . else null end;
    def str: if type == "string" and . != "" then . else null end;
    def obj: if type == "object" then . else {} end;
    ($facts | (try fromjson catch {}) | obj) as $f
    | ($ej | (try fromjson catch {}) | obj) as $e
    | ($brief | split("\n")) as $bl
    | ([$bl[1:][] | select(startswith("K\t")) | .[2:] | capture("^(?<n>[0-9]+)\t(?<k>.*)$")? | {key: .n, value: .k}] | from_entries) as $ko
    | {role: $role, state: $state, ask_id: ($id | str), started_at: $start,
       elapsed_s: (if $state == "running" and $start != null then ([$now - $start, 0] | max)
                   elif $state == "exited" and ($e.duration_ms | num) != null then (($e.duration_ms / 1000) | floor)
                   else null end),
       idle_s: (if $idle == null then null else ([$idle, 0] | max) end),
       turns: ($f.turns | num), ctx: ($f.ctx | num),
       model: (if ($f.model // "?") == "?" then null else ($f.model | str) end),
       brief_title: (($bl[0] // "") | if . == "(untitled brief)" then "" else . end | str),
       now: (if $state == "running" then (($f.now // {}) | ([.sum, (.detail // "" | split("\n") | map(select(test("\\S"))) | .[0])] | map(select(type == "string" and test("\\S"))) | .[0] // null) | if . == null then null else .[0:120] end) else null end),
       title_ko: ([$bl[1:][] | select(startswith("T\t")) | .[2:] | select(. != "")] | first // null),
       steps: [$bl[1:][] | select(startswith("S\t")) | .[2:] | capture("^(?<n>[0-9]+)[.] (?<t>.*)$")? | {n: (.n | tonumber), text: .t, ko: ($ko[.n] // null)}],
       step: ([($f.markers // [])[] | select(type == "number" and . >= 1 and . <= ($bl[1:] | map(select(startswith("S\t"))) | length))] | last),
       verify: ($f.verify | if . == "running" or . == "pass" or . == "fail" then . else null end),
       exit: (if $state == "exited" then {rc: ($e.rc | num), result: ($e.result | str), cost_usd: ($e.cost_usd | num),
                duration_s: (if ($e.duration_ms | num) != null then (($e.duration_ms / 1000) | floor) else null end),
                verdict: (if $role == "reviewer" and ($verdict == "VERDICT: PASS" or $verdict == "VERDICT: FAIL") then ($verdict | ltrimstr("VERDICT: ")) else null end)} else null end)}' 2>/dev/null
}

# st_folder_json <primary 0|1> <branch> — the folder object for the cwd, workers in role order
st_folder_json() {
  local prim=$1 br=${2:-} role w="" lane=""
  for role in $AGENTS; do w="$w$(st_worker_json "$role")"$'\n'; done
  case "$br" in feat/[0-9]*-*|fix/[0-9]*-*|docs/[0-9]*-*) lane=${br#*/}; lane=${lane%%-*} ;; esac
  { [ "$prim" = 0 ] && digits_only "$lane"; } || lane=""
  printf '%s' "$w" | jq -s -c --arg path "$(pwd -P)" --argjson primary "$([ "$prim" = 1 ] && echo true || echo false)" \
    --arg branch "${br#refs/heads/}" --argjson lane "$(num_or_null "$lane")" \
    '{path: $path, primary: $primary, lane: $lane, branch: (if $branch == "" then null else $branch end), workers: .}'
}

# dash_status_json <all 0|1> — the whole document (one line) on stdout
dash_status_json() {
  local all=$1 here rows p b first=1 docs="" cur
  here=$(pwd -P)
  rows=$(lane_all_rows 2>/dev/null)
  if [ "$all" = 1 ] && [ -n "$rows" ]; then
    while IFS=$'\t' read -r p b; do
      if [ -d "$p/.harness/asks" ]; then docs="$docs$(cd "$p" 2>/dev/null && st_folder_json "$first" "$b")"$'\n'; fi
      first=0
    done <<<"$rows"
  else
    cur=$(printf '%s\n' "$rows" | awk -F'\t' -v h="$here" '$1 == h { print NR "\t" $2; exit }')   # row number, branch
    if [ -n "$cur" ]; then
      b=${cur#*$'\t'}
      if [ "${cur%%$'\t'*}" = 1 ]; then first=1; else first=0; fi
    else
      b=$(git symbolic-ref -q --short HEAD 2>/dev/null || true)
      if git rev-parse --git-dir >/dev/null 2>&1 && ! lane_in_primary; then first=0; else first=1; fi
    fi
    docs="$(st_folder_json "$first" "$b")"$'\n'
  fi
  printf '%s' "$docs" | jq -s -c --argjson now "$(dash_now)" '{version: 1, generated_at: $now, folders: .}'
}

# jq def cw: display columns of a code point (2 = East-Asian Wide/Fullwidth; deliberately conservative: all of
# U+1F000-1FAFF counts 2, overcounting only clips a line early). Autowrap is off while drawing (dash_begin).
DASH_JQ_CW='def cw: [[4352,4447],[8986,8987],[9001,9002],[9193,9196],[9200,9200],[9203,9203],[9725,9726],[9748,9749],
  [9800,9811],[9855,9855],[9875,9875],[9889,9889],[9898,9899],[9917,9918],[9924,9925],[9934,9934],[9940,9940],
  [9962,9962],[9970,9973],[9978,9978],[9981,9981],[9989,9989],[9994,9995],[10024,10024],[10060,10060],
  [10062,10062],[10067,10069],[10071,10071],[10133,10135],[10160,10160],[10175,10175],[11035,11036],
  [11088,11088],[11093,11093],[11904,12350],[12353,13311],[13312,19903],[19968,40959],[40960,42191],
  [44032,55203],[63744,64255],[65040,65049],[65072,65131],[65280,65376],[65504,65510],[126976,129791],
  [131072,262141]] as $r
  | . as $c | if any($r[]; $c >= .[0] and $c <= .[1]) then 2 else 1 end;
# jq def ctl: C0 controls (except \t, handled apart; \n splits lines), DEL and C1 shown as "·", so stream text can
# never drive the terminal (ESC sequences, \r) from inside the frame
def ctl: gsub("[\u0001-\u0008\u000b-\u001f\u007f-\u009f]"; "·");
'

# dash_wrap <width> <max-lines> — stdin text -> wrapped lines on stdout (by display width, never cut: the rest
# continues on the next line). Blank lines are dropped, tabs become 2 spaces; when more than <max-lines> remain,
# the last kept line ends with "…".
dash_wrap() {
  jq -R -r -s --argjson w "$(( $1 > 2 ? $1 : 2 ))" --argjson m "$2" "$DASH_JQ_CW"'
    def wrapline($n): explode | reduce .[] as $c ({w: 0, cur: [], out: []};
        ($c | cw) as $k | if .w + $k > $n and (.cur | length) > 0 then .out += [.cur] | .cur = [$c] | .w = $k
                          else .cur += [$c] | .w += $k end) | (.out + [.cur]) | map(implode);
    split("\n") | map(gsub("\t"; "  ") | ctl | select(test("\\S"))) | map(wrapline($w)) | add // []
    | if length > $m then .[0:$m] | .[-1] |= ((wrapline($w - 1) | .[0]) + "…") else . end | .[]'
}

# dash_size — "H W" of the pane, read fresh on every call: HARNESS_DASH_LINES / HARNESS_DASH_COLS (tests only;
# deliberately not LINES/COLUMNS, which an exported shell value would freeze), else the controlling tty
# (tput inside $(...) has no tty on stdout), else tput, else 24x80. A single override is honoured alone.
dash_size() {
  local sz="" H W
  [ -n "${HARNESS_DASH_LINES:-}" ] && [ -n "${HARNESS_DASH_COLS:-}" ] || sz=$({ stty size </dev/tty; } 2>/dev/null)
  H=${HARNESS_DASH_LINES:-${sz%% *}}; W=${HARNESS_DASH_COLS:-${sz##* }}
  [ -n "$H" ] || H=$(env -u LINES -u COLUMNS tput lines 2>/dev/null); [ -n "$W" ] || W=$(env -u LINES -u COLUMNS tput cols 2>/dev/null)
  case "$H" in ''|*[!0-9]*|0) H=24 ;; esac
  case "$W" in ''|*[!0-9]*|0) W=80 ;; esac
  echo "$H $W"
}

# dash_nap <seconds> — sleep that a trapped signal (WINCH, INT, ...) interrupts at once (a foreground sleep would
# delay the trap until it returns)
dash_nap() { sleep "$1" & DASH_NAP_PID=$!; wait "$DASH_NAP_PID" 2>/dev/null; kill "$DASH_NAP_PID" 2>/dev/null; return 0; }

# hl_dash_frame <role> <raw> — the dashboard text. Size: dash_size (read per frame). Final frame (result + report head) when the run is not
# live: HARNESS_DASH_FINAL=1 forces it, else hl_alive decides.
hl_dash_frame() {
  local role=$1 raw=$2 a="$ASK_DIR/$1" H W id start facts model turns ctx verify now_s dur final=0
  read -r H W <<<"$(dash_size)"
  read -r id start _ < "$a.current" 2>/dev/null
  if [ "${HARNESS_DASH_FINAL:-}" = 1 ] || ! hl_alive "$role"; then final=1; fi
  facts=$(dash_facts "$raw"); [ -n "$facts" ] || facts='{"model":"?","turns":0,"ctx":0,"now":{"sum":"","detail":""},"verify":"none"}'
  model=$(jq -r '.model' <<<"$facts"); turns=$(jq -r '.turns' <<<"$facts")
  ctx=$(jq -r 'if .ctx >= 1000 then "\((.ctx / 1000) | round)k" else "\(.ctx)" end' <<<"$facts")
  verify=$(jq -r '.verify' <<<"$facts")
  # the exit record / report count only when they belong to this ask (not left over from an earlier one)
  local exit_ok=0 rep_ok=0
  if [ -f "$a.exit.json" ] && grep -q "\"ask_id\":\"$id\"" "$a.exit.json" 2>/dev/null; then exit_ok=1; fi
  if [ -f ".harness/reports/$role.md" ] && ! [ ".harness/reports/$role.md" -ot "$a.current" ]; then rep_ok=1; fi
  if [ "$final" = 1 ] && [ "$exit_ok" = 1 ]; then
    dur=$(jq -r '((.duration_ms // 0) / 1000) | floor' "$a.exit.json" 2>/dev/null)
  elif digits_only "${start:-}"; then dur=$(( $(dash_now) - start ))
  else dur=0; fi

  local bt brief_lines steps="" heads="" l k
  brief_lines=$(dash_brief "$role")
  bt=$(printf '%s\n' "$brief_lines" | sed -n 1p)
  while IFS=$'\t' read -r k l; do
    case "$k" in S) steps="$steps$l"$'\n' ;; H) heads="$heads$l"$'\n' ;; esac
  done <<<"$(printf '%s\n' "$brief_lines" | sed 1d)"
  # a STEP marker from the stream marks the brief's own steps: ✓ done, ▶ current (headings are never marked)
  local cur=""
  if [ -n "$steps" ]; then
    cur=$(jq -r --argjson n "$(printf '%s' "$steps" | grep -c '')" '[(.markers // [])[] | select(type == "number" and . >= 1 and . <= $n)] | last // empty' <<<"$facts")
    # an ask that ended with rc 0 has finished its marked step: ✓; a failed or dead one keeps ▶
    local fin=0; [ "$final" != 1 ] || [ "$exit_ok" != 1 ] || [ "$(jq -r '.rc // empty' "$a.exit.json" 2>/dev/null)" != 0 ] || fin=1
    [ -z "$cur" ] || steps=$(printf '%s' "$steps" | awk -v c="$cur" -v d="$fin" '{ printf "%s%s\n", (NR < c || (NR == c && d) ? "✓ " : NR == c ? "▶ " : "  "), $0 }')
  else steps=$(printf '%s' "$heads" | awk '{ print NR ". " $0 }'); fi
  [ -z "$steps" ] || steps=${steps%$'\n'}
  steps=$(printf '%s\n' "$steps" | sed '/^$/d' | head -n 10)

  # verify text: the step of a failed run comes from verify/<role>.json when present
  local vtxt
  case "$verify" in
    none) vtxt="not started" ;;
    running) vtxt="verifying…" ;;
    pass) vtxt="pass" ;;
    report) vtxt="waiting for report" ;;
    *) vtxt="fail"
       if ! [ ".harness/verify/$role.json" -ot "$a.current" ]; then
         l=$(jq -r '.step // empty' ".harness/verify/$role.json" 2>/dev/null)
         [ -z "$l" ] || vtxt="fail ($l)"
       fi ;;
  esac

  # diff (implementer only): git diff --stat against the base sha of the ask
  local diff="" dwant=0 base
  if [ "$role" = implementer ]; then
    base=$(sed -n 1p ".harness/verify/$role.base" 2>/dev/null)
    if [ -n "$base" ]; then
      diff=$(git diff --stat "$base" -- . ':(exclude).harness' 2>/dev/null)
      [ -n "$diff" ] || diff="(no changes)"
    else diff="(no baseline)"; fi
    dwant=$(( $(printf '%s\n' "$diff" | wc -l) + 1 ))
    [ "$dwant" -le 6 ] || dwant=6
  fi

  # line budget, in the order of keeping: header, brief, now/result, steps, verify, diff, recent/report
  local rem=$H hdr=1 abrief=0 anow=0 asteps=0 averify=0 adiff=0 arecent=0 want
  rem=$((rem - 1)); [ "$rem" -ge 0 ] || rem=0
  [ "$rem" -lt 1 ] || { abrief=1; rem=$((rem - 1)); }
  # Now = summary line + the full command/text wrapped (<= 6 lines): the minimum (summary + 1 detail line) is
  # kept before Steps; the other detail lines come after Diff and before Recent
  local nsum=0 dl="" dn=0 xdet=0 dind="    " nmin=1
  if [ "$final" != 1 ]; then
    l=$(jq -r '.now.sum' <<<"$facts"); [ -z "$l" ] || nsum=1
    [ "$nsum" = 1 ] || dind="  "
    dl=$(jq -r '.now.detail' <<<"$facts" | dash_wrap $((W - 1 - ${#dind})) 6 | sed "s/^/$dind/")
    [ -z "$dl" ] || dn=$(printf '%s\n' "$dl" | wc -l | tr -d ' ')
    nmin=$((nsum + (dn > 0 ? 1 : 0))); [ "$nmin" -ge 1 ] || nmin=1
  fi
  anow=$(dash_min $((nmin + 1)) "$rem"); [ "$final" = 1 ] && anow=$(dash_min 1 "$rem")
  [ "$anow" -ge 2 ] || [ "$final" = 1 ] || anow=0
  rem=$((rem - anow))
  want=$(( $(printf '%s\n' "$steps" | sed '/^$/d' | wc -l) ))
  if [ "$want" -gt 0 ]; then asteps=$(dash_min $((want + 1)) "$rem"); [ "$asteps" -ge 2 ] || asteps=0; rem=$((rem - asteps)); fi
  [ "$rem" -lt 1 ] || { averify=1; rem=$((rem - 1)); }
  if [ "$dwant" -gt 0 ]; then adiff=$(dash_min "$dwant" "$rem"); [ "$adiff" -ge 2 ] || adiff=0; rem=$((rem - adiff)); fi
  if [ "$final" != 1 ] && [ "$anow" -ge "$((nmin + 1))" ] && [ "$dn" -gt 1 ]; then
    xdet=$(dash_min $((dn - 1)) "$rem"); anow=$((anow + xdet)); rem=$((rem - xdet))
  fi
  [ "$rem" -ge 2 ] && arecent=$rem

  local out="" sec="── "
  # idle: seconds since the stream last grew (file mtime), shown from 10 s while the run is live
  local idle="" mt
  if [ "$final" != 1 ] && [ -f "$raw" ] && mt=$(file_mtime "$raw") && [ $(( $(dash_now) - mt )) -ge 10 ]; then
    idle=" · idle $(dash_fmt_dur $(( $(dash_now) - mt )))"
  fi
  out=$(printf '%s  %s  ⏱ %s%s  turns %s  ctx %s  %s' "$role" "${id:-?}" "$(dash_fmt_dur "$dur")" "$idle" "$turns" "$ctx" "$model")
  [ "$abrief" -eq 0 ] || out="$out"$'\n'"${sec}Brief ── $bt"
  if [ "$final" = 1 ]; then
    if [ "$anow" -ge 1 ]; then
      if [ "$exit_ok" = 1 ]; then
        l=$(jq -r '"■ \(.result // "ended") · rc \(.rc // "?") · \(.num_turns // 0) turns · \(((.duration_ms // 0) / 1000) | floor)s · $\(.cost_usd // 0)"' "$a.exit.json" 2>/dev/null)
      else l="■ ended (no result)"; fi
      out="$out"$'\n'"${sec}Result ── $l"
    fi
  elif [ "$anow" -ge 2 ]; then
    l=$(jq -r '.now.sum' <<<"$facts" | sed '/^$/d' | sed 's/^/  → /')
    [ -z "$dl" ] || l="${l:+$l$'\n'}$(printf '%s\n' "$dl" | head -n $((anow - 1 - nsum)))"
    [ -n "$l" ] || l="  (waiting for output)"
    out="$out"$'\n'"${sec}Now ──"$'\n'"$l"
  fi
  if [ "$asteps" -ge 2 ]; then
    out="$out"$'\n'"${sec}Steps ──"$'\n'"$(printf '%s\n' "$steps" | head -n $((asteps - 1)) | sed 's/^/  /')"
  fi
  [ "$averify" -eq 0 ] || out="$out"$'\n'"${sec}Verify ── $vtxt"
  if [ "$adiff" -ge 2 ]; then
    local nd=$((adiff - 1)) total
    total=$(printf '%s\n' "$diff" | wc -l)
    if [ "$total" -gt "$nd" ]; then diff=$({ [ "$nd" -le 1 ] || printf '%s\n' "$diff" | sed -n "1,$((nd - 1))p"; printf '%s\n' "$diff" | tail -n 1; }); fi
    out="$out"$'\n'"${sec}Diff ──"$'\n'"$(printf '%s\n' "$diff" | sed 's/^/  /')"
  fi
  if [ "$arecent" -ge 2 ]; then
    if [ "$final" = 1 ]; then
      l=""; [ "$rep_ok" != 1 ] || l=$(head -n $((arecent - 1)) ".harness/reports/$role.md" 2>/dev/null)
      [ -n "$l" ] || l="(no report)"
      out="$out"$'\n'"${sec}Report ──"$'\n'"$(printf '%s\n' "$l" | sed 's/^/  /')"
    else
      l=$(tail -n 400 "$raw" 2>/dev/null | harness-view 2>/dev/null | tail -n $((arecent - 1)) | sed 's/^/  /')
      [ -z "$l" ] || out="$out"$'\n'"${sec}Recent ──"$'\n'"$l"
    fi
  fi
  # cut by display width (East-Asian Wide/Fullwidth incl. emoji = 2 columns; jq works in code points, bash 3.2
  # ${v:0:n} in bytes) so no line wraps; a line is clipped, never wrapped. Tabs become 2 spaces first.
  # Cut at W-1 columns: the trailing \033[K (dash_paint) must never erase the last glyph with autowrap off.
  printf '%s\n' "$out" | jq -R -r --argjson w "$((W > 1 ? W - 1 : 1))" "$DASH_JQ_CW"'
    gsub("\t"; "  ") | ctl | explode | reduce .[] as $c ({w: 0, o: [], f: false};
      if .f then . else ($c | cw) as $k | if .w + $k > $w then .f = true else .w += $k | .o += [$c] end end)
    | .o | implode'
}

# dash_begin / dash_end — hide the cursor and turn terminal autowrap off while the loop draws, so a width
# miscount can only cut a line short, never wrap or scroll; dash_end restores both and ends the line
# dash_end is idempotent (traps + normal exit may both call it): only the first call after dash_begin prints
DASH_ON=0
dash_begin() { DASH_ON=1; printf '\033[?25l\033[?7l'; }
dash_end() { [ "$DASH_ON" = 1 ] || return 0; DASH_ON=0; printf '\033[?7h\033[?25h\n'; }

# dash_paint <frame> — redraw in place (no full clear, so no flicker): home, each line cleared to its
# end, then everything below the frame cleared
dash_paint() {
  printf '\033[H'
  # no newline after the last line: a frame of exactly H lines would scroll the pane by one every tick
  printf '%s\n' "$1" | awk 'BEGIN { e = sprintf("%c", 27) } { if (NR > 1) printf "\n"; printf "%s%s[K", $0, e }'
  printf '\033[J'
}

# dash_watch <role> <raw> <id> — the viewer loop: live frames every HARNESS_DASH_SEC and on SIGWINCH, then the final
# frame, kept alive and re-rendered on a size change (polled every HARNESS_DASH_IDLE_SEC too) until HUP/INT/TERM/QUIT
# or the ask is removed or replaced. dash_end runs on every exit path.
dash_watch() {
  local role=$1 raw=$2 id=$3
  trap 'dash_end; exit 130' INT TERM
  trap 'dash_end; exit 129' HUP
  trap 'dash_end; exit 131' QUIT
  trap dash_end EXIT
  trap 'DASH_WINCH=1' WINCH
  dash_begin
  if hl_alive "$role"; then
    while hl_alive "$role" && ! hl_done "$role" "$id"; do
      DASH_WINCH=0
      dash_paint "$(hl_dash_frame "$role" "$raw")"
      [ "$DASH_WINCH" = 1 ] || dash_nap "${HARNESS_DASH_SEC:-2}"
    done
    sleep 1   # let the runner write exit.json
  fi
  local sz="" now
  while :; do
    DASH_WINCH=0; now=$(dash_size)
    if [ "$now" != "$sz" ]; then
      sz=$now
      dash_paint "$(HARNESS_DASH_FINAL=1 hl_dash_frame "$role" "$raw")"
    fi
    # the ask was removed or replaced: nothing left to show
    [ "$(awk 'NR == 1 { print $1 }' "$ASK_DIR/$role.current" 2>/dev/null)" = "$id" ] || break
    [ "$DASH_WINCH" = 1 ] || dash_nap "${HARNESS_DASH_IDLE_SEC:-1}"
  done
  dash_end
}
