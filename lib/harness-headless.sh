# harness-headless.sh — the headless runner glue (decisions 0007, 0011): hl_*, ask/report/close_headless.
# Sourced eagerly by bin/harness (see the loader there): definitions only, no side effects.
# Shared helpers (die, has_uncollected, ...) stay in bin/harness and resolve at call time.

# --- headless runner (decision 0007) --------------------------------------------------------------
# `harness ask` writes the instruction to a file and starts `harness-run` (claude -p, stream-json)
# detached in the background. Completion = the run's .harness/asks/<role>.exit.json carrying this
# ask-id. A viewer is an optional herdr pane running `harness watch <role>`; it is closed when the
# run is collected or closed.

# viewer_mode — auto|pane|none: where a run is shown (env HARNESS_VIEWER, then config
# `viewer`, then the default). auto = a herdr pane when herdr is usable, else none.
viewer_mode() {
  local v=${HARNESS_VIEWER:-}
  [ -n "$v" ] || v=$(jq -r '.viewer // empty' "$CONFIG_FILE" 2>/dev/null)
  case "$v" in auto|pane|none) echo "$v" ;; *) echo "$HARNESS_VIEWER_DEFAULT" ;; esac
}
hl_bg_note() { echo "harness: no herdr pane; running $1 in the background (status: harness status; collect: harness report $1)" >&2; }

# env a background run must not inherit: the conductor's herdr and Claude identity (a denylist, not
# env -i: API keys, CLAUDE_CONFIG_DIR, proxies, PATH, HOME and TMPDIR pass through)
HL_ENV_STRIP="-u HERDR_ENV -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_SOCKET_PATH -u HERDR_BIN_PATH"
HL_ENV_STRIP="$HL_ENV_STRIP -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_AGENT -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION"
HL_ENV_STRIP="$HL_ENV_STRIP -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_PID -u CLAUDE_EFFORT -u CLAUDE_CODE_EXECPATH"

# hl_alive <role> — a harness-run for the role is running (pid file, live harness-run process)
hl_alive() {
  local f="$ASK_DIR/$1.pid" id pid
  [ -f "$f" ] || return 1
  read -r id pid _ < "$f"
  digits_only "${pid:-}" && kill -0 "$pid" 2>/dev/null || return 1
  ps -p "$pid" -o command= 2>/dev/null | grep -q 'harness-run'
}
# hl_last_session <role> — session id of the role's latest *successful* headless run (progress
# line with result "success" and a session). Old rows with an ask_id (the removed --worktree asks)
# are ignored, as in last_ask_record. A close event of the role is a boundary: when one came after the last such run, print "closed" instead (no session id looks like that).
hl_last_session() {
  [ -f "$JSONL" ] || return 1
  tail -n 200 "$JSONL" 2>/dev/null \
    | jq -R -n -r --arg r "$1" '
        reduce (inputs | fromjson? | select(type == "object")) as $e ({sid: "", closed: false};
          if $e.event == "close" then (if $e.role == $r and ($e.ask_id // "") == "" then {sid: "", closed: true} else . end)
          elif ($e.ask_id // "") != "" then .
          elif $e.agent == $r and $e.runner == "headless" and $e.result == "success" and (($e.session // "") != "") then {sid: $e.session, closed: false}
          else . end)
        | if .sid != "" then .sid elif .closed then "closed" else empty end' 2>/dev/null \
    | grep .
}
hl_pid() { awk 'NR == 1 { print $2 }' "$ASK_DIR/$1.pid" 2>/dev/null; }
# hl_done <role> <ask-id> — exit.json exists for that ask
hl_done() { grep -q "\"ask_id\":\"$2\"" "$ASK_DIR/$1.exit.json" 2>/dev/null; }

# hl_run_viewer <role> — the viewer pane of the role's current run, from .run (viewer=pane:<id>);
# empty for a run without one (viewer=bg)
hl_run_viewer() {
  local v
  v=$(sed -n 's/^viewer=//p' "$ASK_DIR/$1.run" 2>/dev/null | head -n 1)
  case "$v" in pane:*) printf '%s\n' "${v#pane:}" ;; esac
  return 0
}

# hl_open_viewer <role> — show the (already started) run in a herdr pane running `harness watch`:
# viewer none = nothing; auto = a pane when herdr is usable, else a note; pane = a pane (ask_headless
# refused the ask before launching when herdr is unusable). The run is a background run either way,
# so a failed split only warns. Records viewer=pane:<id> in .run.
hl_open_viewer() {
  local role=$1 a="$ASK_DIR/$1" mode out pane dir
  mode=$(viewer_mode)
  case "$mode" in
    none) return 0 ;;
    auto) herdr_usable || { hl_bg_note "$role"; return 0; } ;;
  esac
  dir=$(pick_direction)
  if ! out=$(herdr pane split --current --direction "$dir" --cwd "$PWD" --no-focus 2>&1); then
    echo "harness: pane split failed: $out" >&2; hl_bg_note "$role"; return 0
  fi
  pane=$(printf '%s' "$out" | jq -r '.result.pane.pane_id // empty' 2>/dev/null)
  if [ -z "$pane" ]; then
    echo "harness: pane split returned no pane id: $out" >&2; hl_bg_note "$role"; return 0
  fi
  if ! herdr pane run "$pane" "harness watch $role" >/dev/null 2>&1; then
    echo "harness: pane run failed for $pane" >&2
    herdr pane close "$pane" >/dev/null 2>&1 || echo "harness: could not close pane $pane" >&2
    hl_bg_note "$role"; return 0
  fi
  sed "s/^viewer=.*/viewer=pane:$pane/" "$a.run" > "$a.run.tmp.$$" && mv "$a.run.tmp.$$" "$a.run"
  return 0
}

# hl_close_viewer <role> [forget] — close the run's viewer pane (when herdr can be reached; with
# <forget> also when it cannot) and record viewer=bg. Never fails.
hl_close_viewer() {
  local role=$1 a="$ASK_DIR/$1" pane
  pane=$(hl_run_viewer "$role")
  [ -n "$pane" ] || return 0
  if herdr_env_ok; then herdr pane close "$pane" >/dev/null 2>&1 || true
  elif [ -z "${2:-}" ]; then return 0; fi
  sed 's/^viewer=.*/viewer=bg/' "$a.run" > "$a.run.tmp.$$" && mv "$a.run.tmp.$$" "$a.run"
  return 0
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

# hl_status_line <role> status|progress — one line for `harness status` / progress.md. Keyed on the
# run state, not the pane: a background run has no pane (column "bg")
hl_status_line() {
  local role=$1 mode=$2 pane st el ctx
  pane=$(hl_run_viewer "$role")
  if hl_alive "$role"; then st=running
  elif [ -f "$ASK_DIR/$role.current" ] || [ -n "$pane" ]; then st=idle
  else
    if [ "$mode" = status ]; then printf '%-12s %s\n' "$role" "-"; else printf '%s -' "$role"; fi
    return 0
  fi
  ctx=$(jq -r '.ctx // empty' "$ASK_DIR/$role.exit.json" 2>/dev/null)
  el=""
  [ "$st" != running ] || el=$(( $(date +%s) - $(awk 'NR == 1 { print $2 }' "$ASK_DIR/$role.current" 2>/dev/null || echo 0) ))
  if [ "$mode" = status ]; then
    if [ "$st" = running ]; then printf '%-12s %-8s %-8s hl %ss\n' "$role" "$st" "${pane:-bg}" "$el"
    else printf '%-12s %-8s %-8s hl ctx %s\n' "$role" "$st" "${pane:-bg}" "$(fmt_ctx "$ctx")"; fi
  else
    printf '%s %s ctx %s hl' "$role" "$st" "$(fmt_ctx "$ctx")"
  fi
}

# hl_collect <role> — a finished run (exit.json present): print the report or explain, exit.
# First match wins (spec §3). Never returns.
hl_collect() {
  local role=$1 ej="$ASK_DIR/$1.exit.json" report="$REPORT_DIR/$1.md" cur="$ASK_DIR/$1.current"
  local rc res iserr killed sid tinit perm ejc denied
  ejc=$(cat "$ej" 2>/dev/null)   # one read
  rc=$(jq -r '.rc // empty' <<<"$ejc" 2>/dev/null); res=$(jq -r '.result // empty' <<<"$ejc" 2>/dev/null)
  iserr=$(jq -r '.is_error // false' <<<"$ejc" 2>/dev/null); killed=$(jq -r '.killed // empty' <<<"$ejc" 2>/dev/null)
  sid=$(jq -r '(.session_id // "") | .[0:8]' <<<"$ejc" 2>/dev/null); tinit=$(jq -r '.t_init // empty' <<<"$ejc" 2>/dev/null)
  perm=$(jq -r '.perm // empty' <<<"$ejc" 2>/dev/null)
  if [ -n "$perm" ] && [ "$perm" != auto ]; then
    echo "harness: warning: $role ran with permission mode '$perm', not auto; tools may have been denied (see harness watch)" >&2
  fi
  denied=$(jq -r '(.denied // [])[] | "  - \(.tool): \(.input)\(if (.reason // "") != "" then " (" + .reason + ")" else "" end)"' <<<"$ejc" 2>/dev/null)
  restore_interrupted "$role" "$report"
  if [ -f "$report" ] && { [ ! -f "$cur" ] || [ ! "$report" -ot "$cur" ]; }; then
    [ -z "$denied" ] || printf 'harness: note: %s denied tool call(s):\n%s\n' "$(grep -c . <<<"$denied")" "$denied" >&2
    if { [ -n "$rc" ] && [ "$rc" != 0 ]; } || [ "$iserr" = true ]; then
      echo "harness: note: $role's run ended with ${res:-no result} (rc ${rc:-?}) but wrote a report" >&2
    fi
    finish_report "$role" "$report"
  fi
  if [ "$res" = error_max_turns ]; then
    echo "harness: $role stopped at the max-turns limit without a report; continue with: harness ask $role '...' --keep"
    hl_view_tail "$role" 30; exit 3
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
    hl_view_tail "$role" 30; exit 3
  fi
  # permissions blocked the worker and it wrote nothing: there is no answer to relay (exit 2), only when the run ended without errors
  if [ -n "$denied" ] && [ -z "$killed" ] && [ -n "$tinit" ]; then
    printf 'harness: %s was denied %s tool call(s) and wrote no report; nothing to answer. Re-ask with a changed brief:\n%s\n' \
      "$role" "$(grep -c . <<<"$denied")" "$denied"
    hl_view_tail "$role" 30; exit 2
  fi
  echo "harness: $role finished without a report at $report; collect: harness report $role"
  hl_view_tail "$role" 30; exit 3
}
# hl_view_tail <role> <n> — the last n lines the run showed: the rendered stream
hl_view_tail() {
  local role=$1 n=${2:-30} raw
  raw=$(jq -r '.stream_log // empty' "$ASK_DIR/$role.exit.json" 2>/dev/null)
  [ -n "$raw" ] || raw=$(awk 'NR == 1 { print $2 }' "$ASK_DIR/$role.stream" 2>/dev/null)
  if [ -n "$raw" ] && [ -f "$raw" ]; then harness-view < "$raw" 2>/dev/null | tail -n "$n"; fi
  return 0
}

# hl_spawn_bg <role> <id> <root> — start harness-run detached from this process tree: a double fork
# (the subshell exits at once, so the run is reparented to init and ask_finish's kill_tree never
# reaches it) in a new session (no controlling tty, and a pgid kill of the caller's call misses it).
# There is no setsid binary on macOS: perl does it. HARNESS_HL_NO_PERL=1 forces the fallback (tests).
# Under this spawn harness-run's INT/HUP traps are inert (an async start ignores INT, nohup ignores
# HUP); only TERM reaches it, which is what hl_kill sends. Intended.
hl_spawn_bg() {
  local role=$1 id=$2 root=$3 log
  case "$ASK_DIR" in /*) log=$ASK_DIR ;; *) log=$root/$ASK_DIR ;; esac
  log=$log/$role.runner.log
  if [ "${HARNESS_HL_NO_PERL:-}" != 1 ] && command -v perl >/dev/null 2>&1; then
    ( cd "$root" && exec env $HL_ENV_STRIP HARNESS_ROLE=worker CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000 \
        nohup perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' \
        harness-run "$role" "$id" "$root" </dev/null >>"$log" 2>&1 & )
  else
    # no perl: its own process group through job control (the session stays shared)
    ( cd "$root" || exit 1; set -m
      env $HL_ENV_STRIP HARNESS_ROLE=worker CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000 \
        nohup harness-run "$role" "$id" "$root" </dev/null >>"$log" 2>&1 & )
  fi
}

# hl_launch <role> <id> <resume> <max_s> <ctxb> <start_s> <poll> — write the run file, start
# harness-run detached in the background and wait for its pid file; exits 1 when it never starts.
# A second launch of the same ask (resume retry) keeps the viewer recorded in .run.
hl_launch() {
  local role=$1 id=$2 resume=$3 max_s=$4 ctxb=$5 start_s=$6 poll=$7 a="$ASK_DIR/$1" s0 root viewer
  root=$(pwd -P)
  viewer=$(sed -n 's/^viewer=//p' "$a.run" 2>/dev/null | head -n 1)
  rm -f "$a.finished" "$a.exit.json" "$a.pid"
  printf 'resume=%s\nmax_s=%s\nctx_before=%s\nviewer=%s\n' "$resume" "$max_s" "$ctxb" "${viewer:-bg}" > "$a.run"
  hl_spawn_bg "$role" "$id" "$root"
  # the run announces itself with its pid file
  s0=$(date +%s)
  until grep -q "^$id " "$a.pid" 2>/dev/null || hl_done "$role" "$id"; do
    if [ $(( $(date +%s) - s0 )) -ge "$start_s" ]; then
      echo "harness: $role's background run did not start in $start_s s; runner log:" >&2
      tail -n 20 "$a.runner.log" >&2 2>/dev/null
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

# hl_max_s <role> — the role's headless run cap in seconds: env, then config headless_max_minutes, then the default
hl_max_s() {
  local m=${HARNESS_HL_MAX_S:-}
  digits_only "$m" && { echo "$m"; return 0; }
  m=$(jq -r '.headless_max_minutes // empty' "$CONFIG_FILE" 2>/dev/null)
  digits_only "$m" && { echo $((m * 60)); return 0; }
  if [ "$1" = implementer ]; then echo "$HARNESS_HL_MAX_S_IMPLEMENTER_DEFAULT"; else echo "$HARNESS_HL_MAX_S_DEFAULT"; fi
}

# hl_clock_gap <prev-epoch> <now-epoch> <poll-s> — print the seconds to add to a deadline when the
# wall clock jumped between two polls (laptop sleep): a gap above 5x the poll interval + 5 s counts as a
# suspend; 0 otherwise. Pure arithmetic, so tests inject the timestamps.
hl_clock_gap() {
  awk -v p="$1" -v n="$2" -v i="${3:-2}" 'BEGIN { g = n - p; if (g > 5 * i + 5) printf "%d\n", g; else print 0 }'
}
# hl_deadline_bump <prev> <now> <poll> <deadline> [<cap-s> <deadline0>] — print the (possibly extended) deadline;
# one stderr line when it moved. With a cap, one bump is at most <cap-s> and all bumps together at most
# 2x<cap-s> over <deadline0> (the deadline before any bump), so a bogus clock jump cannot keep an ask alive forever.
hl_deadline_bump() {
  local g=0 cap=${5:-} d0=${6:-$4} room
  g=$(hl_clock_gap "$1" "$2" "$3")
  case "$cap" in ''|*[!0-9]*) cap=0 ;; esac
  if [ "$g" -gt 0 ] && [ "$cap" -gt 0 ]; then
    [ "$g" -le "$cap" ] || g=$cap
    room=$((2 * cap - ($4 - d0)))
    [ "$room" -gt 0 ] || room=0
    [ "$g" -le "$room" ] || g=$room
  fi
  if [ "$g" -gt 0 ]; then
    echo "harness: clock jumped ${g}s (sleep?); deadline extended" >&2
    echo $(($4 + g))
  else
    echo "$4"
  fi
}

# ask_headless <role> <text> <timeout-ms> <fresh> <keep> — the whole headless ask; always exits
ask_headless() {
  local role=$1 text=$2 timeout=$3 fresh=$4 keep=$5 id start retried resume="" sid max_s ctxb="" report="$REPORT_DIR/$1.md" last
  local a="$ASK_DIR/$role" now prev deadline dl0 poll=${HARNESS_POLL_SEC:-2} start_s=${HARNESS_HL_START_S:-15} s0 g
  mkdir -p "$ASK_DIR" "$REPORT_DIR" "$LOG_DIR"
  if hl_alive "$role"; then
    echo "harness: $role is still running (pid $(hl_pid "$role")); nothing sent. Collect with: harness report $role; stop: harness close $role --force" >&2
    exit 4
  fi
  if [ "$(viewer_mode)" = pane ] && ! herdr_usable; then die "viewer is 'pane' but herdr is not usable here (HERDR_ENV=1 and herdr on PATH); set viewer to auto or none"; fi
  hl_close_viewer "$role"   # the previous run is over: close its viewer before the record goes
  rm -f "$a.run"   # a stale viewer record must not carry over
  # implementer only (decision 0009, amends D6): after an ask that did not end cleanly the next one
  # continues the session; --fresh overrides, --keep needs no help
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
  rm -f "$report"
  id="$(date +%s)-$$-$RANDOM"; start=$(date +%s)
  printf '%s %s\n' "$id" "$start" > "$a.current"
  rm -f "$a.finished" "$a.exit.json" "$a.pid"
  if [ "$role" = implementer ]; then verify_tool baseline implementer 2>/dev/null || rm -f .harness/verify/implementer.json; fi
  max_s=$(hl_max_s "$role")
  printf '%s\n' "$text" > "$a.prompt"
  hl_launch "$role" "$id" "$resume" "$max_s" "$ctxb" "$start_s" "$poll"
  hl_open_viewer "$role"
  deadline=$((start + (timeout + 999) / 1000))
  # no --timeout: wait for the run to end (its cap plus a margin for the watchdog kill and exit.json), so a
  # background `harness ask` returns exactly when the run does and the conductor's task notification fires
  [ "${ASK_TIMEOUT_SET:-0}" = 1 ] || deadline=$((start + max_s + 30))
  prev=$(date +%s); dl0=$deadline
  retried=0
  while :; do
    if hl_done "$role" "$id"; then
      if [ "$retried" = 0 ] && hl_resume_missing "$role"; then
        # the session is gone: one fresh run in the same ask; the dead sid must not stay the resume target
        retried=1
        echo "harness: resume of ${resume:0:8} failed, running fresh" >&2
        resume=""; ctxb=""
        hl_launch "$role" "$id" "" "$max_s" "" "$start_s" "$poll"
        continue
      fi
      hl_close_viewer "$role"
      hl_collect "$role"
    fi
    if ! hl_alive "$role"; then
      # the runner may still be writing exit.json (jq, mv) as its pid disappears: give it ~3 s
      g=0; while [ "$g" -lt 30 ] && ! hl_done "$role" "$id"; do sleep 0.1; g=$((g + 1)); done
      if hl_done "$role" "$id"; then continue; fi
      hl_close_viewer "$role"
      sid=$(sed -n 1p "$a.session" 2>/dev/null | cut -c1-8)
      if [ -n "$sid" ]; then
        echo "harness: $role's run is gone without a result (killed?); --keep resumes session $sid"
      else
        echo "harness: $role's run is gone without a result (killed?); it recorded no session (--keep resumes the last successful one, if any)"
      fi
      exit 3
    fi
    now=$(date +%s)
    deadline=$(hl_deadline_bump "$prev" "$now" "$poll" "$deadline" "$max_s" "$dl0"); prev=$now
    if [ "$now" -ge "$deadline" ]; then
      if [ "$role" = implementer ] && [ -f "$report.pending" ]; then
        # the Stop hook has hidden the report while it verifies; the run is never killed at the deadline
        echo "harness: $role is still verifying (Stop hook running, $(cat .harness/verify/implementer.attempts 2>/dev/null || echo 0) failed attempt(s) so far, $((now - start))s); collect: harness report $role; stop: harness close $role --force" >&2
        exit 4
      fi
      echo "harness: $role is still running (pid $(hl_pid "$role"), $((now - start))s); collect: harness report $role; stop: harness close $role --force" >&2
      exit 4
    fi
    sleep "$poll"
  done
}

# report_headless <role> — `harness report` for a headless role; always exits
report_headless() {
  local role=$1 report="$REPORT_DIR/$1.md"
  if hl_alive "$role"; then
    echo "harness: still running ($(( $(date +%s) - $(awk 'NR == 1 { print $2 }' "$ASK_DIR/$role.current" 2>/dev/null || echo 0) ))s); harness wait $role blocks until done" >&2
    exit 4
  fi
  if [ ! -f "$ASK_DIR/$role.exit.json" ]; then
    echo "harness: no finished run for $role" >&2
    exit 3
  fi
  stamp_finished "$role"
  hl_close_viewer "$role"
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

# hl_finish_close <role> <pane> <reason> — close the viewer pane (when there is one), drop the
# conversation (--keep must not resume a session across a close), log
hl_finish_close() {
  local a="$ASK_DIR/$1"
  hl_close_viewer "$1" forget
  # .current ends the run slot: status shows "-" again (exit.json stays for the post-mortem)
  rm -f "$a.finished" "$a.session" "$a.current"
  log_close "$1" "${2:--}" "$3" headless
  echo "closed $1 (${2:-bg})"
}

# close_headless <role> <force> <skip-missing> — close the role's run slot: kill a live run (--force), close its viewer
close_headless() {
  local role=$1 force=$2 skip=$3 pane reason=manual
  pane=$(hl_run_viewer "$role")
  # a viewer pane cannot be closed while herdr is unusable: close the run state only
  if [ -n "$pane" ] && ! herdr_env_ok; then pane=""; fi
  if [ -z "$pane" ] && ! hl_alive "$role" && [ ! -f "$ASK_DIR/$role.current" ]; then
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

# hl_target <cmd> <target> — validate the role for wait/watch: sets ASK_AGENT; dies for an unknown one
hl_target() {
  case " $AGENTS " in
    *" $2 "*) ASK_AGENT=$2 ;;
    *) die "$1: unknown agent '$2' (expected one of: $AGENTS)" ;;
  esac
}
# hl_starting <role> <id> — the run was just launched and has not written its pid file yet
hl_starting() {
  local a="$ASK_DIR/$1" st
  grep -q "^$2 " "$a.pid" 2>/dev/null && return 1
  st=$(awk -v i="$2" 'NR == 1 && $1 == i { print $2 }' "$a.current" 2>/dev/null)
  digits_only "${st:-}" && [ $(( $(date +%s) - st )) -lt "${HARNESS_HL_START_S:-15}" ]
}

# cmd_wait <role> [--timeout ms] — block until the target's run ends; never collects.
# 0 done (exit.json carries the ask), 3 no ask / run gone without a result, 4 timeout.
cmd_wait() {
  local t=${1:-} timeout="" role id a start deadline dl0 max_s prev now g poll=${HARNESS_POLL_SEC:-2}
  [ -n "$t" ] || usage
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) case "${2:-}" in ''|*[!0-9]*|0) die "--timeout needs a number of milliseconds" ;; esac; timeout=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  hl_target wait "$t"
  role=$ASK_AGENT; a="$ASK_DIR/$role"
  id=$(awk 'NR == 1 { print $1 }' "$a.current" 2>/dev/null)
  [ -n "$id" ] || { echo "harness: no ask for $role" >&2; exit 3; }
  [ -n "$timeout" ] || timeout=$(( $(hl_max_s "$role") * 1000 ))
  start=$(date +%s); deadline=$((start + (timeout + 999) / 1000)); prev=$start; dl0=$deadline; max_s=$(hl_max_s "$role")
  while :; do
    if hl_done "$role" "$id"; then hl_close_viewer "$role"; echo "done; collect: harness report $role"; exit 0; fi
    if ! hl_alive "$role" && ! hl_starting "$role" "$id"; then
      # the runner may still be writing exit.json as its pid disappears: the same ~3 s grace as ask
      g=0; while [ "$g" -lt 30 ] && ! hl_done "$role" "$id"; do sleep 0.1; g=$((g + 1)); done
      if hl_done "$role" "$id"; then continue; fi
      echo "harness: $role's run is gone without a result (killed?); harness report $role explains" >&2
      exit 3
    fi
    now=$(date +%s)
    deadline=$(hl_deadline_bump "$prev" "$now" "$poll" "$deadline" "$max_s" "$dl0"); prev=$now
    if [ "$now" -ge "$deadline" ]; then
      echo "harness: $role is still running ($((now - start))s waited); harness wait $role again, or harness close $role --force" >&2
      exit 4
    fi
    sleep "$poll"
  done
}

# hl_stream_of <role> — the raw stream of the role's current/last run (empty when unknown): .stream when its
# id is the current ask, else exit.json's stream_log; a rotated stream is <raw>.gz
hl_stream_of() {
  local a="$ASK_DIR/$1" raw cur
  cur=$(awk 'NR == 1 { print $1 }' "$a.current" 2>/dev/null)
  raw=$(awk -v i="$cur" 'NR == 1 && $1 == i { print $2 }' "$a.stream" 2>/dev/null)
  [ -n "$raw" ] || raw=$(jq -r '.stream_log // empty' "$a.exit.json" 2>/dev/null)
  [ -n "$raw" ] || raw=$(awk 'NR == 1 { print $2 }' "$a.stream" 2>/dev/null)
  printf '%s' "$raw"
}

hl_stream_id() { awk 'NR == 1 { print $1 }' "$ASK_DIR/$1.stream" 2>/dev/null; }

# cmd_watch <role> [-n N] — human only: a live run as a redrawn dashboard (lib/harness-dash.sh), or print the last N
# (default 40) rendered lines of a finished one. 0 ok, 1 refused (not a tty), 3 no stream known.
cmd_watch() {
  local t=${1:-} n=40 role raw i id
  [ -n "$t" ] || usage
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      -n) case "${2:-}" in ''|*[!0-9]*) die "-n needs a number of lines" ;; esac; n=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -t 1 ] || die "watch is for a human terminal; the conductor reads the report"
  hl_target watch "$t"
  role=$ASK_AGENT
  id=$(awk 'NR == 1 { print $1 }' "$ASK_DIR/$role.current" 2>/dev/null)
  raw=$(hl_stream_of "$role"); i=0
  # a run that is still starting has not announced its stream yet: give it a few seconds
  while [ "$(hl_stream_id "$role")" != "$id" ] && [ "$i" -lt 100 ] && { hl_alive "$role" || hl_starting "$role" "$id"; }; do
    sleep 0.2; i=$((i + 1)); raw=$(hl_stream_of "$role")
  done
  if [ -z "$raw" ]; then echo "harness: no stream known for $t" >&2; exit 3; fi
  if ! hl_alive "$role"; then
    if [ -f "$raw" ]; then harness-view < "$raw" | tail -n "$n"
    elif [ -f "$raw.gz" ]; then gzip -dc "$raw.gz" | harness-view | tail -n "$n"
    else echo "harness: stream $raw is gone" >&2; exit 3; fi
    exit 0
  fi
  # live: a dashboard redrawn every HARNESS_DASH_SEC (2 s), then a final frame (result + report head)
  trap 'dash_end; exit 130' INT TERM
  dash_begin
  while hl_alive "$role" && ! hl_done "$role" "$id"; do
    dash_paint "$(hl_dash_frame "$role" "$raw")"
    sleep "${HARNESS_DASH_SEC:-2}"
  done
  sleep 1   # let the runner write exit.json
  dash_paint "$(HARNESS_DASH_FINAL=1 hl_dash_frame "$role" "$raw")"
  dash_end
  exit 0
}
