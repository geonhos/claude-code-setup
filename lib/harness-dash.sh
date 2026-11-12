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

# dash_brief <role> — title line, then "S<TAB>step" / "H<TAB>heading" lines. The brief is the task
# file only when the ask's prompt names it; otherwise the prompt text itself (first line, no steps).
dash_brief() {
  local role=$1 p="$ASK_DIR/$1.prompt" f=".harness/task-$1.md"
  if [ -f "$f" ] && grep -qF "$f" "$p" 2>/dev/null; then
    awk '
      BEGIN { t = ""; sec = 0 }
      /^# / && t == "" { t = substr($0, 3); next }
      /^## / { h[++nh] = substr($0, 4); sec = ($0 ~ /^## Steps[ \t]*$/); next }
      sec && /^[0-9]+[.)] / { s = $0; sub(/^[0-9]+[.)] +/, "", s); st[++ns] = ++k ". " s }
      END {
        print (t == "" ? "(untitled brief)" : t)
        if (ns > 0) { for (i = 1; i <= ns; i++) print "S\t" st[i] }
        else { for (i = 1; i <= nh; i++) print "H\t" h[i] }
      }' "$f"
  else
    awk 'NR == 1 { print; exit }' "$p" 2>/dev/null
  fi
}

# dash_facts <raw> — one JSON object of what the stream says (model, turns, ctx, now, verify)
dash_facts() {
  local raw=$1
  { if [ -f "$raw" ]; then cat "$raw"; elif [ -f "$raw.gz" ]; then gzip -dc "$raw.gz"; fi; } 2>/dev/null | jq -R -n -c '
    def first_line: tostring | split("\n")[0];
    [inputs | fromjson? | select(type == "object")] as $e
    | ([$e[] | select(.type == "system" and .subtype == "init")] | first) as $i
    | [$e[] | select(.type == "assistant")] as $a
    | ([$a[] | .message.usage?] | map(select(. != null)) | last) as $u
    | ([$a[] | (.message.content // [])[] | select((.type == "text" and ((.text // "") | test("\\S"))) or .type == "tool_use")] | last) as $n
    | ([$e[] | select(.type == "system" and .hook_event == "Stop" and (.subtype == "hook_started" or .subtype == "hook_response"))] | last) as $h
    | {model: ($i.model // "?"),
       turns: ([$a | to_entries[] | (.value.message.id // "n\(.key)")] | unique | length),
       ctx: (if $u then (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0)) else 0 end),
       now: (if $n == null then []
             elif $n.type == "text" then ($n.text | split("\n") | map(select(test("\\S"))) | .[0:3])
             else ["→ \($n.name // "?") \(($n.input // {}) | (.description // .command // .file_path // .pattern // .url // tostring) | first_line)"] end),
       verify: (if $h == null then "none"
                elif $h.subtype == "hook_started" then "running"
                elif ([($h.stdout // "") | fromjson? | select(type == "object" and .decision == "block" and ((.reason // "") | test("\\.harness/reports/")))] | length > 0) then "report"
                elif (($h.exit_code // 0) != 0) or ([($h.stdout // "") | fromjson? | select(type == "object" and .decision == "block")] | length > 0) then "fail"
                else "pass" end)}'
}

# hl_dash_frame <role> <raw> — the dashboard text. Size: HARNESS_DASH_LINES / HARNESS_DASH_COLS,
# else the terminal (24x80 when unknown). Final frame (result + report head) when the run is not
# live: HARNESS_DASH_FINAL=1 forces it, else hl_alive decides.
hl_dash_frame() {
  local role=$1 raw=$2 a="$ASK_DIR/$1" H W id start facts model turns ctx verify now_s dur final=0
  H=${HARNESS_DASH_LINES:-$(tput lines 2>/dev/null)}; W=${HARNESS_DASH_COLS:-$(tput cols 2>/dev/null)}
  case "$H" in ''|*[!0-9]*|0) H=24 ;; esac
  case "$W" in ''|*[!0-9]*|0) W=80 ;; esac
  read -r id start _ < "$a.current" 2>/dev/null
  if [ "${HARNESS_DASH_FINAL:-}" = 1 ] || ! hl_alive "$role"; then final=1; fi
  facts=$(dash_facts "$raw"); [ -n "$facts" ] || facts='{"model":"?","turns":0,"ctx":0,"now":[],"verify":"none"}'
  model=$(jq -r '.model' <<<"$facts"); turns=$(jq -r '.turns' <<<"$facts")
  ctx=$(jq -r 'if .ctx >= 1000 then "\((.ctx / 1000) | round)k" else "\(.ctx)" end' <<<"$facts")
  verify=$(jq -r '.verify' <<<"$facts")
  # the exit record / report count only when they belong to this ask (not left over from an earlier one)
  local exit_ok=0 rep_ok=0
  if [ -f "$a.exit.json" ] && grep -q "\"ask_id\":\"$id\"" "$a.exit.json" 2>/dev/null; then exit_ok=1; fi
  if [ -f ".harness/reports/$role.md" ] && ! [ ".harness/reports/$role.md" -ot "$a.current" ]; then rep_ok=1; fi
  if [ "$final" = 1 ] && [ "$exit_ok" = 1 ]; then
    dur=$(jq -r '((.duration_ms // 0) / 1000) | floor' "$a.exit.json" 2>/dev/null)
  elif digits_only "${start:-}"; then dur=$(( $(date +%s) - start ))
  else dur=0; fi

  local bt brief_lines steps="" heads="" l k
  brief_lines=$(dash_brief "$role")
  bt=$(printf '%s\n' "$brief_lines" | sed -n 1p)
  while IFS=$'\t' read -r k l; do
    case "$k" in S) steps="$steps$l"$'\n' ;; H) heads="$heads$l"$'\n' ;; esac
  done <<<"$(printf '%s\n' "$brief_lines" | sed 1d)"
  [ -n "$steps" ] || steps=$(printf '%s' "$heads" | awk '{ print NR ". " $0 }')
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
  want=$(( $(printf '%s\n' "$(jq -r '.now[]' <<<"$facts")" | sed '/^$/d' | head -n 3 | wc -l) ))
  [ "$final" = 1 ] && want=0
  [ "$want" -gt 0 ] || want=1
  anow=$(dash_min $((want + 1)) "$rem"); [ "$final" = 1 ] && anow=$(dash_min 1 "$rem")
  [ "$anow" -ge 2 ] || [ "$final" = 1 ] || anow=0
  rem=$((rem - anow))
  want=$(( $(printf '%s\n' "$steps" | sed '/^$/d' | wc -l) ))
  if [ "$want" -gt 0 ]; then asteps=$(dash_min $((want + 1)) "$rem"); [ "$asteps" -ge 2 ] || asteps=0; rem=$((rem - asteps)); fi
  [ "$rem" -lt 1 ] || { averify=1; rem=$((rem - 1)); }
  if [ "$dwant" -gt 0 ]; then adiff=$(dash_min "$dwant" "$rem"); [ "$adiff" -ge 2 ] || adiff=0; rem=$((rem - adiff)); fi
  [ "$rem" -ge 2 ] && arecent=$rem

  local out="" sec="── "
  out=$(printf '%s  %s  ⏱ %s  turns %s  ctx %s  %s' "$role" "${id:-?}" "$(dash_fmt_dur "$dur")" "$turns" "$ctx" "$model")
  [ "$abrief" -eq 0 ] || out="$out"$'\n'"${sec}Brief ── $bt"
  if [ "$final" = 1 ]; then
    if [ "$anow" -ge 1 ]; then
      if [ "$exit_ok" = 1 ]; then
        l=$(jq -r '"■ \(.result // "ended") · rc \(.rc // "?") · \(.num_turns // 0) turns · \(((.duration_ms // 0) / 1000) | floor)s · $\(.cost_usd // 0)"' "$a.exit.json" 2>/dev/null)
      else l="■ ended (no result)"; fi
      out="$out"$'\n'"${sec}Result ── $l"
    fi
  elif [ "$anow" -ge 2 ]; then
    l=$(jq -r '.now[]' <<<"$facts" | sed '/^$/d' | head -n 3 | sed 's/^/  /')
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
  # cut by display width (Hangul/CJK/fullwidth = 2 columns; jq works in code points, bash 3.2 ${v:0:n} in
  # bytes) so no line wraps; a line is clipped, never wrapped
  printf '%s\n' "$out" | jq -R -r --argjson w "$W" '
    def cw: if (. >= 4352 and . <= 4447) or (. >= 11904 and . <= 42191) or (. >= 44032 and . <= 55203)
              or (. >= 63744 and . <= 64255) or (. >= 65040 and . <= 65049) or (. >= 65072 and . <= 65135)
              or (. >= 65280 and . <= 65376) or (. >= 65504 and . <= 65510) or (. >= 127744 and . <= 128591)
              or (. >= 129280 and . <= 129535) or (. >= 131072 and . <= 262141) then 2 else 1 end;
    explode | reduce .[] as $c ({w: 0, o: [], f: false};
      if .f then . else ($c | cw) as $k | if .w + $k > $w then .f = true else .w += $k | .o += [$c] end end)
    | .o | implode'
}

# dash_paint <frame> — redraw in place (no full clear, so no flicker): home, each line cleared to its
# end, then everything below the frame cleared
dash_paint() {
  printf '\033[H'
  printf '%s\n' "$1" | awk 'BEGIN { e = sprintf("%c", 27) } { print $0 e "[K" }'
  printf '\033[J'
}
