#!/bin/bash
# bin/harness against tests/fake-herdr: pane lifecycle, close guards, TTL, config, progress. Run: /bin/bash tests/harness-lifecycle.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"

# --- pane lifecycle: close guards, after-ask, TTL, legacy ------------------------------
# live_worker ROLE STATUS PANE — a live, harness-registered worker
live_worker() {
  echo "$2" > "$FAKE_DIR/live.$(WN "$1")"
  echo "$3" > "$FAKE_DIR/pane.$(WN "$1")"
  mkdir -p .harness; echo "$1 $3" >> .harness/panes
}
# stale ROLE MINUTES — collected-stamp of that age
stale() { mkdir -p .harness/asks; : > ".harness/asks/$1.finished"; touch -t "$(date -v-"$2"M +%Y%m%d%H%M 2>/dev/null || date -d "$2 minutes ago" +%Y%m%d%H%M)" ".harness/asks/$1.finished"; }

# refuses while working / blocked / uncollected report; --force overrides
jqt() { jq -e "$@" >/dev/null; }
setup
live_worker analyst working w1:p2
run close analyst
check "close working: rc 4" [ "$RC" -eq 4 ]
check "close working: message" grep -q "is working" <<<"$OUT"
check "close working: no pane close" not_logged "pane close"
run close analyst --force
check "close working --force: rc 0" [ "$RC" -eq 0 ]
check "close working --force: closed" logged "pane close w1:p2"
check "close --force: unregistered" not_grep "^analyst " "$WORK/.harness/panes"
setup
live_worker analyst blocked w1:p2
run close analyst
check "close blocked: rc 4" [ "$RC" -eq 4 ]
setup
live_worker analyst idle w1:p2
mkdir -p .harness/reports; echo "# r" > .harness/reports/analyst.md
run close analyst
check "close uncollected report: rc 4" [ "$RC" -eq 4 ]
check "close uncollected report: message" grep -q "not collected" <<<"$OUT"
run close analyst --force
check "close uncollected --force: rc 0" [ "$RC" -eq 0 ]
setup
live_worker implementer idle w1:p2
mkdir -p .harness/reports; echo x > .harness/reports/implementer.md.pending
run close implementer
check "close .pending: rc 4" [ "$RC" -eq 4 ]
# collected report (stamp newer than report) closes
setup
live_worker analyst idle w1:p2
mkdir -p .harness/reports .harness/asks; echo "# r" > .harness/reports/analyst.md
sleep 1; : > .harness/asks/analyst.finished
run close analyst
check "close collected report: rc 0" [ "$RC" -eq 0 ]
check "close logs event" grep -q '"event":"close","role":"analyst","pane":"w1:p2","reason":"manual"' .harness/progress.jsonl
check "close shows in progress.md" grep -q "^Recent closes (max 5): .* analyst (manual)" .harness/progress.md

# --all: closes idle ones, rc 4 when one is refused; other-repo -> 6
setup
live_worker analyst idle w1:p2; live_worker implementer working w1:p3
run close --all
check "close --all: refused rc 4" [ "$RC" -eq 4 ]
check "close --all: idle closed" logged "pane close w1:p2"
check "close --all: working kept" not_logged "pane close w1:p3"
setup
live_worker analyst idle w1:p2
echo "/nonexistent-elsewhere" > "$FAKE_DIR/cwd.$(WN analyst)"
run close --all
check "close --all other repo: rc 6" [ "$RC" -eq 6 ]
check "close --all other repo: not closed" not_logged "pane close"
run close --bogus
check "close bad flag: usage rc 1" [ "$RC" -eq 1 ]

# idle TTL
setup
live_worker analyst idle w1:p2; live_worker reviewer idle w1:p3; live_worker implementer idle w1:p4
stale analyst 90
: > .harness/asks/reviewer.finished           # fresh
echo "/nonexistent-elsewhere" > "$FAKE_DIR/cwd.$(WN implementer)"; stale implementer 90   # other repo
run status
check "ttl: stale analyst reaped" logged "pane close w1:p2"
check "ttl: fresh reviewer kept" not_logged "pane close w1:p3"
check "ttl: other-repo implementer kept" not_logged "pane close w1:p4"
check "ttl: logged with reason" grep -q '"role":"analyst".*"reason":"ttl"' .harness/progress.jsonl
check "ttl: config created" [ -s .harness/config.json ]
setup
live_worker analyst idle w1:p2; stale analyst 90
mkdir -p .harness/reports; echo "# r" > .harness/reports/analyst.md      # newer than stamp: uncollected
run status
check "ttl: uncollected report kept" not_logged "pane close"
rm .harness/reports/analyst.md; echo x > .harness/reports/analyst.md.pending
run status
check "ttl: .pending kept" not_logged "pane close"
rm .harness/reports/analyst.md.pending; echo working > "$FAKE_DIR/live.$(WN analyst)"
run status
check "ttl: working kept" not_logged "pane close"
echo idle > "$FAKE_DIR/live.$(WN analyst)"
HARNESS_NO_AUTOCLOSE=1 run status
check "ttl: HARNESS_NO_AUTOCLOSE=1 disables" not_logged "pane close"
HARNESS_IDLE_TTL_MINUTES=0 run status
check "ttl: 0 disables" not_logged "pane close"
HARNESS_IDLE_TTL_MINUTES=200 run status
check "ttl: env raises ttl" not_logged "pane close"
echo '{"idle_ttl_minutes": 120}' > .harness/config.json
run status
check "ttl: config raises ttl" not_logged "pane close"
echo '{"idle_ttl_minutes": 60}' > .harness/config.json
run status
check "ttl: config lowers ttl" logged "pane close w1:p2"

# default: implementer pane is kept (decision 0006); config/env on_success closes after ask 0, not after 5
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK implementer)"
run ask implementer "do it"
check "default: ask rc 0" [ "$RC" -eq 0 ]
check "default: implementer pane kept" not_logged "pane close"
check "default: config template says never" jqt '.close_after_ask.implementer=="never"' .harness/config.json
# config migration: untouched pre-decision-0006 template is rewritten; edited / new files are not
OLDCFG=$(sed 's/"implementer": "never"/"implementer": "on_success"/' <<'EOC'
{
  "_doc": "close_after_ask.<role>: never | on_success (close the worker after `harness ask` exits 0; reviewer: 0 or 5). idle_ttl_minutes: close this repo's workers idle longer than N minutes after their last collected report (0 = off). HARNESS_NO_AUTOCLOSE=1 disables both. Env overrides: HARNESS_CLOSE_AFTER_ASK_<ROLE>, HARNESS_IDLE_TTL_MINUTES.",
  "close_after_ask": { "analyst": "never", "implementer": "never", "reviewer": "never" },
  "idle_ttl_minutes": 30
}
EOC
)
setup; mkdir -p .harness; printf '%s\n' "$OLDCFG" > .harness/config.json
run status
check "migrate: old template -> implementer never" jqt '.close_after_ask.implementer=="never"' .harness/config.json
cp .harness/config.json "$WORK/new.json"; run status
check "migrate: new template untouched" cmp -s .harness/config.json "$WORK/new.json"
setup; mkdir -p .harness; printf '%s\n' "$OLDCFG" | sed 's/"idle_ttl_minutes": 30/"idle_ttl_minutes": 31/' > .harness/config.json
cp .harness/config.json "$WORK/edited.json"; run status
check "migrate: edited old file untouched" cmp -s .harness/config.json "$WORK/edited.json"
setup; mkdir -p .harness; printf '%s\n' "$OLDCFG" > .harness/config.json
HERDR_ENV=1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" HARNESS_ROLE=worker /bin/bash "$HARNESS" status >/dev/null 2>&1
check "migrate: worker session does not rewrite" jqt '.close_after_ask.implementer=="on_success"' .harness/config.json
export HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER=on_success
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports; printf '# implementer report\nstatus: done\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it"
check "after_ask: ask rc 0" [ "$RC" -eq 0 ]
check "after_ask: implementer closed" logged "pane close w1:p2"
check "after_ask: logged" grep -q '"role":"implementer".*"reason":"after_ask"' .harness/progress.jsonl
check "after_ask: stdout is only the report" grep -qx "# implementer report" <<<"$OUT"
# ask after close respawns the worker
: > "$FAKE_LOG"
run ask implementer "again"
check "respawn after close: rc 0" [ "$RC" -eq 0 ]
check "respawn after close: pane split + start" logged "agent start $(WN implementer) --kind claude"
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '# implementer report\nstatus: partial\n' > $WORK/.harness/reports/implementer.md; printf '{\"status\":\"fail\",\"attempts\":3,\"step\":\"test\",\"tail\":\"x\"}' > $WORK/.harness/verify/implementer.json"
run ask implementer "do it"
check "after_ask: exit 5 not closed" [ "$RC" -eq 5 ]
check "after_ask 5: no pane close" not_logged "pane close"
setup
live_worker analyst idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q"
check "after_ask: analyst never closed" not_logged "pane close"
HARNESS_CLOSE_AFTER_ASK_ANALYST=on_success run ask analyst "q"
check "after_ask: env override closes analyst" logged "pane close w1:p2"
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK implementer)"
HARNESS_NO_AUTOCLOSE=1 run ask implementer "do it"
check "after_ask: HARNESS_NO_AUTOCLOSE=1 keeps worker" not_logged "pane close"
unset FAKE_PROMPT_HOOK HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER

# --legacy: only same-repo unscoped workers
setup
echo idle > "$FAKE_DIR/live.analyst"; echo w1:p5 > "$FAKE_DIR/pane.analyst"
echo idle > "$FAKE_DIR/live.reviewer"; echo w1:p6 > "$FAKE_DIR/pane.reviewer"; echo "/nonexistent-elsewhere" > "$FAKE_DIR/cwd.reviewer"
live_worker implementer idle w1:p7
run close --legacy
check "legacy: rc 0" [ "$RC" -eq 0 ]
check "legacy: same-repo unscoped closed" logged "pane close w1:p5"
check "legacy: other-repo unscoped kept" not_logged "pane close w1:p6"
check "legacy: scoped worker kept" not_logged "pane close w1:p7"
check "legacy: logged" grep -q '"role":"analyst".*"reason":"legacy"' .harness/progress.jsonl
echo working > "$FAKE_DIR/live.analyst"
run close --legacy
check "legacy working: rc 4" [ "$RC" -eq 4 ]
run spawn analyst
check "migration hint mentions --legacy" grep -q "harness close --legacy" <<<"$OUT"

# --- review fixes: --keep note, stamps, race, pane gone, progress.md ------------------
# 1: --keep after an auto-close prints the note; no note without --keep; exit 5 keeps the worker
export HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER=on_success
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK implementer)"
run ask implementer "one"
check "keep note: first ask closes" [ "$RC" -eq 0 ]
run ask implementer "two" --keep
check "keep note: rc 0" [ "$RC" -eq 0 ]
check "keep note: printed" grep -q "harness: note: implementer was closed (after_ask) — previous context is gone; running on a fresh worker" <<<"$OUT"
setup
live_worker implementer idle w1:p2
run ask implementer "one"
run ask implementer "two"
check "no note without --keep" not_grep "previous context is gone" <(echo "$OUT")
setup
live_worker analyst idle w1:p2; stale analyst 90
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q" --keep
check "keep note after ttl reap" grep -q "analyst was closed (ttl)" <<<"$OUT"
setup
live_worker implementer idle w1:p2
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports $WORK/.harness/verify; printf '# implementer report\nstatus: partial\n' > $WORK/.harness/reports/implementer.md; printf '{\"status\":\"fail\",\"attempts\":3,\"step\":\"test\",\"tail\":\"x\"}' > $WORK/.harness/verify/implementer.json"
run ask implementer "one"
check "exit 5: worker stays" bash -c '[ "$1" -eq 5 ] && ! grep -qF "pane close" "$2"' _ "$RC" "$FAKE_LOG"
run ask implementer "one-b" --fresh >/dev/null; : > "$FAKE_LOG"
run ask implementer "fix" --keep
check "exit 5 then --keep: context kept, no note" not_grep "previous context is gone" <(echo "$OUT")
check "exit 5 then --keep: no /clear" not_logged "/clear"
unset FAKE_PROMPT_HOOK HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER

# 2: harness report on an interrupted verify stamps .finished
setup
live_worker implementer idle w1:p2
mkdir -p .harness/reports; echo "# r" > .harness/reports/implementer.md.pending
run report implementer
check "report interrupted: rc 5" [ "$RC" -eq 5 ]
check "report interrupted: stamped" [ -f .harness/asks/implementer.finished ]

# 3: starting an ask removes the collected stamp
setup
live_worker analyst idle w1:p2; mkdir -p .harness/asks; : > .harness/asks/analyst.finished
export FAKE_PROMPT_HOOK="test ! -e $WORK/.harness/asks/analyst.finished && touch $WORK/no-stamp-in-flight"
run ask analyst "q" --timeout 1000
check "ask in flight: no .finished" [ -e "$WORK/no-stamp-in-flight" ]
unset FAKE_PROMPT_HOOK

# 4: pane still present after close -> failure, registry kept
setup
live_worker analyst idle w1:p2
touch "$FAKE_DIR/close_noop"
HARNESS_CLOSE_POLLS=2 HARNESS_CLOSE_INTERVAL=0.1 run close analyst
check "pane survives: rc 1" [ "$RC" -eq 1 ]
check "pane survives: message" grep -q "still present" <<<"$OUT"
check "pane survives: registry kept" grep -q "^analyst w1:p2$" .harness/panes
check "pane survives: no close event" not_grep '"event":"close"' .harness/progress.jsonl

# 4b: a transient `pane get` error is not proof the pane is gone
setup
live_worker analyst idle w1:p2
touch "$FAKE_DIR/get_error"
HARNESS_CLOSE_POLLS=2 HARNESS_CLOSE_INTERVAL=0.1 run close analyst
check "pane get transient error: rc 1" [ "$RC" -eq 1 ]
check "pane get transient error: registry kept" grep -q "^analyst w1:p2$" .harness/panes

# 5: progress.md separates closes; ask-window lookups ignore them
setup
mkdir -p .harness
i=0; while [ $i -lt 20 ]; do echo '{"ts":"t","event":"close","role":"implementer","pane":"p","reason":"after_ask"}' >> .harness/progress.jsonl; i=$((i + 1)); done
echo '{"ts":"t0","agent":"analyst","exit":0,"summary":"S"}' | cat - .harness/progress.jsonl > .harness/j && mv .harness/j .harness/progress.jsonl
live_worker analyst idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q"
check "progress.md: asks listed" grep -q "analyst exit 0" .harness/progress.md
check "progress.md: no close line in asks" not_grep "^- .* close " .harness/progress.md
check "progress.md: closes line capped at 5" [ "$(grep '^Recent closes' .harness/progress.md | tr ';' '\n' | wc -l | tr -d ' ')" -le 5 ]
unset FAKE_PROMPT_HOOK

# stray .harness: workers and read-only status never create it; a conductor ask does
setup; rm -rf .harness
OUT=$(HERDR_ENV=1 PATH="$FAKE_BIN:$HERE/../bin:$PATH" HARNESS_ROLE=worker /bin/bash "$HARNESS" status 2>&1); RC=$?
check "stray: worker status creates no .harness" [ ! -e .harness ]
setup; rm -rf .harness
run status
check "stray: status without .harness creates none" [ ! -e .harness ]
setup; rm -f .harness/config.json
live_worker analyst idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 HARNESS_IDLE_GRACE=1 HARNESS_POLL_SEC=0.2 PATH="$FAKE_BIN:$HERE/../bin:$PATH" $GUARD env HARNESS_ROLE=worker /bin/bash "$HARNESS" ask analyst "q" 2>&1)
check "stray: worker ask creates no config.json" [ ! -e .harness/config.json ]
unset FAKE_PROMPT_HOOK
setup; rm -f .harness/config.json
live_worker analyst idle w1:p2
export FAKE_PROMPT_HOOK="$(REPORT_HOOK analyst)"
run ask analyst "q"
check "stray: conductor ask creates config" [ -s .harness/config.json ]
unset FAKE_PROMPT_HOOK
setup; rm -rf .harness
OUT=$(env -u HERDR_ENV HARNESS_ROLE=worker /bin/bash "$HARNESS" route-log '{"event":"x"}' 2>&1)
check "stray: worker route-log creates none" [ ! -e .harness ]

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
