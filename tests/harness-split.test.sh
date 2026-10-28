#!/bin/bash
# Structure of the bin/harness + lib/*.sh split. Run: /bin/bash tests/harness-split.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$HERE/..
pass=0
fail=0
WORKS=""
trap 'for d in $WORKS; do rm -rf "$d"; done' EXIT
OUT=""
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi; }

# lib_named SCRIPT NAME — NAME is in SCRIPT's `for m in …` loader list
lib_named() { [ -n "$2" ] && grep -E '^for m in ' "$1" | head -1 | grep -qw -- "$2"; }
no_glob() { ! printf '%s' "$1" | grep -qE 'lib/\*|harness-\*'; }
not() { ! "$@"; }
# eager_ok SCRIPT — one `# end loader` marker, below the first function definition's line (so it cannot
# sit at EOF or after a lazy function); >=1 harness-*.sh source line, all above the marker.
# Limit: a textual check only; a source via a variable or eval is not detected.
eager_ok() {
  local mark srcs n fn
  mark=$(grep -n '^# end loader$' "$1" | cut -d: -f1)
  case $mark in ''|*[!0-9]*) OUT="$1: need exactly one '# end loader' marker"; return 1 ;; esac
  fn=$(grep -nE '^([a-zA-Z_][a-zA-Z0-9_]*\(\) *\{|function )' "$1" | head -1 | cut -d: -f1)
  if [ -n "$fn" ] && [ "$mark" -gt "$fn" ]; then OUT="$1: '# end loader' (line $mark) is below the first function (line $fn)"; return 1; fi
  srcs=$(grep -nvE '^[[:space:]]*#' "$1" | grep -E '^[0-9]+:([^#]*[;&|[:space:]])?(\.|source)[[:space:]]+[^#]*harness-' | cut -d: -f1)
  [ -n "$srcs" ] || { OUT="$1: no lib source found"; return 1; }
  for n in $srcs; do
    [ "$n" -lt "$mark" ] || { OUT="$1:$n sources a lib after '# end loader' (line $mark)"; return 1; }
  done
}
# all_listed SCRIPT LIBDIR — every LIBDIR/harness-*.sh is in SCRIPT's loader list
all_listed() {
  local f b
  for f in "$2"/harness-*.sh; do
    b=$(basename "$f" .sh)
    lib_named "$1" "${b#harness-}" || { OUT="${b#harness-} missing from loader list"; return 1; }
  done
}

# top-level function names of a file (column-0 `name() {`)
fnames() { grep -oE '^[a-zA-Z_][a-zA-Z_0-9]*\(\)' "$1" | sed 's/()$//'; }

LIBS=$(ls "$ROOT"/lib/harness-*.sh)
for f in $LIBS; do
  b=$(basename "$f" .sh); m=${b#harness-}
  check "$b: bash -n" bash -n "$f"
  # every function name is defined exactly once across bin/harness and lib/*.sh
  OUT=$(for n in $(fnames "$f"); do
          c=$(cat "$ROOT/bin/harness" $LIBS | grep -cE "^$n\(\)")
          [ "$c" -eq 1 ] || echo "$n defined $c times"
        done)
  check "$b: each function defined once" [ -z "$OUT" ]
  # sourcing defines only: no output, no exit, no side effects on the cwd
  d=$(mktemp -d); WORKS="$WORKS $d"
  OUT=$(cd "$d" && . "$f" 2>&1; echo "rc=$?")
  check "$b: sourcing prints nothing and exits 0" [ "$OUT" = "rc=0" ]
  OUT=$(ls -A "$d")
  check "$b: sourcing creates no files" [ -z "$OUT" ]
  # the loader names it explicitly (the loop list)
  OUT=$(grep -n '^for m in ' "$ROOT/bin/harness" | head -1)
  check "$b: named in the loader list" lib_named "$ROOT/bin/harness" "$m"
done
load=$(grep -n '^for m in ' "$ROOT/bin/harness" | head -1)
loadn=${load%%:*}
firstfn=$(grep -nE '^[a-z_]+\(\) *\{' "$ROOT/bin/harness" | head -1 | cut -d: -f1)
OUT="loader at $loadn, first function at $firstfn"
check "loader precedes the first function in bin/harness" [ "$loadn" -lt "$firstfn" ]
# no glob in the loader
OUT=$(sed -n "${loadn},$((loadn+3))p" "$ROOT/bin/harness")
check "loader lists files, not a glob" no_glob "$OUT"

# eager loading, structurally: every source of a harness-*.sh sits above `# end loader`, nowhere else
for s in harness harness-verify; do
  OUT=""
  check "bin/$s: libs sourced only inside the loader block" eager_ok "$ROOT/bin/$s"
done
check "bin/harness loads every lib/harness-*.sh" all_listed "$ROOT/bin/harness" "$ROOT/lib"
# test the test: a dropped list entry and a lazy source must both be caught
M=$(mktemp -d); WORKS="$WORKS $M"
sed 's/^for m in defaults metrics worktree;/for m in defaults metrics;/' "$ROOT/bin/harness" > "$M/dropped"
mkdir -p "$M/lib"; cp $LIBS "$M/lib/"
OUT="control: unmutated copy"
check "control: unmutated copy passes all_listed" all_listed "$ROOT/bin/harness" "$M/lib"
check "control: unmutated copy passes eager_ok" eager_ok "$ROOT/bin/harness"
OUT="mutant: worktree dropped from the list"
check "mutation: dropped list entry is caught" not all_listed "$M/dropped" "$M/lib"
cp "$ROOT/bin/harness" "$M/lazy"
printf '%s\n' '. "$HARNESS_LIB/harness-metrics.sh"' >> "$M/lazy"
OUT="mutant: lazy source after the loader"
check "mutation: lazy source is caught" not eager_ok "$M/lazy"
# marker moved to EOF (every source is then "above" it) and a lazy function defined above the marker
grep -v '^# end loader$' "$ROOT/bin/harness" > "$M/eof"; echo '# end loader' >> "$M/eof"
OUT="mutant: marker at EOF"
check "mutation: marker at EOF is caught" not eager_ok "$M/eof"
awk '/^# end loader$/ { print "lazy() { :; }" } { print }' "$ROOT/bin/harness" > "$M/fnbefore"
OUT="mutant: function defined before the marker"
check "mutation: function before marker is caught" not eager_ok "$M/fnbefore"

# in-place protection: overwrite bin/harness and every lib file while a run is in flight (a slow
# jq stands in for a long ask); the run was read whole at start and must still finish normally
W=$(mktemp -d); WORKS="$WORKS $W"
mkdir -p "$W/bin" "$W/lib" "$W/fakebin" "$W/repo/.harness"
cp "$ROOT/bin/harness" "$W/bin/harness"; cp $LIBS "$W/lib/"
REALJQ=$(command -v jq)
printf '#!/bin/bash\n: > "%s"\nsleep 1\nexec "%s" "$@"\n' "$W/started" "$REALJQ" > "$W/fakebin/jq"; chmod +x "$W/fakebin/jq"
printf '{"ts":"2026-10-20T00:00:00Z","agent":"analyst","exit":0,"dur_s":5}\n' > "$W/repo/.harness/progress.jsonl"
( cd "$W/repo" && PATH="$W/fakebin:$PATH" env -u HARNESS_ROLE /bin/bash "$W/bin/harness" metrics --json > "$W/out" 2> "$W/err"; echo $? > "$W/rc" ) &
# barrier: the fake jq creates $W/started once bin/harness is running (all sourcing is behind it)
i=0; while [ ! -e "$W/started" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
for f in "$W/bin/harness" "$W/lib/"*.sh; do printf 'echo CLOBBERED; exit 99\n' > "$f"; done
wait
OUT="rc=$(cat "$W/rc") $(head -c 300 "$W/out") $(head -c 300 "$W/err")"
run_ok() { [ -e "$W/started" ] && [ "$(cat "$W/rc")" = 0 ] && jq -e . "$W/out" >/dev/null 2>&1; }
check "in-place overwrite mid-run: run finishes normally" run_ok
check "in-place overwrite mid-run: injected text not executed" [ -z "$(grep CLOBBERED "$W/out" "$W/err")" ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
