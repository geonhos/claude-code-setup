#!/bin/bash
# harness open-watch (issue #102): fake herdr / tmux on PATH record their arguments.
# Run: /bin/bash tests/openwatch.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
BIN=$(mktemp -d); WORKS="$WORKS $BIN"
for t in herdr tmux; do
  printf '#!/bin/bash\nprintf "%%s|%%s\\n" "$(basename "$0")" "$*" >> "$OW_LOG"\n[ "$(basename "$0")" = herdr ] && [ "$1 $2" = "pane split" ] && echo "{\\"result\\":{\\"pane\\":{\\"pane_id\\":\\"w:p9\\"}}}"\n[ -n "${OW_RUNFAIL:-}" ] && [ "$1 $2" = "pane run" ] && exit 1\n[ -n "${OW_FAIL:-}" ] && exit 1\nexit 0\n' > "$BIN/$t"
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
ow HERDR_ENV=1 TMUX=/tmp/x -- open-watch analyst
check "herdr wins over tmux" not_grep '^tmux' "$OW_LOG"
# path with a space and a quote: shell-quoted
SP="$WORK/a b\"c"; mkdir -p "$SP"
ow TMUX=/tmp/x -- -C "$SP" open-watch implementer
check "tmux: space/quote path shell-quoted" grep -qF "split-window -h harness -C $(printf '%q' "$(cd "$SP" && pwd)") watch implementer" "$OW_LOG"
ow -- open-watch bogus
check "unknown role refused" [ "$RC" -ne 0 ]
check "unknown role: nothing launched" [ ! -s "$OW_LOG" ]
# herdr: split ok but run fails -> the new pane is closed, then the next backend runs
ow HERDR_ENV=1 TMUX=/tmp/x OW_RUNFAIL=1 -- open-watch analyst
check "herdr run failure: pane closed" grep -q "^herdr|pane close w:p9" "$OW_LOG"
check "herdr run failure: falls to tmux" grep -q "^tmux|split-window" "$OW_LOG"
# no backend: herdr and tmux absent -> the command is printed, exit 0
ow -- open-watch analyst
check "no backend: exit 0" [ "$RC" -eq 0 ]
check "no backend: command shown" grep -q "no pane backend.*harness -C $ABS watch analyst" <<<"$OUT"
# control characters in the folder path: command printed, nothing launched
CP="$WORK/ctl"$'\t'"dir"; mkdir -p "$CP"
ow -- -C "$CP" open-watch analyst
check "control char path: nothing launched" [ ! -s "$OW_LOG" ]
check "control char path: message, exit 0" grep -q "control characters" <<<"$OUT"
check "control char path: exit 0" [ "$RC" -eq 0 ]
echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
