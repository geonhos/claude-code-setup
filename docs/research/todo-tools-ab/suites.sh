#!/bin/bash
# suites.sh RUN : run affected suites in the run's clone (parallel within the run), write out/RUN.suites
RUN=$1; T=${RUN%%-*}
case $T in T1) S="verify harness";; T4) S="progress gate harness metrics headless wiki";; esac
cd /tmp/tta/clones/$RUN || exit 1
: > /tmp/tta/out/$RUN.suites; pids=""
for s in $S; do ( perl -e 'alarm shift; exec @ARGV' 900 bash tests/$s.test.sh >/tmp/tta/out/$RUN.$s.log 2>&1; echo "$s $?" >> /tmp/tta/out/$RUN.suites ) & done; wait
