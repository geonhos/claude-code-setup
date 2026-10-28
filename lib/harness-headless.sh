# harness-headless.sh — headless runner glue (decision 0007): runner_of, use_hl, hl_*, ask/report/close_headless.
# Sourced eagerly by bin/harness (see the loader there): definitions only, no side effects.
# Shared helpers (die, has_uncollected, ...) stay in bin/harness and resolve at call time.

# --- headless runner (decision 0007) --------------------------------------------------------------
# runner.<role> = headless: `harness ask` writes the instruction to a file and runs
# `harness-run` (claude -p, stream-json) in a kept viewer pane. Completion = the run's
# .harness/asks/<role>.exit.json carrying this ask-id; no herdr agent, no Stop-hook marker.

# runner_of <role> — headless|pane (env HARNESS_RUNNER_<ROLE>, then config runner.<role>, then pane)
runner_of() {
  local up v
  up=$(printf %s "$1" | tr 'a-z' 'A-Z')
  eval "v=\${HARNESS_RUNNER_$up:-}"
  [ -n "$v" ] || v=$(jq -r --arg r "$1" '.runner[$r] // empty' "$CONFIG_FILE" 2>/dev/null)
  case "$v" in headless) echo headless ;; *) echo "$HARNESS_RUNNER_DEFAULT" ;; esac
}

# use_hl <role> — this role is handled by the headless code: configured so, or (runner flipped
# back to pane) a headless run is still alive. A leftover .run / exit.json is not enough, and
# herdr answers never decide it.
use_hl() {
  [ -z "$ASK_WT" ] || return 0    # a worktree ask is always headless
  [ "$(runner_of "$1")" != headless ] || return 0
  hl_alive "$1"
}
is_headless() { [ "$(runner_of "$1")" = headless ]; }

# hl_registered_pane <role> — the viewer pane in .harness/panes (last line for the role)
hl_registered_pane() { awk -v r="${ASK_KEY:-$1}" '$1 == r { p = $2 } END { if (p != "") print p }' "$PANES_FILE" 2>/dev/null; }

# hl_alive <role> — a harness-run for the role is running (pid file, live harness-run process)
hl_alive() {
  local f="$ASK_DIR/$1.pid" id pid
  [ -f "$f" ] || return 1
  read -r id pid _ < "$f"
  digits_only "${pid:-}" && kill -0 "$pid" 2>/dev/null || return 1
  ps -p "$pid" -o command= 2>/dev/null | grep -q 'harness-run'
}
# hl_last_session <role> — session id of the role's latest *successful* headless run (progress
# line with result "success" and a session). A close event of the role with the same ask-id rule as
# last_ask_record is a boundary: when one came after the last such run, print "closed" instead (no session id looks like that).
hl_last_session() {
  [ -f "$JSONL" ] || return 1
  tail -n 200 "$JSONL" 2>/dev/null \
    | jq -R -n -r --arg r "$1" --arg id "${ASK_ID:-}" '
        reduce (inputs | fromjson? | select(type == "object")) as $e ({sid: "", closed: false};
          if $e.event == "close" then (if $e.role == $r and ($e.ask_id // "") == $id then {sid: "", closed: true} else . end)
          elif ($e.ask_id // "") != $id then .
          elif $e.agent == $r and $e.runner == "headless" and $e.result == "success" and (($e.session // "") != "") then {sid: $e.session, closed: false}
          else . end)
        | if .sid != "" then .sid elif .closed then "closed" else empty end' 2>/dev/null \
    | grep .
}
hl_pid() { awk 'NR == 1 { print $2 }' "$ASK_DIR/$1.pid" 2>/dev/null; }
# hl_done <role> <ask-id> — exit.json exists for that ask
hl_done() { grep -q "\"ask_id\":\"$2\"" "$ASK_DIR/$1.exit.json" 2>/dev/null; }

# hl_pane <role> — print the role's viewer pane: reuse the registered one while it exists in
# this repo, else split a plain shell pane (no herdr agent) and register it
hl_pane() {
  local role=$1 pane out c dir
  if [ -z "$ASK_WT" ] && herdr agent get "$(wname "$role")" >/dev/null 2>&1; then
    die "a pane-mode $role worker is live; close it first: harness close $role"
  fi
  pane=$(hl_registered_pane "$role")
  if [ -n "$pane" ]; then
    if out=$(herdr pane get "$pane" 2>/dev/null); then
      c=$(printf '%s' "$out" | jq -r '.result.pane.cwd // empty' 2>/dev/null)
      if [ -z "$c" ] || cwd_in_repo "$c"; then printf '%s\n' "$pane"; return 0; fi
    fi
    unregister "${ASK_KEY:-$role}" "$pane"
  fi
  dir=$(pick_direction)
  if ! out=$(herdr pane split --current --direction "$dir" --cwd "$PWD" --env HARNESS_ROLE=worker --env CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000 --no-focus 2>&1); then
    die "pane split failed: $out"
  fi
  pane=$(printf '%s' "$out" | jq -r '.result.pane.pane_id // empty' 2>/dev/null)
  [ -n "$pane" ] || die "pane split returned no pane id: $out"
  register "${ASK_KEY:-$role}" "$pane"
  printf '%s\n' "$pane"
}

# hl_progress_obj <role> <t0> — extra progress.jsonl fields of the role's last run, as one
# JSON object (keys session / ctx_after are consumed by the caller)
hl_progress_obj() {
  local role=$1 t0=${2:-} ej="$ASK_DIR/$1.exit.json" id resume=false resumed=false
  id=$(awk 'NR == 1 { print $1 }' "$ASK_DIR/$role.current" 2>/dev/null)
  [ -z "$(sed -n 's/^resume=//p' "$ASK_DIR/$role.run" 2>/dev/null | head -n 1)" ] || resume=true
  [ -f "$ASK_DIR/$role.autoresume" ] && [ "$resume" = true ] && resumed=true
  if [ -f "$ej" ] && { [ -z "$id" ] || hl_done "$role" "$id"; }; then
    jq -c --argjson resume "$resume" --argjson resumed "$resumed" --argjson t0 "$(num_or_null "$t0")" '
      {runner: "headless", cost_usd: (.cost_usd // null), turns: (.num_turns // null), result: (.result // null),
       denials: (.denials // null), stream_log: (.stream_log // null), resume: $resume,
       startup_s: (if (.t_init | type) == "number" and $t0 != null then (.t_init - $t0) else null end),
       session: (.session_id // ""), ctx_after: (.ctx // "")} + (if $resumed then {resumed: true} else {} end)' "$ej" 2>/dev/null && return 0
  fi
  jq -n -c --argjson resume "$resume" '{runner: "headless", resume: $resume, session: "", ctx_after: ""}'
}

# hl_status_line <role> status|progress — one line for `harness status` / progress.md
hl_status_line() {
  local role=$1 mode=$2 pane st el ctx
  pane=$(hl_registered_pane "$role")
  if [ -z "$pane" ]; then
    if [ "$mode" = status ]; then printf '%-12s %s\n' "$role" "-"; else printf '%s -' "$role"; fi
    return 0
  fi
  ctx=$(jq -r '.ctx // empty' "$ASK_DIR/$role.exit.json" 2>/dev/null)
  if hl_alive "$role"; then
    st=running
    el=$(( $(date +%s) - $(awk 'NR == 1 { print $2 }' "$ASK_DIR/$role.current" 2>/dev/null || echo 0) ))
  else
    st=idle; el=""
  fi
  if [ "$mode" = status ]; then
    if [ "$st" = running ]; then printf '%-12s %-8s %-8s hl %ss\n' "$role" "$st" "$pane" "$el"
    else printf '%-12s %-8s %-8s hl ctx %s\n' "$role" "$st" "$pane" "$(fmt_ctx "$ctx")"; fi
  else
    printf '%s %s ctx %s hl' "$role" "$st" "$(fmt_ctx "$ctx")"
  fi
}

# hl_collect <role> — a finished run (exit.json present): print the report or explain, exit.
# First match wins (spec §3). Never returns.
hl_collect() {
  local role=$1 ej="$ASK_DIR/$1.exit.json" report="$REPORT_DIR/$1.md" cur="$ASK_DIR/$1.current"
  local rc res iserr killed sid tinit pane perm ejc denied
  ejc=$(cat "$ej" 2>/dev/null)   # one read: a racing close removes the checkout under us
  rc=$(jq -r '.rc // empty' <<<"$ejc" 2>/dev/null); res=$(jq -r '.result // empty' <<<"$ejc" 2>/dev/null)
  iserr=$(jq -r '.is_error // false' <<<"$ejc" 2>/dev/null); killed=$(jq -r '.killed // empty' <<<"$ejc" 2>/dev/null)
  sid=$(jq -r '(.session_id // "") | .[0:8]' <<<"$ejc" 2>/dev/null); tinit=$(jq -r '.t_init // empty' <<<"$ejc" 2>/dev/null)
  # a worktree ask whose result vanished was closed under it (`harness close --force` kills the
  # run and removes the checkout while this process is still collecting): that is a kill, not a failure
  if [ -n "$ASK_WT" ] && [ -z "$ejc" ]; then
    echo "harness: $role's run was killed (closed); its checkout was removed"
    exit 3
  fi
  pane=$(hl_registered_pane "$role")
  perm=$(jq -r '.perm // empty' <<<"$ejc" 2>/dev/null)
  if [ -n "$perm" ] && [ "$perm" != auto ]; then
    echo "harness: warning: $role ran with permission mode '$perm', not auto; tools may have been denied (see the viewer pane)" >&2
  fi
  denied=$(jq -r '(.denied // [])[] | "  - \(.tool): \(.input)\(if (.reason // "") != "" then " (" + .reason + ")" else "" end)"' <<<"$ejc" 2>/dev/null)
  restore_interrupted "$role" "$report"
  if [ -f "$report" ] && { [ ! -f "$cur" ] || [ ! "$report" -ot "$cur" ]; }; then
    [ -z "$denied" ] || printf 'harness: note: %s denied tool call(s):\n%s\n' "$(grep -c . <<<"$denied")" "$denied" >&2
    if { [ -n "$rc" ] && [ "$rc" != 0 ]; } || [ "$iserr" = true ]; then
      echo "harness: note: $role's run ended with ${res:-no result} (rc ${rc:-?}) but wrote a report" >&2
    fi
    finish_report "$role" "$report" "${pane:--}"
  fi
  if [ "$res" = error_max_turns ]; then
    echo "harness: $role stopped at the max-turns limit without a report; continue with: harness ask $role '...' --keep"
    hl_view_tail "$pane"; exit 3
  fi
  if [ -n "$killed" ]; then
    echo "harness: $role's run was killed ($killed); --keep resumes session ${sid:-?}"
    exit 3
  fi
  if [ "$rc" = 127 ] || [ -z "$tinit" ]; then
    echo "harness: $role's claude did not start (rc ${rc:-?}):" >&2
    tail -n 20 "$ASK_DIR/$role.err" 2>/dev/null >&2
    exit 1
  fi
  if [ "$iserr" = true ] || [ -n "$res" -a "$res" != success ] || { [ -n "$rc" ] && [ "$rc" != 0 ]; }; then
    echo "harness: $role's worker ended with ${res:-error} (rc ${rc:-?}) and wrote no report"
    tail -n 20 "$ASK_DIR/$role.err" 2>/dev/null
    hl_view_tail "$pane"; exit 3
  fi
  # permissions blocked the worker and it wrote nothing: there is no answer to relay (exit 2), only when the run ended without errors
  if [ -n "$denied" ] && [ -z "$killed" ] && [ -n "$tinit" ]; then
    printf 'harness: %s was denied %s tool call(s) and wrote no report; nothing to answer. Re-ask with a changed brief:\n%s\n' \
      "$role" "$(grep -c . <<<"$denied")" "$denied"
    hl_view_tail "$pane"; exit 2
  fi
  echo "harness: $role finished without a report at $report; collect: harness report $(ask_ref "$role")"
  hl_view_tail "$pane"; exit 3
}
hl_view_tail() { [ -z "${1:-}" ] || herdr pane read "$1" 2>/dev/null | tail -n 30; return 0; }

# hl_launch <role> <id> <pane> <resume> <max_s> <ctxb> <start_s> <poll> — write the run file, start
# harness-run in the pane and wait for its pid file; exits 1 when the pane never starts it
hl_launch() {
  local role=$1 id=$2 pane=$3 resume=$4 max_s=$5 ctxb=$6 start_s=$7 poll=$8 a="$ASK_DIR/$1" s0
  rm -f "$a.finished" "$a.exit.json" "$a.pid"
  printf 'resume=%s\nmax_s=%s\nctx_before=%s\n' "$resume" "$max_s" "$ctxb" > "$a.run"
  # a worktree ask streams into the main checkout's log dir, tagged with its id8
  [ -z "$ASK_WT" ] || printf 'log_dir=%s\nlog_tag=%s\n' "$(pwd -P)/.harness/log" "$ASK_ID8" >> "$a.run"
  if ! herdr pane run "$pane" "$(printf 'harness-run %q %q %q' "$role" "$id" "${ASK_WT:-$(pwd -P)}")" >/dev/null 2>&1; then
    echo "harness: pane run failed for $pane" >&2
    exit 1
  fi
  # the run announces itself with its pid file; a pane whose shell is busy never does
  s0=$(date +%s)
  until grep -q "^$id " "$a.pid" 2>/dev/null || hl_done "$role" "$id"; do
    if [ $(( $(date +%s) - s0 )) -ge "$start_s" ]; then
      echo "harness: $role's run did not start in $start_s s (is the pane $pane at a shell prompt?)" >&2
      show_pane_screen "$pane"
      exit 1
    fi
    sleep "$poll"
  done
}
# hl_resume_missing <role> — the finished run was a --resume that produced no init event because
# claude could not find the conversation (real claude: result-only stream, error_during_execution)
hl_resume_missing() {
  local role=$1 a="$ASK_DIR/$1" raw
  [ -n "$(sed -n 's/^resume=//p' "$a.run" 2>/dev/null | head -n 1)" ] || return 1
  [ -z "$(jq -r '.t_init // empty' "$a.exit.json" 2>/dev/null)" ] || return 1
  raw=$(jq -r '.stream_log // empty' "$a.exit.json" 2>/dev/null)
  grep -qi 'no conversation found' "$a.err" 2>/dev/null && return 0
  [ -z "$raw" ] || grep -qi 'no conversation found' "$raw" 2>/dev/null
}

# ask_headless <role> <text> <timeout-ms> <fresh> <keep> — the whole headless ask; always exits
ask_headless() {
  local role=$1 text=$2 timeout=$3 fresh=$4 keep=$5 pane id start retried resume="" sid max_s ctxb="" report="$REPORT_DIR/$1.md" last
  local a="$ASK_DIR/$role" now deadline poll=${HARNESS_POLL_SEC:-2} start_s=${HARNESS_HL_START_S:-15} s0 g
  mkdir -p "$ASK_DIR" .harness/done "$REPORT_DIR" "$LOG_DIR"
  if hl_alive "$role"; then
    echo "harness: $role is still running (pid $(hl_pid "$role")); nothing sent. Collect with: harness report $role; stop: harness close $role --force" >&2
    exit 4
  fi
  pane=$(hl_pane "$role") || exit $?
  [ -z "$ASK_WT" ] || wt_update pane "$pane"
  # implementer only (decision 0009, amends D6): after an ask that did not end cleanly the next one
  # continues the session, like the pane's maybe_reset; --fresh overrides, --keep needs no help
  rm -f "$a.autoresume"
  if [ "$role" = implementer ] && [ "$keep" = 0 ] && [ "$fresh" = 0 ]; then
    last=$(last_exit "$role")
    case "$last" in
      ''|0) ;;
      *) keep=1; : > "$a.autoresume"; echo "keeping context (last ask exit $last)" >&2 ;;
    esac
  fi
  if [ "$keep" = 1 ]; then
    sid=$(sed -n 1p "$a.session" 2>/dev/null)
    if [ -n "$sid" ]; then
      resume=$sid
      ctxb=$(jq -r '.ctx // empty' "$a.exit.json" 2>/dev/null)
    elif sid=$(hl_last_session "$role") && [ "$sid" = closed ]; then
      echo "harness: note: $role was closed after its last successful run; no session to resume — running fresh"
    elif [ -n "$sid" ]; then
      # the previous run died before it reported a session: fall back to the last successful one
      resume=$sid
      echo "harness: note: the previous run recorded no session; resuming the last successful one from progress.jsonl (${sid:0:8})"
    else
      echo "harness: note: no previous session for $role — running fresh"
    fi
  fi
  # a session file left by an earlier run must never be mistaken for this run's
  rm -f "$a.session"
  if [ -f "$report" ]; then
    archive_late "$role" "$report" || {
      echo "harness: could not archive the leftover report; kept as $report.unlogged" >&2
      mv -f "$report" "$report.unlogged"
    }
  fi
  rm -f "$report"
  id=${ASK_ID:-"$(date +%s)-$$-$RANDOM"}; start=$(date +%s)
  printf '%s %s\n' "$id" "$start" > "$a.current"
  rm -f "$a.finished" "$a.exit.json" "$a.pid"
  if [ "$role" = implementer ]; then verify_tool baseline implementer 2>/dev/null || rm -f .harness/verify/implementer.json; fi
  max_s=${HARNESS_HL_MAX_S:-}
  digits_only "$max_s" || { max_s=$(jq -r '.headless_max_minutes // empty' "$CONFIG_FILE" 2>/dev/null); digits_only "$max_s" && max_s=$((max_s * 60)) || { max_s=$HARNESS_HL_MAX_S_DEFAULT; [ "$role" != implementer ] || max_s=$HARNESS_HL_MAX_S_IMPLEMENTER_DEFAULT; }; }
  printf '%s\n' "$text" > "$a.prompt"
  hl_launch "$role" "$id" "$pane" "$resume" "$max_s" "$ctxb" "$start_s" "$poll"
  deadline=$((start + (timeout + 999) / 1000))
  retried=0
  while :; do
    if hl_done "$role" "$id"; then
      if [ "$retried" = 0 ] && hl_resume_missing "$role"; then
        # the session is gone: one fresh run in the same ask; the dead sid must not stay the resume target
        retried=1
        echo "harness: resume of ${resume:0:8} failed, running fresh" >&2
        resume=""; ctxb=""
        hl_launch "$role" "$id" "$pane" "" "$max_s" "" "$start_s" "$poll"
        continue
      fi
      hl_collect "$role"
    fi
    if ! hl_alive "$role"; then
      # the runner may still be writing exit.json (jq, mv) as its pid disappears: give it ~3 s
      g=0; while [ "$g" -lt 30 ] && ! hl_done "$role" "$id"; do sleep 0.1; g=$((g + 1)); done
      if hl_done "$role" "$id"; then continue; fi
      sid=$(sed -n 1p "$a.session" 2>/dev/null | cut -c1-8)
      if [ -n "$sid" ]; then
        echo "harness: $role's run is gone without a result (killed?); --keep resumes session $sid"
      else
        echo "harness: $role's run is gone without a result (killed?); it recorded no session (--keep resumes the last successful one, if any)"
      fi
      exit 3
    fi
    now=$(date +%s)
    if [ "$now" -ge "$deadline" ]; then
      if [ "$role" = implementer ] && [ -f "$report.pending" ]; then
        # the Stop hook has hidden the report while it verifies; the run is never killed at the deadline
        echo "harness: $role is still verifying (Stop hook running, $(cat .harness/verify/implementer.attempts 2>/dev/null || echo 0) failed attempt(s) so far, $((now - start))s); collect: harness report $(ask_ref "$role"); stop: harness close $(ask_ref "$role") --force" >&2
        exit 4
      fi
      echo "harness: $role is still running (pid $(hl_pid "$role"), $((now - start))s); collect: harness report $(ask_ref "$role"); stop: harness close $(ask_ref "$role") --force" >&2
      exit 4
    fi
    sleep "$poll"
  done
}

# report_headless <role> — `harness report` for a headless role; always exits
report_headless() {
  local role=$1 report="$REPORT_DIR/$1.md"
  if hl_alive "$role"; then
    echo "harness: $role is still running (pid $(hl_pid "$role")); wait, then run: harness report $(ask_ref "$role")" >&2
    exit 4
  fi
  if [ ! -f "$ASK_DIR/$role.exit.json" ]; then
    echo "harness: no finished run for $role" >&2
    exit 3
  fi
  if [ -f "$report" ]; then
    retro_on_report "$role" "$report" || true
    archive_late "$role" "$report" || true
  fi
  stamp_finished "$role"
  hl_collect "$role"
}

# hl_kill <role> — stop the role's run: TERM the runner (it kills its tree and writes
# exit.json killed:signal), wait up to 5 s, then kill the tree
hl_kill() {
  local role=$1 pid i=0 id
  pid=$(hl_pid "$role"); id=$(awk 'NR == 1 { print $1 }' "$ASK_DIR/$role.pid" 2>/dev/null)
  digits_only "$pid" || return 0
  kill -TERM "$pid" 2>/dev/null
  while [ "$i" -lt 50 ]; do
    hl_alive "$role" || return 0
    sleep 0.1; i=$((i + 1))
  done
  kill_tree "$pid"; kill -KILL "$pid" 2>/dev/null
  return 0
}

# hl_finish_close <role> <pane> <reason> — close the viewer pane, drop the registry line, log
hl_finish_close() {
  herdr pane close "$2" >/dev/null || die "pane close failed for $2"
  pane_gone "$2" || die "pane $2 is still present after close; registry entry kept"
  unregister "$1" "$2"
  # a close ends the conversation: --keep must not resume a session across it
  rm -f "$ASK_DIR/$1.finished" "$ASK_DIR/$1.session"
  log_close "$1" "$2" "$3" headless
  echo "closed $1 ($2)"
}

# close_headless <role> <force> <skip-missing> — close_one for a headless role
close_headless() {
  local role=$1 force=$2 skip=$3 pane reason=${CLOSE_REASON:-manual}
  pane=$(hl_registered_pane "$role")
  if [ -z "$pane" ]; then
    [ "$skip" = 1 ] && return 0
    die "$role is not running"
  fi
  if hl_alive "$role"; then
    if [ "$force" != 1 ]; then
      echo "harness: $role has a run in progress (pid $(hl_pid "$role")); not closing (use --force to kill it)" >&2
      return 4
    fi
    hl_kill "$role"
    reason=force_kill
  elif [ "$force" != 1 ] && has_uncollected "$role"; then
    echo "harness: $role has a report that was not collected (harness report $role); not closing (use --force to close anyway)" >&2
    return 4
  fi
  hl_finish_close "$role" "$pane" "$reason"
}
