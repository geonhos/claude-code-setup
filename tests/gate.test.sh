#!/bin/bash
# Tests for claude/hooks/conductor-gate.sh. Run: /bin/bash tests/gate.test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GATE="$HERE/../claude/hooks/conductor-gate.sh"
CWD=/repo
pass=0
fail=0

# run_gate ROLE JSON -> prints the gate's stdout; returns the gate's exit code
run_gate() {
  printf '%s' "$2" | HARNESS_ROLE="$1" /bin/bash "$GATE" 2>/dev/null
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
expect deny  $C "NotebookEdit"            "$(tool NotebookEdit '{"notebook_path":"/repo/nb.ipynb","new_source":"x"}')"

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
expect allow $C "Grep .harness"           "$(tool Grep '{"pattern":"foo","path":"/repo/.harness"}')"
expect deny  $C "Glob no path"            "$(tool Glob '{"pattern":"**/*.ts"}')"
expect deny  $C "Glob src"                "$(tool Glob '{"pattern":"*.ts","path":"/repo/src"}')"
expect allow $C "Glob docs"               "$(tool Glob '{"pattern":"*.md","path":"docs/superpowers"}')"
expect deny  $C "Glob pattern dotdot"     "$(tool Glob '{"pattern":"../src/**","path":"docs"}')"
expect deny  $C "Glob pattern abs"        "$(tool Glob '{"pattern":"/repo/src/**","path":"docs"}')"
expect deny  $C "Glob pattern tilde"      "$(tool Glob '{"pattern":"~/x/**","path":"docs"}')"
expect allow $C "Glob docs pattern no path"     "$(tool Glob '{"pattern":"docs/**/*.md"}')"
expect allow $C "Glob .harness pattern no path" "$(tool Glob '{"pattern":".harness/reports/*.md"}')"
expect deny  $C "Glob src pattern no path"      "$(tool Glob '{"pattern":"src/**"}')"

# --- Agent / Workflow --------------------------------------------------------
expect deny  $C "Agent"                   "$(tool Agent    '{"prompt":"x","description":"y"}')"
expect deny  $C "Workflow"                "$(tool Workflow '{"script":"x"}')"
expect deny  $C "Monitor"                 "$(tool Monitor '{"command":"tail -f src/a.log"}')"

# --- Bash: allowlist ---------------------------------------------------------
expect allow $C "bash harness ask"        "$(bcmd 'harness ask analyst "what is this"')"
expect allow $C "bash harness status"     "$(bcmd 'harness status')"
expect allow $C "bash herdr"              "$(bcmd 'herdr agent list')"
expect allow $C "bash gh"                 "$(bcmd 'gh pr view 12')"
expect deny  $C "bash npm test"           "$(bcmd 'npm test')"
expect deny  $C "bash sed -i"             "$(bcmd 'sed -i s/a/b/ src/a.ts')"
expect deny  $C "bash cd"                 "$(bcmd 'cd src && ls')"
expect deny  $C "bash empty"              "$(tool Bash '{}')"   # missing command field: bcmd cannot build this
expect deny  $C "bash only separator"     "$(bcmd ';')"
expect allow $C "bash herdr agent get"    "$(bcmd 'herdr agent get analyst')"
expect allow $C "bash herdr pane layout"  "$(bcmd 'herdr pane layout --pane w1:p1')"
expect allow $C "bash herdr status"       "$(bcmd 'herdr status')"
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
expect allow $C "bash compound ok"        "$(bcmd 'git status && harness status')"
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
expect allow $C "bash dq escaped \$("    "$(bcmd 'harness ask analyst "cost \$(x)"')"

# --- Bash: redirects ---------------------------------------------------------
expect deny  $C "bash redirect"           "$(bcmd 'git status > out.txt')"
expect deny  $C "bash here-string"        "$(bcmd 'jq . <<< x')"
expect allow $C "bash 2>&1 end"           "$(bcmd 'herdr agent get analyst 2>&1')"
expect allow $C "bash 2>&1 pipe"          "$(bcmd 'herdr agent get analyst 2>&1 | jq .result')"
expect deny  $C "bash 2>&1 glued file"    "$(bcmd 'cat .harness/x2>&1src')"
expect deny  $C "bash 2>&1 glued tail"    "$(bcmd 'harness status 2>&1x')"

# --- Bash: jq ----------------------------------------------------------------
expect allow $C "bash jq piped"           "$(bcmd 'herdr agent list | jq .result')"
expect allow $C "bash jq quoted filter"   "$(bcmd "herdr agent list | jq -r '.result.agents[].pane_id'")"
expect deny  $C "bash jq first"           "$(bcmd 'jq . src/secret.json')"
expect deny  $C "bash jq piped file"      "$(bcmd 'herdr agent list | jq -r . src/a.ts')"
expect deny  $C "bash jq piped qfile"     "$(bcmd 'herdr agent list | jq -r . "src/a.ts"')"
expect deny  $C "bash jq quoted slash"    "$(bcmd 'herdr x | jq "./a"')"
expect deny  $C "bash jq glob"            "$(bcmd 'herdr x | jq *')"
expect deny  $C "bash jq -f quoted path"  "$(bcmd 'herdr x | jq -f "src/a.ts"')"
expect deny  $C "bash jq -f"              "$(bcmd 'herdr x | jq -f a.jq')"
expect deny  $C "bash jq -rf"             "$(bcmd 'herdr x | jq -rf a.jq')"
expect deny  $C "bash jq -L"              "$(bcmd 'herdr x | jq -L lib .')"
expect deny  $C "bash jq --rawfile path"  "$(bcmd 'herdr x | jq --rawfile a src/a.ts .')"
expect deny  $C "bash jq --rawfile"       "$(bcmd 'herdr x | jq --rawfile a a.ts .')"
expect deny  $C "bash jq --slurpfile"     "$(bcmd 'herdr x | jq --slurpfile a a.json')"
expect deny  $C "bash jq --args"          "$(bcmd 'herdr x | jq --args . a')"
expect deny  $C "bash jq env"             "$(bcmd 'herdr x | jq -n env')"
expect deny  $C "bash jq \$ENV"           "$(bcmd "herdr x | jq -n '\$ENV'")"

# --- Bash: git ---------------------------------------------------------------
expect allow $C "bash git status"         "$(bcmd 'git status')"
expect allow $C "bash git status short"   "$(bcmd 'git status --short')"
expect allow $C "bash git log"            "$(bcmd 'git log --oneline -5')"
expect allow $C "bash git log --stat"     "$(bcmd 'git log --stat')"
expect allow $C "bash git diff --stat"    "$(bcmd 'git diff --stat main...HEAD')"
expect allow $C "bash git branch"         "$(bcmd 'git branch --show-current')"
expect allow $C "bash git show --stat"    "$(bcmd 'git show --stat HEAD')"
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

# --- MCP filesystem ---------------------------------------------------------
expect deny  $C "mcp read src"            "$(tool mcp__filesystem__read_text_file '{"path":"/repo/src/a.ts"}')"
expect allow $C "mcp read docs"           "$(tool mcp__filesystem__read_text_file '{"path":"/repo/docs/a.md"}')"
expect deny  $C "mcp read_file src"       "$(tool mcp__filesystem__read_file '{"path":"src/a.ts"}')"
expect deny  $C "mcp search src"          "$(tool mcp__filesystem__search_files '{"path":"/repo","pattern":"x"}')"
expect deny  $C "mcp tree root"           "$(tool mcp__filesystem__directory_tree '{"path":"/repo"}')"
expect allow $C "mcp list docs"           "$(tool mcp__filesystem__list_directory '{"path":"docs"}')"
expect deny  $C "mcp read multiple src"   "$(tool mcp__filesystem__read_multiple_files '{"paths":["src/a.ts"]}')"
expect allow $C "mcp read multiple docs"  "$(tool mcp__filesystem__read_multiple_files '{"paths":["docs/a.md"]}')"
expect deny  $C "mcp read multiple mixed" "$(tool mcp__filesystem__read_multiple_files '{"paths":["docs/a.md","src/a.ts"]}')"
expect deny  $C "mcp read multiple empty" "$(tool mcp__filesystem__read_multiple_files '{"paths":[]}')"
expect deny  $C "mcp write src"           "$(tool mcp__filesystem__write_file '{"path":"src/x","content":"x"}')"
expect allow $C "mcp write .harness"      "$(tool mcp__filesystem__write_file '{"path":".harness/x","content":"x"}')"
expect deny  $C "mcp edit src"            "$(tool mcp__filesystem__edit_file '{"path":"src/a.ts","edits":[]}')"
expect deny  $C "mcp mkdir src"           "$(tool mcp__filesystem__create_directory '{"path":"src/new"}')"
expect deny  $C "mcp move into src"       "$(tool mcp__filesystem__move_file '{"source":".harness/x","destination":"src/x"}')"
expect deny  $C "mcp move out of src"     "$(tool mcp__filesystem__move_file '{"source":"src/x","destination":".harness/x"}')"
expect allow $C "mcp move in .harness"    "$(tool mcp__filesystem__move_file '{"source":".harness/x","destination":".harness/y"}')"

# --- hardening: jq missing fails closed (spec 5) ----------------------------
JQBIN=$(mktemp -d)
for b in cat awk sed tr grep; do ln -s "$(command -v $b)" "$JQBIN/$b"; done
nojq() { printf '%s' "$2" | PATH="$JQBIN" HARNESS_ROLE="$1" /bin/bash "$GATE" 2>/dev/null; }
got=$(nojq conductor "$(bcmd 'ls')")
if [ "$got" = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Conductor gate requires jq. Install jq, or run a worker session."}}' ]
then report ok "no jq: conductor denied" deny deny x; else report bad "no jq: conductor denied" deny "$got" "$(bcmd 'ls')"; fi
got=$(nojq worker "$(bcmd 'rm -rf x')")
if [ -z "$got" ]; then report ok "no jq: worker allowed" allow allow x; else report bad "no jq: worker allowed" allow "$got" "$(bcmd 'rm -rf x')"; fi
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
expect allow $C "gh run view"             "$(bcmd 'gh run view 1')"
expect allow $C "gh run list"             "$(bcmd 'gh run list')"
expect allow $C "gh issue view"           "$(bcmd 'gh issue view 3')"
expect allow $C "gh auth status"          "$(bcmd 'gh auth status')"
expect allow $C "gh repo view"            "$(bcmd 'gh repo view')"
expect allow $C "gh pr checks"            "$(bcmd 'gh pr checks 1')"
expect allow $C "gh browse"               "$(bcmd 'gh browse')"

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
expect allow $C "git branch -vv"          "$(bcmd 'git branch -vv')"
expect allow $C "git branch --all"        "$(bcmd 'git branch --all')"
expect allow $C "git branch --remotes"    "$(bcmd 'git branch --remotes')"
expect allow $C "git branch --list pat"   "$(bcmd 'git branch --list feat')"
expect deny  $C "git branch --list quoted" "$(bcmd "git branch --list 'feat*'")"
expect allow $C "git branch --contains"   "$(bcmd 'git branch --contains HEAD')"
expect allow $C "git branch --merged"     "$(bcmd 'git branch --merged main')"
expect allow $C "git branch --no-merged"  "$(bcmd 'git branch --no-merged')"
expect allow $C "git branch --points-at"  "$(bcmd 'git branch --points-at HEAD')"
expect allow $C "git branch --sort"       "$(bcmd 'git branch --sort=-committerdate')"
expect allow $C "git branch -a --contains" "$(bcmd 'git branch -a --contains HEAD')"

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
mkdir -p "$SL/src" "$SL/docs" "$SL/.harness"
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
expect deny  $C "sym mcp read link"           "$(stool mcp__filesystem__read_text_file "$(sp docs/link.md)")"
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
expect allow $C "gh auth status -h"         "$(bcmd 'gh auth status -h github.com')"
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

# --- other tools pass through ----------------------------------------------
expect allow $C "Skill"                   "$(tool Skill '{"skill":"x"}')"
expect allow $C "TodoWrite"               "$(tool TodoWrite '{"todos":[]}')"
expect allow $C "MCP tool"                "$(tool mcp__context7__query-docs '{"q":"x"}')"

# --- robustness ------------------------------------------------------------
expect allow $C "garbage input"           'not json at all'
expect allow $C "missing tool_name"       '{"tool_input":{}}'

# --- deny output shape -------------------------------------------------------
expect_reason "Conductor cannot edit"   "reason: write" "$(tool Write '{"file_path":"src/a.ts","content":"x"}')"
expect_reason "Conductor does not read" "reason: read"  "$(tool Read '{"file_path":"src/a.ts"}')"
expect_reason "Native subagents"        "reason: agent" "$(tool Agent '{"prompt":"x"}')"
expect_reason "Conductor shell"         "reason: bash"  "$(bcmd 'npm test')"
expect_event  "event name"                              "$(bcmd 'npm test')"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
