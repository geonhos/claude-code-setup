#!/bin/bash
# usage: s1.sh <cond> <model> ; cond: none|todo|todowrite
cond=$1; model=$2
d=$(mktemp -d /tmp/tta/w.XXXX); cd $d
case $cond in
 none) ;;
 todo) export CLAUDE_CODE_ENABLE_TODO_TOOLS=1;;
 todowrite) export CLAUDE_CODE_ENABLE_TODO_TOOLS=1 CLAUDE_CODE_ENABLE_TASKS=0;;
esac
claude -p --model $model --output-format stream-json --verbose --permission-mode auto \
 "Create three files a.txt b.txt c.txt in this directory, one at a time, using a separate step for each file." \
 > /tmp/tta/s1/$cond-$model.jsonl 2>/tmp/tta/s1/$cond-$model.err
