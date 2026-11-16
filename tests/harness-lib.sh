# Shared helpers for the harness*.test.sh suites (sourced, not a suite itself).
# Sourcing suite must `set -u` first; $0 is then that suite, so HERE is tests/.
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
pass=0
fail=0

# hinit — make the current dir a harness checkout (what `harness init` does, minus the agent
# settings); ask refuses without it. Leaves OUT/RC alone.
hinit() { env -u HARNESS_ROLE /bin/bash "$HARNESS" init --no-agent >/dev/null 2>&1; }

# fresh WORK FAKE_DIR per case; every case starts as an initialised checkout (hinit); all of them removed on exit
WORKS=""
trap 'cd / && for d in $WORKS; do rm -rf "$d"; done' EXIT
setup() {
  WORK=$(mktemp -d)
  WORKS="$WORKS $WORK"
  export FAKE_DIR="$WORK/fake"
  export FAKE_LOG="$WORK/claude.log"
  mkdir -p "$FAKE_DIR"
  : > "$FAKE_LOG"
  unset FAKE_PROMPT_HOOK
  export HARNESS_POLL_SEC=0.2
  cd "$WORK" || exit 1
  hinit
}

# run ARGS... -> sets OUT, RC  (killed by SIGALRM after 10s so a hang fails fast)
GUARD="perl -e alarm(10);exec(@ARGV)"
run() {
  OUT=$(HARNESS_POLL_SEC=0.2 PATH="$HERE/../bin:$PATH" $GUARD env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}

# hrun ARGS... -> OUT, RC. Like run(), with the fake claude (and $EXTRA_PATH, e.g. a fake gh dir) on PATH,
# a 60 s alarm (HRUN_ALARM_S) and HARNESS_HL_START_S=${HRUN_START_S:-5}.
FAKE_CLAUDE="$HERE/fake-claude"
hrun() {
  OUT=$(HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=${HRUN_START_S:-5} \
    PATH="${EXTRA_PATH:+$EXTRA_PATH:}$FAKE_CLAUDE:$HERE/../bin:$PATH" perl -e 'alarm($ENV{HRUN_ALARM_S} || 60);exec(@ARGV)' \
    env -u HARNESS_ROLE /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
jqt() { jq -e "$@" >/dev/null; }
lastprog() { tail -n 1 .harness/progress.jsonl 2>/dev/null; }
# killpids FILE — kill exactly the pids a test recorded (no pattern kills anywhere in tests/)
killpids() { local p; for p in $(cat "$1" 2>/dev/null); do kill "$p" 2>/dev/null; done; return 0; }
# live_runs RID — pids whose command line carries this run id (empty RID matches nothing)
live_runs() { [ -n "${1:-}" ] || return 0; pgrep -f "harness-run analyst $1 "; }
# wait_no_runs <run-id> [tenths] — until no process of that run is left (the watchdog reaps the
# group in steps: claude dies first, the pipeline's subshells a moment later; 15 s cap)
wait_no_runs() { local i=0; while [ $i -lt "${2:-150}" ] && [ -n "$(live_runs "$1")" ]; do sleep 0.1; i=$((i + 1)); done; }

# FAKE_LOG holds `printf %q` of each fake-claude argv: match literally (spaces inside an
# argument appear as "\ ").
logged() { grep -qF -- "$1" "$FAKE_LOG"; }
not_logged() { ! grep -qF -- "$1" "$FAKE_LOG"; }
not() { ! "$@"; }
check() { # check LABEL CONDITION...
  local label=$1; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi
}
not_grep() { ! grep -q "$@" 2>/dev/null; }
REPORT_HOOK() { echo "mkdir -p $WORK/.harness/reports && printf '# $1 report\nstatus: done\n' > $WORK/.harness/reports/$1.md"; }
