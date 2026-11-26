# harness-lane.sh — per-issue work folders (git worktrees): `harness lane` (issue #63).
# Sourced eagerly by bin/harness: definitions only. Uses die/usage/cmd_init/hl_alive/AGENTS from it.

# lane_primary — path of the primary worktree (first entry of git's list), from any folder
lane_primary() { git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p'; }

# lane_mirror <json-line> — in a work folder, append the row just written to ./.harness/progress.jsonl
# also to the primary's file with "lane":"<issue#>" and refresh the primary's progress.md (#246 C), so
# `harness metrics` and the conductor see lane work after `harness lane rm`. Never fails the caller.
lane_mirror() {
  local prim b id
  lane_in_primary && return 0
  prim=$(lane_primary)
  [ -n "$prim" ] && [ -d "$prim/.harness/asks" ] || return 0
  b=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  case "$b" in
    feat/[0-9]*-*|fix/[0-9]*-*|docs/[0-9]*-*) id=${b#*/}; id=${id%%-*} ;;
    *) id=$(basename "$PWD") ;;
  esac
  { printf '%s\n' "$1" | jq -c --arg l "$id" '. + {lane: $l}' >> "$prim/.harness/progress.jsonl"; } 2>/dev/null \
    || { echo "harness: could not copy the progress row to $prim (folder row kept)" >&2; return 0; }
  ( cd "$prim" && write_progress_md ) 2>/dev/null
  return 0
}

# lane_in_primary — 0 when the cwd is the primary worktree of a git repo
lane_in_primary() {
  local g c
  g=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  c=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || return 1
  [ "$(cd "$g" && pwd -P)" = "$c" ]
}

# lane_rows — "path<TAB>branch" for every non-primary worktree (path canonical, pwd -P)
lane_rows() {
  local p b
  git worktree list --porcelain | awk -v RS= -F'\n' 'NR > 1 { p = b = ""
    for (i = 1; i <= NF; i++) { if ($i ~ /^worktree /) p = substr($i, 10); if ($i ~ /^branch /) b = substr($i, 19) }
    print p "\t" b }' | while IFS="$(printf '\t')" read -r p b; do
    printf '%s\t%s\n' "$(cd "$p" 2>/dev/null && pwd -P || echo "$p")" "$b"
  done
}

# lane_running <path> — a worker of this folder is running
lane_running() {
  local a
  for a in $AGENTS; do ( cd "$1" 2>/dev/null && hl_alive "$a" ) && return 0; done
  return 1
}

# lane_pr <branch> — PR state (OPEN|MERGED|CLOSED) or empty (no PR, no gh)
lane_pr() { command -v gh >/dev/null 2>&1 && gh pr view "$1" --json state -q .state 2>/dev/null; }

# lane_prinfo <branch> — "STATE<TAB>headRefOid" of the branch's PR, or empty (no PR, no gh)
lane_prinfo() {
  command -v gh >/dev/null 2>&1 && gh pr view "$1" --json state,headRefOid -q '[.state,.headRefOid]|@tsv' 2>/dev/null
}

# lane_find <issue#|path> — "path<TAB>branch" of a work folder (issue numbers match lane branches only)
lane_find() {
  local t=$1 r
  [ ! -d "$t" ] || t=$(cd "$t" && pwd -P)
  r=$(lane_rows | awk -F'\t' -v t="$t" '$1 == t || (t ~ /^[0-9]+$/ && $2 ~ ("^(feat|fix|docs)/" t "-")) { print; exit }')
  [ -n "$r" ] && printf '%s\n' "$r"
}

# lane_ls — one row per folder; the PR state counts only when the PR head equals the folder's HEAD (as lane rm checks)
lane_ls() {
  local p b n s w info tab st oid num head pr
  tab=$(printf '\t')
  lane_rows | while IFS="$tab" read -r p b; do
    b=${b#refs/heads/}; n=${b#*/}; n=${n%%-*}
    info=""; [ -n "$b" ] && command -v gh >/dev/null 2>&1 \
      && info=$(gh pr view "$b" --json state,headRefOid,number -q '[.state,.headRefOid,.number]|@tsv' 2>/dev/null)
    IFS="$tab" read -r st oid num <<EOI
$info
EOI
    head=$(git -C "$p" rev-parse HEAD 2>/dev/null)
    if [ -n "$st" ] && [ -n "$oid" ] && [ "$head" = "$oid" ]; then pr="PR:$st"
    elif [ -n "$st" ]; then pr="PR:- (old #$num $(printf '%s' "$st" | tr 'A-Z' 'a-z'))"
    else pr="PR:-"; fi
    w=""
    ! lane_running "$p" || w=" running"
    printf '#%s  %s  %s  %s%s\n' "$n" "$b" "$p" "$pr" "$w"
  done
}

# lane_ignored_diff <primary> <dir> — ignored files of the work folder that differ from (or are missing in) the primary
# (AGENTS.md is skipped: init regenerates the ignored copy it made, #243)
lane_ignored_diff() {
  git -C "$2" ls-files --others --ignored --exclude-standard \
    | grep -Ev '^\.harness/|^\.claude/settings\.local\.json$|^AGENTS\.md$|(^|/)(node_modules|dist|build|\.venv|target|\.next|coverage|__pycache__)/' \
    | while IFS= read -r f; do
        if [ ! -e "$1/$f" ]; then echo "$f only in the work folder"
        elif ! cmp -s "$1/$f" "$2/$f"; then echo "$f differs from the original folder"; fi
      done
}

lane_new() {
  [ "${HARNESS_ROLE:-}" != worker ] || die "harness lane is for the conductor"
  local issue="" slug="" type=feat prim dir base branch hint setup shared=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --type) type=${2:-}; shift ;;
      -*) usage ;;
      *) if [ -z "$issue" ]; then issue=$1; elif [ -z "$slug" ]; then slug=$1; else usage; fi ;;
    esac
    shift
  done
  digits_only "$issue" || usage
  case "$type" in feat|fix|docs) ;; *) die "--type must be feat, fix or docs" ;; esac
  prim=$(lane_primary); [ -n "$prim" ] || die "not a git repository"
  dir=${prim%/*}/${prim##*/}-$issue
  if [ -z "$slug" ]; then
    slug=$(gh issue view "$issue" --json title -q .title 2>/dev/null | tr 'A-Z' 'a-z' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-30 | sed -E 's/-+$//')
    [ -n "$slug" ] || slug=task
  fi
  git fetch origin -q 2>/dev/null || echo "harness lane: git fetch origin failed; using the local refs" >&2
  base=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || base=origin/main
  if [ -d "$dir" ]; then
    lane_rows | awk -F'\t' -v d="$(cd "$dir" && pwd -P)" '$1 == d { f = 1 } END { exit !f }' \
      || die "$dir exists but is not a work folder of this repo (git worktree list); move it away or pick another issue"
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    echo "harness lane: $dir exists; reusing it ($branch)"
  else
    branch=$type/$issue-$slug
    if git show-ref --verify -q "refs/heads/$branch"; then
      git worktree add "$dir" "$branch" >&2 || die "git worktree add failed"
      echo "harness lane: branch $branch exists; reusing it"
    else
      git worktree add "$dir" -b "$branch" "$base" >&2 || die "git worktree add failed"
    fi
  fi
  # same mode as the primary: shared only when its committed settings already name the conductor
  ! jq -e '.agent == "conductor"' "$prim/.claude/settings.json" >/dev/null 2>&1 || shared=--shared
  ( cd "$dir" && cmd_init $shared ) || echo "harness lane: harness init failed in $dir" >&2
  setup=$(jq -r '.lane_setup // empty' "$dir/.claude/harness.json" 2>/dev/null)
  if [ -n "$setup" ]; then
    ( cd "$dir" && sh -c "$setup" ) || echo "harness lane: lane_setup failed in $dir (folder kept)" >&2
  fi
  echo "$dir"
}

lane_rm() {
  [ "${HARNESS_ROLE:-}" != worker ] || die "harness lane is for the conductor"
  local force="" t="" row p b info="" st="" oid="" head n tab prim base lost
  tab=$(printf '\t')
  while [ $# -gt 0 ]; do
    case "$1" in --force) force=1 ;; -*) usage ;; *) [ -z "$t" ] || usage; t=$1 ;; esac
    shift
  done
  [ -n "$t" ] || usage
  row=$(lane_find "$t") || die "no work folder for '$t' (harness lane ls)"
  p=${row%%"$tab"*}; b=${row#*"$tab"}; b=${b#refs/heads/}
  prim=$(lane_primary)
  lane_running "$p" && die "a worker is running in $p; wait for it or harness -C $p close <role>"
  if [ -n "$b" ]; then
    info=$(lane_prinfo "$b"); st=${info%%"$tab"*}
    case "$info" in *"$tab"*) oid=${info#*"$tab"} ;; esac
  elif [ -z "$force" ]; then
    die "work folder $p is on a detached HEAD; check out a branch first (or --force)"
  fi
  head=$(git -C "$p" rev-parse HEAD 2>/dev/null)
  if [ -z "$force" ]; then
    case "$st" in MERGED|CLOSED) ;; *) die "PR of $b is '${st:-none}', not merged or closed; merge it first (or --force)" ;; esac
    [ -n "$oid" ] && [ "$head" = "$oid" ] \
      || die "$b has commits that are not in its PR (local ${head:0:8}, PR ${oid:0:8}); push or rescue them first (or --force)"
    lost=$(lane_ignored_diff "$prim" "$p")
    [ -z "$lost" ] || die "ignored files would be lost in $p (--force to remove anyway):
$lost"
  else
    if [ -n "$oid" ] && git -C "$p" cat-file -e "$oid^{commit}" 2>/dev/null; then base=$oid
    else base=$(git -C "$p" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main); fi
    n=$(git -C "$p" rev-list --count "$base..HEAD" 2>/dev/null)
    echo "harness lane: --force; ${b:-detached HEAD} has ${n:-?} commit(s) not in a PR; uncommitted and ignored files in $p are discarded" >&2
  fi
  cd "$prim" || die "cannot enter the primary worktree"
  git worktree remove ${force:+--force} "$p" || die "git worktree remove failed for $p (uncommitted changes? --force)"
  [ -z "$b" ] || git branch -D "$b" >/dev/null || echo "harness lane: could not delete branch $b" >&2
  # a merged PR's branch is done (unless someone pushed to it after the merge); a closed PR keeps its remote branch
  if [ "$st" = MERGED ] && [ -n "$oid" ] && git ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1; then
    git push --force-with-lease="$b:$oid" origin --delete "$b" >/dev/null 2>&1 \
      || echo "harness lane: kept origin/$b (it has commits after the merged PR head, or the delete failed)" >&2
  fi
  echo "removed $p${b:+ and branch $b}"
}

cmd_lane() {
  case "${1:-}" in
    ls) lane_ls ;;
    rm) shift; lane_rm "$@" ;;
    *) lane_new "$@" ;;
  esac
}
