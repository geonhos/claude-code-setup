# harness-root.sh — the one `.harness` root lookup (decision 0011, step 6).
# Sourced eagerly by bin/harness, bin/harness-verify and both claude/hooks: definitions only.

# harness_root DIR -> prints the harness checkout root and returns 0, or returns 1.
# DIR is resolved physically (pwd -P) first.
# The root is the nearest dir at or above DIR with .harness/asks/, searched up to
# the dir holding .git (file or dir) inclusive; outside git only DIR counts.
# Callers must pass a non-empty DIR (an empty one searches from /).
harness_root() {
  local start d hit=""
  start=$(cd "${1:-/}" 2>/dev/null && pwd -P) || return 1
  d=$start
  while :; do
    if [ -z "$hit" ] && [ -d "$d/.harness/asks" ]; then hit=$d; fi
    if [ -e "$d/.git" ]; then
      [ -n "$hit" ] || return 1
      printf '%s' "$hit"
      return 0
    fi
    [ "$d" = / ] && break
    d=${d%/*}
    [ -n "$d" ] || d=/
  done
  [ -d "$start/.harness/asks" ] || return 1
  printf '%s' "$start"
}
