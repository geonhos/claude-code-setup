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
