#!/bin/bash
# SessionStart hook for the conductor (matcher: startup|clear|compact).
# Injects .harness/progress.md as additionalContext so a /clear, compaction or
# crash recovery resumes from the durable progress log. Silent for workers
# (HARNESS_ROLE=worker), when there is nothing to inject, or when jq is unavailable.
# Also appends the `(active,` lines of docs/wiki/index.md (at most WIKI_MAX bytes,
# default 2048, then a "… see docs/wiki/index.md" line). Workers get no SessionStart
# injection; they rely on the AGENTS.md pointer to the wiki index.
# Does nothing outside a harness checkout (no .harness/asks/ between the cwd and
# the repo top; decision 0010): no progress, no wiki, so it never injects into a repo
# that does not use the harness. Reads under the checkout root.
# Never fails: a SessionStart hook must not block a session.
[ "${HARNESS_ROLE:-}" = worker ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

dir=$PWD
if [ ! -t 0 ]; then
  c=$(cat 2>/dev/null | jq -r '.cwd // empty' 2>/dev/null)
  [ -z "$c" ] || [ ! -d "$c" ] || dir=$c
fi
# harness_root DIR -> prints the harness checkout root and returns 0, or returns 1.
# DIR is resolved physically (pwd -P) first, like enter_root.
# The root is the nearest dir at or above DIR with .harness/asks/, searched up to
# the dir holding .git (file or dir) inclusive; outside git only DIR counts. Same
# rule as enter_root in bin/harness-verify. This body is copied byte-for-byte into
# conductor-gate, -route and -resume (tests/gate.test.sh checks it).
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
root=$(harness_root "$dir") || exit 0
f="$root/.harness/progress.md"
ctx=""
if [ -s "$f" ]; then
  ctx=$(printf 'Harness progress (resume from here; verify with harness status)\n'; cat "$f"; printf x)
  ctx=${ctx%x}
fi

WIKI_HEADER="Wiki (active pages; read docs/wiki/index.md, open a page only when relevant)"
# wiki_lines <index> — active lines, capped so header + lines fit in WIKI_MAX bytes
wiki_lines() {
  LC_ALL=C awk -v max="${WIKI_MAX:-2048}" -v hdr="${#WIKI_HEADER}" '
    BEGIN { max -= hdr + 1; note = "… see docs/wiki/index.md"; used = 0 }
    index($0, "(active,") {
      if (cut) next
      if (used + length($0) + 1 > max - length(note) - 1) { cut = 1; next }
      print; used += length($0) + 1
    }
    END { if (cut) print note }
  ' "$1"
}
w="$root/docs/wiki/index.md"
if [ -s "$w" ]; then
  wl=$(wiki_lines "$w")
  if [ -n "$wl" ]; then
    [ -z "$ctx" ] || ctx="$ctx
"
    ctx="${ctx}$WIKI_HEADER
$wl
"
  fi
fi
[ -n "$ctx" ] || exit 0

printf '%s' "$ctx" \
  | jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: .}}' 2>/dev/null
exit 0
