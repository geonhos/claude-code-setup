#!/bin/bash
# harness lane / -C / implementer guard (issue #63): temp repos, a bare remote, fake gh and fake claude.
# Run: /bin/bash tests/lane.test.sh
set -u
. "$(dirname "$0")/harness-lib.sh"
FAKE_CLAUDE="$HERE/fake-claude"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# fake gh: `issue view` prints $FAKE_GH_TITLE; `pr view <branch> -q Q` runs jq Q on the JSON in $GH_DIR/<branch with / -> _>
GH_BIN=$(mktemp -d); GH_DIR=$(mktemp -d); WORKS="$WORKS $GH_BIN $GH_DIR"
cat > "$GH_BIN/gh" <<'EOG'
#!/bin/bash
case "$1 $2" in
  "issue view") echo "${FAKE_GH_TITLE:-}" ;;
  "pr view") f=$GH_DIR/${3//\//_}; [ -f "$f" ] || exit 1
    q=""; while [ $# -gt 0 ]; do [ "$1" = -q ] && q=$2; shift; done
    jq -r "${q:-.}" "$f" ;;
esac
EOG
chmod +x "$GH_BIN/gh"
export GH_DIR

hl() { # hl ARGS... -> OUT, RC (conductor env, fake claude + fake gh on PATH)
  OUT=$(HARNESS_POLL_SEC=0.2 HARNESS_HL_START_S=5 PATH="$GH_BIN:$FAKE_CLAUDE:$HERE/../bin:$PATH" \
    perl -e 'alarm(60);exec(@ARGV)' env -u HARNESS_ROLE -u HERDR_ENV /bin/bash "$HARNESS" "$@" 2>&1)
  RC=$?
}
# lsetup — bare remote + primary clone (initialised) under a fresh base dir; cwd = primary
lsetup() {
  BASE=$(cd "$(mktemp -d)" && pwd -P); WORKS="$WORKS $BASE"
  export FAKE_DIR="$BASE/fake" FAKE_LOG="$BASE/fake.log"; mkdir -p "$FAKE_DIR"; : > "$FAKE_LOG"
  git init -q --bare -b main "$BASE/remote.git"
  git clone -q "$BASE/remote.git" "$BASE/repo" 2>/dev/null
  cd "$BASE/repo" || exit 1
  git checkout -q -b main 2>/dev/null
  mkdir -p .claude; echo '{"lane_setup": "touch .harness/lane-setup-ran"}' > .claude/harness.json
  git add . && git commit -q -m init && git push -q origin main 2>/dev/null
  git remote set-head origin main >/dev/null 2>&1
  rm -f "$GH_DIR"/*; unset FAKE_GH_TITLE
  hinit
}
setpr() { printf '{"state":"%s","headRefOid":"%s","number":1}\n' "$2" "${3:-}" > "$GH_DIR/${1//\//_}"; } # setpr BRANCH STATE [OID]
alive_in() { local f="$1/.harness/asks/implementer.pid" id pid; read -r id pid _ < "$f" 2>/dev/null; [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; }

# 1. create: folder, branch, init, exclude, setup command, printed path
lsetup
hl lane 12 my-slug
D="$BASE/repo-12"
check "lane: rc 0" [ "$RC" -eq 0 ]
check "lane: prints the folder path last" [ "$(printf '%s\n' "$OUT" | tail -n 1)" = "$D" ]
check "lane: branch feat/12-my-slug" [ "$(git -C "$D" rev-parse --abbrev-ref HEAD)" = feat/12-my-slug ]
check "lane: based on origin/main" [ "$(git -C "$D" rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
check "lane: harness init ran" test -d "$D/.harness/asks"
check "lane: git status clean (exclude patterns)" [ -z "$(git -C "$D" status --porcelain)" ]
check "lane: lane_setup ran in the folder" test -f "$D/.harness/lane-setup-ran"

# 2. reuse
hl lane 12 my-slug
check "lane reuse: rc 0 and says so" grep -q "reusing" <<<"$OUT"
check "lane reuse: still one folder" [ "$(git worktree list | wc -l | tr -d ' ')" = 2 ]

# 3. slug from the issue title, --type
export FAKE_GH_TITLE="Fix the Big Bug!! with a very long title here"
hl lane 13 --type fix
check "lane title: branch fix/13-<kebab, 30 chars>" [ "$(git -C "$BASE/repo-13" rev-parse --abbrev-ref HEAD)" = fix/13-fix-the-big-bug-with-a-very-lo ]
unset FAKE_GH_TITLE

# 4. ls
setpr feat/12-my-slug OPEN
hl lane ls
check "ls: issue, branch, path, PR state" grep -q "#12  feat/12-my-slug  $D  PR:OPEN" <<<"$OUT"
check "ls: no PR shows -" grep -q "#13 .*PR:-" <<<"$OUT"
check "ls: not running" not_grep "running" <(printf '%s' "$OUT")

# 5. rm
hl lane rm 12
check "rm: refuses an open PR" [ "$RC" -ne 0 ]
check "rm: open PR keeps the folder" test -d "$D"
hl lane rm 13
check "rm: refuses without a PR" [ "$RC" -ne 0 ]
git -C "$D" push -q origin feat/12-my-slug 2>/dev/null
setpr feat/12-my-slug MERGED "$(git rev-parse feat/12-my-slug)"
printf '#!/bin/bash\nsleep 30\n' > "$BASE/harness-run"; chmod +x "$BASE/harness-run"; "$BASE/harness-run" & SP=$!
mkdir -p "$D/.harness/asks"; echo "id $SP" > "$D/.harness/asks/implementer.pid"
hl lane ls
check "ls: shows a running worker" grep -q "#12 .* running" <<<"$OUT"
hl lane rm 12
check "rm: refuses with a running worker" [ "$RC" -ne 0 ]
check "rm: running worker keeps the folder" test -d "$D"
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null; rm -f "$D/.harness/asks/implementer.pid"
hl lane rm "$D"
check "rm merged: rc 0" [ "$RC" -eq 0 ]
check "rm merged: folder gone" test ! -d "$D"
check "rm merged: local branch gone" not git show-ref -q --verify refs/heads/feat/12-my-slug
check "rm merged: remote branch gone" [ -z "$(git ls-remote --heads origin feat/12-my-slug)" ]
hl lane rm 13 --force
check "rm --force: removes without a PR" [ "$RC" -eq 0 ]
check "rm --force: folder gone" test ! -d "$BASE/repo-13"

# 6. -C and the implementer guard
lsetup
hl lane 20 x
D="$BASE/repo-20"
export FAKE_CLAUDE_MODE=success
export FAKE_REPORT_CMD="mkdir -p .harness/reports && printf '# implementer report\nstatus: done\n' > .harness/reports/implementer.md"
hl ask implementer "q"
check "guard: refused in the primary worktree" [ "$RC" -ne 0 ]
check "guard: message names harness lane" grep -q "harness lane" <<<"$OUT"
hl ask analyst "q"
check "guard: analyst is not guarded" not_grep "primary worktree" <(printf '%s' "$OUT")
hl -C "$D" ask implementer "q"
check "-C ask: rc 0" [ "$RC" -eq 0 ]
check "-C ask: state in the folder" test -s "$D/.harness/progress.jsonl"
check "-C ask: report in the folder" test -s "$D/.harness/reports/implementer.md"
check "-C ask: none in the primary for the implementer" not_grep '"agent":"implementer"' .harness/progress.jsonl
hl -C "$D" status
check "-C status: implementer line" grep -q "^implementer" <<<"$OUT"
hl -C "$D" report implementer
check "-C report: prints the folder's report" grep -q "implementer report" <<<"$OUT"
hl -C /nonexistent status
check "-C: bad dir fails" [ "$RC" -ne 0 ]
hl ask implementer "q" --no-lane
check "--no-lane: allowed in the primary" [ "$RC" -eq 0 ]
check "--no-lane: logged in progress.jsonl" jq -e 'select(.agent == "implementer" and .no_lane == true)' .harness/progress.jsonl

# 7. two implementers in two folders at the same time
hl lane 21 y
D2="$BASE/repo-21"
export FAKE_CLAUDE_MODE=slow30   # 3 s
( hl -C "$D" ask implementer "a"; echo $RC > "$BASE/rc1" ) & P1=$!
( hl -C "$D2" ask implementer "b"; echo $RC > "$BASE/rc2" ) & P2=$!
i=0; both=0
while [ "$i" -lt 40 ]; do
  if alive_in "$D" && alive_in "$D2"; then both=1; break; fi
  sleep 0.1; i=$((i + 1))
done
wait "$P1" "$P2"
check "parallel: both runs alive at the same time" [ "$both" = 1 ]
check "parallel: both finished rc 0" [ "$(cat "$BASE/rc1" "$BASE/rc2" | tr -d '\n')" = 00 ]
check "parallel: each folder has its own report" test -s "$D2/.harness/reports/implementer.md"

# 8. rm never deletes unmerged work
lsetup
hl lane 30 a; D="$BASE/repo-30"; B=feat/30-a
git -C "$D" commit -q --allow-empty -m w1; git -C "$D" push -q origin "$B" 2>/dev/null
setpr "$B" MERGED "$(git -C "$D" rev-parse HEAD)"
git -C "$D" commit -q --allow-empty -m unpushed
hl lane rm 30
check "rm: unpushed commit after MERGED refused" [ "$RC" -ne 0 ]
check "rm: unpushed commit keeps folder and branch" git show-ref -q --verify "refs/heads/$B"
check "rm: refusal says commits are not in the PR" grep -q "not in its PR" <<<"$OUT"
hl lane rm 30 --force
check "rm --force: rc 0" [ "$RC" -eq 0 ]
check "rm --force: reports the lost commit count" grep -q "1 commit(s)" <<<"$OUT"
check "rm --force: folder gone" test ! -d "$D"

lsetup
hl lane 31 b; D="$BASE/repo-31"; B=feat/31-b
git -C "$D" commit -q --allow-empty -m old; OLD=$(git -C "$D" rev-parse HEAD)
setpr "$B" MERGED "$OLD"
git -C "$D" commit -q --allow-empty -m "after the old merged PR"
hl lane rm 31
check "rm: reused branch with an old MERGED PR plus new commits refused" [ "$RC" -ne 0 ]
check "rm: reused branch keeps the folder" test -d "$D"
echo dirty > "$D/dirty.txt"
setpr "$B" MERGED "$(git -C "$D" rev-parse HEAD)"
hl lane rm 31
check "rm: uncommitted changes refused" [ "$RC" -ne 0 ]
check "rm: uncommitted changes keep the folder" test -f "$D/dirty.txt"
rm -f "$D/dirty.txt"

lsetup
hl lane 32 c; D="$BASE/repo-32"; B=feat/32-c
git -C "$D" commit -q --allow-empty -m w; git -C "$D" push -q origin "$B" 2>/dev/null
setpr "$B" CLOSED "$(git -C "$D" rev-parse HEAD)"
hl lane rm 32
check "rm closed: rc 0" [ "$RC" -eq 0 ]
check "rm closed: folder and local branch gone" test ! -d "$D"
check "rm closed: remote branch kept" [ -n "$(git ls-remote --heads origin "$B")" ]

lsetup
hl lane 33 d; D="$BASE/repo-33"; B=feat/33-d
git -C "$D" commit -q --allow-empty -m w; git -C "$D" push -q origin "$B" 2>/dev/null
setpr "$B" MERGED "$(git -C "$D" rev-parse HEAD)"
git push -q origin --delete "$B" 2>/dev/null   # "delete head branches" already did it
hl lane rm 33
check "rm merged, remote already auto-deleted: rc 0" [ "$RC" -eq 0 ]
check "rm merged, remote already auto-deleted: folder gone" test ! -d "$D"

# 9. reuse only a real work folder of this repo
lsetup
mkdir -p "$BASE/repo-40"
hl lane 40 e
check "reuse: a plain directory is refused" [ "$RC" -ne 0 ]
check "reuse: refusal names git worktree list" grep -q "not a work folder" <<<"$OUT"

# 10. canonical paths and strict issue matching (each check asserts the reason)
lsetup
ln -s "$BASE" "$BASE.link"; WORKS="$WORKS $BASE.link"
hl lane 50 f; hl lane 51 g
ln -s "$BASE/repo-50" "$BASE/link50"
cd "$BASE.link/repo" || exit 1
hl lane ls
check "symlink: ls works under a symlinked parent" grep -q "#50 .*$BASE/repo-50 " <<<"$OUT"
hl lane rm "$BASE.link/repo-51" --force
check "symlink: rm through a symlinked parent removes that lane" grep -q "removed $BASE/repo-51 and branch feat/51-g" <<<"$OUT"
check "symlink: the other lane is untouched" test -d "$BASE/repo-50"
hl lane rm "$BASE/link50" --force
check "symlink: rm through a symlink to the folder resolves it" grep -q "removed $BASE/repo-50 and branch feat/50-f" <<<"$OUT"
cd "$BASE/repo" || exit 1
git worktree add -q "$BASE/other" -b topic/5-x origin/main 2>/dev/null
hl lane rm 5
check "match: issue 5 does not match topic/5-x (no work folder)" grep -q "no work folder for '5'" <<<"$OUT"
check "match: non-lane folder and branch kept" test -d "$BASE/other"
check "match: non-lane branch kept" git show-ref -q --verify refs/heads/topic/5-x

# 11. remote delete is lease-protected
lsetup
hl lane 60 h; D="$BASE/repo-60"; B=feat/60-h
git -C "$D" commit -q --allow-empty -m w; git -C "$D" push -q origin "$B" 2>/dev/null
setpr "$B" MERGED "$(git -C "$D" rev-parse HEAD)"
git clone -q "$BASE/remote.git" "$BASE/other-clone" 2>/dev/null
( cd "$BASE/other-clone" && git checkout -q "$B" && git commit -q --allow-empty -m "someone else" && git push -q origin "$B" ) 2>/dev/null
hl lane rm 60
check "lease: rm still succeeds locally" [ "$RC" -eq 0 ]
check "lease: says the remote branch was kept" grep -q "kept origin/$B" <<<"$OUT"
check "lease: remote branch with later commits survives" [ -n "$(git ls-remote --heads origin "$B")" ]

# 12. detached HEAD
lsetup
hl lane 61 i; D="$BASE/repo-61"
git -C "$D" checkout -q --detach
hl lane rm "$D"
check "detached: refused" [ "$RC" -ne 0 ]
check "detached: clear message" grep -q "detached HEAD" <<<"$OUT"
git -C "$D" commit -q --allow-empty -m d1; git -C "$D" commit -q --allow-empty -m d2
cd /tmp || exit 1   # the caller's cwd must not matter
hl -C "$BASE/repo" lane rm "$D" --force
check "detached --force: counts the folder's own commits" grep -q "2 commit(s)" <<<"$OUT"
check "detached --force: folder gone" test ! -d "$D"
cd "$BASE/repo" || exit 1

# 13. ignored files on remove
lsetup
echo "SECRET=1" > .env; printf '.env\nnode_modules/\n' >> .git/info/exclude
hl lane 62 j; D="$BASE/repo-62"; B=feat/62-j
setpr "$B" MERGED "$(git -C "$D" rev-parse HEAD)"
cp .env "$D/.env"; mkdir -p "$D/node_modules"; echo x > "$D/node_modules/x"
hl lane rm 62
check "ignored: identical .env copy and node_modules do not block" [ "$RC" -eq 0 ]
check "ignored: folder removed" test ! -d "$D"
hl lane 63 k; D="$BASE/repo-63"; B=feat/63-k
setpr "$B" MERGED "$(git -C "$D" rev-parse HEAD)"
echo "SECRET=2" > "$D/.env"
hl lane rm 63
check "ignored: changed .env refused" [ "$RC" -ne 0 ]
check "ignored: message names the file" grep -q ".env differs from the original folder" <<<"$OUT"
check "ignored: folder kept" test -d "$D"
echo "tok" > "$D/only.env"; printf 'only.env\n' >> .git/info/exclude
hl lane rm 63
check "ignored: file missing in the primary is listed" grep -q "only.env only in the work folder" <<<"$OUT"
hl lane rm 63 --force
check "ignored: --force removes" [ "$RC" -eq 0 ]
check "ignored: --force folder gone" test ! -d "$D"

# 14. lane_copy
lsetup
echo "SECRET=1" > .env; mkdir -p cfg; echo c > cfg/local.json
printf '.env\ncfg/local.json\n' >> .git/info/exclude
echo '{"lane_copy": [".env", "cfg/local.json", "missing.txt", "../escape", "/etc/hosts"]}' > .claude/harness.json
hl lane 64 l; D="$BASE/repo-64"
check "copy: .env copied" [ "$(cat "$D/.env" 2>/dev/null)" = "SECRET=1" ]
check "copy: nested path copied" [ "$(cat "$D/cfg/local.json" 2>/dev/null)" = c ]
check "copy: missing file noted and skipped" grep -q "missing.txt is missing" <<<"$OUT"
check "copy: unsafe paths skipped" [ "$(grep -c 'unsafe path' <<<"$OUT")" -eq 2 ]
check "copy: nothing escaped" test ! -e "$BASE/escape"
echo '{}' > .claude/harness.json
hl lane 65 m
check "copy: default copies nothing" test ! -e "$BASE/repo-65/.env"

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
