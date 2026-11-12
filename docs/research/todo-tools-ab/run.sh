#!/bin/bash
# run.sh <T1|T4> <base|todo|nudge> <n>
set -u
T=$1; C=$2; N=$3; RUN=$T-$C-$N
REPO=/Users/geonho.yeom/workspace/claude-code-setup
case $T in T1) BASE=2b30519;; T4) BASE=77252a8;; esac
CL=/tmp/tta/clones/$RUN; rm -rf $CL; mkdir -p /tmp/tta/clones
git clone --local --no-hardlinks -q $REPO $CL && cd $CL
git checkout -q -B main $BASE; git remote remove origin
for b in $(git for-each-ref --format='%(refname:short)' refs/heads | grep -vx main); do git branch -q -D "$b"; done
for t in $(git tag); do git tag -d $t >/dev/null; done
git reflog expire --expire=now --all; git gc --prune=now -q
mkdir -p .harness docs/wiki/inbox
if [ $T = T1 ]; then for f in 2026-10-22-analyst-1792671569-52258-6342.md 2026-10-22-retro-1792643421-12588-9450.md; do git -C $REPO show 101fae0:docs/wiki/inbox/$f > docs/wiki/inbox/$f; done; fi
if [ $T = T4 ]; then cp $REPO/.harness/gate-shrink-detail.md .harness/; mkdir -p .harness/spike-bprime; cp $REPO/.harness/spike-bprime/RESULTS.md .harness/spike-bprime/; fi
case $C in base) P=$T-base;; todo) P=$T-base; export CLAUDE_CODE_ENABLE_TODO_TOOLS=1;; nudge) P=$T-nudge; export CLAUDE_CODE_ENABLE_TODO_TOOLS=1;; esac
DIFFBASE=$(git rev-parse HEAD)
PATH="/tmp/tta/shim:$PATH" HARNESS_ROLE=worker perl -e 'alarm shift; exec @ARGV' 1800 \
  claude -p --agent implementer --output-format stream-json --verbose --permission-mode auto \
  --disallowedTools=AskUserQuestion < /tmp/tta/briefs/$P.prompt > /tmp/tta/out/$RUN.jsonl 2>/tmp/tta/out/$RUN.err
echo "exit=$?" > /tmp/tta/out/$RUN.exit
git add -N . 2>/dev/null
git diff $DIFFBASE -- . ':(exclude).harness' ':(exclude).claude/agent-memory' > /tmp/tta/out/$RUN.diff
git diff --numstat $DIFFBASE -- . ':(exclude).harness' ':(exclude).claude/agent-memory' > /tmp/tta/out/$RUN.numstat
