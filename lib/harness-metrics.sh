# harness-metrics.sh — `harness metrics` and `harness wiki-lint` (file-only, no herdr).
# Sourced eagerly by bin/harness (see the loader there): definitions only, no side effects.

# --- wiki-lint ---------------------------------------------------------------------------
# harness wiki-lint [DIR]   mechanical checks over DIR (default docs/wiki); prints
# `file: problem` lines, exit 1 on any error (warnings: old inbox items, fluff).
cmd_wiki_lint() {
  local dir=${1:-docs/wiki} errs=0 f rel p n links l c k v t st
  while [ "${#dir}" -gt 1 ] && [ "${dir%/}" != "$dir" ]; do dir=${dir%/}; done
  [ -d "$dir" ] || { echo "$dir: wiki directory not found"; return 1; }
  local idx="$dir/index.md"
  err() { echo "$1: $2"; errs=$((errs + 1)); }
  warn() { echo "$1: warning: $2"; }
  [ -f "$idx" ] || err "$idx" "index.md missing"
  if [ -f "$idx" ]; then
    n=$(wc -l < "$idx" | tr -d ' ')
    [ "$n" -le 80 ] || err "$idx" "$n lines (max 80)"
    links=$(grep -E '^- \[' "$idx" | sed -n 's/^[^]]*\]( *\([^) ]*\)).*/\1/p')
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      case "$l" in http://*|https://*) continue ;; esac
      [ -f "$dir/$l" ] || err "$idx" "link does not resolve: $l"
    done <<EOF_LINKS
$links
EOF_LINKS
  fi
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel=${f#"$dir"/}
    case "$rel" in index.md|log.md|inbox/*) continue ;; esac
    n=$(wc -l < "$f" | tr -d ' ')
    [ "$n" -le 150 ] || err "$f" "$n lines (max 150)"
    if [ "$(sed -n 1p "$f")" != "---" ]; then
      err "$f" "missing frontmatter"
    else
      st=$(awk 'NR == 1 { next } /^---[ \t]*$/ { exit } { print }' "$f")
      awk 'NR > 1 && /^---[ \t]*$/ { f = 1; exit } END { exit !f }' "$f" || err "$f" "frontmatter not closed"
      for k in type status updated sources verified_by; do
        v=$(printf '%s\n' "$st" | sed -n "s/^$k:[ ]*//p" | head -1)
        if [ -z "$v" ]; then err "$f" "frontmatter key missing or empty: $k"; continue; fi
        case "$k" in
          type) case "$v" in troubleshooting|decision|how-to) ;; *) err "$f" "invalid type: $v" ;; esac ;;
          status) case "$v" in draft|active|stale|superseded) ;; *) err "$f" "invalid status: $v" ;; esac ;;
          updated) printf '%s\n' "$v" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || err "$f" "invalid updated date: $v" ;;
          sources) case "$v" in \[*\]) [ "$v" != "[]" ] || err "$f" "sources is empty" ;; *) err "$f" "sources must be a [list]" ;; esac ;;
        esac
      done
    fi
    if [ -f "$idx" ]; then
      c=$(grep -E '^- \[' "$idx" | grep -cF "]($rel)")
      [ "$c" -eq 1 ] || err "$f" "listed $c times in index.md (expected 1)"
    fi
    grep -Eqi 'works well|잘 동작|very important|중요하다' "$f" && warn "$f" "fluff phrase (works well / 잘 동작 / very important / 중요하다)"
  done <<EOF_PAGES
$(find "$dir" -type f -name '*.md' 2>/dev/null | sort)
EOF_PAGES
  if [ -d "$dir/inbox" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && warn "$f" "inbox item older than 14 days; review or delete"
    done <<EOF_OLD
$(find "$dir/inbox" -type f -name '*.md' -mtime +14 2>/dev/null | sort)
EOF_OLD
  fi
  [ "$errs" -eq 0 ] || return 1
  return 0
}

# --- harness metrics -------------------------------------------------------------------------
# cmd_metrics [--since YYYY-MM-DD] [--json] — numbers from .harness/progress.jsonl (the
# current window and the equal one before it) plus a snapshot of retro and wiki state.
# Windows: [start, now] and [start - len, start). Default start = now - 28 days.
# Abnormal = a late-report row or an ask whose exit is not 0/5; rate = abnormal / rows.
cmd_metrics() {
  local since="" json=0 now top pend=0 done_n=0 recur=0 wiki="null" pages inbox_n=0 oldest="" f st mt idxl=0 inj=0
  local act=0 stale=0 draft=0 sup=0 oth=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      --since)
        [ $# -ge 2 ] || usage
        printf '%s' "$2" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "--since expects YYYY-MM-DD (got '$2')"
        since=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  now=${HARNESS_NOW:-$(date +%s)}
  digits_only "$now" || die "HARNESS_NOW must be epoch seconds"
  if [ -n "$since" ]; then
    jq -n -e --arg s "$since" '($s + "T00:00:00Z" | fromdateiso8601 | strftime("%Y-%m-%d")) == $s' >/dev/null 2>&1 || die "--since: not a valid date ('$since')"
    [ ! "$since" \> "$(jq -n -r --argjson n "$now" '$n | strftime("%Y-%m-%d")')" ] || die "--since $since is in the future"
  fi
  top=$(git rev-parse --show-toplevel 2>/dev/null) || top=$PWD
  pend=$(ls "$RETRO_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
  done_n=$(ls "$RETRO_DIR"/done/*.json 2>/dev/null | wc -l | tr -d ' ')
  if [ -d "$top/docs/wiki" ]; then
    for f in $(find "$top/docs/wiki" -name '*.md' ! -path "$top/docs/wiki/inbox/*" ! -name index.md ! -name log.md 2>/dev/null); do
      st=$(sed -n 's/^status: *//p' "$f" | head -n 1)
      case "$st" in
        active) act=$((act + 1)) ;; stale) stale=$((stale + 1)) ;;
        draft) draft=$((draft + 1)) ;; superseded) sup=$((sup + 1)) ;; *) oth=$((oth + 1)) ;;
      esac
    done
    for f in $(find "$top/docs/wiki/inbox" -type f -name '*.md' 2>/dev/null); do
      inbox_n=$((inbox_n + 1))
      mt=$(file_mtime "$f") || continue
      if [ -z "$oldest" ] || [ "$mt" -lt "$oldest" ]; then oldest=$mt; fi
      recur=$((recur + $(grep -ci 'recurrence of' "$f" 2>/dev/null)))
    done
    [ ! -f "$top/docs/wiki/index.md" ] || idxl=$(wc -l < "$top/docs/wiki/index.md" | tr -d ' ')
    [ ! -f "$top/docs/wiki/index.md" ] || inj=$(LC_ALL=C grep -F '(active,' "$top/docs/wiki/index.md" | wc -c | tr -d ' ')
    wiki=$(jq -n -c --argjson a "$act" --argjson s "$stale" --argjson d "$draft" --argjson u "$sup" --argjson o "$oth" \
      --argjson inbox "$inbox_n" --argjson oldest "$(num_or_null "$oldest")" --argjson now "$now" --argjson il "$idxl" --argjson ib "$inj" '
      {pages: {active: $a, stale: $s, draft: $d, superseded: $u, other: $o}, inbox_items: $inbox,
       inbox_oldest_days: (if $oldest == null then null else ((($now - $oldest) / 86400) | floor) end),
       index_lines: $il, session_start_bytes: $ib}')
  fi
  { [ -f "$JSONL" ] && cat "$JSONL"; true; } | jq -R -s -r --argjson now "$now" --arg since "$since" --argjson json "$json" \
    --argjson roles "$(printf '%s\n' $HARNESS_ROLES | jq -R . | jq -s -c .)" --argjson pend "$pend" --argjson done "$done_n" --argjson recur "$recur" --argjson wiki "$wiki" '
    def pct($n; $d): if $d == 0 then null else (($n * 1000 / $d) | round) / 10 end;
    def median: sort | if length == 0 then null elif length % 2 == 1 then .[(length / 2 | floor)]
      else (((.[length / 2 - 1] + .[length / 2]) / 2) | round) end;
    def p95: sort | if length == 0 then null else .[((length * 0.95 | ceil) - 1)] end;
    def day: strftime("%Y-%m-%d");
    def rows: split("\n") | map(fromjson? | select(type == "object" and .event != "close"))
      | map(. + {t: (try (.ts | fromdateiso8601) catch null)}) | map(select(.t != null));
    def abn: .late == true or (.exit != null and .exit != 0 and .exit != 5);
    def role_stat($rs):
      ($rs | map(select(.late != true))) as $a
      | { asks: ($a | length), late: ($rs | map(select(.late == true)) | length),
          abnormal: ($rs | map(select(abn)) | length),
          abnormal_rate: pct($rs | map(select(abn)) | length; $rs | length),
          exit: ($rs | map(if .late == true then "late" else (.exit | if . == null then "?" else tostring end) end)
                 | group_by(.) | map({key: .[0], value: length}) | from_entries),
          exit5: ($a | map(select(.exit == 5)) | length),
          duration_median_s: ($a | map(.dur_s | select(type == "number")) | median),
          duration_p95_s: ($a | map(.dur_s | select(type == "number")) | p95),
          mean_verify_attempts: ($a | map(.verify_attempts | select(type == "number")) | if length == 0 then null else ((add / length * 10 | round) / 10) end) };
    def clear_stat($rs):
      ($rs | map(select(.late != true))) as $a
      | ($a | map(select(.clear == "ok")) | length) as $ok
      | ($a | map(select(.clear == "retry")) | length) as $rt
      | ($a | map(select(.clear == "respawn")) | length) as $rs2
      | { ok: $ok, retry: $rt, respawn: $rs2, none: ($a | map(select(.clear == "none")) | length),
          retry_rate: pct($rt; $ok + $rt + $rs2), respawn_rate: pct($rs2; $ok + $rt + $rs2) };
    def stat($rs):
      { total: role_stat($rs), clear: clear_stat($rs),
        roles: ($roles | map(. as $r | {key: $r, value: role_stat($rs | map(select(.agent == $r)))}) | from_entries) }
      | .roles.implementer.verify_failure_rate = pct(.roles.implementer.exit5; .roles.implementer.asks)
      | .roles.reviewer.fail_rate = pct(.roles.reviewer.exit5; .roles.reviewer.asks)
      | .by_runner = ($rs | group_by("\(.agent)/\(.runner // "pane")")
          | map({key: "\(.[0].agent)/\(.[0].runner // "pane")",
                 value: (role_stat(.) + {cost_usd_sum: (map(.cost_usd | select(type == "number")) | add // 0),
                   cost_usd_median: (map(select(.late != true) | .cost_usd | select(type == "number")) | median),
                   startup_s_median: (map(select(.late != true) | .startup_s | select(type == "number")) | median)})})
          | from_entries);
    (rows) as $all
    | (if $since == "" then $now - 28 * 86400 else ($since + "T00:00:00Z" | fromdateiso8601) end) as $start
    | ($now - $start) as $len
    | { window: {start: ($start | day), end: ($now | day), days: (($len / 86400) | round)},
        previous: {start: ($start - $len | day), end: ($start | day)},
        current: stat($all | map(select(.t >= $start and .t <= $now))),
        prev: stat($all | map(select(.t >= $start - $len and .t < $start))),
        retro: {pending: $pend, processed: $done, recurrences_noted: $recur},
        wiki: $wiki }
    | if $json == 1 then tojson else
      def pad($n): tostring | . + ([range(0; $n - length) | " "] | join(""));
      def lpad($n): tostring | ([range(0; $n - length) | " "] | join("")) + .;
      def f: if . == null then "-" else tostring end;
      def pc: if . == null then "-" else "\(.)%" end;
      def dist: if (. | length) == 0 then "-" else (to_entries | map("\(.key):\(.value)") | join(" ")) end;
      def dur: if .duration_median_s == null then "-" else "\(.duration_median_s)s / \(.duration_p95_s)s" end;
      def row($label; $c; $p): "  " + ($label | pad(34)) + ($c | f | lpad(22)) + ($p | f | lpad(22));
      . as $m
      | [ "harness metrics  \(.window.start) .. \(.window.end) (\(.window.days)d)  vs  \(.previous.start) .. \(.previous.end)",
          "",
          ("  " + ("" | pad(34)) + ("current" | lpad(22)) + ("previous" | lpad(22))),
          row("asks"; .current.total.asks; .prev.total.asks),
          ($roles[] as $r | row("  \($r)"; .current.roles[$r].asks; .prev.roles[$r].asks)),
          row("late reports"; .current.total.late; .prev.total.late),
          row("abnormal rate (exit not 0/5, late)"; (.current.total.abnormal_rate | pc); (.prev.total.abnormal_rate | pc)),
          ($roles[] as $r | row("  \($r)"; (.current.roles[$r].abnormal_rate | pc); (.prev.roles[$r].abnormal_rate | pc))),
          row("implementer verify-failure rate"; (.current.roles.implementer.verify_failure_rate | pc); (.prev.roles.implementer.verify_failure_rate | pc)),
          row("implementer mean verify attempts"; .current.roles.implementer.mean_verify_attempts; .prev.roles.implementer.mean_verify_attempts),
          row("/clear retry rate"; (.current.clear.retry_rate | pc); (.prev.clear.retry_rate | pc)),
          row("/clear respawn rate"; (.current.clear.respawn_rate | pc); (.prev.clear.respawn_rate | pc)),
          row("reviewer FAIL rate"; (.current.roles.reviewer.fail_rate | pc); (.prev.roles.reviewer.fail_rate | pc)),
          ($roles[] as $r | row("duration median / p95  \($r)"; (.current.roles[$r] | dur); (.prev.roles[$r] | dur))),
          "",
          (if ((.current.by_runner | keys) + (.prev.by_runner | keys) | any(endswith("/headless"))) then
            "  runner split (agent/runner: asks, abnormal, duration median, cost sum, startup median)",
            ((.current.by_runner | to_entries[]) | "    \(.key | pad(24)) \(.value.asks) asks · abn \(.value.abnormal) · \(.value | dur) · $\(.value.cost_usd_sum) · startup \(.value.startup_s_median | f)s")
           else empty end),
          "  exits current:  \(.current.total.exit | dist)",
          "  exits previous: \(.prev.total.exit | dist)",
          "",
          "retro: \(.retro.pending) pending · \(.retro.processed) processed · \(.retro.recurrences_noted) recurrence note(s) in the inbox",
          (if .wiki == null then "wiki: none (no docs/wiki)" else
            "wiki: pages active \(.wiki.pages.active) · stale \(.wiki.pages.stale) · draft \(.wiki.pages.draft) · superseded \(.wiki.pages.superseded) · other \(.wiki.pages.other)",
            "wiki: inbox \(.wiki.inbox_items) item(s), oldest \(.wiki.inbox_oldest_days | if . == null then "-" else "\(.)d" end) · index \(.wiki.index_lines) lines · SessionStart wiki \(.wiki.session_start_bytes) bytes" end) ]
      | .[] end'
}
