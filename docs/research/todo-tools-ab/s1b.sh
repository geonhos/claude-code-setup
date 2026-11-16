#!/bin/bash
cond=$1; model=$2
d=$(mktemp -d /tmp/tta/wb.XXXX); cd $d; git init -q .; mkdir -p tests
case $cond in
 todo) export CLAUDE_CODE_ENABLE_TODO_TOOLS=1;;
 todowrite) export CLAUDE_CODE_ENABLE_TODO_TOOLS=1 CLAUDE_CODE_ENABLE_TASKS=0;;
esac
claude -p --model $model --output-format stream-json --verbose --permission-mode auto \
 "Build a tiny bash CLI in this repo: (1) write tests/add.test.sh asserting 'add 2 3' prints 5, (2) write add.sh to pass it, (3) add a 'sub' command with a test, (4) write README.md documenting both, (5) run the tests, (6) commit everything. Work through the steps in order." \
 > /tmp/tta/s1/b-$cond-$model.jsonl 2>/dev/null
