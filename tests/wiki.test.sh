#!/bin/bash
# Tests for `harness wiki-lint` against fixture wiki dirs. Run: /bin/bash tests/wiki.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
pass=0
fail=0
WORKS=""
trap 'for d in $WORKS; do rm -rf "$d"; done' EXIT
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi; }
lint() { OUT=$(env -u HARNESS_ROLE /bin/bash "$HARNESS" wiki-lint "$1" 2>&1); RC=$?; }
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }

# mk — fresh valid wiki in $W: one gotcha, indexed
mk() {
  W=$(mktemp -d); WORKS="$WORKS $W"
  mkdir -p "$W/gotchas" "$W/inbox"
  printf -- '---\ntype: gotcha\nstatus: active\nupdated: 2026-10-21\nsources: [commit abc1234]\nverified_by: human\n---\n# A\nbody\n' > "$W/gotchas/a.md"
  printf '# Wiki index\n\n- [A](gotchas/a.md) — hook (active, 2026-10-21)\n' > "$W/index.md"
  printf '# log\n' > "$W/log.md"
}
setkey() { # setkey KEY VALUE FILE
  awk -v k="$1" -v v="$2" 'BEGIN { p = k ":" } index($0, p) == 1 { print k ": " v; next } { print }' "$3" > "$3.t" && mv "$3.t" "$3"
}

mk; lint "$W"
check "valid wiki passes" [ "$RC" -eq 0 ]
check "valid wiki silent" [ -z "$OUT" ]

lint "$W/"
check "trailing slash accepted" [ "$RC" -eq 0 ]
lint "$W//"
check "double trailing slash accepted" [ "$RC" -eq 0 ]

lint "$W/nope"
check "missing dir fails" [ "$RC" -eq 1 ]

mk; setkey type bogus "$W/gotchas/a.md"; lint "$W"
check "invalid type" has "gotchas/a.md: invalid type: bogus"
check "invalid type rc" [ "$RC" -eq 1 ]

mk; setkey status done "$W/gotchas/a.md"; lint "$W"
check "invalid status" has "invalid status: done"

mk; setkey updated 21-10-2026 "$W/gotchas/a.md"; lint "$W"
check "invalid date" has "invalid updated date"

mk; setkey sources "[]" "$W/gotchas/a.md"; lint "$W"
check "empty sources" has "sources is empty"

mk; setkey sources "commit abc" "$W/gotchas/a.md"; lint "$W"
check "sources must be list" has "sources must be a [list]"

mk; grep -v '^verified_by' "$W/gotchas/a.md" > "$W/x" && mv "$W/x" "$W/gotchas/a.md"; lint "$W"
check "missing key" has "frontmatter key missing or empty: verified_by"

mk; printf '# no frontmatter\n' > "$W/gotchas/a.md"; lint "$W"
check "no frontmatter" has "gotchas/a.md: missing frontmatter"

mk; printf -- '---\ntype: gotcha\n' > "$W/gotchas/a.md"; lint "$W"
check "unclosed frontmatter" has "frontmatter not closed"

mk; cp "$W/gotchas/a.md" "$W/gotchas/b.md"; lint "$W"
check "unlisted page" has "gotchas/b.md: listed 0 times"
check "unlisted rc" [ "$RC" -eq 1 ]

mk; printf -- '- [A again](gotchas/a.md) — dup (active, 2026-10-21)\n' >> "$W/index.md"; lint "$W"
check "double-listed page" has "gotchas/a.md: listed 2 times"

mk; printf -- '- [Z](gotchas/z.md) — gone (active, 2026-10-21)\n' >> "$W/index.md"; lint "$W"
check "dangling index link" has "index.md: link does not resolve: gotchas/z.md"

mk; rm "$W/index.md"; lint "$W"
check "missing index" has "index.md missing"

mk; i=0; while [ $i -lt 80 ]; do echo "x" >> "$W/index.md"; i=$((i+1)); done; lint "$W"
check "index too long" has "index.md: 83 lines (max 80)"

mk; i=0; while [ $i -lt 150 ]; do echo "x" >> "$W/gotchas/a.md"; i=$((i+1)); done; lint "$W"
check "page too long" has "gotchas/a.md: 159 lines (max 150)"

mk; printf 'nonsense\n' > "$W/inbox/x.md"; printf 'x\n' > "$W/log.md"; lint "$W"
check "inbox/log/index need no frontmatter" [ "$RC" -eq 0 ]

mk; printf 'old lesson\n' > "$W/inbox/old.md"; touch -t 202001010000 "$W/inbox/old.md"; lint "$W"
check "old inbox item warns" has "inbox/old.md: warning: inbox item older than 14 days"
check "old inbox item is not an error" [ "$RC" -eq 0 ]

mk; printf 'new lesson\n' > "$W/inbox/new.md"; lint "$W"
check "fresh inbox item silent" [ -z "$OUT" ]

mk; printf 'This works well.\n' >> "$W/gotchas/a.md"; lint "$W"
check "fluff warns" has "gotchas/a.md: warning: fluff phrase"
check "fluff is not an error" [ "$RC" -eq 0 ]
mk; printf '이건 잘 동작 한다\n' >> "$W/gotchas/a.md"; lint "$W"
check "korean fluff warns" has "warning: fluff phrase"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
