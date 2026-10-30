#!/bin/bash
# Tests for claude/hooks/conductor-gate.sh. Run: /bin/bash tests/gate.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GATE="${GATE_UNDER_TEST:-$HERE/../claude/hooks/conductor-gate.sh}"
CWD=/repo
# chk is a harness checkout (has .harness/asks), plain is not. The payloads say
# cwd=/repo (absent), so the gate falls back to $PWD = chk.
GATE_HOME=$(cd "$(mktemp -d)" && pwd -P)
mkdir -p "$GATE_HOME/chk/.harness/asks" "$GATE_HOME/plain"
pass=0
fail=0

# run_gate ROLE JSON -> prints the gate's stdout; returns the gate's exit code
run_gate() {
  printf '%s' "$2" | (cd "$GATE_HOME/chk" && HARNESS_ROLE="$1" /bin/bash "$GATE" 2>/dev/null)
}

# decision ROLE JSON -> prints allow|deny, or exit=<rc> when the gate exits
# non-zero (the hook must always exit 0)
decision() {
  local out rc
  out=$(run_gate "$1" "$2")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "exit=$rc"
  elif [ -z "$out" ]; then
    echo allow
  else
    printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'
  fi
}

# subject JSON -> the payload's command or file path, for FAIL messages
subject() {
  printf '%s' "$1" | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.path // empty' 2>/dev/null
}

# report OK LABEL EXPECTED GOT JSON
report() {
  if [ "$1" = ok ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL [$2]: expected $3, got $4 -- input: $(subject "$5")"
  fi
}

# expect EXPECTED ROLE LABEL JSON
expect() {
  local got
  got=$(decision "$2" "$4")
  if [ "$got" = "$1" ]; then report ok "$3" "$1" "$got" "$4"
  else report bad "$3" "$1" "$got" "$4"; fi
}

# expect_reason PREFIX LABEL JSON -> conductor deny whose reason starts with PREFIX
expect_reason() {
  local got
  got=$(run_gate conductor "$3" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
  case "$got" in
    "$1"*) report ok "$2" "$1..." "$got" "$3" ;;
    *)     report bad "$2" "$1..." "$got" "$3" ;;
  esac
}

# expect_event LABEL JSON -> conductor deny carries hookEventName PreToolUse
expect_event() {
  local got
  got=$(run_gate conductor "$2" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
  if [ "$got" = PreToolUse ]; then report ok "$1" PreToolUse "$got" "$2"
  else report bad "$1" PreToolUse "$got" "$2"; fi
}

# tool NAME INPUT_JSON -> full hook payload
tool() {
  jq -n -c --arg t "$1" --argjson i "$2" --arg c "$CWD" \
    '{tool_name:$t, tool_input:$i, cwd:$c, hook_event_name:"PreToolUse", session_id:"s1"}'
}

# bcmd COMMAND -> Bash hook payload with COMMAND as tool_input.command
bcmd() { tool Bash "$(printf '%s' "$1" | jq -Rs '{command:.}')"; }

TAB=$(printf '\t')
NL='
'

C=conductor
W=worker

# --- role bypass ---------------------------------------------------------
expect allow $W "worker: Edit src"        "$(tool Edit  '{"file_path":"/repo/src/a.ts","old_string":"a","new_string":"b"}')"
expect allow $W "worker: Read src"        "$(tool Read  '{"file_path":"/repo/src/a.ts"}')"
expect allow $W "worker: Agent"           "$(tool Agent '{"prompt":"x"}')"
expect allow $W "worker: Bash rm"         "$(bcmd 'rm -rf build')"

# --- agent_type keying (v21): the hook input's agent decides, not the env ---
# as_agent AGENT JSON -> JSON with agent_type set
as_agent() { printf '%s' "$2" | jq -c --arg a "$1" '. + {agent_type:$a}'; }
RM=$(bcmd 'rm -rf build')
expect deny  $C "agent conductor: Bash rm"                "$(as_agent conductor "$RM")"
expect deny  $W "agent conductor beats HARNESS_ROLE=worker" "$(as_agent conductor "$RM")"
expect allow $C "agent analyst allowed"                   "$(as_agent analyst "$RM")"
expect allow $C "agent implementer allowed"               "$(as_agent implementer "$RM")"
expect allow $W "agent solo + worker env allowed"         "$(as_agent solo "$RM")"
expect deny  $C "no agent_type, conductor env: gated"     "$RM"
expect allow $W "no agent_type, worker env: allowed"      "$RM"
as_sub() { printf '%s' "$2" | jq -c --arg a "$1" '. + {agent_type:$a, agent_id:"sub1"}'; }
expect deny  $C "subagent (agent_id) of conductor, conductor env: gated" "$(as_sub conductor "$RM")"
expect deny  $C "subagent (agent_id) other type, conductor env: gated"   "$(as_sub analyst "$RM")"
expect allow $W "subagent (agent_id), worker env: allowed"               "$(as_sub conductor "$RM")"
expect deny  $C "agent_type but no tool_name"             '{"agent_type":"analyst","tool_input":{}}'

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
expect allow $C "cwd trailing slash"      "$(jq -n -c '{tool_name:"Write",tool_input:{file_path:"/repo/docs/a.md",content:"x"},cwd:"/repo/"}')"

# --- Read / Grep / Glob ------------------------------------------------------
expect deny  $C "Read src"                "$(tool Read '{"file_path":"/repo/src/a.ts"}')"
expect allow $C "Read root md"            "$(tool Read '{"file_path":"/repo/README.md"}')"
expect allow $C "Read docs any"           "$(tool Read '{"file_path":"docs/img.png"}')"
expect allow $C "Read .harness report"    "$(tool Read '{"file_path":".harness/reports/analyst.md"}')"
expect deny  $C "Read outside cwd"        "$(tool Read '{"file_path":"/Users/x/other/a.md"}')"
expect deny  $C "Read tilde"              "$(tool Read '{"file_path":"~/secret.md"}')"
expect deny  $C "Grep no path"            "$(tool Grep '{"pattern":"foo"}')"
expect deny  $C "Grep src"                "$(tool Grep '{"pattern":"foo","path":"src"}')"
expect allow $C "Grep docs"               "$(tool Grep '{"pattern":"foo","path":"docs"}')"
expect deny  $C "Grep .harness (raw streams)" "$(tool Grep '{"pattern":"foo","path":"/repo/.harness"}')"
expect deny  $C "Grep .harness/log"        "$(tool Grep '{"pattern":"foo","path":".harness/log"}')"
expect allow $C "Grep .harness/reports"    "$(tool Grep '{"pattern":"foo","path":".harness/reports"}')"
expect deny  $C "Read raw stream"          "$(tool Read '{"file_path":"/repo/.harness/log/20261023-analyst.jsonl"}')"
expect deny  $C "Read gz raw stream"       "$(tool Read '{"file_path":".harness/log/20261023-analyst.jsonl.gz"}')"
expect allow $C "Read failure log .md"     "$(tool Read '{"file_path":".harness/log/20261023-analyst.md"}')"
expect deny  $C "cat raw stream"           "$(bcmd 'cat .harness/log/x.jsonl')"
expect allow $C "cat log md"               "$(bcmd 'cat .harness/log/x.md')"
expect deny  $C "harness-run not delegable" "$(bcmd 'harness-run analyst x /')"
expect deny  $C "jq raw stream"            "$(bcmd 'jq . .harness/log/x.jsonl')"
expect deny  $C "Read raw stream .JSONL"    "$(tool Read '{"file_path":".harness/log/20261023-analyst.JSONL"}')"
expect deny  $C "Read raw stream .Jsonl.GZ" "$(tool Read '{"file_path":"/repo/.harness/log/x.Jsonl.GZ"}')"
expect deny  $C "cat raw stream .JSONL"     "$(bcmd 'cat .harness/log/x.JSONL')"
expect deny  $C "Grep file raw .Jsonl"      "$(tool Grep '{"pattern":"foo","path":".harness/log/x.Jsonl"}')"
expect deny  $C "Read raw stream mixed dir" "$(tool Read '{"file_path":".harness/LOG/x.jsonl"}')"
expect deny  $C "Glob no path"            "$(tool Glob '{"pattern":"**/*.ts"}')"
expect deny  $C "Glob src"                "$(tool Glob '{"pattern":"*.ts","path":"/repo/src"}')"
expect allow $C "Glob docs"               "$(tool Glob '{"pattern":"*.md","path":"docs/superpowers"}')"
expect deny  $C "Glob pattern dotdot"     "$(tool Glob '{"pattern":"../src/**","path":"docs"}')"
expect deny  $C "Glob pattern abs"        "$(tool Glob '{"pattern":"/repo/src/**","path":"docs"}')"
expect deny  $C "Glob pattern tilde"      "$(tool Glob '{"pattern":"~/x/**","path":"docs"}')"
expect allow $C "Glob docs pattern no path"     "$(tool Glob '{"pattern":"docs/**/*.md"}')"
expect allow $C "Glob .harness pattern no path" "$(tool Glob '{"pattern":".harness/reports/*.md"}')"
expect deny  $C "Glob src pattern no path"      "$(tool Glob '{"pattern":"src/**"}')"


# --- Bash: allowlist ---------------------------------------------------------
expect allow $C "bash harness ask"        "$(bcmd 'harness ask analyst "what is this"')"
expect allow $C "bash harness ask --via"  "$(bcmd "harness ask implementer 'x' --via skill")"
expect allow $C "bash harness route-log"  "$(bcmd "harness route-log '{\"event\":\"prompt\"}'")"
expect allow $C "bash harness status"     "$(bcmd 'harness status')"
expect allow $C "bash herdr"              "$(bcmd 'herdr agent list')"
expect allow $C "bash gh"                 "$(bcmd 'gh pr view 12')"
expect deny  $C "bash npm test"           "$(bcmd 'npm test')"
expect deny  $C "bash sed -i"             "$(bcmd 'sed -i s/a/b/ src/a.ts')"
expect deny  $C "bash cd"                 "$(bcmd 'cd src && ls')"
expect deny  $C "bash empty"              "$(tool Bash '{}')"   # missing command field: bcmd cannot build this
expect deny  $C "bash only separator"     "$(bcmd ';')"
expect allow $C "bash herdr agent get"    "$(bcmd 'herdr agent get analyst')"
expect allow $C "bash herdr agent wait"   "$(bcmd 'herdr agent wait analyst --timeout 600')"
expect allow $C "bash herdr pane current" "$(bcmd 'herdr pane current')"
expect allow $C "bash herdr pane get"     "$(bcmd 'herdr pane get w1:p2')"
expect allow $C "bash git branch -a"      "$(bcmd 'git branch -a')"
expect allow $C "bash gh pr merge"        "$(bcmd 'gh pr merge 30 --squash')"
expect deny  $C "bash herdr pane run"     "$(bcmd 'herdr pane run w1:p2 "npm test"')"
expect deny  $C "bash herdr send-keys"    "$(bcmd 'herdr agent send-keys analyst esc')"
expect deny  $C "bash herdr prompt"       "$(bcmd 'herdr agent prompt analyst "x"')"
expect deny  $C "bash herdr pane read"    "$(bcmd 'herdr pane read w1:p2')"
expect deny  $C "bash herdr server stop"  "$(bcmd 'herdr server stop')"
expect deny  $C "bash herdr quoted verb"  "$(bcmd 'herdr agent "send-keys" analyst esc')"
expect allow $C "bash gh pr create"       "$(bcmd 'gh pr create --title x --body-file .harness/pr.md')"
expect deny  $C "bash gh api"             "$(bcmd 'gh api repos/o/r/contents/src/a.ts')"
expect deny  $C "bash gh pr diff"         "$(bcmd 'gh pr diff 12')"
expect deny  $C "bash gh quoted api"      "$(bcmd 'gh "api" repos/o/r/contents/src/a.ts')"
expect deny  $C "bash gh pr  diff spaces" "$(bcmd 'gh pr  diff 12')"
expect deny  $C "bash gh alias"           "$(bcmd "gh alias set x '!sh -c id'")"
expect deny  $C "bash gh extension"       "$(bcmd 'gh extension install o/r')"

# --- Bash: separators --------------------------------------------------------
expect deny  $C "bash compound denied"        "$(bcmd 'git status && harness status')"
expect deny  $C "bash compound bad"       "$(bcmd 'git status && npm test')"
expect deny  $C "bash single &"           "$(bcmd 'git status & npm test')"
expect deny  $C "bash single & nospace"   "$(bcmd 'harness status &rm -rf src')"
expect deny  $C "bash pipe bad"           "$(bcmd 'cat .harness/reports/a.md | sh')"
expect deny  $C "bash newline separator"  "$(bcmd "git status${NL}rm -rf src")"
expect deny  $C "bash tab separator"      "$(bcmd "cat .harness/x${TAB}src/a.ts")"
expect deny  $C "bash comment quote"      "$(bcmd "harness x #'${NL}echo PWNED #'")"
expect deny  $C "bash comment ;"          "$(bcmd 'harness x # ; rm -rf src')"

# --- Bash: quoting and expansion ---------------------------------------------
expect allow $C "bash quoted ;"           "$(bcmd 'harness ask analyst "fix a; b"')"
expect allow $C "bash quoted >"           "$(bcmd 'harness ask analyst "is a > b?"')"
expect allow $C "bash squoted &&"         "$(bcmd "harness ask implementer 'run x && y'")"
expect allow $C "bash quoted #"           "$(bcmd 'harness ask analyst "see issue #12"')"
expect deny  $C "bash subshell"           "$(bcmd 'harness ask analyst "$(cat src/a.ts)"')"
expect deny  $C "bash quote confusion"    "$(bcmd "harness 'a\"' ; rm -rf src ; echo '\"'")"
expect deny  $C "bash escaped quotes"     "$(bcmd 'harness \" ; rm -rf src ; echo \"')"
expect deny  $C "bash unterminated quote" "$(bcmd 'harness "abc')"
expect deny  $C "bash ansi-c quote"       "$(bcmd "harness \$'\\'' ; rm -rf src #'")"
expect deny  $C "bash locale quote"       "$(bcmd 'harness $"x" ; rm -rf src')"
expect deny  $C "bash proc subst <("     "$(bcmd 'cat <(ls src)')"
expect deny  $C "bash proc subst >("     "$(bcmd 'harness status >(cat)')"
expect allow $C "bash sq backticks"       "$(bcmd "harness ask analyst 'Edit \`src/a.ts\` then run tests'")"
expect allow $C "bash sq \$("            "$(bcmd "harness ask analyst 'see \$(not expanded)'")"
expect deny  $C "bash dq backticks"       "$(bcmd 'harness ask analyst "run `id`"')"
expect deny  $C "bash unquoted backticks" "$(bcmd 'harness `id`')"
expect deny  $C "bash dq escaped \$("    "$(bcmd 'harness ask analyst "cost \$(x)"')"

# --- Bash: redirects ---------------------------------------------------------
expect deny  $C "bash redirect"           "$(bcmd 'git status > out.txt')"
expect deny  $C "bash here-string"        "$(bcmd 'jq . <<< x')"
expect deny  $C "bash 2>&1 end denied"           "$(bcmd 'herdr agent get analyst 2>&1')"
expect deny  $C "bash 2>&1 pipe denied"          "$(bcmd 'herdr agent get analyst 2>&1 | jq .result')"
expect deny  $C "bash 2>&1 glued file"    "$(bcmd 'cat .harness/x2>&1src')"
expect deny  $C "bash 2>&1 glued tail"    "$(bcmd 'harness status 2>&1x')"

# --- Bash: jq is not on the allowlist (pipes are denied outright) ----------------------------------------------------------------
expect deny  $C "bash jq pipe denied"           "$(bcmd 'herdr agent list | jq .result')"
expect deny  $C "bash jq quoted pipe denied"   "$(bcmd "herdr agent list | jq -r '.result.agents[].pane_id'")"
expect deny  $C "bash jq first"           "$(bcmd 'jq . src/secret.json')"

# --- Bash: git ---------------------------------------------------------------
expect allow $C "bash git status"         "$(bcmd 'git status')"
expect allow $C "bash git status short"   "$(bcmd 'git status --short')"
expect allow $C "bash git log"            "$(bcmd 'git log --oneline -5')"
expect allow $C "bash git log --stat"     "$(bcmd 'git log --stat')"
expect allow $C "bash git diff --stat"    "$(bcmd 'git diff --stat main...HEAD')"
expect allow $C "bash git branch"         "$(bcmd 'git branch --show-current')"
expect deny  $C "bash git diff full"      "$(bcmd 'git diff main...HEAD')"
expect deny  $C "bash git show full"      "$(bcmd 'git show HEAD')"
expect deny  $C "bash git commit"         "$(bcmd 'git commit -m x')"
expect deny  $C "bash git show path"      "$(bcmd 'git show --stat HEAD:src/a.ts')"
expect deny  $C "bash git show qpath"     "$(bcmd 'git show --stat "HEAD:src/a.ts"')"
expect deny  $C "bash git log --output"   "$(bcmd 'git log --output=src/a.ts')"
expect deny  $C "bash git diff --output"  "$(bcmd 'git diff --stat --output=x')"
expect deny  $C "bash git branch -D"      "$(bcmd 'git branch -D main')"
expect deny  $C "bash git branch -Df"     "$(bcmd 'git branch -Df main')"
expect deny  $C "bash git branch qD"      "$(bcmd 'git branch "-D" main')"
expect deny  $C "bash git branch --delete" "$(bcmd 'git branch --delete main')"
expect deny  $C "bash git branch -m"      "$(bcmd 'git branch -m x')"
expect deny  $C "bash git branch --move"  "$(bcmd 'git branch --move x y')"
expect deny  $C "bash git branch -c"      "$(bcmd 'git branch -c x y')"
expect deny  $C "bash git log -p"         "$(bcmd 'git log -p')"
expect deny  $C "bash git log --patch"    "$(bcmd 'git log --patch')"
expect deny  $C "bash git diff --stat -p" "$(bcmd 'git diff --stat -p')"
expect deny  $C "bash git log -u"         "$(bcmd 'git log -u')"
expect deny  $C "bash git log -U3"        "$(bcmd 'git log -U3')"
expect deny  $C "bash git diff --unified" "$(bcmd 'git diff --stat --unified=3')"
expect deny  $C "bash git log --cc"       "$(bcmd 'git log --cc')"
expect deny  $C "bash git log --binary"   "$(bcmd 'git log --binary')"
expect deny  $C "bash git log --remerge"  "$(bcmd 'git log --remerge-diff')"
expect deny  $C "bash git log --raw"      "$(bcmd 'git log --raw')"
expect deny  $C "bash git log --dd"       "$(bcmd 'git log --dd')"
expect deny  $C "bash git log diff-merges" "$(bcmd 'git log --diff-merges=on')"
expect deny  $C "bash git log --check"    "$(bcmd 'git log --check')"
expect deny  $C "bash git diff --check"   "$(bcmd 'git diff --stat --check')"

# --- Bash: cat / ls ----------------------------------------------------------
expect allow $C "bash cat report"         "$(bcmd 'cat .harness/reports/analyst.md')"
expect allow $C "bash cat docs"           "$(bcmd 'cat docs/superpowers/specs/x.md')"
expect allow $C "bash ls .harness"        "$(bcmd 'ls .harness/reports')"
expect allow $C "bash ls docs"            "$(bcmd 'ls -la docs/superpowers')"
expect allow $C "bash ls docs bare"       "$(bcmd 'ls docs')"
expect deny  $C "bash cat src"            "$(bcmd 'cat src/a.ts')"
expect deny  $C "bash ls src"             "$(bcmd 'ls src')"
expect deny  $C "bash ls .harnessx"       "$(bcmd 'ls .harnessx')"
expect deny  $C "bash cat dotdot"         "$(bcmd 'cat .harness/../src/a.ts')"
expect deny  $C "bash cat docs dotdot"    "$(bcmd 'cat docs/../src/a.ts')"
expect deny  $C "bash ls dotdot"          "$(bcmd 'ls docs/../src')"
expect deny  $C "bash cat quoted dotdot"  "$(bcmd 'cat ".harness/../src/a.ts"')"
expect deny  $C "bash cat dq dotdot"      "$(bcmd 'cat .harness/"../src/a.ts"')"
expect deny  $C "bash cat sq dotdot"      "$(bcmd "cat .harness/'..'/src/a.ts")"
expect deny  $C "bash ls dq dotdot"       "$(bcmd 'ls docs/".."/src')"
expect deny  $C "bash cat brace"          "$(bcmd 'cat .harness/{,../src/a.ts}')"
expect deny  $C "bash cat param exp"      "$(bcmd 'cat .harness/${X:-../src/a.ts}')"
expect deny  $C "bash cat ?"              "$(bcmd 'cat .harness/.?/src/a.ts')"
expect deny  $C "bash cat *"              "$(bcmd 'cat .harness/*')"
expect deny  $C "bash cat \$HOME"         "$(bcmd 'cat .harness/$HOME')"
expect deny  $C "bash cat backslash"      "$(bcmd 'cat .harness/\.\./src/a.ts')"


# --- hardening: jq missing fails closed (spec 5) ----------------------------
JQBIN=$(mktemp -d)
for b in cat awk sed tr grep; do ln -s "$(command -v $b)" "$JQBIN/$b"; done
nojq() { printf '%s' "$2" | (cd "${3:-$GATE_HOME/chk}" && PATH="$JQBIN" HARNESS_ROLE="$1" /bin/bash "$GATE" 2>/dev/null); }
got=$(nojq conductor "$(bcmd 'ls')")
if [ "$got" = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Conductor gate requires jq. Install jq, or run a worker session."}}' ]
then report ok "no jq: conductor denied" deny deny x; else report bad "no jq: conductor denied" deny "$got" "$(bcmd 'ls')"; fi
got=$(nojq worker "$(bcmd 'rm -rf x')")
if [ -n "$got" ]; then report ok "no jq: worker env denied (agent unknown)" deny deny x; else report bad "no jq: worker env denied (agent unknown)" deny "$got" "$(bcmd 'rm -rf x')"; fi
rm -rf "$JQBIN"

# --- hardening: gh allowlist (spec 1) ---------------------------------------
expect deny  $C "gh run view --log"       "$(bcmd 'gh run view 1 --log')"
expect deny  $C "gh run view --log-failed" "$(bcmd 'gh run view 1 --log-failed')"
expect deny  $C "gh gist view"            "$(bcmd 'gh gist view x')"
expect deny  $C "gh repo clone"           "$(bcmd 'gh repo clone o/r')"
expect deny  $C "gh pr checkout"          "$(bcmd 'gh pr checkout 1')"
expect deny  $C "gh -R api"               "$(bcmd 'gh -R o/r api repos')"
expect deny  $C "gh --repo pr diff"       "$(bcmd 'gh --repo o/r pr diff 1')"
expect deny  $C "gh search"               "$(bcmd 'gh search code foo')"
expect deny  $C "gh release download"     "$(bcmd 'gh release download v1')"
expect deny  $C "gh run download"         "$(bcmd 'gh run download 1')"
expect deny  $C "gh bare"                 "$(bcmd 'gh')"
expect deny  $C "gh pr bare"              "$(bcmd 'gh pr')"
expect deny  $C "gh hostname api"         "$(bcmd 'gh --hostname h.com api x')"
expect deny  $C "gh -R no value"          "$(bcmd 'gh -R')"
expect deny  $C "gh unknown flag first"   "$(bcmd 'gh --version')"
expect deny  $C "gh run view quoted log"  "$(bcmd 'gh run view 1 "--log"')"
expect allow $C "gh pr create body-file"  "$(bcmd "gh pr create --title 't' --body-file .harness/pr.md")"
expect allow $C "gh -R pr view"           "$(bcmd 'gh -R o/r pr view 1')"
expect allow $C "gh --repo= pr view"      "$(bcmd 'gh --repo=o/r pr view 1')"
expect allow $C "gh pr list"              "$(bcmd 'gh pr list')"
expect allow $C "gh pr checks"            "$(bcmd 'gh pr checks 1')"

# --- hardening: git branch list-only (spec 2) -------------------------------
expect deny  $C "git branch create"       "$(bcmd 'git branch tmpx')"
expect deny  $C "git branch -f"           "$(bcmd 'git branch -f tmpx HEAD')"
expect deny  $C "git branch -D x"         "$(bcmd 'git branch -D x')"
expect deny  $C "git branch -m a b"       "$(bcmd 'git branch -m a b')"
expect deny  $C "git branch -u"           "$(bcmd 'git branch -u o/m')"
expect deny  $C "git branch --force"      "$(bcmd 'git branch --force x HEAD')"
expect deny  $C "git branch --set-upstream-to" "$(bcmd 'git branch --set-upstream-to=o/m')"
expect deny  $C "git branch --track"      "$(bcmd 'git branch --track x o/m')"
expect deny  $C "git branch --edit-description" "$(bcmd 'git branch --edit-description')"
expect deny  $C "git branch --format"     "$(bcmd 'git branch --format=%(refname)')"
expect deny  $C "git branch -a positional" "$(bcmd 'git branch -a tmpx')"
expect deny  $C "git branch -l (short list)" "$(bcmd 'git branch -l tmpx')"
expect deny  $C "git branch --list then -f" "$(bcmd 'git branch --list -f x')"
expect allow $C "git branch bare"         "$(bcmd 'git branch')"
expect allow $C "git branch -a"           "$(bcmd 'git branch -a')"
expect allow $C "git branch -r"           "$(bcmd 'git branch -r')"
expect deny  $C "git branch --list quoted" "$(bcmd "git branch --list 'feat*'")"

# --- hardening: ls without recursion (spec 3) --------------------------------
expect deny  $C "ls -R"                   "$(bcmd 'ls -R')"
expect deny  $C "ls -laR docs"            "$(bcmd 'ls -laR docs')"
expect deny  $C "ls -Ra"                  "$(bcmd 'ls -Ra')"
expect deny  $C "ls --recursive .harness" "$(bcmd 'ls --recursive .harness')"
expect deny  $C "ls -l -R docs"           "$(bcmd 'ls -l -R docs')"
expect deny  $C "ls -R .harness"          "$(bcmd 'ls -R .harness')"
expect allow $C "ls bare"                 "$(bcmd 'ls')"
expect allow $C "ls -la"                  "$(bcmd 'ls -la')"
expect allow $C "ls -la docs"             "$(bcmd 'ls -la docs')"

# --- hardening: symlink-resolved paths (spec 4) ------------------------------
SL=$(mktemp -d); SLOUT=$(mktemp -d)
mkdir -p "$SL/src" "$SL/docs" "$SL/.harness/asks"
echo x > "$SL/src/a.sh"; echo x > "$SL/docs/real.md"; echo x > "$SL/.harness/ok.txt"
ln -s ../src/a.sh "$SL/docs/link.md"
ln -s real.md "$SL/docs/ln2.md"
ln -s src/a.sh "$SL/README.md"
ln -s loop2.md "$SL/docs/loop1.md"; ln -s loop1.md "$SL/docs/loop2.md"
ln -s "$SLOUT" "$SL/.harness/outdir"
ln -s ../src "$SL/.harness/srclink"
ln -s ../src "$SL/docs/srcdir"
stool() { jq -n -c --arg t "$1" --argjson i "$2" --arg c "$SL" '{tool_name:$t, tool_input:$i, cwd:$c}'; }
sp() { jq -n -c --arg p "$1" '{file_path:$p, content:"x", path:$p}'; }
expect deny  $C "sym Read docs link->src"     "$(stool Read "$(sp docs/link.md)")"
expect deny  $C "sym Read abs link->src"      "$(stool Read "$(sp "$SL/docs/link.md")")"
expect deny  $C "sym Read README->src"        "$(stool Read "$(sp README.md)")"
expect deny  $C "sym Read loop"               "$(stool Read "$(sp docs/loop1.md)")"
expect deny  $C "sym Read via dir link"       "$(stool Read "$(sp docs/srcdir/a.sh)")"
expect deny  $C "sym Grep link"               "$(stool Grep "$(sp docs/link.md)")"
expect deny  $C "sym Grep dir link"           "$(stool Grep "$(sp docs/srcdir)")"
expect deny  $C "sym Write dir link outside"  "$(stool Write "$(sp .harness/outdir/x.txt)")"
expect deny  $C "sym Write dir link src"      "$(stool Write "$(sp .harness/srclink/x.txt)")"
expect deny  $C "sym Write to file link"      "$(stool Write "$(sp docs/link.md)")"
expect deny  $C "sym bash cat link"           "$(stool Bash '{"command":"cat docs/link.md"}')"
expect allow $C "sym Read real docs md"       "$(stool Read "$(sp docs/real.md)")"
expect allow $C "sym Read link within docs"   "$(stool Read "$(sp docs/ln2.md)")"
expect allow $C "sym Read .harness file"      "$(stool Read "$(sp .harness/ok.txt)")"
expect allow $C "sym Write new docs md"       "$(stool Write "$(sp docs/x.md)")"
expect allow $C "sym Write new deep .harness" "$(stool Write "$(sp .harness/new/deep/x.txt)")"
expect allow $C "sym Write existing docs md"  "$(stool Write "$(sp "$SL/docs/real.md")")"
expect allow $C "sym bash cat real"           "$(stool Bash '{"command":"cat docs/real.md"}')"
expect deny  $C "sym ls dir link"            "$(stool Bash '{"command":"ls docs/srcdir"}')"
expect deny  $C "sym ls dir link slash"      "$(stool Bash '{"command":"ls -la docs/srcdir/"}')"
expect allow $C "sym ls real docs"           "$(stool Bash '{"command":"ls docs"}')"
expect deny  $C "sym Glob path link"         "$(stool Glob '{"pattern":"*","path":"docs/srcdir"}')"
expect deny  $C "sym Glob pattern prefix link" "$(stool Glob '{"pattern":"docs/srcdir/*"}')"
expect deny  $C "sym Glob pattern prefix w/ path" "$(stool Glob '{"pattern":"srcdir/*","path":"docs"}')"
expect allow $C "sym Glob real docs"         "$(stool Glob '{"pattern":"docs/*.md"}')"
expect allow $C "sym Glob real docs path"    "$(stool Glob '{"pattern":"*.md","path":"docs"}')"
rm -rf "$SL" "$SLOUT"

# --- review fixes -------------------------------------------------------------
expect deny  $C "gh quoted -R desync diff"  "$(bcmd 'gh -R "https://github.com/o/r#x pr view" pr diff 1')"
expect deny  $C "gh quoted -R desync checkout" "$(bcmd 'gh -R "https://github.com/o/r#x pr view" pr checkout 1')"
expect deny  $C "gh escaped space desync"   "$(bcmd 'gh -R https://github.com/o/r\ pr\ view pr diff 1')"
expect deny  $C "gh quoted group"           "$(bcmd 'gh "pr" view 1')"
expect deny  $C "gh quoted sub"             "$(bcmd 'gh pr "view" 1')"
expect deny  $C "gh quoted -R value"        "$(bcmd 'gh -R "o/r" pr view 1')"
expect deny  $C "git branch sort dq desync" "$(bcmd 'git branch --sort="refname --list" newbr')"
expect deny  $C "git branch sort bs desync" "$(bcmd 'git branch --sort=refname\ --list newbr')"
expect deny  $C "gh body-file source"       "$(bcmd 'gh pr comment 1 --body-file claude/hooks/conductor-gate.sh')"
expect deny  $C "gh body-file= source"      "$(bcmd 'gh pr comment 1 --body-file=claude/hooks/conductor-gate.sh')"
expect deny  $C "gh -F source"              "$(bcmd 'gh pr comment 1 -F claude/hooks/conductor-gate.sh')"
expect deny  $C "gh -Fsource"               "$(bcmd 'gh pr comment 1 -Fclaude/hooks/conductor-gate.sh')"
expect deny  $C "gh -dF source cluster"     "$(bcmd 'gh pr create -dF src/a.sh')"
expect deny  $C "gh body-file stdin"        "$(bcmd 'gh pr comment 1 --body-file -')"
expect deny  $C "gh body-file dotdot"       "$(bcmd 'gh pr comment 1 --body-file .harness/../src/a')"
expect deny  $C "gh quoted body-file flag"  "$(bcmd 'gh pr comment 1 "--body-file" src/a')"
expect deny  $C "gh quoted body-file value" "$(bcmd 'gh pr comment 1 --body-file ".harness/a b/../../src/x"')"
expect deny  $C "gh body-file missing value" "$(bcmd 'gh pr comment 1 --body-file')"
expect allow $C "gh body-file .harness"     "$(bcmd 'gh pr comment 1 --body-file .harness/pr.md')"
expect allow $C "gh body-file= docs"        "$(bcmd 'gh pr comment 1 --body-file=docs/x.md')"
expect allow $C "gh -F docs"                "$(bcmd 'gh pr comment 1 -F docs/x.md')"
expect deny  $C "gh pr merge -d"            "$(bcmd 'gh pr merge 1 -d')"
expect deny  $C "gh pr merge --delete-branch" "$(bcmd 'gh pr merge 1 --delete-branch')"
expect deny  $C "gh pr merge -sd"           "$(bcmd 'gh pr merge 1 -sd')"
expect allow $C "gh pr merge squash"        "$(bcmd 'gh pr merge 1 --squash')"
expect allow $C "gh title mentions api"     "$(bcmd 'gh pr create --title "fix api timeout" --body-file .harness/pr.md')"
expect deny  $C "gh api repos"              "$(bcmd 'gh api repos/x')"
expect deny  $C "gh -R api x"               "$(bcmd 'gh -R o/r api x')"
expect deny  $C "gh auth status -t"         "$(bcmd 'gh auth status -t')"
expect deny  $C "gh auth status --show-token" "$(bcmd 'gh auth status --show-token')"
expect deny  $C "gh auth status quoted token" "$(bcmd 'gh auth status "--show-token"')"
expect allow $C "Write docs v1..2.md"       "$(tool Write '{"file_path":"docs/v1..2.md","content":"x"}')"
expect deny  $C "Write docs/../x.md"        "$(tool Write '{"file_path":"docs/../x.md","content":"x"}')"


# --- round 3 -------------------------------------------------------------------
expect deny  $C "\$ git log IFS brace"      "$(bcmd 'git log -1${=IFS}-p')"
expect deny  $C "\$ git log IFS"            "$(bcmd 'git log -1$IFS-p')"
expect deny  $C "\$ git branch IFS"         "$(bcmd 'git branch --sort=refname${IFS}newbr')"
expect deny  $C "\$ gh body IFS -F"         "$(bcmd 'gh pr comment 1 --body x${=IFS}-F${=IFS}install.sh')"
expect deny  $C "\$ gh merge IFS -d"        "$(bcmd 'gh pr merge 1 --squash${=IFS}-d')"
expect deny  $C "\$ gh dq var"              "$(bcmd 'gh pr view "$X"')"
expect deny  $C "\$ harness dq var"         "$(bcmd 'harness ask analyst "cost $5"')"
expect deny  $C "\$ after sq in dq"         "$(bcmd "harness ask a \"it's \$X\"")"
expect allow $C "\$ harness single-quoted"  "$(bcmd "harness ask analyst 'cost is \$5 and \$(x) here'")"
expect allow $C "git log oneline"           "$(bcmd 'git log --oneline -5')"
expect deny  $C "gh merge --delete-branch=" "$(bcmd 'gh pr merge 1 --delete-branch=true')"
expect deny  $C "gh show-token=true"        "$(bcmd 'gh auth status --show-token=true')"
expect deny  $C "gh recover source"         "$(bcmd 'gh pr create --recover src/a.sh')"
expect deny  $C "gh recover= source"        "$(bcmd 'gh issue create --recover=src/a.sh')"
expect deny  $C "gh quoted recover"         "$(bcmd 'gh pr create "--recover" src/a.sh')"
expect allow $C "gh recover .harness"       "$(bcmd 'gh pr create --recover .harness/r.json')"


# --- round 4: character allowlist for unquoted text -------------------------------
expect deny  $C "al git log brace"          "$(bcmd 'git log {-p,-1}')"
expect deny  $C "al gh merge brace"         "$(bcmd 'gh pr merge 1 --squash {--delete-branch,}')"
expect deny  $C "al gh auth brace"          "$(bcmd 'gh auth status {--show-token,-a}')"
expect deny  $C "al gh run brace"           "$(bcmd 'gh run view 1 {--log,}')"
expect deny  $C "al gh issue brace"         "$(bcmd 'gh issue create --title x {--body-file=install.sh,}')"
expect deny  $C "al zsh glob qualifier"     "$(bcmd "harness ask x *(e:'cat install.sh':)")"
expect deny  $C "al zsh glob qualifier 2"   "$(bcmd "git status *(e{'cat install.sh'})")"
expect deny  $C "al =(cmd)"                 "$(bcmd 'gh pr view 1 =(cat install.sh)')"
expect deny  $C "al =cmd word"              "$(bcmd 'harness ask x =ls')"
expect deny  $C "al git log -'p'"           "$(bcmd "git log -'p'")"
expect deny  $C "al gh run view dq log"     "$(bcmd 'gh run view 1 "--log"')"
expect deny  $C "al ls tilde"               "$(bcmd 'ls ~')"
expect deny  $C "al git branch glob"        "$(bcmd 'git branch --list feat*')"
expect deny  $C "al dq backtick"            "$(bcmd 'harness ask x "a `b`"')"
expect deny  $C "al dq bang"                "$(bcmd 'harness ask x "hi!"')"
expect deny  $C "al dq backslash"           "$(bcmd 'harness ask x "a\\nb"')"
expect deny  $C "al unquoted bang"          "$(bcmd 'harness ask x hi!')"
expect deny  $C "al unquoted caret"         "$(bcmd 'harness ask x a^b')"
expect allow $C "al unquoted backslash space"     "$(bcmd 'harness ask x a\ b')"
expect allow $C "al harness read task"      "$(bcmd "harness ask implementer 'Read .harness/task-implementer.md and do it.'")"
expect allow $C "al harness sq specials"    "$(bcmd "harness ask x 'a {b} (c) *d* \$e'")"
expect allow $C "al gh create paren title"  "$(bcmd "gh pr create --title 'fix: x (y)' --body-file .harness/pr.md")"
expect allow $C "al git diff range"         "$(bcmd 'git diff --stat main...HEAD')"
expect deny  $C "al two segs denied"               "$(bcmd 'harness status; herdr agent get reviewer')"
expect deny  $C "al 2>&1 denied"                   "$(bcmd 'harness report implementer 2>&1')"
expect allow $C "al dq plain"               "$(bcmd 'harness ask x "plain words, fine (really) {ok}"')"


# --- round 5 --------------------------------------------------------------------
expect allow $C "r5 escaped apostrophe idiom" "$(bcmd "harness ask analyst 'please review; don'\\''t fix'")"
expect allow $C "r5 backslash dquote"         "$(bcmd 'harness ask x a\"b')"
expect allow $C "r5 backslash space"          "$(bcmd 'harness ask x a\ b')"
expect deny  $C "r5 backslash letter"         "$(bcmd 'harness ask x a\nb')"
expect deny  $C "r5 backslash dollar"         "$(bcmd 'harness ask x a\$b')"
expect deny  $C "r5 trailing backslash"       "$(bcmd 'harness ask x a\')"
expect deny  $C "r5 empty sq then ="          "$(bcmd "harness ask x ''=ls")"
expect deny  $C "r5 empty dq then ="          "$(bcmd 'harness ask x ""=ls')"
expect deny  $C "r5 empty quotes then ="      "$(bcmd "harness ask x ''\"\"=ls")"
expect deny  $C "r5 empty sq then ~"          "$(bcmd "harness ask x ''~")"
expect allow $C "r5 quoted word then ="       "$(bcmd "harness ask x 'a'=b")"
expect allow $C "r5 mid-word ="               "$(bcmd 'harness ask x a=b')"
expect allow $C "r5 quoted tilde"             "$(bcmd "git log -1 'HEAD~1'")"

# --- other tools pass through ----------------------------------------------
expect allow $C "Skill"                   "$(tool Skill '{"skill":"x"}')"
expect allow $C "TodoWrite"               "$(tool TodoWrite '{"todos":[]}')"
expect allow $C "MCP tool"                "$(tool mcp__context7__query-docs '{"q":"x"}')"

# --- robustness ------------------------------------------------------------
# unparseable input fails closed (decision 0005)
expect deny  $C "garbage input"           'not json at all'
expect deny  $C "missing tool_name"       '{"tool_input":{}}'
expect deny  $C "empty input"             ''
expect deny  $W "worker garbage input"    'not json at all'

# --- the gate acts only in a harness checkout (decision 0010) -----------------
# gate_at DIR ENVSPEC JSON -> allow|deny; runs the gate with cwd DIR, ENVSPEC passed to env
gate_at() {
  local out
  out=$(printf '%s' "$3" | (cd "$1" && env $2 /bin/bash "$GATE" 2>/dev/null))
  if [ -z "$out" ]; then echo allow; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}
gchk() {  # WANT DIR ENVSPEC JSON LABEL
  local got
  got=$(gate_at "$2" "$3" "$4")
  if [ "$got" = "$1" ]; then report ok "$5" "$1" "$got" "$4"; else report bad "$5" "$1" "$got" "$4"; fi
}
EDIT_SRC="$(tool Edit '{"file_path":"src/a.ts","old_string":"a","new_string":"b"}')"
CHK=$GATE_HOME/chk
PLAIN=$GATE_HOME/plain
# 1-3: inside a checkout HERDR_ENV does not matter
gchk deny  "$CHK" "-u HERDR_ENV HARNESS_ROLE=conductor" "$EDIT_SRC"          "chk, no HERDR_ENV: Edit src"
gchk deny  "$CHK" "HERDR_ENV=0 HARNESS_ROLE=conductor"  "$(bcmd 'npm test')" "chk, HERDR_ENV=0: Bash"
gchk deny  "$CHK" "HARNESS_ROLE=conductor" 'not json at all'                 "chk: garbage"
# 4-6: a plain repo is never gated
gchk allow "$PLAIN" "HARNESS_ROLE=conductor" "$EDIT_SRC"                                        "plain: Edit src"
gchk allow "$PLAIN" "HARNESS_ROLE=conductor" "$(tool Read '{"file_path":"/repo/src/a.ts"}')"    "plain: Read src"
gchk allow "$PLAIN" "HARNESS_ROLE=conductor" "$(bcmd 'npm test')"                               "plain: Bash"
gchk allow "$PLAIN" "HARNESS_ROLE=conductor" "$(tool Agent '{"prompt":"x"}')"                   "plain: Agent"
gchk allow "$PLAIN" "HARNESS_ROLE=conductor" 'not json at all'                                  "plain: garbage"
got=$(nojq conductor "$(bcmd 'ls')" "$PLAIN")
if [ -z "$got" ]; then report ok "plain, no jq: allow" allow allow x; else report bad "plain, no jq: allow" allow "$got" x; fi
# 7: chk without jq stays denied (see the nojq cases above)
# 8: .cwd wins over $PWD
gchk deny  "$PLAIN" "HARNESS_ROLE=conductor" "$(jq -n -c --arg c "$CHK" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"src/a.ts"}}')" "cwd=chk while PWD=plain: deny"
gchk allow "$CHK"   "HARNESS_ROLE=conductor" "$(jq -n -c --arg c "$PLAIN" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"src/a.ts"}}')" "cwd=plain while PWD=chk: allow"
# 9: a subdir of a git checkout resolves to the root's marker
mkdir -p "$CHK/.git" "$CHK/sub/deep"
gchk deny  "$CHK" "HARNESS_ROLE=conductor" "$(jq -n -c --arg c "$CHK/sub/deep" '{tool_name:"Edit",cwd:$c,tool_input:{file_path:"src/a.ts"}}')" "cwd=chk/sub/deep: deny"
# 10: a stray .harness/config.json without asks/ gates nothing
mkdir -p "$PLAIN/.harness" && echo '{}' > "$PLAIN/.harness/config.json"
gchk allow "$PLAIN" "HARNESS_ROLE=conductor" "$EDIT_SRC" "stray config.json: allow"
# 11: an asks/ above a .git boundary does not count
mkdir -p "$GATE_HOME/up/.harness/asks" "$GATE_HOME/up/repo/.git"
gchk allow "$GATE_HOME/up/repo" "HARNESS_ROLE=conductor" "$EDIT_SRC" "asks above .git: allow"
# 12: daemon case (conductor agent_type with an inherited worker env) stays gated
gchk deny  "$CHK" "HARNESS_ROLE=worker HERDR_ENV=1" "$(jq -n -c '{tool_name:"Edit",agent_type:"conductor",tool_input:{file_path:"src/a.ts"}}')" "chk, daemon env + agent_type conductor: deny"
gchk allow "$CHK" "HARNESS_ROLE=conductor" "$(jq -n -c '{tool_name:"Edit",agent_type:"analyst",tool_input:{file_path:"src/a.ts"}}')" "chk, agent_type analyst: allow"
# 13: harness_root is byte-identical in the gate, route and resume hooks
fn_body() { awk -v n="$2" 'index($0, n "() {") == 1 {p=1} p{print} p&&/^}/{exit}' "$1"; }
G1=$(fn_body "$GATE" harness_root); G2=$(fn_body "$HERE/../claude/hooks/conductor-route.sh" harness_root); G3=$(fn_body "$HERE/../claude/hooks/conductor-resume.sh" harness_root)
if [ -n "$G1" ] && [ "$G1" = "$G2" ] && [ "$G1" = "$G3" ]; then report ok "harness_root identical in 3 hooks" same same x
else report bad "harness_root identical in 3 hooks" same differs x; fi
# 14: the gate's checkout verdict agrees with harness-verify enter_root
ENTER=$(fn_body "$HERE/../bin/harness-verify" enter_root)
agree() {  # LABEL DIR WANT(gated|free) — enter_root must land on the marker iff the gate is gated
  local d=$2 gate ver
  gate=$(gate_at "$d" "HARNESS_ROLE=conductor" "$EDIT_SRC")
  [ "$gate" = deny ] && gate=gated || gate=free
  ver=$(cd "$d" && /bin/bash -c "$ENTER"'; IS_GIT=0; ROOT=$PWD; enter_root; [ -d "$ROOT/.harness/asks" ] && echo gated || echo free' 2>/dev/null)
  if [ "$gate" = "$3" ] && [ "$ver" = "$3" ]; then report ok "agree: $1" "$3" "$gate/$ver" x
  else report bad "agree: $1" "$3" "gate=$gate verify=$ver" x; fi
}
AG=$GATE_HOME/agree
mkdir -p "$AG/g1/.git" "$AG/g1/.harness/asks" "$AG/g1/sub" "$AG/g2/.git" "$AG/g2/sub" "$AG/ng/.harness/asks" "$AG/ng2" "$AG/wt/sub"
echo "gitdir: /nowhere" > "$AG/wt/.git"; mkdir -p "$AG/wt/.harness/asks"
(cd "$AG/g1" && git init -q . 2>/dev/null); (cd "$AG/g2" && git init -q . 2>/dev/null)
agree "git root"            "$AG/g1"     gated
agree "git subdir"          "$AG/g1/sub" gated
agree "git, no marker"      "$AG/g2/sub" free
agree "no git, marker here" "$AG/ng"     gated
agree "no git, no marker"   "$AG/ng2"    free
expect_reason "Conductor gate could not parse" "reason: unparseable" 'not json at all'

# --- deny output shape -------------------------------------------------------
expect_reason "Conductor cannot edit"   "reason: write" "$(tool Write '{"file_path":"src/a.ts","content":"x"}')"
expect_reason "Conductor does not read" "reason: read"  "$(tool Read '{"file_path":"src/a.ts"}')"
expect_reason "Conductor shell"         "reason: bash"  "$(bcmd 'npm test')"
# every deny reason names the skill to use, not a raw `harness ask`
expect_reason_has() {
  local got
  got=$(run_gate conductor "$3" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
  case "$got" in
    *"$1"*) report ok "$2" "*$1*" "$got" "$3" ;;
    *)      report bad "$2" "*$1*" "$got" "$3" ;;
  esac
}
expect_reason_has "/implement" "skill named: write" "$(tool Write '{"file_path":"src/a.ts","content":"x"}')"
expect_reason_has "/analyze"   "skill named: read"  "$(tool Read '{"file_path":"src/a.ts"}')"
expect_reason_has "/implement" "skill named: bash"  "$(bcmd 'npm test')"
# ...and none of them mentions a raw `harness ask`
expect_reason_lacks() {
  local got
  got=$(run_gate conductor "$3" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
  case "$got" in
    *"$1"*) report bad "$2" "no *$1*" "$got" "$3" ;;
    *)      report ok  "$2" "no *$1*" "$got" "$3" ;;
  esac
}
expect_reason_lacks "harness ask" "no raw ask: write" "$(tool Write '{"file_path":"src/a.ts","content":"x"}')"
expect_reason_lacks "harness ask" "no raw ask: read"  "$(tool Read '{"file_path":"src/a.ts"}')"
expect_reason_lacks "harness ask" "no raw ask: bash"  "$(bcmd 'npm test')"
expect_event  "event name"                              "$(bcmd 'npm test')"

# --- regression list: tests/gate-denied.list (deny probes must stay denied) ---
while IFS="$(printf '\t')" read -r want cmd; do
  case "$want" in deny|allow) ;; *) continue ;; esac
  expect "$want" $C "list: $cmd" "$(bcmd "$cmd")"
done < "$HERE/gate-denied.list"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
