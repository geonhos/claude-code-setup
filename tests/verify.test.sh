#!/bin/bash
# Tests for bin/harness-verify. Run: /bin/bash tests/verify.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
VERIFY="$HERE/../bin/harness-verify"
pass=0
fail=0

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
N=0

check() { # check LABEL CONDITION...
  local label=$1; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: out=$OUT"; fi
}

# newrepo -> sets R to a fresh git repo with one commit (cwd stays put)
newrepo() {
  N=$((N + 1))
  R="$ROOT/r$N"
  mkdir -p "$R"
  ( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
      && echo seed > seed.txt && git add seed.txt && git -c core.hooksPath=/dev/null commit -q -m seed )
}

# hv ARGS... -> runs harness-verify inside $R; sets OUT (stdout) and RC
hv() { OUT=$(cd "$R" && /bin/bash "$VERIFY" "$@" 2>/dev/null </dev/null); RC=$?; }
# hvin JSON ARGS... -> same, with JSON on stdin
hvin() { local j=$1; shift; OUT=$(cd "$R" && printf '%s' "$j" | /bin/bash "$VERIFY" "$@" 2>/dev/null); RC=$?; }

cfg() { mkdir -p "$R/.claude"; printf '%s' "$1" > "$R/.claude/harness.json"; }
lcfg() { mkdir -p "$R/.harness"; printf '%s' "$1" > "$R/.harness/verify.local.json"; }
det() { hv detect; printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }
stopjson() { jq -n -c --arg c "$R" '{hook_event_name:"Stop",agent_type:"implementer",cwd:$c,stop_hook_active:false}'; }
postjson() { jq -n -c --arg c "$R" --arg t "$1" --arg f "$2" '{hook_event_name:"PostToolUse",agent_type:"implementer",cwd:$c,tool_name:$t,tool_input:{file_path:$f}}'; }
not_grep() { ! grep "$@"; }
not_out_has() { ! printf '%s' "$OUT" | grep -q -- "$1"; }
reason_grep() { printf '%s' "$OUT" | jq -r .reason | grep "$@"; }
not_reason_grep() { ! reason_grep "$@"; }
result() { jq -r ".$1" "$R/.harness/verify/implementer.json" 2>/dev/null; }

# --- detect: explicit config only, no auto-detection ---------------------------------
newrepo
hv detect
check "detect empty rc" [ "$RC" -eq 0 ]
check "detect empty format null" [ "$(det .format)" = null ]
check "detect empty lint null" [ "$(det .lint)" = null ]
check "detect empty test null" [ "$(det .test)" = null ]
check "detect default maxAttempts" [ "$(det .maxAttempts)" = 3 ]
OUT=$(cd "$R" && /bin/bash "$VERIFY" detect 2>&1 >/dev/null </dev/null)
check "detect unconfigured: stderr names config location" grep -q '.claude/harness.json' <<<"$OUT"

# project-type files are ignored
newrepo
printf 'fmt:\n\ttrue\nlint:\n\ttrue\ntest:\n\ttrue\n' > "$R/Makefile"
echo '{"scripts":{"format":"x","lint":"y","test":"z"}}' > "$R/package.json"
printf '[tool.ruff]\n[tool.pytest.ini_options]\n' > "$R/pyproject.toml"
echo '[package]' > "$R/Cargo.toml"; echo 'module x' > "$R/go.mod"
printf '#!/bin/bash\n# --test\n' > "$R/install.sh"; chmod +x "$R/install.sh"
check "no autodetect format" [ "$(det .format)" = null ]
check "no autodetect lint" [ "$(det .lint)" = null ]
check "no autodetect test" [ "$(det .test)" = null ]
OUT=$(cd "$R" && /bin/bash "$VERIFY" detect 2>&1 >/dev/null </dev/null)
check "detect autodetect-files: still hints at config" grep -q '.claude/harness.json' <<<"$OUT"

# configured: no hint on stderr
newrepo
cfg '{"test":"x"}'
OUT=$(cd "$R" && /bin/bash "$VERIFY" detect 2>&1 >/dev/null </dev/null)
check "detect configured: silent stderr" [ -z "$OUT" ]

# --- precedence: local > project ----------------------------------------------------
newrepo
cfg '{"test":"project-test","maxAttempts":5}'
check "project test" [ "$(det .test)" = project-test ]
check "key absent everywhere is null" [ "$(det .lint)" = null ]
check "project maxAttempts" [ "$(det .maxAttempts)" = 5 ]
lcfg '{"test":"local-test"}'
check "local beats project" [ "$(det .test)" = local-test ]
check "project still used when local lacks key" [ "$(det .maxAttempts)" = 5 ]
lcfg '{"test":null}'
check "null disables a step" [ "$(det .test)" = null ]
cfg '{"app":{"start":"npm run dev","url":"http://localhost:3000"}}'
check "app passes through" [ "$(det .app.url)" = "http://localhost:3000" ]
cfg 'not json'
rm "$R/.harness/verify.local.json"
check "invalid config ignored" [ "$(det .test)" = null ]

# --- run -----------------------------------------------------------------------------
newrepo
cfg '{"lint":"echo lint-ran {files}","test":"echo test-ran"}'
( cd "$R" && git add .claude && git -c core.hooksPath=/dev/null commit -q -m cfg )
hv run
check "run all rc" [ "$RC" -eq 0 ]
check "run all runs test" grep -q test-ran <<<"$OUT"
check "run all skips file-less lint when nothing changed" not_out_has lint-ran
hv run test
check "run test only" grep -q test-ran <<<"$OUT"
cfg '{"test":"echo broken; exit 3"}'
hv run test
check "run failing rc" [ "$RC" -eq 1 ]
check "run failing prints output" grep -q broken <<<"$OUT"
cfg '{"lint":"echo bad-lint; exit 1","test":"echo test-ran"}'
hv run all
check "run all stops at lint failure" [ "$RC" -eq 1 ]
cfg '{}'
hv run all
check "run nothing configured rc" [ "$RC" -eq 0 ]

# {files} with spaces
newrepo
echo x > "$R/a b.txt"; echo y > "$R/c.txt"
cfg '{"lint":"printf \"%s\\n\" {files} > files.out"}'
hv run lint
check "files: rc" [ "$RC" -eq 0 ]
check "files: name with space is one argument" grep -qx 'a b.txt' "$R/files.out"
check "files: other file" grep -qx 'c.txt' "$R/files.out"
check "files: .harness excluded" not_grep -q '^.harness' "$R/files.out"

# --- baseline ------------------------------------------------------------------------
newrepo
hv baseline
check "baseline rc" [ "$RC" -eq 0 ]
check "baseline writes base" [ -s "$R/.harness/verify/implementer.base" ]
check "baseline attempts 0" [ "$(cat "$R/.harness/verify/implementer.attempts")" = 0 ]
echo '{"status":"fail"}' > "$R/.harness/verify/implementer.json"
echo 2 > "$R/.harness/verify/implementer.attempts"
hv baseline
check "baseline resets attempts" [ "$(cat "$R/.harness/verify/implementer.attempts")" = 0 ]
check "baseline clears last result" [ ! -e "$R/.harness/verify/implementer.json" ]
hv baseline reviewer
check "baseline other agent" [ -s "$R/.harness/verify/reviewer.base" ]

# --- stop ----------------------------------------------------------------------------
newrepo
cfg '{"test":"echo tests-ran"}'
hv baseline
hvin "$(stopjson)" stop
check "stop unchanged rc" [ "$RC" -eq 0 ]
check "stop unchanged allows" [ -z "$OUT" ]
check "stop unchanged status" [ "$(result status)" = skipped ]

echo change > "$R/new.txt"
hvin "$(stopjson)" stop
check "stop pass allows" [ -z "$OUT" ]
check "stop pass status" [ "$(result status)" = pass ]

newrepo
hv baseline
echo change > "$R/new.txt"
hvin "$(stopjson)" stop
check "stop no config allows" [ -z "$OUT" ]
check "stop no config skipped" [ "$(result status)" = skipped ]

newrepo
cfg '{"test":"echo boom-output; exit 1","maxAttempts":2}'
mkdir -p "$R/.harness/reports"; echo report > "$R/.harness/reports/implementer.md"
hv baseline
echo change > "$R/new.txt"
hvin "$(stopjson)" stop
check "stop fail rc" [ "$RC" -eq 0 ]
check "stop fail decision" [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ]
check "stop fail reason has output" reason_grep -q boom-output
check "stop fail reason names step" reason_grep -q test
check "stop fail only decision+reason" [ "$(printf '%s' "$OUT" | jq -c 'keys')" = '["decision","reason"]' ]
check "stop fail deletes report" [ ! -e "$R/.harness/reports/implementer.md" ]
check "stop fail leaves no pending" [ ! -e "$R/.harness/reports/implementer.md.pending" ]
check "stop fail status" [ "$(result status)" = fail ]
check "stop fail step" [ "$(result step)" = test ]
check "stop fail attempts 1" [ "$(result attempts)" = 1 ]
hvin "$(stopjson)" stop
check "stop 2nd fail blocks" [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ]
check "stop attempts 2" [ "$(result attempts)" = 2 ]
echo report > "$R/.harness/reports/implementer.md"
hvin "$(stopjson)" stop
check "stop cap allows" [ -z "$OUT" ]
check "stop cap keeps report" [ -e "$R/.harness/reports/implementer.md" ]
check "stop cap leaves no pending" [ ! -e "$R/.harness/reports/implementer.md.pending" ]
check "stop cap records fail" [ "$(result status)" = fail ]
check "stop cap attempts stay" [ "$(result attempts)" = 2 ]
hv baseline
check "baseline after cap resets" [ "$(cat "$R/.harness/verify/implementer.attempts")" = 0 ]

# stop: tail limited to 40 lines
newrepo
cfg '{"test":"seq 1 100; exit 1"}'
hv baseline; echo c > "$R/new.txt"
hvin "$(stopjson)" stop
check "stop tail has last line" reason_grep -qx 100
check "stop tail drops early lines" not_reason_grep -qx 10
check "stop tail 40 lines in json" [ "$(result tail | wc -l | tr -d ' ')" -le 41 ]

# stop: lint failure reported before test; lint uses changed files
newrepo
cfg '{"lint":"grep -q ^ok {files}","test":"echo tests-ran"}'
hv baseline; echo nope > "$R/new.txt"
hvin "$(stopjson)" stop
check "stop lint fail blocks" [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ]
check "stop lint step" [ "$(result step)" = lint ]

# stop: report hidden while verifying, restored on pass
newrepo
cfg '{"test":"test ! -e .harness/reports/implementer.md && test -e .harness/reports/implementer.md.pending"}'
mkdir -p "$R/.harness/reports"; echo rep > "$R/.harness/reports/implementer.md"
hv baseline; echo c > "$R/new.txt"
hvin "$(stopjson)" stop
check "stop hides report while verifying" [ "$(result status)" = pass ]
check "stop pass restores report" [ "$(cat "$R/.harness/reports/implementer.md")" = rep ]
check "stop pass no pending" [ ! -e "$R/.harness/reports/implementer.md.pending" ]

# stop/ask from a subdirectory of the repo: root is the cwd
newrepo
mkdir -p "$R/sub/deep"
echo '{"test":"echo tests-ran"}' > "$R/sub/deep/c.json"
SUBR=$R; R="$R/sub"
cfg '{"test":"echo tests-ran"}'
mkdir -p "$R/.harness/reports"; echo rep > "$R/.harness/reports/implementer.md"
hv baseline
check "sub: baseline in cwd" [ -s "$R/.harness/verify/implementer.base" ]
check "sub: no state at toplevel" [ ! -e "$SUBR/.harness/verify" ]
echo c > "$R/new.txt"
hvin "$(stopjson)" stop
check "sub: stop result in cwd" [ "$(result status)" = pass ]
check "sub: no result at toplevel" [ ! -e "$SUBR/.harness/verify/implementer.json" ]
cfg '{"test":"exit 1","maxAttempts":1}'
hvin "$(stopjson)" stop
check "sub: stop fail blocks" [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ]
check "sub: report deleted in cwd" [ ! -e "$R/.harness/reports/implementer.md" ]
cfg '{"lint":"printf \"%s\\n\" {files} > files.out","test":"true"}'
hv baseline; echo z > "$R/z.txt"; echo y > "$SUBR/outside.txt"
hvin "$(stopjson)" stop
check "sub: files relative to cwd" grep -qx 'z.txt' "$R/files.out"
check "sub: files exclude outside cwd" not_grep -q outside "$R/files.out"
hvin "$(postjson Write "$R/z.txt")" format
check "sub: format rc ok" [ "$RC" -eq 0 ]

# stop: staged at baseline, edited + re-added -> must run
newrepo
cfg '{"test":"echo tests-ran > ran.out"}'
echo v1 > "$R/st.txt"; ( cd "$R" && git add st.txt )
hv baseline
echo v2 > "$R/st.txt"; ( cd "$R" && git add st.txt )
hvin "$(stopjson)" stop
check "staged edit: not skipped" [ "$(result status)" = pass ]
check "staged edit: test ran" [ -s "$R/ran.out" ]

# stop: implementer committed (HEAD moved) still counts as changed
newrepo
cfg '{"lint":"printf \"%s\\n\" {files} > files.out","test":"echo tests-ran > ran.out"}'
( cd "$R" && git add .claude && git -c core.hooksPath=/dev/null commit -q -m cfg )
hv baseline
echo c > "$R/c.txt"; ( cd "$R" && git add c.txt && git -c core.hooksPath=/dev/null commit -q -m work )
hvin "$(stopjson)" stop
check "committed: not skipped" [ "$(result status)" = pass ]
check "committed: test ran" [ -s "$R/ran.out" ]
check "committed: committed file linted" grep -qx 'c.txt' "$R/files.out"

# baseline clears stale result even outside git
N=$((N + 1)); R="$ROOT/nogitb$N"; mkdir -p "$R/.harness/verify"
echo '{"status":"fail"}' > "$R/.harness/verify/implementer.json"
hv baseline
check "baseline non-repo clears stale result" [ ! -e "$R/.harness/verify/implementer.json" ]

# run all: files versus merge base of --base, plus dirty
newrepo
cfg '{"lint":"printf \"%s\\n\" {files} > files.out","test":"echo test-ran"}'
( cd "$R" && git add .claude && git -c core.hooksPath=/dev/null commit -q -m cfg && git branch -M main && git checkout -q -b feat )
echo a > "$R/committed.txt"; ( cd "$R" && git add committed.txt && git -c core.hooksPath=/dev/null commit -q -m c )
echo d > "$R/dirty.txt"
hv run all
check "run all: committed file linted" grep -qx committed.txt "$R/files.out"
check "run all: dirty file linted" grep -qx dirty.txt "$R/files.out"
check "run all: seed not linted" not_grep -q seed "$R/files.out"
( cd "$R" && git checkout -q -b other main~0 ) 
hv run all --base feat
check "run --base: committed on base not linted" not_grep -q committed "$R/files.out"
( cd "$R" && git checkout -q feat && rm dirty.txt )
rm -f "$R/files.out"
hv run all --base feat
check "run empty list: test still runs" grep -q test-ran <<<"$OUT"
check "run empty list: lint not run" [ ! -e "$R/files.out" ]
OUT=$(cd "$R" && /bin/bash "$VERIFY" run all --base feat 2>&1 >/dev/null </dev/null)
check "run empty list: says so on stderr" grep -qi 'no changed files' <<<"$OUT"

# {files} is never filtered by extension
newrepo
echo a > "$R/a.py"; echo b > "$R/b.md"
cfg '{"lint":"printf \"%s\\n\" {files} > files.out"}'
hv run lint
check "explicit lint unfiltered" grep -qx b.md "$R/files.out"
check "explicit lint all files" grep -qx a.py "$R/files.out"

# --base: unresolvable ref -> exit 2; main missing -> master -> error
newrepo
cfg '{"test":"echo test-ran"}'
( cd "$R" && git branch -M master )
hv run all
check "run default base falls back to master" [ "$RC" -eq 0 ]
hv run all --base nosuchref
check "run bad --base exits 2" [ "$RC" -eq 2 ]
OUT=$(cd "$R" && /bin/bash "$VERIFY" run all --base nosuchref 2>&1 >/dev/null </dev/null)
check "run bad --base names ref" grep -q nosuchref <<<"$OUT"
( cd "$R" && git branch -M trunk )
hv run all
check "run no main/master exits 2" [ "$RC" -eq 2 ]

# stop with an interrupted hook leaves .pending (harness handles it); nothing configured -> skipped
newrepo
hv baseline; echo c > "$R/new.txt"
mkdir -p "$R/.harness/reports"; echo rep > "$R/.harness/reports/implementer.md"
hvin "$(stopjson)" stop
check "stop nothing configured: allows" [ -z "$OUT" ]
check "stop nothing configured: skipped" [ "$(result status)" = skipped ]
check "stop nothing configured: report kept" [ -e "$R/.harness/reports/implementer.md" ]

# stop: not a git repo -> skipped, allowed
N=$((N + 1)); R="$ROOT/nogit$N"; mkdir -p "$R"
cfg '{"test":"exit 1"}'
hvin "$(stopjson)" stop
check "stop non-repo allows" [ -z "$OUT" ] 
check "stop non-repo rc" [ "$RC" -eq 0 ]

# --- format (PostToolUse) ---------------------------------------------------------------
newrepo
echo base > "$R/x.txt"
cfg '{"format":"echo formatted >> {files}","lint":"grep -q formatted {files}"}'
hvin "$(postjson Write "$R/x.txt")" format
check "format rc" [ "$RC" -eq 0 ]
check "format passing lint is silent" [ -z "$OUT" ]
check "format ran on the file" grep -qx formatted "$R/x.txt"
cfg '{"format":"true","lint":"echo LINT-ERR-1; echo LINT-ERR-2; exit 1 #{files}"}'
hvin "$(postjson Edit "$R/x.txt")" format
check "format lint failure blocks" [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ]
check "format lint reason" reason_grep -q LINT-ERR-2
check "format lint only decision+reason" [ "$(printf '%s' "$OUT" | jq -c 'keys')" = '["decision","reason"]' ]
hvin "$(postjson MultiEdit "$R/x.txt")" format
check "format MultiEdit handled" [ "$(printf '%s' "$OUT" | jq -r .decision)" = block ]
cfg '{"format":"echo SHOULD-NOT-RUN >> {files}"}'
hvin "$(postjson Read "$R/x.txt")" format
check "format ignores other tools" [ -z "$OUT" ] 
check "format ignored tool leaves file" not_grep -q SHOULD-NOT-RUN "$R/x.txt"
cfg '{"lint":"echo ran-full-lint; exit 1"}'
hvin "$(postjson Write "$R/x.txt")" format
check "format skips lint without {files}" [ -z "$OUT" ]
cfg '{}'
hvin "$(postjson Write "$R/x.txt")" format
check "format no config silent" [ -z "$OUT" ]
hvin "$(postjson Write "$R/missing.txt")" format
check "format missing file silent" [ -z "$OUT" ]
hvin "$(postjson Write "/etc/hosts")" format
check "format outside repo silent" [ -z "$OUT" ]
echo q > "$R/f q.txt"
cfg '{"format":"echo ok >> {files}"}'
hvin "$(postjson Write "$R/f q.txt")" format
check "format quotes file with space" grep -qx ok "$R/f q.txt"
hv format x.txt
check "format with file argument" [ "$RC" -eq 0 ]

# --- jq missing never blocks ------------------------------------------------------------
newrepo
JB=$(mktemp -d); for b in cat sed awk tr; do ln -s "$(command -v $b)" "$JB/$b"; done
OUT=$(cd "$R" && printf '{}' | PATH="$JB" /bin/bash "$VERIFY" stop 2>&1); RC=$?
check "no jq rc 0" [ "$RC" -eq 0 ]
check "no jq one stderr line" [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -eq 1 ]
check "no jq mentions jq" grep -q jq <<<"$OUT"
rm -rf "$JB"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
