#!/bin/bash
# `harness ask` argument parsing (#246): options may stand before or after the instruction, `--` ends
# options, usage errors start nothing and write no progress row. Run: /bin/bash tests/ask-args.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"

asetup() {
  setup
  export FAKE_CLAUDE_MODE=success
  export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# analyst report\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
}
nrows() { [ -f .harness/progress.jsonl ] && wc -l < .harness/progress.jsonl | tr -d ' ' || echo 0; }

# --- options before the instruction -----------------------------------------------------------
asetup
hrun ask analyst "first"
hrun ask analyst --keep "second"
check "--keep before the text: rc 0" [ "$RC" -eq 0 ]
check "--keep before the text: the text is the instruction" logged "claude stdin: second"
check "--keep before the text: resumes" logged "--resume sess-1"
check "--keep before the text: not taken as instruction" not_logged "claude stdin: --keep"

asetup
hrun ask analyst "first"
hrun ask analyst "second" --keep
check "--keep after the text: resumes" logged "--resume sess-1"
check "--keep after the text: instruction" logged "claude stdin: second"

asetup
hrun ask analyst "first"
hrun ask analyst --keep "second" --timeout 30000
check "options on both sides: rc 0" [ "$RC" -eq 0 ]
check "options on both sides: resumes" logged "--resume sess-1"
check "options on both sides: instruction" logged "claude stdin: second"

asetup
hrun ask analyst --timeout 30000 --keep "third"
check "--timeout N before the text: rc 0" [ "$RC" -eq 0 ]
check "--timeout N before the text: instruction" logged "claude stdin: third"

asetup; export FAKE_CLAUDE_MODE=slow30
hrun ask analyst --timeout 1000 "q"
check "--timeout 1000 before the text is the ask deadline (rc 4)" [ "$RC" -eq 4 ]
killpids "$FAKE_DIR/claude.pid"

# --- `--` ends the options -----------------------------------------------------------------
asetup
hrun ask analyst -- "--keep is the text"
check "-- then an option-looking text: rc 0" [ "$RC" -eq 0 ]
check "-- then an option-looking text: it is the instruction" logged "claude stdin: --keep is the text"
check "-- then an option-looking text: no resume" not_logged "--resume"
asetup
hrun ask analyst --timeout 30000 -- "--x"
check "option, --, text: instruction" logged "claude stdin: --x"
asetup
hrun ask analyst -- "q" --keep
check "after --, a second argument is an error (rc 1)" [ "$RC" -eq 1 ]
check "after --, a second argument starts nothing" not_logged "claude: "

# --- errors: usage, rc 1, nothing started, no progress row -----------------------------------
ERRS=(
  "no instruction|analyst"
  "only an option|analyst --keep"
  "two instructions|analyst one two"
  "two instructions around an option|analyst one --keep two"
  "unknown option before the text|analyst --bogus q"
  "unknown option after the text|analyst q --bogus"
  "--timeout without a value (last)|analyst q --timeout"
  "--timeout without a value (first)|analyst --timeout"
  "--timeout eats no instruction|analyst --timeout q"
  "--timeout 0|analyst --timeout 0 q"
  "--timeout abc|analyst q --timeout abc"
  "--timeout 00|analyst --timeout 00 q"
  "--timeout 000|analyst q --timeout 000"
  "--timeout 13 digits|analyst --timeout 9999999999999 q"
  "--timeout 2^63|analyst q --timeout 9223372036854775808"
  "empty instruction|analyst ''"
)
for e in "${ERRS[@]}"; do
  label=${e%%|*}; args=${e#*|}
  asetup
  eval "hrun ask $args"
  check "error ($label): rc 1" [ "$RC" -eq 1 ]
  check "error ($label): usage printed" grep -q "^usage:" <<<"$OUT"
  check "error ($label): nothing started" not_logged "claude: "
  check "error ($label): no progress row" [ "$(nrows)" -eq 0 ]
done

# #250: an unknown --option that contains whitespace is an instruction that forgot the bare --: say so
HINT="harness ask: an instruction that starts with -- must follow a bare --"
asetup
hrun ask analyst '--fix the bug'
check "--instruction with spaces: rc 1, hint line first, then usage" bash -c '[ "$1" = 1 ] && [ "$(grep -n -F "$3" <<<"$2" | cut -d: -f1)" = 1 ] && [ "$(grep -n "^usage:" <<<"$2" | head -1 | cut -d: -f1)" = 2 ]' _ "$RC" "$OUT" "$HINT"
check "--instruction with spaces: no row" [ "$(nrows)" -eq 0 ]
hrun ask analyst --bogus q
check "plain unknown option: no hint" not_grep -F "$HINT" <<<"$OUT"
asetup; export FAKE_CLAUDE_MODE=success
hrun ask analyst --timeout 007 "leading zeros"
check "--timeout 007: still accepted (rc 0)" [ "$RC" -eq 0 ]
unset FAKE_CLAUDE_MODE

# #257: a leading zero is decimal (08 used to fail in $(( )) after the worker launched; 010 meant 8 ms)
asetup; export FAKE_CLAUDE_MODE=slow30
hrun ask analyst --timeout 08 "leading zero 08"
check "--timeout 08: the ask deadline, not an octal error (rc 4)" [ "$RC" -eq 4 ]
check "--timeout 08: no arithmetic error" bash -c '! grep -q "value too great" <<<"$1"' _ "$OUT"
killpids "$FAKE_DIR/claude.pid"
asetup; export FAKE_CLAUDE_MODE=slow100
t0=$(date +%s)
hrun ask analyst --timeout 03001 "leading zero 03001"
t1=$(date +%s)
check "--timeout 03001 is 3001 ms (octal 1537 would end after 2 s): rc 4, at least 4 s" bash -c '[ "$1" = 4 ] && [ "$2" -ge 4 ]' _ "$RC" "$((t1 - t0))"
killpids "$FAKE_DIR/claude.pid"
unset FAKE_CLAUDE_MODE

# a usage error after an ordinary ask leaves exactly that ask's row (no copy of its cost or session)
asetup
hrun ask analyst "ok"
hrun ask analyst --keep
check "usage after an ask: rc 1" [ "$RC" -eq 1 ]
check "usage after an ask: still one progress row" [ "$(nrows)" -eq 1 ]

# --- --no-lane in any position -------------------------------------------------------------
asetup; export FAKE_CLAUDE_MODE=success
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
printf 'fake/\nclaude.log\n.harness/\n' > .gitignore
git init -q . && git add .gitignore && git commit -q -m s
export FAKE_REPORT_CMD="mkdir -p $WORK/.harness/reports && printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
hrun ask implementer "q"
check "implementer without --no-lane: refused in the primary" [ "$RC" -ne 0 ]
hrun ask implementer --no-lane "q"
check "--no-lane before the text: allowed" [ "$RC" -eq 0 ]
hrun ask implementer "q" --no-lane
check "--no-lane after the text: allowed" [ "$RC" -eq 0 ]
hrun ask --no-lane implementer "q" 2>/dev/null
check "--no-lane before the agent: rc 1 (agent comes first)" [ "$RC" -eq 1 ]

# #257: 12 significant digits are accepted (leading zeros do not count); 13 are a usage error (see ERRS)
asetup
hrun ask analyst --timeout 0999999999999 "twelve digits"
check "--timeout of 12 digits after leading zeros: accepted (rc 0)" [ "$RC" -eq 0 ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
