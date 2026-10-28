# harness-worktree.sh — `--worktree` asks: wt_* registry, checkout, copy-back, reap (decision 0008).
# Sourced eagerly by bin/harness (see the loader there): definitions only, no side effects.

# --- worktree asks (decision 0008, S1) ----------------------------------------------------------
# A `--worktree` ask of a headless analyst/reviewer runs in its own detached checkout
# $WT_HOME/<repo8>/<role>-<id8>. The registry .harness/wt/<ask-id>.json (main root) tracks it;
# <ask-id>.report.md keeps the collected report after the checkout is removed.

# ask_ref <role> — what a message tells the conductor to pass to report/close
ask_ref() { if [ -n "$ASK_WT" ]; then printf '%s' "$ASK_ID"; else printf '%s' "$1"; fi; }

# ask_wt_check <agent> — validates what ask_parse_args found (ASK_WT_WANT/HAS_BASE/BASE_REF) and
# sets ASK_BASE; usage errors exit 1 here, before any file access, so they queue no retro candidate
ask_wt_check() {
  local agent=$1 base=$ASK_BASE_REF
  [ "$ASK_BASE_NOVAL" = 0 ] || die "--base needs a ref"
  [ "$ASK_HAS_BASE" = 0 ] || [ "$ASK_WT_WANT" = 1 ] || die "--base is only with --worktree (usage: harness ask <analyst|reviewer> '<instruction>' --worktree [--base REF])"
  [ "$ASK_WT_WANT" = 1 ] || return 0
  role_in "$agent" "$HARNESS_WT_ROLES" || die "--worktree is for the headless analyst and reviewer only (not $agent)"
  is_headless "$agent" || die "--worktree needs the headless runner for $agent (config runner.$agent=headless or HARNESS_RUNNER_$(printf %s "$agent" | tr 'a-z' 'A-Z')=headless)"
  [ "$ASK_KEEP" = 0 ] || die "--keep cannot be combined with --worktree (every worktree ask is a fresh session)"
  wt_root_check
  ASK_BASE=$(git rev-parse --verify --quiet "${base:-HEAD}^{commit}") || die "--base: '${base:-HEAD}' is not a commit"
}

# wt_root_check — HARNESS_WT_ROOT must be absolute, outside the git toplevel and outside .harness/
# (a checkout inside the repo would show up in its own status and in every search of it)
wt_root_check() {
  local top p
  case "$WT_HOME" in /*) ;; *) die "HARNESS_WT_ROOT must be an absolute path (got '$WT_HOME')" ;; esac
  case "/$WT_HOME/" in */../*) die "HARNESS_WT_ROOT must not contain a '..' component (got '$WT_HOME')" ;; esac
  case "$WT_HOME" in */.harness|*/.harness/*) die "HARNESS_WT_ROOT must not be inside a .harness/ directory (got '$WT_HOME')" ;; esac
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  # resolve symlinks through the nearest existing ancestor (the root itself may not exist yet)
  local rest="" d=$WT_HOME real
  while [ ! -d "$d" ] && [ "$d" != / ]; do rest="/${d##*/}$rest"; d=${d%/*}; [ -n "$d" ] || d=/; done
  real=$(cd "$d" 2>/dev/null && pwd -P)${rest}
  for p in "$top" "$(cd "$top" && pwd -P)" "$(pwd -P)"; do
    case "$WT_HOME/" in "$p"/*) die "HARNESS_WT_ROOT must be outside the repository (got '$WT_HOME', repo $top)" ;; esac
    case "$real/" in "$p"/*) die "HARNESS_WT_ROOT must be outside the repository (got '$WT_HOME', repo $top)" ;; esac
  done
}

wt_max_parallel() {
  local v=${HARNESS_MAX_PARALLEL:-}
  [ -n "$v" ] || v=$(jq -r '.max_parallel // empty' "$CONFIG_FILE" 2>/dev/null)
  if digits_only "$v" && [ "$v" -gt 0 ]; then echo "$v"; else echo 3; fi
}

# wt_run_alive <wt-path> <role> — a harness-run of that worktree is running
wt_run_alive() {
  local f="$1/.harness/asks/$2.pid" id pid
  [ -f "$f" ] || return 1
  read -r id pid _ < "$f"
  digits_only "${pid:-}" && kill -0 "$pid" 2>/dev/null || return 1
  ps -p "$pid" -o command= 2>/dev/null | grep -q 'harness-run'
}

# wt_entry_live <registry-file> — state running and the ask or its run is alive
wt_entry_live() {
  local f=$1 st pid path role
  st=$(jq -r '.state // empty' "$f" 2>/dev/null)
  [ "$st" = running ] || return 1
  pid=$(jq -r '.pid // empty' "$f" 2>/dev/null)
  if digits_only "$pid" && kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q 'harness'; then return 0; fi
  path=$(jq -r '.path // empty' "$f" 2>/dev/null); role=$(jq -r '.role // empty' "$f" 2>/dev/null)
  [ -n "$path" ] && wt_run_alive "$path" "$role"
}

# wt_capacity_check — refuse (exit 4, nothing logged) when max_parallel worktree asks are live
wt_capacity_check() {
  local f n=0 max
  max=$(wt_max_parallel)
  for f in "$WT_DIR"/*.json; do
    [ -f "$f" ] || continue
    ! wt_entry_live "$f" || n=$((n + 1))
  done
  if [ "$n" -ge "$max" ]; then
    echo "harness: $n worktree asks are running (max_parallel $max); wait for one (harness status) or collect/close it" >&2
    exit 4
  fi
}

# wt_update <key> <value> — set a string field of this ask's registry entry (tmp + mv, under a
# lock). A terminal state (closed by `close`, reaped) is never overwritten by another state: a
# `close --force` racing the ask's own wrap-up wins.
wt_update() {
  local reg="$WT_DIR/$ASK_ID.json" tmp cur rc=0
  [ -f "$reg" ] || return 0
  lock_take "$reg.lock"
  if [ "$1" = state ]; then
    cur=$(jq -r '.state // empty' "$reg" 2>/dev/null)
    case "$cur" in closed|reaped) [ "$2" = "$cur" ] || { lock_drop "$reg.lock"; return 0; } ;; esac
  fi
  tmp=$(mktemp "$reg.XXXXXX") || { lock_drop "$reg.lock"; return 1; }
  if jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$reg" > "$tmp" 2>/dev/null; then mv "$tmp" "$reg"; else rm -f "$tmp"; rc=1; fi
  lock_drop "$reg.lock"
  return "$rc"
}

# wt_lookup <ref> — print the registry file of an ask-id, an id8, or role@id8
wt_lookup() {
  local ref=$1 f
  [ -d "$WT_DIR" ] || return 1
  case "$ref" in ''|*/*|-*) return 1 ;; esac
  if [ -f "$WT_DIR/$ref.json" ]; then printf '%s\n' "$WT_DIR/$ref.json"; return 0; fi
  for f in "$WT_DIR"/*.json; do
    [ -f "$f" ] || continue
    if [ "$(jq -r '[.id8, (.role + "@" + .id8)] | index("'"$ref"'") // empty' "$f" 2>/dev/null)" != "" ]; then printf '%s\n' "$f"; return 0; fi
  done
  return 1
}

# wt_load <registry-file> — set the per-ask globals from it
wt_load() {
  ASK_ID=$(jq -r '.id' "$1"); ASK_ID8=$(jq -r '.id8' "$1"); ASK_AGENT=$(jq -r '.role' "$1")
  ASK_WT=$(jq -r '.path' "$1"); ASK_BASE=$(jq -r '.base // ""' "$1")
  ASK_KEY="$ASK_AGENT@$ASK_ID8"
  ASK_DIR="$ASK_WT/.harness/asks"; REPORT_DIR="$ASK_WT/.harness/reports"
}

# wt_copy_in <rel> — copy a main-root .harness/ file into the worktree; records top-level .md
# files (sha) in $WT_DIR/<ask-id>.in so copy-back can tell what the worker changed
wt_copy_in() {
  local rel=$1
  mkdir -p "$ASK_WT/$(dirname "$rel")" && cp "$rel" "$ASK_WT/$rel" || return 1
  case "$rel" in .harness/*/*) ;; .harness/*.md) printf '%s %s\n' "$(file_sum "$rel")" "${rel#.harness/}" >> "$WT_DIR/$ASK_ID.in" ;; esac
  return 0
}

# wt_git <git args> — git worktree add/remove/prune are not safe to run side by side (concurrent
# asks failed with "failed to read .git/worktrees/<n>/commondir"): serialise them under a lock
wt_git() {
  local rc
  mkdir -p "$WT_DIR" 2>/dev/null
  lock_take "$WT_DIR/.git.lock"
  git "$@"; rc=$?
  lock_drop "$WT_DIR/.git.lock"
  return $rc
}

# wt_create — git worktree add --detach, per-ask dirs, brief copy, memory link, registry.
# The registry entry is written first (state creating); a failing later step removes the checkout.
wt_create() {
  local out
  mkdir -p "$WT_DIR" "$WT_HOME/$REPO8" || return 1
  if ! out=$(wt_git worktree add --detach "$ASK_WT" "$ASK_BASE" 2>&1); then
    echo "harness: git worktree add failed: $out" >&2
    return 1
  fi
  jq -n -c --arg id "$ASK_ID" --arg id8 "$ASK_ID8" --arg role "$ASK_AGENT" --arg path "$ASK_WT" --arg base "$ASK_BASE" \
    --argjson pid "$$" --argjson cs "$(date +%s)" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{id: $id, id8: $id8, role: $role, path: $path, base: $base, branch: null, pane: "", pid: $pid, created: $ts, created_s: $cs, state: "creating"}' \
    > "$WT_DIR/$ASK_ID.json" || { wt_create_undo; return 1; }
  if ! wt_create_rest; then
    echo "harness: could not prepare the worktree $ASK_WT; removed it" >&2
    wt_create_undo
    return 1
  fi
  wt_update state running
  echo "harness: ask $ASK_ID ($ASK_AGENT@$ASK_ID8) in $ASK_WT (base ${ASK_BASE:0:8}); collect: harness report $ASK_ID; stop: harness close $ASK_ID --force" >&2
}

wt_create_undo() {
  rm -f "$ASK_WT/.claude/agent-memory" 2>/dev/null
  wt_git worktree remove --force "$ASK_WT" >/dev/null 2>&1 || rm -rf "$ASK_WT"
  wt_git worktree prune 2>/dev/null
  wt_update state closed
  return 0
}

wt_create_rest() {
  local mm f rel seen="" q r
  mkdir -p "$ASK_DIR" "$REPORT_DIR" || return 1
  mm="$(pwd -P)/.claude/agent-memory"
  mkdir -p "$mm" "$ASK_WT/.claude" 2>/dev/null
  { [ -e "$ASK_WT/.claude/agent-memory" ] || [ -L "$ASK_WT/.claude/agent-memory" ]; } || ln -s "$mm" "$ASK_WT/.claude/agent-memory" || return 1
  : > "$WT_DIR/$ASK_ID.in" || return 1
  # the brief (and any other .harness/ file the instruction names) is not in git: copy it in; each
  # copied .harness/*.md is scanned once more for .harness/ files it names (a spec, a design)
  for rel in $(printf '%s\n' "$ASK_TEXT" | grep -oE '\.harness/[A-Za-z0-9._/-]+\.(md|json)' | sort -u) .harness/verify.local.json; do
    case "$rel" in *..*) continue ;; esac
    [ -f "$rel" ] || continue
    wt_copy_in "$rel" || return 1
    seen="$seen $rel"
  done
  for q in $seen; do
    case "$q" in *.md) ;; *) continue ;; esac
    for r in $(grep -oE '\.harness/[A-Za-z0-9._/-]+\.(md|json)' "$q" 2>/dev/null | sort -u); do
      case "$r" in *..*) continue ;; esac
      case " $seen " in *" $r "*) continue ;; esac
      [ -f "$r" ] || continue
      wt_copy_in "$r" || return 1
    done
  done
  return 0
}

# wt_copy_back — new or changed top-level <wt>/.harness/*.md files (detail files, designs) go back
# to the main .harness/ (an allowlist: regular top-level *.md files only, never goal.md, progress.md
# or task-*.md, which the harness writes itself; symlinks are skipped); a file the main root changed
# since the copy-in is not overwritten: the worker's version lands in <name>.<id8>.md.
wt_copy_back() {
  local f name base_sha cur_sha dest sum in="$WT_DIR/$ASK_ID.in"
  for f in "$ASK_WT"/.harness/*.md; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue   # regular files only: a symlink could point anywhere
    name=${f##*/}
    case "$name" in goal.md|progress.md|task-*.md) continue ;; esac   # the harness's own files
    sum=$(file_sum "$f")
    base_sha=$(awk -v n="$name" '$2 == n { print $1 }' "$in" 2>/dev/null | tail -n 1)
    if [ -n "$base_sha" ] && [ "$base_sha" = "$sum" ]; then continue; fi         # the copied-in brief, untouched
    if [ -z "$base_sha" ] && git -C "$ASK_WT" ls-files --error-unmatch ".harness/$name" >/dev/null 2>&1 \
       && git -C "$ASK_WT" diff --quiet -- ".harness/$name" 2>/dev/null; then continue; fi   # tracked, untouched
    dest=".harness/$name"
    if [ -f "$dest" ]; then
      cur_sha=$(file_sum "$dest")
      [ "$cur_sha" != "$sum" ] || continue
      if [ "$cur_sha" != "$base_sha" ]; then dest=".harness/${name%.md}.$ASK_ID8.md"; fi
    fi
    mkdir -p .harness && cp "$f" "$dest" || continue
    if [ "$dest" = ".harness/$name" ]; then
      echo "harness: $ASK_KEY wrote $dest (copied back from the worktree)"
    else
      echo "harness: $ASK_KEY wrote $dest (main .harness/$name changed meanwhile; not overwritten)"
    fi
  done
}

# wt_patch — any other change in the worktree (tracked or untracked, outside .harness/) is saved
# as $WT_DIR/<ask-id>.patch in the main root. Sets WT_PATCH to the path, or "" when there is none.
wt_patch() {
  local p="$WT_DIR/$ASK_ID.patch" msg
  WT_PATCH=""
  [ -d "$ASK_WT" ] || return 0   # checkout gone: the saved patch stays (it outlives the worktree)
  # A saved patch is replaced only by a new, non-empty one: a tree cleaned in place after the
  # patch was written keeps it (it is the only copy of those changes).
  wt_clean "$ASK_WT" && return 0
  # add warns (rc 1) about the ignored .harness/ pathspec although it staged everything else
  git -C "$ASK_WT" add -A -- . ':!.harness' ':!.claude/agent-memory' >/dev/null 2>&1
  # diff against the recorded base, not HEAD: commits the worker made in the detached checkout count
  git -C "$ASK_WT" diff --cached --binary "${ASK_BASE:-HEAD}" -- . ':!.harness' ':!.claude/agent-memory' > "$p.tmp" 2>/dev/null
  if [ -s "$p.tmp" ]; then
    mv "$p.tmp" "$p"
    WT_PATCH=$p
    msg="harness: $ASK_KEY changed files outside .harness/; saved as a patch: $p (apply it via /implement; worktree kept)"
    echo "$msg"; echo "$msg" >&2
  else
    rm -f "$p.tmp"
  fi
  return 0
}

# wt_finalize — before any removal: keep the report, bring results back, patch other edits
wt_finalize() {
  [ ! -f "$REPORT_DIR/$ASK_AGENT.md" ] || cp "$REPORT_DIR/$ASK_AGENT.md" "$WT_DIR/$ASK_ID.report.md" 2>/dev/null
  [ -d "$ASK_WT" ] || return 0
  wt_copy_back
  wt_patch
}

# wt_clean <path> — nothing to lose: no modified or untracked files (ignoring the agent-memory link
# harness made), and the tree equals the base the checkout was created from. A worker commit moves
# HEAD off the base; that still counts as clean when the tree is back at the base (a commit
# reverted, an empty commit) because there is then no diff to lose.
wt_clean() {
  local ex=(':!.harness' ':!.claude/agent-memory')
  [ -d "$1" ] || return 1
  if [ -n "$ASK_BASE" ] && [ "$(git -C "$1" rev-parse HEAD 2>/dev/null)" != "$ASK_BASE" ]; then
    git -C "$1" diff --quiet "$ASK_BASE" -- . "${ex[@]}" 2>/dev/null || return 1
    ! git -C "$1" status --porcelain --untracked-files=all 2>/dev/null | grep -E '^\?\? ' | grep -vE '^\?\? (\.claude/agent-memory|\.harness/.*)$' | grep -q .
    return
  fi
  ! git -C "$1" status --porcelain --untracked-files=all 2>/dev/null | grep -vE '^\?\? (\.claude/agent-memory|\.harness/.*)$' | grep -q .
}

# wt_remove <force> <state> — remove this ask's checkout (agent-memory link first), prune, close its pane
wt_remove() {
  local force=$1 state=$2 link="$ASK_WT/.claude/agent-memory" target="" pane out reg="$WT_DIR/$ASK_ID.json"
  if [ -d "$ASK_WT" ]; then
    if [ -L "$link" ]; then target=$(readlink "$link"); rm -f "$link"; fi
    if [ "$force" = 1 ]; then out=$(wt_git worktree remove --force "$ASK_WT" 2>&1); else out=$(wt_git worktree remove "$ASK_WT" 2>&1); fi || {
      [ -z "$target" ] || ln -s "$target" "$link" 2>/dev/null
      echo "harness: git worktree remove failed: $out" >&2
      return 1
    }
  fi
  wt_git worktree prune 2>/dev/null
  pane=$(jq -r '.pane // empty' "$reg" 2>/dev/null)
  if [ -n "$pane" ]; then
    herdr pane close "$pane" >/dev/null 2>&1 || true
    unregister "$ASK_KEY" "$pane" 2>/dev/null || true
  fi
  wt_update state "$state"
  return 0
}

# wt_after_ask <rc> — after an ask (or a late `harness report`): save the report, bring results back
# (.harness/*.md files, other edits as a patch), then remove the checkout when the report was
# collected (rc 0/5) and nothing is left in it; else keep it. Prints notes on stdout (the ask output).
wt_after_ask() {
  local rc=$1 reg="$WT_DIR/$ASK_ID.json" role=$ASK_AGENT g=0
  [ -f "$reg" ] || return 0
  [ -d "$ASK_WT" ] || return 0
  if [ -f "$ASK_DIR/$role.exit.json" ]; then
    while [ "$g" -lt 30 ] && wt_run_alive "$ASK_WT" "$role"; do sleep 0.1; g=$((g + 1)); done
  fi
  if wt_run_alive "$ASK_WT" "$role"; then wt_update state running; return 0; fi
  wt_finalize
  case "$rc" in
    0|5)
      if [ -z "$WT_PATCH" ]; then
        if wt_clean "$ASK_WT"; then
          wt_remove 0 collected && return 0
        else
          echo "harness: worktree $ASK_WT has changes; kept (harness close $ASK_ID --force removes it)" >&2
        fi
      fi ;;
    *) echo "harness: ask $ASK_ID ended with exit $rc; worktree $ASK_WT kept (harness report $ASK_ID, or harness close $ASK_ID --force)" >&2 ;;
  esac
  wt_update state kept
  return 0
}

# report_wt <registry-file> — `harness report <ask-id>`; always exits
report_wt() {
  local rc saved
  wt_load "$1"
  if [ ! -d "$ASK_WT" ]; then
    saved="$WT_DIR/$ASK_ID.report.md"
    [ ! -f "$saved" ] || finish_report "$ASK_AGENT" "$saved" -
    echo "harness: worktree of $ASK_ID is gone and no report was saved" >&2
    exit 3
  fi
  ( report_headless "$ASK_AGENT" ); rc=$?
  case "$rc" in 4) ;; *) wt_after_ask "$rc" ;; esac
  exit "$rc"
}

# close_wt <registry-file> <force> — `harness close <ask-id>`
close_wt() {
  local f=$1 force=$2 pane old
  wt_load "$f"
  pane=$(jq -r '.pane // empty' "$f")
  if wt_run_alive "$ASK_WT" "$ASK_AGENT"; then
    if [ "$force" != 1 ]; then
      echo "harness: $ASK_KEY has a run in progress; not closing (use --force to kill it)" >&2
      return 4
    fi
    hl_kill "$ASK_AGENT"
  fi
  if [ "$force" = 1 ]; then
    # discarding the checkout is the point of --force: keep the report and the .harness/*.md results only
    [ ! -f "$REPORT_DIR/$ASK_AGENT.md" ] || cp "$REPORT_DIR/$ASK_AGENT.md" "$WT_DIR/$ASK_ID.report.md" 2>/dev/null
    [ ! -d "$ASK_WT" ] || wt_copy_back
  else
    old=""; [ ! -s "$WT_DIR/$ASK_ID.patch" ] || old=$(file_sum "$WT_DIR/$ASK_ID.patch")
    wt_finalize
    if [ -n "$WT_PATCH" ]; then
      # the same patch as the saved one: nothing beyond it, so the checkout may go without --force
      if [ -n "$old" ] && [ "$(file_sum "$WT_PATCH")" = "$old" ]; then force=1
      else
        echo "harness: $ASK_KEY not closed: its other changes are in $WT_PATCH (use --force to discard the checkout)" >&2
        return 4
      fi
    fi
  fi
  if ! wt_remove "$force" closed; then
    echo "harness: $ASK_KEY not closed (use --force to discard its changes)" >&2
    return 4
  fi
  log_close "$ASK_KEY" "$pane" manual headless "$ASK_ID"
  echo "closed $ASK_KEY ($ASK_WT)"
}

# wt_status_lines — one line per running/kept worktree ask
wt_status_lines() {
  local f st now cs
  now=$(date +%s)
  for f in "$WT_DIR"/*.json; do
    [ -f "$f" ] || continue
    st=$(jq -r '.state // empty' "$f" 2>/dev/null)
    case "$st" in running|kept) ;; *) continue ;; esac
    if [ "$st" = running ] && ! wt_entry_live "$f"; then st=stale; fi
    cs=$(jq -r '.created_s // 0' "$f")
    printf '%-12s %-8s %-8s detached %ss%s\n' "$(jq -r '.role + "@" + .id8' "$f")" "$st" "$(jq -r '.pane // "-"' "$f")" "$((now - cs))" \
      "$([ ! -s "${f%.json}.patch" ] || printf ' patch %s' "${f%.json}.patch")"
  done
}

# wt_reap <ttl-minutes> <now> — checkouts of kept asks, and of `running` asks whose owner is gone
# (reboot, killed harness), past the TTL: results are brought back first; the checkout goes only
# when nothing is left in it. A worktree with a saved patch is never reaped; it stays `kept`
# until `harness close`. Old collected/closed/reaped entries (and their patch) are forgotten
# after HARNESS_LOG_DAYS.
wt_reap() {
  local ttl=$1 now=$2 f mt st days=${HARNESS_LOG_DAYS:-14}
  [ -d "$WT_DIR" ] || return 0
  for f in "$WT_DIR"/*.json; do
    [ -f "$f" ] || continue
    st=$(jq -r '.state // empty' "$f" 2>/dev/null)
    case "$st" in
      kept) ;;
      running) ! wt_entry_live "$f" || continue ;;
      creating) ! wt_entry_live_owner "$f" || continue ;;
      *) continue ;;
    esac
    # a worktree with a saved patch is never reaped (decision 0008): it waits for `harness close`
    [ ! -s "${f%.json}.patch" ] || continue
    mt=$(file_mtime "$f") || continue
    [ $((now - mt)) -ge $((ttl * 60)) ] || continue
    (
      wt_load "$f"
      if [ ! -d "$ASK_WT" ]; then wt_remove 0 reaped; exit 0; fi
      wt_finalize
      if [ -n "$WT_PATCH" ]; then wt_update state kept   # the patch now holds changes: keep it
      elif wt_clean "$ASK_WT"; then wt_remove 1 reaped
      else wt_update state kept; fi
    ) >&2 || true
  done
  wt_git worktree prune 2>/dev/null
  for f in "$WT_DIR"/*.json; do
    [ -f "$f" ] || continue
    case "$(jq -r '.state // empty' "$f" 2>/dev/null)" in collected|closed|reaped) ;; *) continue ;; esac
    mt=$(file_mtime "$f") || continue
    [ $((now - mt)) -ge $((days * 86400)) ] || continue
    rm -f "$f" "${f%.json}.report.md" "${f%.json}.in" "${f%.json}.patch"
  done
  return 0
}

# wt_entry_live_owner <registry-file> — the harness process that created the entry still runs
wt_entry_live_owner() {
  local pid
  pid=$(jq -r '.pid // empty' "$1" 2>/dev/null)
  digits_only "$pid" && kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= 2>/dev/null | grep -q 'harness'
}
