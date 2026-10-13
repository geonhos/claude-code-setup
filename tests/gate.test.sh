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
