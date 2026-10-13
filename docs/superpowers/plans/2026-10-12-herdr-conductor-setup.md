# herdr Conductor Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn this repo into a user-level Claude Code setup where the Fable main session is a gated conductor that delegates all analysis and implementation to herdr-hosted Claude workers.

**Architecture:** One PreToolUse hook (`conductor-gate.sh`) denies source reads/edits and native subagents unless `HARNESS_ROLE=worker`. One CLI (`harness`) wraps herdr to spawn, prompt, and harvest reports from three named workers (`analyst`, `implementer`, `reviewer`) defined as `~/.claude/agents/*.md`. `install.sh` symlinks everything into `~/.claude` and merges hook + cache settings into `~/.claude/settings.json`.

**Tech Stack:** bash 3.2 (macOS `/bin/bash`), `jq` 1.7, `herdr` 0.9.3 CLI (JSON over socket), Claude Code 2.1.29x hooks + agent frontmatter.

**Spec:** `docs/superpowers/specs/2026-10-12-herdr-conductor-setup-design.md`

**Conventions for every task:**
- All scripts start with `#!/bin/bash` and must run under `/bin/bash` 3.2. No `declare -A`, no `${var,,}`, no `mapfile`.
- Tests are plain bash scripts that print `PASS n / FAIL m` and exit non-zero on any failure. Run them as `/bin/bash tests/<file>` explicitly.
- Commit after each task with the message given. Append this trailer to every commit message:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`

---

## File structure

| Path | Responsibility |
|------|----------------|
| `claude/hooks/conductor-gate.sh` | PreToolUse hook. Role check, path normalisation, per-tool allow/deny, Bash allowlist. Prints deny JSON or nothing. |
| `tests/gate.test.sh` | Table-driven tests for the gate. Feeds synthetic hook JSON on stdin. |
| `bin/harness` | herdr wrapper: `spawn`, `ask`, `status`, `close`. Only file that calls `herdr`. |
| `tests/fake-herdr/herdr` | Stub `herdr` binary for tests. Logs calls, returns canned JSON, state in `$FAKE_DIR`. |
| `tests/harness.test.sh` | Tests `bin/harness` against the stub. |
| `claude/agents/analyst.md`, `implementer.md`, `reviewer.md` | Worker definitions (model, memory, cacheTtl, report contract). |
| `claude/CLAUDE.conductor.md` | Static conductor protocol, imported from `~/.claude/CLAUDE.md`. |
| `install.sh` | Idempotent installer. `--test` runs both test files. |
| `tests/install.test.sh` | Runs installer twice into a temp HOME and checks idempotence. |
| `README.md` | What this is, install, daily use, opt-out. |
| `.gitignore` | Replace v6 ignore list. |

Deleted: everything from the v6 plugin (see Task 1).

---

### Task 1: Remove the v6 plugin content

**Files:**
- Delete: `.claude-plugin/`, `.claude/`, `.mcp.json`, `CHANGELOG.md`, `harness/`, `hooks/`, `logs/`, `memory/`, `plans/`, `plugin.json`, `skills/`, `README.md`
- Delete (untracked, local): `.git/hooks/pre-commit`
- Modify: `.gitignore`

- [ ] **Step 1: Discard the uncommitted `.claude/settings.json` change and remove tracked v6 files**

```bash
cd /Users/geonho.yeom/workspace/claude-code-setup
git checkout -- .claude/settings.json
git rm -r -q .claude-plugin .claude .mcp.json CHANGELOG.md harness hooks plugin.json skills README.md
rm -rf logs memory plans
rm -f .git/hooks/pre-commit
git status --short | head -20
```

Expected: `D` lines for the removed files, nothing else. `logs/`, `memory/`, `plans/` were already gitignored so they produce no status lines.

- [ ] **Step 2: Replace `.gitignore`**

```gitignore
# Conductor runtime (worker reports, pane registry) — per project, never committed
.harness/

# OS
.DS_Store

# Editor
.idea/
.vscode/
*.swp
```

- [ ] **Step 3: Verify the tree is what the plan expects**

Run: `git ls-files`
Expected output (exactly):
```
.gitignore
LICENSE
docs/superpowers/specs/2026-10-12-herdr-conductor-setup-design.md
docs/superpowers/plans/2026-10-12-herdr-conductor-setup.md
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore!: remove v6 plugin content

The repo becomes a user-level conductor setup (see spec). Plugin,
skills, hooks, learning loop and local git pre-commit hook are gone.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Gate — tests first

**Files:**
- Create: `tests/gate.test.sh`

- [ ] **Step 1: Write the test harness and the full case table**

```bash
#!/bin/bash
# Tests for claude/hooks/conductor-gate.sh. Run: /bin/bash tests/gate.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GATE="$HERE/../claude/hooks/conductor-gate.sh"
CWD=/repo
pass=0
fail=0

# decision ROLE JSON -> prints allow|deny
decision() {
  local out
  out=$(printf '%s' "$2" | HARNESS_ROLE="$1" /bin/bash "$GATE" 2>/dev/null)
  if [ -z "$out" ]; then
    echo allow
  else
    printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'
  fi
}

# expect EXPECTED ROLE LABEL JSON
expect() {
  local got
  got=$(decision "$2" "$4")
  if [ "$got" = "$1" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL [$3]: expected $1, got $got"
  fi
}

# tool NAME INPUT_JSON -> full hook payload
tool() {
  jq -n -c --arg t "$1" --argjson i "$2" --arg c "$CWD" \
    '{tool_name:$t, tool_input:$i, cwd:$c, hook_event_name:"PreToolUse", session_id:"s1"}'
}

C=conductor
W=worker

# --- role bypass ---------------------------------------------------------
expect allow $W "worker: Edit src"        "$(tool Edit  '{"file_path":"/repo/src/a.ts","old_string":"a","new_string":"b"}')"
expect allow $W "worker: Read src"        "$(tool Read  '{"file_path":"/repo/src/a.ts"}')"
expect allow $W "worker: Agent"           "$(tool Agent '{"prompt":"x"}')"
expect allow $W "worker: Bash rm"         "$(tool Bash  '{"command":"rm -rf build"}')"

# --- Edit / Write / NotebookEdit -------------------------------------------
expect deny  $C "Edit src abs"            "$(tool Edit  '{"file_path":"/repo/src/a.ts","old_string":"a","new_string":"b"}')"
expect deny  $C "Edit src rel"            "$(tool Edit  '{"file_path":"src/a.ts","old_string":"a","new_string":"b"}')"
expect deny  $C "Write root md"           "$(tool Write '{"file_path":"/repo/README.md","content":"x"}')"
expect allow $C "Write docs md abs"       "$(tool Write '{"file_path":"/repo/docs/superpowers/specs/x.md","content":"x"}')"
expect allow $C "Edit docs md rel"        "$(tool Edit  '{"file_path":"docs/plan.md","old_string":"a","new_string":"b"}')"
expect deny  $C "Write docs non-md"       "$(tool Write '{"file_path":"docs/data.json","content":"x"}')"
expect allow $C "Write .harness"          "$(tool Write '{"file_path":".harness/notes.txt","content":"x"}')"
expect deny  $C "Write outside cwd"       "$(tool Write '{"file_path":"/etc/hosts","content":"x"}')"
expect deny  $C "Write dotdot"            "$(tool Write '{"file_path":"docs/../src/a.md","content":"x"}')"
expect deny  $C "Write empty path"        "$(tool Write '{"content":"x"}')"
expect deny  $C "NotebookEdit"            "$(tool NotebookEdit '{"notebook_path":"/repo/nb.ipynb","new_source":"x"}')"

# --- Read / Grep / Glob ------------------------------------------------------
expect deny  $C "Read src"                "$(tool Read '{"file_path":"/repo/src/a.ts"}')"
expect allow $C "Read root md"            "$(tool Read '{"file_path":"/repo/README.md"}')"
expect allow $C "Read docs any"           "$(tool Read '{"file_path":"docs/img.png"}')"
expect allow $C "Read .harness report"    "$(tool Read '{"file_path":".harness/reports/analyst.md"}')"
expect deny  $C "Read outside cwd"        "$(tool Read '{"file_path":"/Users/x/other/a.md"}')"
expect deny  $C "Grep no path"            "$(tool Grep '{"pattern":"foo"}')"
expect deny  $C "Grep src"                "$(tool Grep '{"pattern":"foo","path":"src"}')"
expect allow $C "Grep docs"               "$(tool Grep '{"pattern":"foo","path":"docs"}')"
expect allow $C "Grep .harness"           "$(tool Grep '{"pattern":"foo","path":"/repo/.harness"}')"
expect deny  $C "Glob no path"            "$(tool Glob '{"pattern":"**/*.ts"}')"
expect deny  $C "Glob src"                "$(tool Glob '{"pattern":"*.ts","path":"/repo/src"}')"
expect allow $C "Glob docs"               "$(tool Glob '{"pattern":"*.md","path":"docs/superpowers"}')"

# --- Agent / Workflow --------------------------------------------------------
expect deny  $C "Agent"                   "$(tool Agent    '{"prompt":"x","description":"y"}')"
expect deny  $C "Workflow"                "$(tool Workflow '{"script":"x"}')"

# --- Bash allowlist ----------------------------------------------------------
expect allow $C "bash harness ask"        "$(tool Bash '{"command":"harness ask analyst \"what is this\""}')"
expect allow $C "bash harness status"     "$(tool Bash '{"command":"harness status"}')"
expect allow $C "bash herdr"              "$(tool Bash '{"command":"herdr agent list"}')"
expect allow $C "bash gh"                 "$(tool Bash '{"command":"gh pr view 12"}')"
expect allow $C "bash git status"         "$(tool Bash '{"command":"git status"}')"
expect allow $C "bash git log"            "$(tool Bash '{"command":"git log --oneline -5"}')"
expect allow $C "bash git diff --stat"    "$(tool Bash '{"command":"git diff --stat main...HEAD"}')"
expect deny  $C "bash git diff full"      "$(tool Bash '{"command":"git diff main...HEAD"}')"
expect allow $C "bash git branch"         "$(tool Bash '{"command":"git branch --show-current"}')"
expect allow $C "bash git show --stat"    "$(tool Bash '{"command":"git show --stat HEAD"}')"
expect deny  $C "bash git show full"      "$(tool Bash '{"command":"git show HEAD"}')"
expect deny  $C "bash git commit"         "$(tool Bash '{"command":"git commit -m x"}')"
expect allow $C "bash cat report"         "$(tool Bash '{"command":"cat .harness/reports/analyst.md"}')"
expect deny  $C "bash cat src"            "$(tool Bash '{"command":"cat src/a.ts"}')"
expect allow $C "bash ls .harness"        "$(tool Bash '{"command":"ls .harness/reports"}')"
expect allow $C "bash ls docs"            "$(tool Bash '{"command":"ls -la docs/superpowers"}')"
expect deny  $C "bash ls src"             "$(tool Bash '{"command":"ls src"}')"
expect deny  $C "bash npm test"           "$(tool Bash '{"command":"npm test"}')"
expect deny  $C "bash sed -i"             "$(tool Bash '{"command":"sed -i s/a/b/ src/a.ts"}')"
expect allow $C "bash compound ok"        "$(tool Bash '{"command":"git status && harness status"}')"
expect deny  $C "bash compound bad"       "$(tool Bash '{"command":"git status && npm test"}')"
expect deny  $C "bash pipe bad"           "$(tool Bash '{"command":"cat .harness/reports/a.md | sh"}')"
expect allow $C "bash pipe ok"            "$(tool Bash '{"command":"herdr agent list | jq .result"}')"
expect deny  $C "bash redirect"           "$(tool Bash '{"command":"git status > out.txt"}')"
expect allow $C "bash stderr redirect"    "$(tool Bash '{"command":"herdr agent get analyst 2>&1"}')"
expect deny  $C "bash subshell"           "$(tool Bash '{"command":"harness ask analyst \"$(cat src/a.ts)\""}')"
expect deny  $C "bash cd"                 "$(tool Bash '{"command":"cd src && ls"}')"
expect deny  $C "bash empty"              "$(tool Bash '{}')"

# --- other tools pass through ----------------------------------------------
expect allow $C "Skill"                   "$(tool Skill '{"skill":"x"}')"
expect allow $C "TodoWrite"               "$(tool TodoWrite '{"todos":[]}')"
expect allow $C "MCP tool"                "$(tool mcp__context7__query-docs '{"q":"x"}')"

# --- robustness ------------------------------------------------------------
expect allow $C "garbage input"           'not json at all'
expect allow $C "missing tool_name"       '{"tool_input":{}}'

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails (gate does not exist yet)**

Run: `/bin/bash tests/gate.test.sh | tail -3`
Expected: many `FAIL [...]` lines (every `deny` case reads as `allow` because the missing script produces no output), ending with `PASS 24 / FAIL 44` or similar, exit status 1.

- [ ] **Step 3: Commit**

```bash
git add tests/gate.test.sh
git commit -m "test(gate): table-driven PreToolUse gate cases

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Gate — implementation

**Files:**
- Create: `claude/hooks/conductor-gate.sh`

- [ ] **Step 1: Write the gate**

```bash
#!/bin/bash
# conductor-gate.sh — PreToolUse hook for the Fable conductor.
# Spec: docs/superpowers/specs/2026-10-12-herdr-conductor-setup-design.md
#
# Role:   HARNESS_ROLE=worker  -> allow everything (herdr workers, manual escape hatch)
#         anything else        -> conductor rules below
# Output: nothing (allow) or a PreToolUse deny JSON on stdout. Always exit 0.
set -u

if [ "${HARNESS_ROLE:-conductor}" = "worker" ]; then
  exit 0
fi

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  echo "conductor-gate: jq not found, allowing" >&2
  exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$TOOL" ]; then
  echo "conductor-gate: unparseable hook input, allowing" >&2
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD=$PWD

# Fixed strings: never interpolate per-call data (keeps the prompt cache stable).
MSG_WRITE="Conductor cannot edit source. Delegate: harness ask implementer '<instruction>'. Direct writes are allowed only under docs/**/*.md and .harness/."
MSG_READ="Conductor does not read source. Delegate: harness ask analyst '<question>' and read its report. Direct reads are allowed only under .harness/, docs/, and *.md files."
MSG_AGENT="Native subagents inherit the Fable model. Use harness ask <analyst|implementer|reviewer> '<instruction>' instead."
MSG_BASH="Conductor shell is limited to: harness, herdr, gh, read-only git (status / log / diff --stat / branch / show --stat), cat or ls under .harness/ and docs/. Delegate command execution: harness ask implementer '<command and goal>'."

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

field() { printf '%s' "$INPUT" | jq -r ".tool_input.$1 // empty" 2>/dev/null; }

# rel PATH -> prints the path relative to CWD, or returns 1 when the path is
# empty, outside CWD, or contains a '..' segment.
rel() {
  local p=$1
  [ -n "$p" ] || return 1
  case "$p" in
    ..|../*|*/..|*/../*) return 1 ;;
  esac
  case "$p" in
    "$CWD")   p="." ;;
    "$CWD"/*) p=${p#"$CWD"/} ;;
    /*)       return 1 ;;
    ./*)      p=${p#./} ;;
  esac
  printf '%s' "$p"
}

# readable PATH -> 0 when the conductor may read it
readable() {
  local p
  p=$(rel "$1") || return 1
  case "$p" in
    .harness|.harness/*|docs|docs/*|*.md) return 0 ;;
  esac
  return 1
}

# writable PATH -> 0 when the conductor may write it
writable() {
  local p
  p=$(rel "$1") || return 1
  case "$p" in
    .harness/*) return 0 ;;
    docs/*.md)  return 0 ;;
  esac
  return 1
}

# bash_ok COMMAND -> 0 when every segment of the command is on the allowlist
bash_ok() {
  local cmd=$1 stripped seg
  [ -n "$cmd" ] || return 1
  case "$cmd" in
    *'$('*|*'`'*) return 1 ;;
  esac
  # tolerate stderr->stdout redirects, reject any other redirect
  stripped=$(printf '%s' "$cmd" | sed 's/2>&1//g')
  case "$stripped" in
    *'>'*|*'<'*) return 1 ;;
  esac
  # split on ; && || |  (one segment per line)
  while IFS= read -r seg; do
    seg=$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$seg" ] || continue
    printf '%s' "$seg" | grep -Eq \
      '^(harness( .*)?|herdr( .*)?|gh( .*)?|jq( .*)?|git status( .*)?|git log( .*)?|git diff --stat( .*)?|git branch( .*)?|git show --stat( .*)?|cat \.harness/[^ ]*|ls( -[A-Za-z]+)*( (\.harness|docs)[^ ]*)?)$' \
      || return 1
  done <<EOF
$(printf '%s' "$stripped" | sed 's/&&/\
/g; s/||/\
/g; s/;/\
/g; s/|/\
/g')
EOF
  return 0
}

case "$TOOL" in
  Edit|Write)
    writable "$(field file_path)" || deny "$MSG_WRITE" ;;
  NotebookEdit)
    writable "$(field notebook_path)" || deny "$MSG_WRITE" ;;
  Read)
    readable "$(field file_path)" || deny "$MSG_READ" ;;
  Grep|Glob)
    readable "$(field path)" || deny "$MSG_READ" ;;
  Agent|Workflow)
    deny "$MSG_AGENT" ;;
  Bash)
    bash_ok "$(field command)" || deny "$MSG_BASH" ;;
esac

exit 0
```

Notes for the implementer:
- `jq` is allowed in the Bash allowlist so the conductor can post-process `herdr ... | jq` output. It is read-only.
- The `sed` newline substitution uses a literal backslash-newline because macOS `sed` does not understand `\n` in the replacement. Do **not** place that `sed` inside an unquoted heredoc (`<<EOF ... $(...)`): an unquoted heredoc treats backslash-newline as a line continuation and removes it before `sed` runs, so the split silently stops working. Run the split into a variable first (`segs=$(... | sed '...')`) and feed `$segs` to the heredoc. (Found and fixed during implementation.)
- `ls` pattern: zero or more flag groups, then an optional single `.harness...` or `docs...` argument. Bare `ls` (no argument) is allowed: it lists top-level names only, which the conductor needs to orient itself. `ls src` is denied because the argument group only accepts `.harness` or `docs` prefixes. Confirm with the `bash ls src` deny case.

- [ ] **Step 2: Make it executable and run the tests**

Run: `chmod +x claude/hooks/conductor-gate.sh && /bin/bash tests/gate.test.sh`
Expected: `PASS n / FAIL 0` where n equals the number of `expect` lines in the test file, exit 0. If any case fails, fix the gate, not the test, unless the test case contradicts the spec table.

- [ ] **Step 3: Check bash 3.2 compatibility explicitly**

Run: `/bin/bash -n claude/hooks/conductor-gate.sh && grep -nE 'declare -A|mapfile|\$\{[a-z]+,,\}' claude/hooks/conductor-gate.sh || echo "no bash4-isms"`
Expected: `no bash4-isms`

- [ ] **Step 4: Smoke test with a real-looking payload**

```bash
printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/Users/geonho.yeom/workspace/claude-code-setup/bin/harness"},"cwd":"/Users/geonho.yeom/workspace/claude-code-setup"}' \
  | /bin/bash claude/hooks/conductor-gate.sh | jq .
```
Expected: a JSON object with `permissionDecision: "deny"` and the `MSG_READ` text.

- [ ] **Step 5: Commit**

```bash
git add claude/hooks/conductor-gate.sh
git commit -m "feat(gate): PreToolUse conductor gate

Denies source reads/edits, native subagents and arbitrary shell for the
conductor role; passes everything when HARNESS_ROLE=worker.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Fake herdr stub for harness tests

**Files:**
- Create: `tests/fake-herdr/herdr`

The stub records every invocation in `$FAKE_LOG` and keeps per-agent state in `$FAKE_DIR/live.<name>` (file content = `agent_status`). Tests manipulate those files to simulate herdr behaviour.

- [ ] **Step 1: Write the stub**

```bash
#!/bin/bash
# Fake `herdr` for tests/harness.test.sh. Not a real client.
# State:  $FAKE_DIR/live.<agent>   exists => agent is live; content = agent_status
#         $FAKE_DIR/split_fail      exists => `pane split` fails
#         $FAKE_DIR/start_fail      exists => `agent start` fails
#         $FAKE_PROMPT_HOOK         shell snippet run when `agent prompt` is called
set -u
: "${FAKE_DIR:?FAKE_DIR must be set}"
: "${FAKE_LOG:?FAKE_LOG must be set}"
printf '%s\n' "$*" >> "$FAKE_LOG"

sub="${1:-} ${2:-}"
case "$sub" in
  "pane layout")
    echo '{"id":"cli:pane:layout","result":{"layout":{"panes":[{"pane_id":"w1:p1","rect":{"width":162,"height":45}}]},"type":"pane_layout"}}'
    ;;
  "pane split")
    if [ -f "$FAKE_DIR/split_fail" ]; then
      echo '{"error":{"code":"pane_not_found"}}' >&2; exit 1
    fi
    echo '{"id":"cli:pane:split","result":{"pane":{"pane_id":"w1:p2"}},"type":"pane_split"}'
    ;;
  "pane close")
    echo '{"id":"cli:pane:close","result":{},"type":"pane_close"}'
    ;;
  "agent get")
    name=$3
    if [ -f "$FAKE_DIR/live.$name" ]; then
      status=$(cat "$FAKE_DIR/live.$name")
      printf '{"id":"cli:agent:get","result":{"agent":{"agent":"claude","agent_status":"%s","pane_id":"w1:p2"}},"type":"agent_info"}\n' "$status"
    else
      echo '{"error":{"code":"agent_not_found"}}' >&2; exit 1
    fi
    ;;
  "agent start")
    name=$3
    if [ -f "$FAKE_DIR/start_fail" ]; then
      echo '{"error":{"code":"agent_not_ready"}}' >&2; exit 1
    fi
    echo idle > "$FAKE_DIR/live.$name"
    echo '{"id":"cli:agent:start","result":{},"type":"agent_start"}'
    ;;
  "agent prompt")
    name=$3
    if [ "$(cat "$FAKE_DIR/live.$name" 2>/dev/null)" = blocked ]; then
      echo '{"error":{"code":"agent_blocked"}}' >&2; exit 1
    fi
    if [ -n "${FAKE_PROMPT_HOOK:-}" ]; then
      /bin/bash -c "$FAKE_PROMPT_HOOK"
    fi
    echo '{"id":"cli:agent:prompt","result":{},"type":"agent_prompt"}'
    ;;
  "agent read")
    echo "fake screen line 1"
    echo "fake screen line 2"
    ;;
  *)
    echo "fake herdr: unhandled '$*'" >&2; exit 1
    ;;
esac
```

- [ ] **Step 2: Make it executable and sanity check**

Run:
```bash
chmod +x tests/fake-herdr/herdr
FAKE_DIR=$(mktemp -d) FAKE_LOG=/dev/null tests/fake-herdr/herdr pane split --current | jq -r .result.pane.pane_id
```
Expected: `w1:p2`

- [ ] **Step 3: Commit**

```bash
git add tests/fake-herdr/herdr
git commit -m "test(harness): fake herdr stub

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: harness CLI — tests first

**Files:**
- Create: `tests/harness.test.sh`

- [ ] **Step 1: Write the tests**

```bash
#!/bin/bash
# Tests for bin/harness against tests/fake-herdr. Run: /bin/bash tests/harness.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HARNESS="$HERE/../bin/harness"
FAKE_BIN="$HERE/fake-herdr"
pass=0
fail=0

# fresh WORK FAKE_DIR per case
setup() {
  WORK=$(mktemp -d)
  export FAKE_DIR="$WORK/fake"
  export FAKE_LOG="$WORK/herdr.log"
  mkdir -p "$FAKE_DIR"
  : > "$FAKE_LOG"
  unset FAKE_PROMPT_HOOK
  cd "$WORK" || exit 1
}

# run ARGS... -> sets OUT, RC
run() {
  OUT=$(HERDR_ENV=1 HERDR_PANE_ID=w1:p1 PATH="$FAKE_BIN:$PATH" /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}

check() { # check LABEL CONDITION...
  local label=$1; shift
  if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]: $OUT"; fi
}
logged() { grep -q -- "$1" "$FAKE_LOG"; }
not_logged() { ! grep -q -- "$1" "$FAKE_LOG"; }

# --- preconditions -----------------------------------------------------------
setup
OUT=$(PATH="$FAKE_BIN:$PATH" /bin/bash "$HARNESS" status 2>&1); RC=$?
check "refuses outside herdr" [ "$RC" -eq 1 ]
check "refuses outside herdr: message" grep -q "herdr pane" <<<"$OUT"

setup
run spawn bogus
check "unknown agent rc" [ "$RC" -eq 1 ]
check "unknown agent message" grep -q "unknown agent" <<<"$OUT"

run
check "no args shows usage" [ "$RC" -eq 1 ]
check "usage text" grep -q "harness ask" <<<"$OUT"

# --- spawn ---------------------------------------------------------------------
setup
run spawn analyst
check "spawn rc" [ "$RC" -eq 0 ]
check "spawn prints pane" [ "$OUT" = "w1:p2" ]
check "spawn splits with env" logged "pane split --current --direction right --cwd $WORK --env HARNESS_ROLE=worker --no-focus"
check "spawn starts agent" logged "agent start analyst --kind claude --pane w1:p2 -- --agent analyst"
check "spawn records pane" grep -q "^analyst w1:p2$" "$WORK/.harness/panes"

run spawn analyst
check "respawn rc" [ "$RC" -eq 0 ]
check "respawn reuses" [ "$(grep -c 'pane split' "$FAKE_LOG")" -eq 1 ]

setup
run spawn analyst --direction down
check "spawn direction flag" logged "pane split --current --direction down"

setup
touch "$FAKE_DIR/split_fail"
run spawn implementer
check "split failure rc" [ "$RC" -eq 1 ]
check "split failure message" grep -q "pane split failed" <<<"$OUT"

setup
touch "$FAKE_DIR/start_fail"
run spawn implementer
check "start failure rc" [ "$RC" -eq 1 ]
check "start failure shows screen" grep -q "fake screen line" <<<"$OUT"

# --- ask: success ----------------------------------------------------------------
setup
export FAKE_PROMPT_HOOK="mkdir -p $WORK/.harness/reports && printf '# analyst report\nstatus: done\n' > $WORK/.harness/reports/analyst.md"
run ask analyst "Describe the repo"
check "ask rc" [ "$RC" -eq 0 ]
check "ask spawns first" logged "agent start analyst"
check "ask prompts with wait" logged "agent prompt analyst Describe the repo --wait --timeout 600000"
check "ask prints report" grep -q "status: done" <<<"$OUT"

# --- ask: reuse + custom timeout + stale report removed --------------------------
setup
echo idle > "$FAKE_DIR/live.implementer"
mkdir -p .harness/reports && echo "OLD" > .harness/reports/implementer.md
export FAKE_PROMPT_HOOK="printf 'NEW\n' > $WORK/.harness/reports/implementer.md"
run ask implementer "do it" --timeout 1000
check "ask reuse: no spawn" not_logged "agent start"
check "ask custom timeout" logged "--wait --timeout 1000"
check "ask stale report replaced" [ "$OUT" = "NEW" ]

# --- ask: blocked before prompt --------------------------------------------------
setup
echo blocked > "$FAKE_DIR/live.analyst"
run ask analyst "x"
check "blocked before rc" [ "$RC" -eq 2 ]
check "blocked before: no prompt sent" not_logged "agent prompt"
check "blocked before: screen" grep -q "fake screen line" <<<"$OUT"

# --- ask: blocked after prompt ----------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.analyst"
export FAKE_PROMPT_HOOK="echo blocked > $FAKE_DIR/live.analyst"
run ask analyst "x"
check "blocked after rc" [ "$RC" -eq 2 ]
check "blocked after: screen" grep -q "fake screen line" <<<"$OUT"

# --- ask: finished without report ------------------------------------------------
setup
echo idle > "$FAKE_DIR/live.reviewer"
run ask reviewer "review"
check "no report rc" [ "$RC" -eq 3 ]
check "no report message" grep -q "no report" <<<"$OUT"
check "no report: screen" grep -q "fake screen line" <<<"$OUT"

# --- ask: still working (stalled/timeout) -----------------------------------------
setup
echo idle > "$FAKE_DIR/live.reviewer"
export FAKE_PROMPT_HOOK="echo working > $FAKE_DIR/live.reviewer"
run ask reviewer "review"
check "working rc" [ "$RC" -eq 4 ]
check "working message" grep -q "still working" <<<"$OUT"

# --- ask: missing instruction ------------------------------------------------------
setup
run ask analyst
check "ask without text rc" [ "$RC" -eq 1 ]

# --- status ----------------------------------------------------------------------------
setup
echo working > "$FAKE_DIR/live.implementer"
run status
check "status rc" [ "$RC" -eq 0 ]
check "status live line" grep -Eq "^implementer +working +w1:p2$" <<<"$OUT"
check "status dead line" grep -Eq "^analyst +-$" <<<"$OUT"

# --- close ------------------------------------------------------------------------------
setup
run spawn analyst
run close analyst
check "close rc" [ "$RC" -eq 0 ]
check "close calls pane close" logged "pane close w1:p2"
check "close unregisters" [ ! -s "$WORK/.harness/panes" ]

setup
echo idle > "$FAKE_DIR/live.analyst"   # live but not created by harness
run close analyst
check "close foreign pane rc" [ "$RC" -eq 1 ]
check "close foreign pane message" grep -q "not created by harness" <<<"$OUT"
check "close foreign pane: no close call" not_logged "pane close"

setup
run close analyst
check "close dead rc" [ "$RC" -eq 1 ]
check "close dead message" grep -q "not running" <<<"$OUT"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `/bin/bash tests/harness.test.sh | tail -3`
Expected: many FAIL lines (`bin/harness` does not exist, so every `run` returns rc 127), exit 1.

- [ ] **Step 3: Commit**

```bash
git add tests/harness.test.sh
git commit -m "test(harness): spawn/ask/status/close against fake herdr

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: harness CLI — implementation

**Files:**
- Create: `bin/harness`

- [ ] **Step 1: Write the CLI**

```bash
#!/bin/bash
# harness — conductor-side wrapper around herdr for named Claude workers.
# Spec: docs/superpowers/specs/2026-10-12-herdr-conductor-setup-design.md
#
#   harness spawn  <agent> [--direction right|down]
#   harness ask    <agent> "<instruction>" [--timeout MS]
#   harness status
#   harness close  <agent>
#
# Exit codes for `ask`: 0 report printed · 1 usage/setup error · 2 worker blocked
#                       3 worker finished without a report · 4 worker still working
set -u

AGENTS="analyst implementer reviewer"
REPORT_DIR=".harness/reports"
PANES_FILE=".harness/panes"
DEFAULT_TIMEOUT=600000

usage() {
  cat >&2 <<EOF
usage:
  harness spawn  <agent> [--direction right|down]
  harness ask    <agent> "<instruction>" [--timeout MS]
  harness status
  harness close  <agent>
agents: $AGENTS
EOF
  exit 1
}

die() { echo "harness: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH"; }

valid_agent() {
  case " $AGENTS " in
    *" $1 "*) return 0 ;;
  esac
  die "unknown agent '$1' (expected one of: $AGENTS)"
}

agent_json()   { herdr agent get "$1" 2>/dev/null; }
agent_live()   { agent_json "$1" >/dev/null; }
agent_pane()   { agent_json "$1" | jq -r '.result.agent.pane_id // empty'; }
agent_status() { agent_json "$1" | jq -r '.result.agent.agent_status // "unknown"'; }

show_screen() {
  echo "--- $1 screen (last 60 lines) ---"
  herdr agent read "$1" --source recent-unwrapped --lines 60 2>/dev/null
  echo "--- end ---"
}

# Terminal cells are roughly twice as tall as wide; a pane is "wide" when
# width >= 2.2 * height. Wide -> split right, otherwise down.
pick_direction() {
  local layout w h
  layout=$(herdr pane layout --pane "${HERDR_PANE_ID:-}" 2>/dev/null) || { echo right; return; }
  w=$(printf '%s' "$layout" | jq -r --arg p "${HERDR_PANE_ID:-}" '.result.layout.panes[] | select(.pane_id==$p) | .rect.width' 2>/dev/null)
  h=$(printf '%s' "$layout" | jq -r --arg p "${HERDR_PANE_ID:-}" '.result.layout.panes[] | select(.pane_id==$p) | .rect.height' 2>/dev/null)
  if [ -n "$w" ] && [ -n "$h" ] && [ "$w" -ge $((h * 22 / 10)) ]; then
    echo right
  else
    echo down
  fi
}

cmd_spawn() {
  local agent=${1:-} dir=""
  [ -n "$agent" ] || usage
  valid_agent "$agent"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --direction) dir=${2:-}; shift 2 ;;
      *) usage ;;
    esac
  done

  if agent_live "$agent"; then
    agent_pane "$agent"
    return 0
  fi

  [ -n "$dir" ] || dir=$(pick_direction)

  local out pane
  if ! out=$(herdr pane split --current --direction "$dir" --cwd "$PWD" --env HARNESS_ROLE=worker --no-focus 2>&1); then
    die "pane split failed: $out"
  fi
  pane=$(printf '%s' "$out" | jq -r '.result.pane.pane_id // empty' 2>/dev/null)
  [ -n "$pane" ] || die "pane split returned no pane id: $out"

  mkdir -p "$(dirname "$PANES_FILE")"
  printf '%s %s\n' "$agent" "$pane" >> "$PANES_FILE"

  if ! out=$(herdr agent start "$agent" --kind claude --pane "$pane" -- --agent "$agent" 2>&1); then
    echo "harness: agent start failed for $agent in $pane: $out" >&2
    show_screen "$pane" >&2
    exit 1
  fi
  echo "$pane"
}

cmd_ask() {
  local agent=${1:-} text=${2:-} timeout=$DEFAULT_TIMEOUT
  [ -n "$agent" ] && [ -n "$text" ] || usage
  valid_agent "$agent"
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout) timeout=${2:-}; shift 2 ;;
      *) usage ;;
    esac
  done

  cmd_spawn "$agent" >/dev/null || exit 1

  local report="$REPORT_DIR/$agent.md"
  mkdir -p "$REPORT_DIR"
  rm -f "$report"

  if [ "$(agent_status "$agent")" = blocked ]; then
    echo "harness: $agent is blocked on a prompt; answer it before sending work." >&2
    show_screen "$agent"
    exit 2
  fi

  local out
  if ! out=$(herdr agent prompt "$agent" "$text" --wait --timeout "$timeout" 2>&1); then
    echo "harness: prompt did not settle: $out" >&2
  fi

  case "$(agent_status "$agent")" in
    blocked)
      echo "harness: $agent is blocked (needs an answer)." >&2
      show_screen "$agent"
      exit 2 ;;
    idle|done)
      if [ -f "$report" ]; then
        cat "$report"
        exit 0
      fi
      echo "harness: $agent finished but wrote no report at $report" >&2
      show_screen "$agent"
      exit 3 ;;
    *)
      echo "harness: $agent is still working or in an unknown state; check 'harness status' before re-prompting." >&2
      show_screen "$agent"
      exit 4 ;;
  esac
}

cmd_status() {
  local a st pane
  for a in $AGENTS; do
    if agent_live "$a"; then
      st=$(agent_status "$a"); pane=$(agent_pane "$a")
      printf '%-12s %-8s %s\n' "$a" "$st" "$pane"
    else
      printf '%-12s %s\n' "$a" "-"
    fi
  done
}

cmd_close() {
  local agent=${1:-} pane
  [ -n "$agent" ] || usage
  valid_agent "$agent"
  pane=$(agent_pane "$agent")
  [ -n "$pane" ] || die "$agent is not running"
  grep -q "^$agent $pane\$" "$PANES_FILE" 2>/dev/null \
    || die "pane $pane was not created by harness; close it yourself"
  herdr pane close "$pane" >/dev/null || die "pane close failed for $pane"
  grep -v "^$agent $pane\$" "$PANES_FILE" > "$PANES_FILE.tmp" || true
  mv "$PANES_FILE.tmp" "$PANES_FILE"
  echo "closed $agent ($pane)"
}

need jq
need herdr
[ "${HERDR_ENV:-}" = 1 ] || die "run Claude inside a herdr pane (HERDR_ENV is not 1)"

case "${1:-}" in
  spawn)  shift; cmd_spawn "$@" ;;
  ask)    shift; cmd_ask "$@" ;;
  status) cmd_status ;;
  close)  shift; cmd_close "$@" ;;
  *)      usage ;;
esac
```

- [ ] **Step 2: Make it executable and run the tests**

Run: `chmod +x bin/harness && /bin/bash tests/harness.test.sh`
Expected: `PASS n / FAIL 0` where n equals the number of `check` calls in the test file, exit 0.

If `"refuses outside herdr"` fails: the `need`/`HERDR_ENV` checks must run before the subcommand dispatch, which they do at the bottom; confirm nothing above them executes herdr.

- [ ] **Step 3: bash 3.2 syntax check**

Run: `/bin/bash -n bin/harness && grep -nE 'declare -A|mapfile|\$\{[a-z]+,,\}' bin/harness || echo "no bash4-isms"`
Expected: `no bash4-isms`

- [ ] **Step 4: Commit**

```bash
git add bin/harness
git commit -m "feat(harness): herdr wrapper CLI for named workers

spawn/ask/status/close. ask returns the worker's report file and maps
blocked / no-report / still-working to exit codes 2 / 3 / 4.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Worker agent definitions

**Files:**
- Create: `claude/agents/analyst.md`, `claude/agents/implementer.md`, `claude/agents/reviewer.md`

- [ ] **Step 1: Write `claude/agents/analyst.md`**

```markdown
---
name: analyst
description: herdr worker for codebase analysis, design questions and plans. Reads anything, edits nothing outside docs/. Started by `harness ask analyst`.
model: opus
memory: project
experimental:
  cacheTtl: 1h
---

You are the **analyst** worker in a herdr pane. The conductor (another Claude
session) cannot read source, so your report is the only thing it will see.
`HARNESS_ROLE=worker` is set; you have full tool access.

## Your job

- Explore and explain code, propose approaches with trade-offs, write plans.
- Write plans or specs only under `docs/superpowers/` when the instruction
  asks for a document. Do not edit source files.
- Use your agent memory: record stable facts about this codebase (layout,
  build/test commands, conventions) so later tasks skip re-discovery.

## Report contract (mandatory)

When the task is complete, write `.harness/reports/analyst.md` with exactly
this shape, then reply with one line: `REPORT: .harness/reports/analyst.md`

```markdown
# analyst report — <one-line task summary>
status: done | partial | blocked
## Findings / Decisions
- ≤ 8 bullets, one line each, file:line where useful
## Verification
- how you confirmed each finding (command → result, or "read <file>")
## Open questions
- ≤ 3 bullets, or "none"
```

Rules: under 40 lines total. Longer detail goes in another file under
`.harness/` and is linked from the report. Never tell the conductor to read
source; answer the question in the report.
```

- [ ] **Step 2: Write `claude/agents/implementer.md`**

```markdown
---
name: implementer
description: herdr worker that implements changes, runs tests and lint, and reports. Started by `harness ask implementer`.
model: sonnet
memory: project
experimental:
  cacheTtl: 1h
---

You are the **implementer** worker in a herdr pane. The conductor (another
Claude session) cannot read or edit source, so you do all the hands-on work
and your report is the only thing it will see. `HARNESS_ROLE=worker` is set;
you have full tool access.

## Your job

- Implement exactly the instruction: goal, files or area, constraints, done
  criteria. If the instruction is ambiguous, pick the smallest reasonable
  reading and say so under Open questions.
- Run the relevant tests and lint before reporting. Add or update tests for
  behaviour you change.
- Commit only when the instruction says to commit, with the message it gives.
- Use your agent memory: record build/test/lint commands and conventions you
  discover so later tasks start faster.

## Report contract (mandatory)

When the task is complete, write `.harness/reports/implementer.md` with
exactly this shape, then reply with one line:
`REPORT: .harness/reports/implementer.md`

```markdown
# implementer report — <one-line task summary>
status: done | partial | blocked
## Changed files
- path — one line why
## Findings / Decisions
- ≤ 8 bullets, one line each
## Verification
- command run → result (tests, lint, manual check)
## Open questions
- ≤ 3 bullets, or "none"
```

Rules: under 40 lines total. Longer detail goes in another file under
`.harness/` and is linked from the report. Never tell the conductor to read
source; summarise what matters in the report.
```

- [ ] **Step 3: Write `claude/agents/reviewer.md`**

```markdown
---
name: reviewer
description: herdr worker that reviews a diff for correctness and reports findings by severity. Does not fix. Started by `harness ask reviewer`.
model: opus
experimental:
  cacheTtl: 1h
---

You are the **reviewer** worker in a herdr pane. The conductor (another
Claude session) cannot read source, so your report is the only thing it will
see. `HARNESS_ROLE=worker` is set; you have full tool access. You review;
you do not fix.

## Your job

- Review `git diff <base>...HEAD` where `<base>` is given in the instruction
  (default `main`). Read surrounding code as needed to judge correctness.
- Report real defects first: wrong behaviour, missing error handling that
  matters, security, data loss, broken tests. Style only if asked.
- Severity: **Critical** (ships a bug or security hole), **Major** (likely
  bug or missing test for changed behaviour), **Minor** (everything else).

## Report contract (mandatory)

When the review is complete, write `.harness/reports/reviewer.md` with
exactly this shape, then reply with one line:
`REPORT: .harness/reports/reviewer.md`

```markdown
# reviewer report — <base>...HEAD, <N> files
status: done | partial | blocked
## Findings / Decisions
- [Critical] file:line — what is wrong and why
- [Major] file:line — ...
- [Minor] file:line — ...
- (or "no findings")
## Verification
- commands you ran (tests, build) → result
## Open questions
- ≤ 3 bullets, or "none"
```

Rules: under 40 lines total; ≤ 8 findings, most severe first. Longer detail
goes in another file under `.harness/` and is linked from the report.
```

- [ ] **Step 4: Validate frontmatter parses and fields are the documented ones**

Run:
```bash
for f in claude/agents/*.md; do
  echo "== $f"; sed -n '2,/^---$/p' "$f" | sed '$d'
done
```
Expected: each file prints `name`, `description`, `model`, (`memory: project` for analyst/implementer), and the two-line `experimental:` / `  cacheTtl: 1h` block. No other keys.

- [ ] **Step 5: Commit**

```bash
git add claude/agents
git commit -m "feat(agents): analyst, implementer, reviewer worker definitions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Conductor protocol (CLAUDE.conductor.md)

**Files:**
- Create: `claude/CLAUDE.conductor.md`

- [ ] **Step 1: Write the protocol (static text only; nothing here may change per session)**

```markdown
# Conductor protocol

You are the **conductor**. You do not read or edit source and you do not
spawn native subagents. A PreToolUse gate denies those calls; its deny reason
names the worker to use. Work runs in herdr-hosted Claude workers that you
drive with the `harness` command.

## Workers

| worker | use it for | model |
|--------|-----------|-------|
| `analyst` | unknown code, design questions, plans, "what/why/where" | opus |
| `implementer` | any change: code, tests, config, commits | sonnet |
| `reviewer` | judging a diff before calling work done | opus |

## Loop

1. Classify the request: understand → `analyst`; change → `implementer`;
   verify → `reviewer`. Big requests: `analyst` plans, then `implementer`
   per task, then `reviewer`.
2. Delegate: `harness ask <worker> "<instruction>"`. Write the instruction so
   the worker needs nothing else: goal, files or area, constraints, done
   criteria, whether to commit and with what message.
3. Read only the report that `harness ask` prints. Decide: done, iterate with
   another `harness ask`, or ask the user.
4. Keep your own output short. Relay the report's substance to the user, not
   the report verbatim.

## Exit codes from `harness ask`

- `2` worker is blocked on a permission or question. Show the user the screen
  text and ask what to answer; then `harness ask` again.
- `3` worker finished without a report. `harness ask <worker> "Write the
  report for the task you just finished."`
- `4` stalled or timed out. Run `harness status` first; do not resend the
  same instruction blindly.

## With superpowers skills

Keep using the installed skills. Where a skill says to dispatch an `Agent`,
use `harness ask implementer`. Where a skill says to read or explore code,
use `harness ask analyst`. Where a skill asks for a code review, use
`harness ask reviewer`. You may write specs and plans yourself under
`docs/`; the gate allows `docs/**/*.md`.

## You may run directly

`harness`, `herdr`, `gh`, `jq`, `git status`, `git log`, `git diff --stat`,
`git branch`, `git show --stat`, and `cat`/`ls` under `.harness/` or `docs/`.
Everything else goes through a worker.

## Escape hatch

A project that must not be gated sets `{ "env": { "HARNESS_ROLE": "worker" } }`
in its `.claude/settings.json`. A human can run `HARNESS_ROLE=worker claude`
for an unrestricted session.
```

- [ ] **Step 2: Check it contains no per-session data (dates, paths with user names, counts)**

Run: `grep -nE '2026|geonho|/Users/' claude/CLAUDE.conductor.md || echo "static ok"`
Expected: `static ok`

- [ ] **Step 3: Commit**

```bash
git add claude/CLAUDE.conductor.md
git commit -m "feat(conductor): static protocol imported into ~/.claude/CLAUDE.md

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: install.sh — test first

**Files:**
- Create: `tests/install.test.sh`

The installer takes its targets from environment variables so tests can point it at a temp directory: `CLAUDE_DIR`, `BIN_DIR`, `GIT_IGNORE`, and `SKIP_HERDR_INTEGRATION=1`.

- [ ] **Step 1: Write the test**

```bash
#!/bin/bash
# Tests for install.sh. Run: /bin/bash tests/install.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
pass=0
fail=0
check() { local label=$1; shift; if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$label]"; fi; }

T=$(mktemp -d)
export CLAUDE_DIR="$T/claude" BIN_DIR="$T/bin" GIT_IGNORE="$T/gitignore" SKIP_HERDR_INTEGRATION=1
mkdir -p "$CLAUDE_DIR"
# pre-existing settings that must survive
cat > "$CLAUDE_DIR/settings.json" <<'EOF'
{
  "model": "fable",
  "permissions": { "defaultMode": "auto" },
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "/opt/other-hook.sh" } ] }
    ],
    "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "/opt/stop.sh" } ] } ]
  }
}
EOF
printf 'node_modules/\n' > "$GIT_IGNORE"

run_install() { /bin/bash "$REPO/install.sh" >"$T/out.txt" 2>&1; RC=$?; }

run_install
check "first run rc" [ "$RC" -eq 0 ]

S="$CLAUDE_DIR/settings.json"
GATE="$REPO/claude/hooks/conductor-gate.sh"
check "settings valid json" jq -e . "$S" >/dev/null
check "model preserved" [ "$(jq -r .model "$S")" = fable ]
check "defaultMode preserved" [ "$(jq -r .permissions.defaultMode "$S")" = auto ]
check "other PreToolUse hook preserved" jq -e '.hooks.PreToolUse[] | select(.hooks[0].command=="/opt/other-hook.sh")' "$S" >/dev/null
check "Stop hook preserved" jq -e '.hooks.Stop[0].hooks[0].command=="/opt/stop.sh"' "$S" >/dev/null
check "gate hook added once" [ "$(jq --arg g "$GATE" '[.hooks.PreToolUse[] | select(.hooks[] | .command==$g)] | length' "$S")" -eq 1 ]
check "gate matcher" jq -e --arg g "$GATE" '.hooks.PreToolUse[] | select(.hooks[] | .command==$g) | .matcher=="Edit|Write|NotebookEdit|Read|Grep|Glob|Bash|Agent|Workflow"' "$S" >/dev/null
check "promptCacheTtl" [ "$(jq -r .promptCacheTtl "$S")" = 1h ]
check "subagentPromptCacheTtl" [ "$(jq -r .subagentPromptCacheTtl "$S")" = 1h ]
check "backup created" ls "$CLAUDE_DIR"/settings.json.bak.* >/dev/null 2>&1

for a in analyst implementer reviewer; do
  check "agent symlink $a" [ "$(readlink "$CLAUDE_DIR/agents/$a.md")" = "$REPO/claude/agents/$a.md" ]
done
check "harness symlink" [ "$(readlink "$BIN_DIR/harness")" = "$REPO/bin/harness" ]
check "CLAUDE.md import line" grep -qxF "@$REPO/claude/CLAUDE.conductor.md" "$CLAUDE_DIR/CLAUDE.md"
check "global gitignore has .harness/" grep -qx '.harness/' "$GIT_IGNORE"
check "global gitignore keeps old lines" grep -qx 'node_modules/' "$GIT_IGNORE"

# second run: idempotent
run_install
check "second run rc" [ "$RC" -eq 0 ]
check "gate hook still once" [ "$(jq --arg g "$GATE" '[.hooks.PreToolUse[] | select(.hooks[] | .command==$g)] | length' "$S")" -eq 1 ]
check "other hook still once" [ "$(jq '[.hooks.PreToolUse[] | select(.hooks[] | .command=="/opt/other-hook.sh")] | length' "$S")" -eq 1 ]
check "import line once" [ "$(grep -cxF "@$REPO/claude/CLAUDE.conductor.md" "$CLAUDE_DIR/CLAUDE.md")" -eq 1 ]
check "gitignore line once" [ "$(grep -cx '.harness/' "$GIT_IGNORE")" -eq 1 ]

# fresh HOME with no settings.json at all
T2=$(mktemp -d)
CLAUDE_DIR="$T2/claude" BIN_DIR="$T2/bin" GIT_IGNORE="$T2/gitignore" /bin/bash "$REPO/install.sh" >/dev/null 2>&1
check "fresh install rc" [ $? -eq 0 ]
check "fresh settings created" jq -e '.hooks.PreToolUse | length == 1' "$T2/claude/settings.json" >/dev/null

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `/bin/bash tests/install.test.sh | tail -2`
Expected: `FAIL [first run rc]` and most other checks failing, exit 1.

- [ ] **Step 3: Commit**

```bash
git add tests/install.test.sh
git commit -m "test(install): idempotent settings merge and symlinks

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: install.sh — implementation

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write the installer**

```bash
#!/bin/bash
# install.sh — wire this repo into ~/.claude as the conductor setup.
# Idempotent. Re-run after pulling changes.
#
#   ./install.sh          install
#   ./install.sh --test   run the test suites and exit
#
# Overridable for tests: CLAUDE_DIR, BIN_DIR, GIT_IGNORE, SKIP_HERDR_INTEGRATION=1
set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
CLAUDE_DIR=${CLAUDE_DIR:-$HOME/.claude}
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}
GIT_IGNORE=${GIT_IGNORE:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}
SETTINGS="$CLAUDE_DIR/settings.json"
GATE="$REPO/claude/hooks/conductor-gate.sh"
IMPORT_LINE="@$REPO/claude/CLAUDE.conductor.md"
MATCHER="Edit|Write|NotebookEdit|Read|Grep|Glob|Bash|Agent|Workflow"

die() { echo "install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not on PATH"; }

if [ "${1:-}" = "--test" ]; then
  rc=0
  /bin/bash "$REPO/tests/gate.test.sh"    || rc=1
  /bin/bash "$REPO/tests/harness.test.sh" || rc=1
  /bin/bash "$REPO/tests/install.test.sh" || rc=1
  exit $rc
fi

need jq
if [ "${SKIP_HERDR_INTEGRATION:-0}" != 1 ]; then
  need herdr
fi

# 1. herdr's Claude integration first: it may rewrite settings.json itself,
#    and our merge below must see the result.
if [ "${SKIP_HERDR_INTEGRATION:-0}" != 1 ]; then
  if herdr integration install claude >/dev/null 2>&1; then
    echo "herdr: claude integration installed"
  else
    echo "warning: 'herdr integration install claude' failed; agent state detection falls back to heuristics" >&2
  fi
fi

# 2. agents + harness symlinks
mkdir -p "$CLAUDE_DIR/agents" "$BIN_DIR"
for f in "$REPO"/claude/agents/*.md; do
  ln -sfn "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
done
ln -sfn "$REPO/bin/harness" "$BIN_DIR/harness"
chmod +x "$REPO/bin/harness" "$GATE"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "warning: $BIN_DIR is not on PATH; add it so the conductor can run 'harness'" >&2 ;;
esac

# 3. settings.json: cache TTLs + exactly one gate hook entry
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq -e . "$SETTINGS" >/dev/null || die "$SETTINGS is not valid JSON; fix it before installing"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
tmp=$(mktemp)
jq --arg gate "$GATE" --arg matcher "$MATCHER" '
  .promptCacheTtl = "1h"
  | .subagentPromptCacheTtl = "1h"
  | .hooks //= {}
  | .hooks.PreToolUse //= []
  | .hooks.PreToolUse |= map(select(((.hooks // []) | map(.command == $gate) | any) | not))
  | .hooks.PreToolUse += [{matcher: $matcher, hooks: [{type: "command", command: $gate}]}]
' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

# 4. CLAUDE.md import
touch "$CLAUDE_DIR/CLAUDE.md"
grep -qxF "$IMPORT_LINE" "$CLAUDE_DIR/CLAUDE.md" || printf '\n%s\n' "$IMPORT_LINE" >> "$CLAUDE_DIR/CLAUDE.md"

# 5. global gitignore
mkdir -p "$(dirname "$GIT_IGNORE")"
touch "$GIT_IGNORE"
grep -qx '.harness/' "$GIT_IGNORE" || printf '.harness/\n' >> "$GIT_IGNORE"

cat <<EOF
installed:
  gate hook      $GATE  (matcher: $MATCHER)
  agents         $CLAUDE_DIR/agents/{analyst,implementer,reviewer}.md
  harness        $BIN_DIR/harness
  CLAUDE.md      $IMPORT_LINE
  cache TTL      promptCacheTtl=1h subagentPromptCacheTtl=1h
  gitignore      $GIT_IGNORE (+ .harness/)
next: start Claude inside a herdr pane and give it work. Escape hatch: HARNESS_ROLE=worker claude
EOF
```

- [ ] **Step 2: Make executable, run the install test**

Run: `chmod +x install.sh && /bin/bash tests/install.test.sh`
Expected: `PASS n / FAIL 0` where n equals the number of `check` calls in the test file, exit 0.

- [ ] **Step 3: Run the whole suite through the installer flag**

Run: `./install.sh --test`
Expected: three `PASS n / FAIL 0` lines, exit 0.

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat(install): idempotent ~/.claude installer with --test

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: README and spec alignment

**Files:**
- Create: `README.md`
- Modify: `docs/superpowers/specs/2026-10-12-herdr-conductor-setup-design.md` (the `harness spawn` step list)

- [ ] **Step 1: Write `README.md`**

```markdown
# claude-code-setup — herdr conductor

A user-level Claude Code setup where the main session (Fable) is a
**conductor**: it reads only worker reports and delegates all analysis and
implementation to Claude workers running in [herdr](https://herdr.dev) panes.

Why: Fable tokens are expensive. The conductor never loads source into its
context, and workers (`analyst` opus · `implementer` sonnet · `reviewer`
opus) carry project memory so they stop re-discovering the codebase.

## Requirements

- macOS, `/bin/bash` 3.2 is enough
- `jq`, `herdr` ≥ 0.9, Claude Code ≥ 2.1.248
- `~/.local/bin` on `PATH`

## Install

```bash
git clone https://github.com/geonhos/claude-code-setup ~/workspace/claude-code-setup
cd ~/workspace/claude-code-setup
./install.sh
```

`install.sh` is idempotent. It symlinks `claude/agents/*.md` into
`~/.claude/agents/`, links `bin/harness` into `~/.local/bin`, merges one
PreToolUse hook and `promptCacheTtl`/`subagentPromptCacheTtl: 1h` into
`~/.claude/settings.json` (backup kept), appends an `@import` line to
`~/.claude/CLAUDE.md`, adds `.harness/` to the global gitignore, and runs
`herdr integration install claude`.

Run `./install.sh --test` to execute the test suites.

## Daily use

1. Open a herdr pane in your project and start `claude` as usual.
2. Give it work. When it tries to read or edit source, the gate denies the
   call and tells it which worker to use.
3. It runs `harness ask <worker> "<instruction>"`. A sibling pane opens with
   a Claude worker; when the worker finishes, its report
   (`.harness/reports/<worker>.md`, ≤ 40 lines) is printed back.
4. You watch workers in their panes; the conductor only sees reports.

```
harness spawn  <agent> [--direction right|down]
harness ask    <agent> "<instruction>" [--timeout MS]   # exit 2 blocked · 3 no report · 4 still working
harness status
harness close  <agent>
```

## What the conductor may do directly

`harness`, `herdr`, `gh`, `jq`, read-only `git` (`status`, `log`,
`diff --stat`, `branch`, `show --stat`), `cat`/`ls` under `.harness/` and
`docs/`, and writing Markdown under `docs/`. Everything else is denied with a
reason naming the worker to use.

## Opt out

- Per project: `{ "env": { "HARNESS_ROLE": "worker" } }` in that project's
  `.claude/settings.json`.
- One session: `HARNESS_ROLE=worker claude`.

## Layout

```
bin/harness                  herdr wrapper CLI
claude/hooks/conductor-gate.sh   PreToolUse gate
claude/agents/*.md           worker definitions (model, memory, cacheTtl, report contract)
claude/CLAUDE.conductor.md   conductor protocol (imported into ~/.claude/CLAUDE.md)
install.sh                   installer (--test runs tests/)
tests/                       gate, harness (against tests/fake-herdr), install
docs/superpowers/            spec and plan
```
```

- [ ] **Step 2: Align the spec with the `--env` discovery**

In `docs/superpowers/specs/2026-10-12-herdr-conductor-setup-design.md`, in the `harness` CLI section, replace the `spawn` numbered steps 1–2:

Old:
```
  1. `herdr pane split --current --direction <d> --cwd "$PWD" --no-focus`
     → new pane id from `.result.pane.pane_id`.
  2. `herdr pane run <id> "export HARNESS_ROLE=worker"` and wait for the
     prompt to return.
```
New:
```
  1. `herdr pane split --current --direction <d> --cwd "$PWD" --env HARNESS_ROLE=worker --no-focus`
     → new pane id from `.result.pane.pane_id`. `--env` sets the variable on
     the pane shell, so Claude started there inherits it.
  2. Record `<agent> <pane>` in `.harness/panes`.
```

Also in the "Roles" section change "because `harness spawn` exports it in the pane shell before starting Claude" to "because `harness spawn` passes `--env HARNESS_ROLE=worker` to `herdr pane split`".

- [ ] **Step 3: Commit**

```bash
git add README.md docs/superpowers/specs/2026-10-12-herdr-conductor-setup-design.md
git commit -m "docs: README for the conductor setup; spec uses pane split --env

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Live verification inside herdr (manual, documented)

This task cannot run from a test script. It needs a real herdr pane with Claude Code. Record results in the PR description or a short note at the end of the plan.

**Files:**
- Modify: `docs/superpowers/plans/2026-10-12-herdr-conductor-setup.md` (append results under "Live verification results")

- [ ] **Step 1: Install for real**

Run: `./install.sh`
Expected: the `installed:` summary, no warnings. Then `jq '.hooks.PreToolUse | length' ~/.claude/settings.json` shows one more entry than before and `cat ~/.claude/CLAUDE.md` ends with the import line.

- [ ] **Step 2: Start the conductor inside herdr**

In a herdr pane, in this repo: `claude`. First prompt:

```
Read bin/harness and tell me what the exit codes mean.
```

Expected: Claude's `Read` is denied, the deny reason mentions `harness ask analyst`, and Claude then runs `harness ask analyst "..."`. A sibling pane opens with the analyst; after it finishes, the conductor relays the report. Note: time to first report, and whether the analyst's pane shows `claude --agent analyst` and the opus model in its UI.

- [ ] **Step 3: Verify `memory: project` is honoured in a `--agent` session**

In the analyst pane after step 2: `ls .claude/agent-memory/analyst/` in this repo should exist with a `MEMORY.md`. If it does not exist, memory is not honoured for `--agent` main sessions. Fallback: add to `analyst.md` and `implementer.md` bodies a line
`Keep durable notes about this project in .claude/agent-memory/<name>/MEMORY.md and read it first.` and record the finding.

- [ ] **Step 4: Verify the implementer round trip and the worker gate bypass**

Prompt the conductor:

```
Add a line "## Status" followed by "experimental" to the end of README.md and commit it with message "docs: status line".
```

Expected: the conductor delegates to `implementer`; the implementer edits README.md (its own gate call passes because `HARNESS_ROLE=worker` is in its environment), commits, writes the report, and the conductor relays it. `git log -1` shows the commit. Then revert: `git reset --hard HEAD~1` from the implementer pane or manually.

- [ ] **Step 5: Verify the blocked path**

Prompt the conductor with something that will trigger a permission prompt in the worker (for example an instruction to run `rm -rf .harness` if the worker pane is not in bypass mode). Expected: `harness ask` exits 2 and the conductor shows the screen text and asks you. If the worker's permission mode auto-approves, note that and skip.

- [ ] **Step 6: Record results**

Append to this plan file:

```markdown
## Live verification results (YYYY-MM-DD)

- analyst round trip: <ok | issue>
- memory honoured for --agent: <yes | no → fallback applied>
- implementer round trip + commit: <ok | issue>
- blocked path (exit 2): <ok | skipped: auto mode>
- notes: ...
```

Commit:
```bash
git add docs/superpowers/plans/2026-10-12-herdr-conductor-setup.md
git commit -m "docs(plan): live verification results

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Self-review against the spec

- Roles / `HARNESS_ROLE` default conductor, worker bypass, per-project opt-out, herdr-only note → Task 3 (first line of gate), Task 6 (`--env`), Task 8 and README (opt-out).
- Requirement 1: input restriction → Task 3 table; cache TTL settings → Task 10 jq merge; static CLAUDE.md → Task 8 step 2 check; `memory: project` + `cacheTtl` → Task 7; worker reuse → Task 6 `cmd_spawn` live check, tested in Task 5 "respawn reuses".
- Requirement 2: gate table incl. compound Bash, deny reasons naming next action → Tasks 2–3; `harness spawn/ask/status/close` with exit codes 2/3/4 → Tasks 5–6; report template → Task 7; conductor protocol → Task 8.
- Installer behaviours (symlinks, jq merge identified by command path, CLAUDE.md import, herdr integration, global gitignore, `--test`) → Tasks 9–10.
- Error table (outside herdr, blocked, no report, unparseable hook input, missing jq/herdr) → Tasks 3, 6, 10; tested in Tasks 2, 5, 9.
- Testing section (gate tests on bash 3.2, harness round trip, `--agent` memory check, installer twice) → Tasks 2, 5, 9, 12.
- Deviation from spec: `pane split --env` replaces `pane run export`; Task 11 updates the spec text.
