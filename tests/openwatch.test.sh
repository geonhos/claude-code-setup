#!/bin/bash
# harness open-watch (issue #102): fake herdr / tmux / osascript on PATH record their arguments.
# Run: /bin/bash tests/openwatch.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
BIN=$(mktemp -d); WORKS="$WORKS $BIN"
for t in herdr tmux osascript; do
  printf '#!/bin/bash\nprintf "%%s|%%s\\n" "$(basename "$0")" "$*" >> "$OW_LOG"\n[ "$(basename "$0")" = herdr ] && [ "$1 $2" = "pane split" ] && echo "{\\"result\\":{\\"pane\\":{\\"pane_id\\":\\"w:p9\\"}}}"\n[ -n "${OW_FAIL:-}" ] && exit 1\nexit 0\n' > "$BIN/$t"
  chmod +x "$BIN/$t"
done
setup
export OW_LOG="$WORK/ow.log"
# ow ENV... -- ARGS: run with the fakes first on PATH (backend tools absent from SAFE unless faked)
ow() { : > "$OW_LOG"; local e=(); while [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  OUT=$(env -u HARNESS_ROLE -u HERDR_ENV -u TMUX ${e[@]+"${e[@]}"} PATH="$BIN:$HERE/../bin:/usr/bin:/bin:$(dirname "$(command -v jq)")" /bin/bash "$HARNESS" "$@" 2>&1); RC=$?; }
ABS=$(pwd)

ow HERDR_ENV=1 -- open-watch implementer
check "herdr: split then run" grep -q "^herdr|pane split --current --direction right" "$OW_LOG"
check "herdr: run in new pane with abs path" grep -q "^herdr|pane run w:p9 harness -C $ABS watch implementer" "$OW_LOG"
check "herdr: message" grep -q "herdr pane" <<<"$OUT"
ow TMUX=/tmp/x,1,0 -- open-watch analyst
check "tmux: split-window" grep -q "^tmux|split-window -h harness -C $ABS watch analyst" "$OW_LOG"
check "tmux: not osascript" not_grep '^osascript' "$OW_LOG"
ow HERDR_ENV=1 TMUX=/tmp/x -- open-watch analyst
check "herdr wins over tmux" not_grep '^tmux' "$OW_LOG"
ow -- open-watch reviewer
check "terminal: osascript" grep -q "^osascript|-e tell application \"Terminal\" to do script \"harness -C $ABS watch reviewer\"" "$OW_LOG"
# path with a space and a quote: shell-quoted, then AppleScript-escaped
SP="$WORK/a b\"c"; mkdir -p "$SP"
ow -- -C "$SP" open-watch implementer
check "terminal: space/quote path escaped" grep -qF 'harness -C '"$(printf '%q' "$(cd "$SP" && pwd)" | sed 's/[\\"]/\\&/g')"' watch implementer' "$OW_LOG"
ow -- open-watch bogus
check "unknown role refused" [ "$RC" -ne 0 ]
check "unknown role: nothing launched" [ ! -s "$OW_LOG" ]
# no backend: the Terminal launcher fails too -> the command is printed, exit 0
ow OW_FAIL=1 -- open-watch analyst
check "no backend: exit 0" [ "$RC" -eq 0 ]
check "no backend: command shown" grep -q "no pane backend.*harness -C $ABS watch analyst" <<<"$OUT"
echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
