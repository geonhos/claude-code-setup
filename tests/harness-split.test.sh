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
  # the loader names it explicitly (the loop list), and sits before the first function definition
  load=$(grep -n '^for m in ' "$ROOT/bin/harness" | head -1)
  OUT=$load
  check "$b: named in the loader list" [ -n "$m" ] && printf '%s\n' "$load" | grep -qw -- "$m"
done
loadn=${load%%:*}
firstfn=$(grep -nE '^[a-z_]+\(\) *\{' "$ROOT/bin/harness" | head -1 | cut -d: -f1)
OUT="loader at $loadn, first function at $firstfn"
check "loader precedes the first function in bin/harness" [ "$loadn" -lt "$firstfn" ]
# no glob in the loader
OUT=$(sed -n "${loadn},$((loadn+3))p" "$ROOT/bin/harness")
check "loader lists files, not a glob" [ -z "$(printf '%s' "$OUT" | grep -E 'lib/\*|harness-\*')" ]

# in-place protection: overwrite bin/harness and every lib file while a run is in flight (a slow
# jq stands in for a long ask); the run was read whole at start and must still finish normally
W=$(mktemp -d); WORKS="$WORKS $W"
mkdir -p "$W/bin" "$W/lib" "$W/fakebin" "$W/repo/.harness"
cp "$ROOT/bin/harness" "$W/bin/harness"; cp $LIBS "$W/lib/"
REALJQ=$(command -v jq)
printf '#!/bin/bash\nsleep 1\nexec "%s" "$@"\n' "$REALJQ" > "$W/fakebin/jq"; chmod +x "$W/fakebin/jq"
printf '{"ts":"2026-10-20T00:00:00Z","agent":"analyst","exit":0,"dur_s":5}\n' > "$W/repo/.harness/progress.jsonl"
( cd "$W/repo" && PATH="$W/fakebin:$PATH" env -u HARNESS_ROLE /bin/bash "$W/bin/harness" metrics --json > "$W/out" 2> "$W/err"; echo $? > "$W/rc" ) &
sleep 0.4
for f in "$W/bin/harness" "$W/lib/"*.sh; do printf 'echo CLOBBERED; exit 99\n' > "$f"; done
wait
OUT="rc=$(cat "$W/rc") $(head -c 300 "$W/out") $(head -c 300 "$W/err")"
check "in-place overwrite mid-run: run finishes normally" [ "$(cat "$W/rc")" = 0 ] && jq -e . "$W/out" >/dev/null 2>&1
check "in-place overwrite mid-run: injected text not executed" [ -z "$(grep CLOBBERED "$W/out" "$W/err")" ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
