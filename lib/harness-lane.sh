# harness-lane.sh — per-issue work folders (git worktrees): `harness lane` (issue #63).
# Sourced eagerly by bin/harness: definitions only. Uses die/usage/cmd_init/hl_alive/AGENTS from it.

# lane_primary — path of the primary worktree (first entry of git's list), from any folder
lane_primary() { git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p'; }

# lane_in_primary — 0 when the cwd is the primary worktree of a git repo
lane_in_primary() {
  local g c
  g=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  c=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P) || return 1
  [ "$(cd "$g" && pwd -P)" = "$c" ]
}

# lane_rows — "path<TAB>branch" for every non-primary worktree
lane_rows() {
  git worktree list --porcelain | awk -v RS= -F'\n' 'NR > 1 { p = b = ""
    for (i = 1; i <= NF; i++) { if ($i ~ /^worktree /) p = substr($i, 10); if ($i ~ /^branch /) b = substr($i, 19) }
    print p "\t" b }'
}

# lane_running <path> — a worker of this folder is running
lane_running() {
  local a
  for a in $AGENTS; do ( cd "$1" 2>/dev/null && hl_alive "$a" ) && return 0; done
  return 1
}

# lane_pr <branch> — PR state (OPEN|MERGED|CLOSED) or empty (no PR, no gh)
lane_pr() { command -v gh >/dev/null 2>&1 && gh pr view "$1" --json state -q .state 2>/dev/null; }

# lane_find <issue#|path> — "path<TAB>branch" of a work folder
lane_find() {
  local t=$1 r
  [ ! -d "$t" ] || t=$(cd "$t" && pwd -P)
  r=$(lane_rows | awk -F'\t' -v t="$t" '$1 == t || $2 ~ ("/" t "(-|$)") { print; exit }')
  [ -n "$r" ] && printf '%s\n' "$r"
}

lane_ls() {
  local p b n s w
  lane_rows | while IFS="$(printf '\t')" read -r p b; do
    b=${b#refs/heads/}; n=${b#*/}; n=${n%%-*}
    s=$(lane_pr "$b"); w=""
    ! lane_running "$p" || w=" running"
    printf '#%s  %s  %s  PR:%s%s\n' "$n" "$b" "$p" "${s:--}" "$w"
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
  local force="" t="" row p b st
  while [ $# -gt 0 ]; do
    case "$1" in --force) force=1 ;; -*) usage ;; *) [ -z "$t" ] || usage; t=$1 ;; esac
    shift
  done
  [ -n "$t" ] || usage
  row=$(lane_find "$t") || die "no work folder for '$t' (harness lane ls)"
  p=${row%%$(printf '\t')*}; b=${row#*$(printf '\t')}; b=${b#refs/heads/}
  lane_running "$p" && die "a worker is running in $p; wait for it or harness -C $p close <role>"
  st=$(lane_pr "$b")
  if [ -z "$force" ]; then
    case "$st" in MERGED|CLOSED) ;; *) die "PR of $b is '${st:-none}', not merged or closed; merge it first (or --force)" ;; esac
  fi
  cd "$(lane_primary)" || die "cannot enter the primary worktree"
  git worktree remove ${force:+--force} "$p" || die "git worktree remove failed for $p (uncommitted changes? --force)"
  git branch -D "$b" >/dev/null || echo "harness lane: could not delete branch $b" >&2
  if git ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1; then
    git push origin --delete "$b" >/dev/null 2>&1 || echo "harness lane: could not delete origin/$b" >&2
  fi
  echo "removed $p and branch $b"
}

cmd_lane() {
  case "${1:-}" in
    ls) lane_ls ;;
    rm) shift; lane_rm "$@" ;;
    *) lane_new "$@" ;;
  esac
}
