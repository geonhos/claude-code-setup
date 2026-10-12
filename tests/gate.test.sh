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

# --- review fixes ----------------------------------------------------------
# 1. single & is a command separator
expect deny  $C "bash single &"           "$(tool Bash '{"command":"git status & npm test"}')"
expect deny  $C "bash single & nospace"   "$(tool Bash '{"command":"harness status &rm -rf src"}')"
# 2. .. escapes in bash args
expect deny  $C "bash cat dotdot"         "$(tool Bash '{"command":"cat .harness/../src/a.ts"}')"
expect deny  $C "bash ls dotdot"          "$(tool Bash '{"command":"ls docs/../src"}')"
expect deny  $C "bash ls .harnessx"       "$(tool Bash '{"command":"ls .harnessx"}')"
expect allow $C "bash ls .harness/reports" "$(tool Bash '{"command":"ls .harness/reports"}')"
expect allow $C "bash ls docs bare"       "$(tool Bash '{"command":"ls docs"}')"
# 3. jq only on piped input, no file args
expect allow $C "bash jq piped"           "$(tool Bash '{"command":"herdr agent list | jq .result"}')"
expect allow $C "bash jq piped quoted"    "$(tool Bash '{"command":"herdr agent list | jq -r '"'"'.result.agents[].pane_id'"'"'"}')"
expect deny  $C "bash jq first"           "$(tool Bash '{"command":"jq . src/secret.json"}')"
expect deny  $C "bash jq piped file"      "$(tool Bash '{"command":"herdr agent list | jq -r . src/a.ts"}')"
expect deny  $C "bash jq piped qfile"     "$(tool Bash '{"command":"herdr agent list | jq -r . \"src/a.ts\""}')"
# 4. git write escapes
expect deny  $C "bash git log --output"   "$(tool Bash '{"command":"git log --output=src/a.ts"}')"
expect deny  $C "bash git diff --output"  "$(tool Bash '{"command":"git diff --stat --output=x"}')"
expect deny  $C "bash git branch -D"      "$(tool Bash '{"command":"git branch -D main"}')"
expect deny  $C "bash git branch -m"      "$(tool Bash '{"command":"git branch -m x"}')"
expect allow $C "bash git branch show"    "$(tool Bash '{"command":"git branch --show-current"}')"
expect allow $C "bash git log -5"         "$(tool Bash '{"command":"git log --oneline -5"}')"
# 5. quoted args are masked before splitting
expect allow $C "bash quoted ;"           "$(tool Bash '{"command":"harness ask analyst \"fix a; b\""}')"
expect allow $C "bash quoted >"           "$(tool Bash '{"command":"harness ask analyst \"is a > b?\""}')"
expect allow $C "bash squoted &&"         "$(tool Bash '{"command":"harness ask implementer '"'"'run x && y'"'"'"}')"
expect deny  $C "bash quoted subshell"    "$(tool Bash '{"command":"harness ask analyst \"$(cat src/a.ts)\""}')"
expect deny  $C "bash quoted cat dotdot"  "$(tool Bash '{"command":"cat \".harness/../src/a.ts\""}')"
expect deny  $C "bash quote confusion"    "$(tool Bash '{"command":"harness '"'"'a\"'"'"' ; rm -rf src ; echo '"'"'\"'"'"'"}')"
expect deny  $C "bash escaped quotes"     "$(tool Bash '{"command":"harness \\\" ; rm -rf src ; echo \\\""}')"
expect deny  $C "bash unterminated quote" "$(tool Bash '{"command":"harness \"abc"}')"
expect deny  $C "bash newline separator"  "$(tool Bash '{"command":"git status\nrm -rf src"}')"
# 6. cwd trailing slash, ~ paths, Glob pattern ..
expect allow $C "cwd trailing slash"      "$(jq -n -c '{tool_name:"Write",tool_input:{file_path:"/repo/docs/a.md",content:"x"},cwd:"/repo/"}')"
expect deny  $C "Read tilde"              "$(tool Read '{"file_path":"~/secret.md"}')"
expect deny  $C "Glob pattern dotdot"     "$(tool Glob '{"pattern":"../src/**","path":"docs"}')"

# --- review round 2 --------------------------------------------------------
# bcmd COMMAND -> Bash hook payload with COMMAND as tool_input.command
bcmd() { tool Bash "$(printf '%s' "$1" | jq -Rs '{command:.}')"; }
TAB=$(printf '\t')
# A. raw-command checks
expect deny  $C "bash ansi-c quote"       "$(bcmd "harness \$'\\'' ; rm -rf src #'")"
expect deny  $C "bash locale quote"       "$(bcmd 'harness $"x" ; rm -rf src')"
expect deny  $C "bash tab separator"      "$(bcmd "cat .harness/x${TAB}src/a.ts")"
expect deny  $C "bash proc subst <("     "$(bcmd 'cat <(ls src)')"
expect deny  $C "bash proc subst >("     "$(bcmd 'harness status >(cat)')"
expect deny  $C "bash here-string"        "$(bcmd 'jq . <<< x')"
# B. file-reading segments: no quotes / expansions / globs
expect deny  $C "bash cat dq dotdot"      "$(bcmd 'cat .harness/"../src/a.ts"')"
expect deny  $C "bash cat sq dotdot"      "$(bcmd "cat .harness/'..'/src/a.ts")"
expect deny  $C "bash ls dq dotdot"       "$(bcmd 'ls docs/".."/src')"
expect deny  $C "bash cat brace"          "$(bcmd 'cat .harness/{,../src/a.ts}')"
expect deny  $C "bash cat param exp"      "$(bcmd 'cat .harness/${X:-../src/a.ts}')"
expect deny  $C "bash cat ?"              "$(bcmd 'cat .harness/.?/src/a.ts')"
expect deny  $C "bash cat *"              "$(bcmd 'cat .harness/*')"
expect deny  $C "bash cat \$HOME"         "$(bcmd 'cat .harness/$HOME')"
expect deny  $C "bash cat backslash"      "$(bcmd 'cat .harness/\.\./src/a.ts')"
expect allow $C "bash cat report 2"       "$(bcmd 'cat .harness/reports/analyst.md')"
expect allow $C "bash ls -la docs 2"      "$(bcmd 'ls -la docs/superpowers')"
# C. jq file-reading flags; quoted filter still fine
expect deny  $C "bash jq -f quoted path"  "$(bcmd 'herdr x | jq -f "src/a.ts"')"
expect deny  $C "bash jq --rawfile path"  "$(bcmd 'herdr x | jq --rawfile a src/a.ts .')"
expect deny  $C "bash jq -f"              "$(bcmd 'herdr x | jq -f a.jq')"
expect deny  $C "bash jq -rf"             "$(bcmd 'herdr x | jq -rf a.jq')"
expect deny  $C "bash jq --rawfile"       "$(bcmd 'herdr x | jq --rawfile a a.ts .')"
expect deny  $C "bash jq --slurpfile"     "$(bcmd 'herdr x | jq --slurpfile a a.json')"
expect deny  $C "bash jq -L"              "$(bcmd 'herdr x | jq -L lib .')"
expect deny  $C "bash jq --args"          "$(bcmd 'herdr x | jq --args . a')"
expect deny  $C "bash jq quoted slash"    "$(bcmd 'herdr x | jq "./a"')"
expect deny  $C "bash jq glob"            "$(bcmd 'herdr x | jq *')"
expect allow $C "bash jq quoted filter"   "$(bcmd "herdr agent list | jq -r '.result.agents[].pane_id'")"
# D. git
expect deny  $C "bash git show path"      "$(bcmd 'git show --stat HEAD:src/a.ts')"
expect deny  $C "bash git show qpath"     "$(bcmd 'git show --stat "HEAD:src/a.ts"')"
expect deny  $C "bash git log -p"         "$(bcmd 'git log -p')"
expect deny  $C "bash git log --patch"    "$(bcmd 'git log --patch')"
expect deny  $C "bash git diff --stat -p" "$(bcmd 'git diff --stat -p')"
expect deny  $C "bash git branch -Df"     "$(bcmd 'git branch -Df main')"
expect deny  $C "bash git branch qD"      "$(bcmd 'git branch "-D" main')"
expect deny  $C "bash git branch --delete" "$(bcmd 'git branch --delete main')"
expect deny  $C "bash git branch -c"      "$(bcmd 'git branch -c x y')"
expect deny  $C "bash git branch --move"  "$(bcmd 'git branch --move x y')"
expect allow $C "bash git show --stat 2"  "$(bcmd 'git show --stat HEAD')"
expect allow $C "bash git log -5 2"       "$(bcmd 'git log --oneline -5')"
expect allow $C "bash git diff range 2"   "$(bcmd 'git diff --stat main...HEAD')"
expect allow $C "bash git status short"   "$(bcmd 'git status --short')"
# E. Glob absolute / home pattern
expect deny  $C "Glob pattern abs"        "$(tool Glob '{"pattern":"/repo/src/**","path":"docs"}')"
expect deny  $C "Glob pattern tilde"      "$(tool Glob '{"pattern":"~/x/**","path":"docs"}')"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
