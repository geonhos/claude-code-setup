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

# viewer_mode — auto|pane|none: where a headless run is shown (env HARNESS_VIEWER, then config
# `viewer`, then the default). auto = a herdr pane when herdr is usable, else the background.
viewer_mode() {
  local v=${HARNESS_VIEWER:-}
  [ -n "$v" ] || v=$(jq -r '.viewer // empty' "$CONFIG_FILE" 2>/dev/null)
  case "$v" in auto|pane|none) echo "$v" ;; *) echo "$HARNESS_VIEWER_DEFAULT" ;; esac
}
hl_bg_note() { echo "harness: no herdr pane; running $1 in the background (watch: harness watch $1)" >&2; }

# env a background run must not inherit: the conductor's herdr and Claude identity (a denylist, not
# env -i: API keys, CLAUDE_CONFIG_DIR, proxies, PATH, HOME and TMPDIR pass through)
HL_ENV_STRIP="-u HERDR_ENV -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_SOCKET_PATH -u HERDR_BIN_PATH"
HL_ENV_STRIP="$HL_ENV_STRIP -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_AGENT -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION"
HL_ENV_STRIP="$HL_ENV_STRIP -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_PID -u CLAUDE_EFFORT -u CLAUDE_CODE_EXECPATH"

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

# hl_run_viewer <role> — the viewer pane of the role's current run: from .run (viewer=pane:<id> or
# viewer=bg), else (an older .run, or no run yet) the registered pane
hl_run_viewer() {
  local v
  v=$(sed -n 's/^viewer=//p' "$ASK_DIR/$1.run" 2>/dev/null | head -n 1)
  case "$v" in
    bg) ;;
    pane:*) printf '%s\n' "${v#pane:}" ;;
    *) hl_registered_pane "$1" ;;
  esac
}

# hl_pane <role> — print the role's viewer pane (empty = run in the background): reuse the
# registered one while it exists in this repo, else split a plain shell pane (no herdr agent) and
# register it. viewer auto falls back to the background when herdr is unusable or a split fails.
hl_pane() {
  local role=$1 pane out c dir mode
  mode=$(viewer_mode)
  case "$mode" in
    none) return 0 ;;
    auto) herdr_usable || { hl_bg_note "$role"; return 0; } ;;
    *) need_herdr ;;
  esac
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
    [ "$mode" = auto ] || die "pane split failed: $out"
    echo "harness: pane split failed: $out" >&2; hl_bg_note "$role"; return 0
  fi
  pane=$(printf '%s' "$out" | jq -r '.result.pane.pane_id // empty' 2>/dev/null)
  if [ -z "$pane" ]; then
    [ "$mode" = auto ] || die "pane split returned no pane id: $out"
    echo "harness: pane split returned no pane id: $out" >&2; hl_bg_note "$role"; return 0
  fi
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
  pane=$(hl_run_viewer "$role")
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
  echo "harness: $role finished without a report at $report; collect: harness report $(ask_ref "$role")"
  hl_view_tail "$role" 30; exit 3
}
# hl_view_tail <role> <n> — the last n lines the run showed: the viewer pane's screen, or for a
# background run the rendered stream (no pane to read)
hl_view_tail() {
  local role=$1 n=${2:-30} pane raw
  pane=$(hl_run_viewer "$role")
  if [ -n "$pane" ]; then
    if herdr_env_ok; then herdr pane read "$pane" 2>/dev/null | tail -n "$n"; fi
    return 0
  fi
  raw=$(jq -r '.stream_log // empty' "$ASK_DIR/$role.exit.json" 2>/dev/null)
  [ -n "$raw" ] || raw=$(awk 'NR == 1 { print $2 }' "$ASK_DIR/$role.stream" 2>/dev/null)
  if [ -n "$raw" ] && [ -f "$raw" ]; then harness-view < "$raw" 2>/dev/null | tail -n "$n"; fi
  return 0
}

# hl_spawn_bg <role> <id> <root> — start harness-run detached from this process tree: a double fork
# (the subshell exits at once, so the run is reparented to init and ask_finish's kill_tree never
# reaches it) in a new session (no controlling tty, and a pgid kill of the caller's call misses it).
# There is no setsid binary on macOS: perl does it. HARNESS_HL_NO_PERL=1 forces the fallback (tests).
hl_spawn_bg() {
  local role=$1 id=$2 root=$3 log
  case "$ASK_DIR" in /*) log=$ASK_DIR ;; *) log=$root/$ASK_DIR ;; esac
  log=$log/$role.runner.log
  if [ "${HARNESS_HL_NO_PERL:-}" != 1 ] && command -v perl >/dev/null 2>&1; then
    ( cd "$root" && exec env $HL_ENV_STRIP HARNESS_ROLE=worker CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000 HARNESS_RUN_VIEW=0 \
        nohup perl -MPOSIX -e 'POSIX::setsid() or die "setsid: $!"; exec @ARGV or die "exec: $!"' \
        harness-run "$role" "$id" "$root" </dev/null >>"$log" 2>&1 & )
  else
    # no perl: its own process group through job control (the session stays shared)
    ( cd "$root" || exit 1; set -m
      env $HL_ENV_STRIP HARNESS_ROLE=worker CLAUDE_CODE_AUTO_COMPACT_WINDOW=160000 HARNESS_RUN_VIEW=0 \
        nohup harness-run "$role" "$id" "$root" </dev/null >>"$log" 2>&1 & )
  fi
}

# hl_launch <role> <id> <pane> <resume> <max_s> <ctxb> <start_s> <poll> — write the run file, start
# harness-run (in the viewer pane, or detached in the background when <pane> is empty) and wait for
# its pid file; exits 1 when it never starts. Sets HL_PANE to the pane actually used ("" = background).
hl_launch() {
  local role=$1 id=$2 pane=$3 resume=$4 max_s=$5 ctxb=$6 start_s=$7 poll=$8 a="$ASK_DIR/$1" s0 root
  root=${ASK_WT:-$(pwd -P)}
  rm -f "$a.finished" "$a.exit.json" "$a.pid"
  printf 'resume=%s\nmax_s=%s\nctx_before=%s\nviewer=%s\n' "$resume" "$max_s" "$ctxb" "${pane:+pane:}${pane:-bg}" > "$a.run"
  # a worktree ask streams into the main checkout's log dir, tagged with its id8
  [ -z "$ASK_WT" ] || printf 'log_dir=%s\nlog_tag=%s\n' "$(pwd -P)/.harness/log" "$ASK_ID8" >> "$a.run"
  if [ -n "$pane" ]; then
    if ! herdr pane run "$pane" "$(printf 'harness-run %q %q %q' "$role" "$id" "$root")" >/dev/null 2>&1; then
      echo "harness: pane run failed for $pane" >&2
      [ "$(viewer_mode)" = auto ] || exit 1
      # nothing was started: drop the just-split pane and run in the background instead
      herdr pane close "$pane" >/dev/null 2>&1 || echo "harness: could not close pane $pane" >&2
      unregister "${ASK_KEY:-$role}" "$pane"
      [ -z "$ASK_WT" ] || wt_update pane ""
      hl_bg_note "$role"
      pane=""
      sed 's/^viewer=.*/viewer=bg/' "$a.run" > "$a.run.tmp.$$" && mv "$a.run.tmp.$$" "$a.run"
    fi
  fi
  HL_PANE=$pane
  [ -n "$pane" ] || hl_spawn_bg "$role" "$id" "$root"
  # the run announces itself with its pid file; a pane whose shell is busy never does. No fallback
  # to the background from here: the pane may still start harness-run later (two runs of one ask)
  s0=$(date +%s)
  until grep -q "^$id " "$a.pid" 2>/dev/null || hl_done "$role" "$id"; do
    if [ $(( $(date +%s) - s0 )) -ge "$start_s" ]; then
      if [ -n "$pane" ]; then
        echo "harness: $role's run did not start in $start_s s (is the pane $pane at a shell prompt?)" >&2
        show_pane_screen "$pane"
      else
        echo "harness: $role's background run did not start in $start_s s; runner log:" >&2
        tail -n 20 "$a.runner.log" >&2 2>/dev/null
      fi
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
  [ -z "$ASK_WT" ] || wt_update pane "$pane"   # "" for a background run
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
  pane=$HL_PANE   # a failed `pane run` under viewer auto fell back to the background
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

# hl_finish_close <role> <pane> <reason> — close the viewer pane (when there is one), drop the
# registry line and the conversation (--keep must not resume a session across a close), log
hl_finish_close() {
  local a="$ASK_DIR/$1"
  if [ -n "$2" ]; then
    herdr pane close "$2" >/dev/null || die "pane close failed for $2"
    pane_gone "$2" || die "pane $2 is still present after close; registry entry kept"
    unregister "$1" "$2"
  fi
  # .current ends the run slot: status shows "-" again (exit.json stays for the post-mortem)
  rm -f "$a.finished" "$a.session" "$a.current"
  log_close "$1" "${2:--}" "$3" headless
  echo "closed $1 (${2:-bg})"
}

# close_headless <role> <force> <skip-missing> — close_one for a headless role
close_headless() {
  local role=$1 force=$2 skip=$3 pane reason=${CLOSE_REASON:-manual}
  pane=$(hl_registered_pane "$role")
  # a registered pane cannot be closed while herdr is unusable: close the run state only
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
