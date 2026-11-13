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

# FAKE_LOG holds `printf %q` of each fake-claude argv: match literally (spaces inside an
# argument appear as "\ ").
logged() { grep -qF -- "$1" "$FAKE_LOG"; }
not_logged() { ! grep -qF -- "$1" "$FAKE_LOG"; }
not() { ! "$@"; }
check() { # check LABEL CONDITION...
  local label=$1; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi
}
not_grep() { ! grep -q -- "$1" "$2" 2>/dev/null; }
REPORT_HOOK() { echo "mkdir -p $WORK/.harness/reports && printf '# $1 report\nstatus: done\n' > $WORK/.harness/reports/$1.md"; }
