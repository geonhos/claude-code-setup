#!/bin/bash
# conductor-gate.sh — PreToolUse hook: gates the conductor (agent_type conductor, no agent_id); any other agent is allowed.
# Acts only in a harness checkout (.harness/asks/ above the cwd, decision 0010); elsewhere it allows before parsing.
# Output: nothing (allow) or a PreToolUse deny JSON on stdout. Always exit 0.
set -u

# lib/harness-root.sh holds the one harness_root. Hooks are not symlinked (install.sh writes
# the repo paths into settings.json), so the lib sits at a fixed place next to this file.
case ${BASH_SOURCE[0]} in */*) hd=${BASH_SOURCE[0]%/*} ;; *) hd=. ;; esac   # run as `bash name` from its dir
. "$(CDPATH= cd -P "$hd/../../lib" 2>/dev/null && pwd)/harness-root.sh" 2>/dev/null || LIB_MISSING=1
# end loader

INPUT=$(cat)

if [ -n "${LIB_MISSING:-}" ]; then
  # no lookup possible: deny only the conductor (it exists only in harness checkouts), allow the rest
  command -v jq >/dev/null 2>&1 || exit 0
  [ "$(printf '%s' "$INPUT" | jq -r 'if type == "object" then (.agent_type // empty) else empty end' 2>/dev/null)" = conductor ] || exit 0
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"conductor-gate: lib/harness-root.sh missing; rerun ./install.sh"}}'
  exit 0
fi

DIR=$PWD
if command -v jq >/dev/null 2>&1; then
  c=$(printf '%s' "$INPUT" | jq -r 'if type == "object" then (.cwd // empty) else empty end' 2>/dev/null)
  if [ -n "$c" ] && [ -d "$c" ]; then DIR=$c; fi
fi
harness_root "$DIR" >/dev/null || exit 0

if ! command -v jq >/dev/null 2>&1; then
  # fail closed; static JSON because jq is unavailable
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Conductor gate requires jq. Install jq, or run a worker session."}}'
  exit 0
fi

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$TOOL" ]; then
  # fail closed (decision 0005): a gate that allows what it cannot read is no gate
  echo "conductor-gate: unparseable hook input, denying" >&2
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Conductor gate could not parse the hook input, so the call is denied. Retry, or delegate with /analyze or /implement."}}'
  exit 0
fi

# agent_id is set only for subagents (and forked skills) inside a session. Their
# hook input carries their OWN agent_type (e.g. "tiny"), not the session's, so
# agent_type alone would wave a conductor's subagent through: the agent_id check
# catches it and falls back to the env rule.
AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
if [ -n "$AGENT" ] && [ -z "$AGENT_ID" ]; then
  [ "$AGENT" = conductor ] || exit 0
elif [ "${HARNESS_ROLE:-conductor}" = worker ]; then
  exit 0
fi

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD=$PWD
CWD=${CWD%/}
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Fixed strings: never interpolate per-call data (keeps the prompt cache stable).
MSG_WRITE="Conductor cannot edit source. Delegate with the /implement skill (implementer worker). Direct writes are allowed only under docs/**/*.md, .harness/, and the .harness/ of a registered work folder (git worktree)."
MSG_READ="Conductor does not read source. Delegate with the /analyze skill (analyst worker) and read its report. Direct reads are allowed only under .harness/, docs/, and *.md files."
MSG_WATCH="harness watch is for a human terminal; the conductor reads the report (harness report <worker>, or harness wait <worker> to block until the run ends)."
MSG_BASH="Conductor shell is limited to ONE command per call: harness (also harness -C <dir> ..., harness lane ...); gh pr create|view|list|checks|comment|edit|merge (no api, no merge -d); gh issue create|list|view|comment|close|edit|reopen; git status / log / diff --stat / branch (list); git show --stat|--name-only <rev> or git show <rev>:<path> (path under .harness/ or docs/, or *.md); ls (no -R) and stat on any path; cat, head, tail -n N under .harness/ and docs/, in a work folder's .harness/, and of this session's Bash task output files (/private/tmp/claude-*/<slug>/<session_id>/tasks/*.output). No ; & | redirects, backticks or \$(. Delegate command execution with the /implement skill (implementer worker)."

# --- Bash allow/deny lists ---------------------------------------------------
# Each piece below is one alternative; they are joined with | into one regex.

# Commands the conductor may run (matched against a whole masked segment).
BASH_ALLOW='harness( .*)?'                                        # delegation CLI
BASH_ALLOW="$BASH_ALLOW|"'gh( .*)?'                               # GitHub CLI (see GH_ALLOW, gh_segment_ok)
BASH_ALLOW="$BASH_ALLOW|"'git status( (-[sb]+|--short|--branch|--porcelain(=v[12])?|--untracked-files=(no|normal|all)))*' # read-only git; no -v (prints diffs) ...
BASH_ALLOW="$BASH_ALLOW|"'git log( .*)?'
BASH_ALLOW="$BASH_ALLOW|"'git diff --stat( .*)?'                  # ... summaries only
BASH_ALLOW="$BASH_ALLOW|"'git branch( (-a|-r|-v|--show-current))*'  # list only
BASH_ALLOW="$BASH_ALLOW|"'git show( .*)?'                         # git_show_ok narrows it: --stat/--name-only, or rev:path
BASH_ALLOW="$BASH_ALLOW|"'(cat|head|tail)( [^ ]+)+'               # cat_ls_segment_ok checks the files
BASH_ALLOW="$BASH_ALLOW|"'(ls|stat)( [^ ]+)*'                     # listing and metadata, any path, never recursive
BASH_ALLOW="^($BASH_ALLOW)\$"

# gh "<group> <subcommand>" pairs the conductor may run. api, run, repo,
# auth, browse, issue delete|transfer|pin, pr diff|checkout|status are not here.
GH_ALLOW='pr (create|view|list|checks|comment|edit|merge)'
GH_ALLOW="$GH_ALLOW|"'issue (create|list|view|comment|close|edit|reopen)'

# git long options that are denied anywhere in a git segment.
GIT_DENY_LONG='output'                                            # writes files
GIT_DENY_LONG="$GIT_DENY_LONG|delete|move|copy"                   # mutates branches
GIT_DENY_LONG="$GIT_DENY_LONG|patch|unified|cc|binary|remerge-diff|dd|diff-merges|raw|check" # prints diff content

# Initials of git short-flag groups that are denied (e.g. -D, -Df, -U3):
#   o = --output (writes files)
#   d D m M c C = branch delete / move / copy (mutates branches)
#   p u U = patch / unified context (prints diff content)
#   G S = git log pickaxe (probes file contents)
GIT_DENY_SHORT='odDmMcCpuUGS'

GIT_DENY="--($GIT_DENY_LONG)| -[$GIT_DENY_SHORT][A-Za-z0-9]* "

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

field() { printf '%s' "$INPUT" | jq -r ".tool_input.$1 // empty" 2>/dev/null; }

# path_bad PATH -> 0 for a path the gate never resolves: '..' segment or leading ~
path_bad() {
  case "$1" in
    ..|../*|*/..|*/../*|'~'*) return 0 ;;
  esac
  return 1
}

# canon PATH -> the one canonical-path helper. Sets CANON_LEX (path relative to CWD as
# written, "." for CWD) and CANON_PHYS (symlink-resolved, relative to the resolved CWD);
# returns 1 when PATH is empty, has a '..' segment, resolves outside CWD, loops, or
# exceeds 16 symlink hops. A path that does not exist yet resolves through its nearest
# existing ancestor. Callers check BOTH values. Needs only cd -P / pwd -P / readlink
# (bash 3.2, BSD). Call it directly, not in $(...), so the variables survive.
canon() {
  local p=$1 root full
  CANON_LEX=""; CANON_PHYS=""
  [ -n "$p" ] || return 1
  path_bad "$p" && return 1
  case "$p" in
    "$CWD")   CANON_LEX="." ;;
    "$CWD"/*) CANON_LEX=${p#"$CWD"/} ;;
    /*)       return 1 ;;
    ./*)      CANON_LEX=${p#./} ;;
    *)        CANON_LEX=$p ;;
  esac
  root=$(physical "$CWD") || return 1
  case "$p" in /*) ;; *) p=$CWD/$p ;; esac
  full=$(physical "$p") || return 1
  case "$full" in
    "$root")   CANON_PHYS="." ;;
    "$root"/*) CANON_PHYS=${full#"$root"/} ;;
    *) return 1 ;;
  esac
}

# physical ABS_PATH -> prints the fully resolved absolute path
physical() {
  local p=$1 hops=0 ex tail par t
  while :; do
    ex=$p; tail=""
    while [ ! -e "$ex" ] && [ ! -L "$ex" ]; do
      [ "$ex" != / ] || return 1
      tail="/${ex##*/}$tail"
      ex=${ex%/*}
      [ -n "$ex" ] || ex=/
    done
    if [ -L "$ex" ]; then
      hops=$((hops + 1))
      [ "$hops" -le 16 ] || return 1
      t=$(readlink "$ex") || return 1
      par=${ex%/*}; [ -n "$par" ] || par=/
      par=$(cd -P "$par" 2>/dev/null && pwd -P) || return 1
      case "$t" in /*) p=$t$tail ;; *) p=$par/$t$tail ;; esac
      continue
    fi
    case "$tail" in */..|*/../*) return 1 ;; esac
    if [ -d "$ex" ]; then
      par=$(cd -P "$ex" 2>/dev/null && pwd -P) || return 1
      if [ "$par" = / ]; then printf '%s' "$tail"; else printf '%s' "$par$tail"; fi
    else
      par=${ex%/*}; [ -n "$par" ] || par=/
      par=$(cd -P "$par" 2>/dev/null && pwd -P) || return 1
      if [ "$par" = / ]; then printf '/%s%s' "${ex##*/}" "$tail"; else printf '%s/%s%s' "$par" "${ex##*/}" "$tail"; fi
    fi
    return 0
  done
}

# readable_rel / writable_rel REL -> 0 when the repo-relative path is allowed
# raw_stream_rel REL -> 0 for a headless run's raw stream (.harness/log/*.jsonl[.gz]); it
# holds source the conductor must not see (decision 0007)
raw_stream_rel() {
  local l
  l=$(printf '%s' "$1" | tr 'A-Z' 'a-z')   # macOS volumes are case-insensitive
  case "$l" in .harness/log/*.jsonl|.harness/log/*.jsonl.*) return 0 ;; esac
  return 1
}
readable_rel() {
  raw_stream_rel "$1" && return 1
  case "$1" in
    .harness|.harness/*|docs|docs/*|*.md) return 0 ;;
  esac
  return 1
}
writable_rel() {
  case "$1" in
    .harness/*) return 0 ;;
    docs/*.md)  return 0 ;;
  esac
  return 1
}

# lane_worktrees -> prints the path of every registered (non-bare) worktree of
# the repo at CWD, one per line
lane_worktrees() {
  git -C "$CWD" worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{ if (p != "" && !b) print p; p = substr($0, 10); b = 0 }
         /^bare$/{ b = 1 }
         END { if (p != "" && !b) print p }'
}

# lane_harness_path PATH -> 0 when PATH, symlinks resolved, is under .harness/ of
# a registered worktree of this repo (raw streams excluded). A relative PATH
# resolves against CWD; a '..' segment is denied.
lane_harness_path() {
  local p=$1 full wt wr rest
  [ -n "$p" ] || return 1
  path_bad "$p" && return 1
  case "$p" in /*) ;; *) p=$CWD/$p ;; esac
  full=$(physical "$p") || return 1
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    wr=$(physical "$wt") || continue
    [ "$wr" != / ] || continue
    case "$full" in
      "$wr"/.harness|"$wr"/.harness/*)
        rest=${full#"$wr"/}
        raw_stream_rel "$rest" && return 1
        return 0 ;;
    esac
  done <<LANES
$(lane_worktrees)
LANES
  return 1
}

# readable PATH -> 0 when the conductor may read it (lexically and after
# resolving symlinks)
readable() {
  canon "$1" && readable_rel "$CANON_LEX" && readable_rel "$CANON_PHYS"
}

# readable_or_lane PATH -> readable, or under .harness/ of a registered work folder
readable_or_lane() { readable "$1" || lane_harness_path "$1"; }

# writable PATH -> 0 when the conductor may write it (lexically and after
# resolving symlinks), or it is under .harness/ of a registered work folder
writable() {
  if canon "$1" && writable_rel "$CANON_LEX" && writable_rel "$CANON_PHYS"; then
    return 0
  fi
  lane_harness_path "$1"
}

# scan_command -> reads ONE command on stdin, scans it like the shell (single
# quotes, double quotes, backslash escapes) and prints "<masked><TAB><raw>".
# <masked> is the command with the contents of every '...' / "..." removed
# (quote chars kept); <raw> is the text as written. Exits 1 (= deny) on anything
# that would make it more than one simple command: an unquoted ; & | < > # `
# or newline, an unquoted $( $' $", ` or $( inside double quotes, an
# unterminated quote. Newlines inside quotes are kept as spaces.
# Input must not contain tabs (callers normalize them to spaces).
scan_command() {
  awk '
    BEGIN { st = 0; bad = 0; m = ""; r = ""; nl = 0 }   # st: 0 unquoted, 1 single, 2 double
    {
      line = $0; n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1); nx = substr(line, i + 1, 1)
        if (st == 0) {
          if (c == "\\") { c = c substr(line, i + 1, 1); i++; m = m c; r = r c }
          else if (c == ";" || c == "&" || c == "|" || c == "<" || c == ">" || c == "#" || c == "`") bad = 1
          else if (c == "$" && (nx == "(" || nx == "\047" || nx == "\"")) bad = 1
          else {
            m = m c; r = r c
            if (c == "\047") st = 1
            else if (c == "\"") st = 2
          }
        } else if (st == 1) {
          r = r c
          if (c == "\047") { m = m c; st = 0 }
        } else {
          r = r c
          if (c == "\\") { r = r substr(line, i + 1, 1); i++ }
          else if (c == "\"") { m = m c; st = 0 }
          else if (c == "`" || (c == "$" && nx == "(")) bad = 1
        }
      }
      if (st == 0) nl++; else r = r " "
    }
    END { if (st != 0 || bad || nl > 1) exit 1; print m "\t" r }
  '
}


# has_expansion TEXT -> 0 when TEXT contains a character that the shell would
# expand or glob ($ { } * ? [ ] ~ \)
has_expansion() {
  case "$1" in
    *[\$\{\}\*\?\[\]~\\]*) return 0 ;;
  esac
  return 1
}

# git_segment_ok RAW -> 0 when a git segment uses no denied option and no
# rev:path (flag checks run on the raw text with quoting removed: "-D" == -D)
git_segment_ok() {
  local norm
  norm=$(printf ' %s ' "$1" | tr -d "\"'\\\\")
  case "$norm" in *:*) return 1 ;; esac
  printf '%s' "$norm" | grep -Eq -- "$GIT_DENY" && return 1
  return 0
}

# plain_tok TOKEN -> 0 when TOKEN has no quote or backslash
plain_tok() {
  case "$1" in *[\"\'\\]*) return 1 ;; esac
  return 0
}

# doc_rel_ok REL [md] -> 0 when a repo-relative path is under .harness/ or docs/ (or, with
# "md", any *.md) and is not a raw stream. Shared by bodyfile_ok and git_show_ok.
doc_rel_ok() {
  raw_stream_rel "$1" && return 1
  case "$1" in
    .harness/*|docs/*) return 0 ;;
    *.md) [ "${2:-}" = md ] && return 0 ;;
  esac
  return 1
}

# bodyfile_ok VALUE -> 0 when a gh --body-file / -F value is a path that stays
# (symlinks resolved) under .harness/ or docs/. "-" (stdin) is denied.
bodyfile_ok() {
  local v=$1
  [ -n "$v" ] && [ "$v" != - ] || return 1
  plain_tok "$v" || return 1
  has_expansion "$v" && return 1
  canon "$v" && doc_rel_ok "$CANON_PHYS"
}

# gh_segment_ok MASKED RAW -> 0 only for "gh pr|issue <sub>" with <sub> in GH_ALLOW
# (merge without -d). Global flags -R/--repo/--hostname (and --x=y) may precede
# the group. Everything up to and including the subcommand is read from the
# MASKED segment and must be plain unquoted tokens, so quoting cannot make this
# parser disagree with gh. --body-file/-F values must be plain paths under
# .harness/ or docs/. Flag checks on the rest of the segment use the raw text
# with quoting removed, so "--delete-branch" == --delete-branch.
gh_segment_ok() {
  local norm tok group sub nflag=0 mflag=0 want=0 v
  norm=$(printf '%s ' "$2" | tr -d "\"'\\\\" | tr -s ' ')
  set -f
  set -- $1
  set +f
  shift   # "gh"
  while [ $# -gt 0 ]; do
    plain_tok "$1" || return 1
    case "$1" in
      -R|--repo|--hostname) [ $# -ge 2 ] || return 1; plain_tok "$2" || return 1; shift 2 ;;
      --repo=*|--hostname=*) shift ;;
      -*) return 1 ;;
      *) break ;;
    esac
  done
  [ $# -ge 1 ] || return 1
  group=$1
  shift
  [ $# -ge 1 ] || return 1
  sub=$1
  shift
  plain_tok "$sub" || return 1
  printf '%s' "$group $sub" | grep -Eq "^($GH_ALLOW)\$" || return 1
  # --body-file / -F values (also --body-file=x, -Fx, clusters like -dF): read
  # from the masked tail, must be plain paths under .harness/ or docs/
  for tok in "$@"; do
    if [ "$want" -eq 1 ]; then want=0; bodyfile_ok "$tok" || return 1; continue; fi
    case "$tok" in
      --body-file|--recover) mflag=$((mflag + 1)); want=1 ;;
      --body-file=*|--recover=*) mflag=$((mflag + 1)); bodyfile_ok "${tok#*=}" || return 1 ;;
      --*) ;;
      -*F*) mflag=$((mflag + 1)); v=${tok#*F}
            if [ -n "$v" ]; then bodyfile_ok "$v" || return 1; else want=1; fi ;;
    esac
  done
  [ "$want" -eq 0 ] || return 1
  # quote-stripped view: a flag that only appears once quotes are removed
  # ("--body-file") must not slip past the check above, and the per-command
  # flag denials apply to it
  set -f
  set -- $norm
  set +f
  for tok in "$@"; do
    case "$tok" in
      --body-file|--body-file=*|--recover|--recover=*) nflag=$((nflag + 1)) ;;
      --delete-branch|--delete-branch=*) [ "$group $sub" != 'pr merge' ] || return 1 ;;
      --*) ;;
      -*F*) nflag=$((nflag + 1)) ;;
    esac
    case "$tok" in
      --*) ;;
      -*d*) [ "$group $sub" != 'pr merge' ] || return 1 ;;
    esac
  done
  [ "$nflag" -le "$mflag" ] || return 1
  return 0
}

# unquoted_text_ok RAW -> 0 when the segment's shell text is plain. Outside
# quotes only A-Z a-z 0-9 . _ / @ % + , : - = and spaces are allowed, and a word
# may not start with = (zsh =cmd) or ~. That rules out braces, globs, glob
# qualifiers, expansions, backslashes, redirects and history bangs in one go.
# Single-quoted text is literal. Double-quoted text may not contain $ ` \ or !.
unquoted_text_ok() {
  printf '%s\n' "$1" | LC_ALL=C awk '
    BEGIN { st = 0; bad = 0; ws = 1 }   # st: 0 unquoted, 1 single, 2 double; ws: still at word start
    { n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (st == 1) { if (c == "\047") st = 0; else ws = 0 }
        else if (st == 2) {
          if (c == "\"") st = 0
          else {
            ws = 0
            if (c == "$" || c == "`" || c == "\\" || c == "!") bad = 1
          }
        } else if (c == " ") ws = 1
        else if (c == "\047") st = 1            # quotes alone do not end word start
        else if (c == "\"") st = 2
        else if (c == "\\") {                   # only \'"'"', \" and "\ " are literal
          nx = substr($0, i + 1, 1)
          if (nx == "\047" || nx == "\"" || nx == " ") { i++; ws = 0 } else bad = 1
        }
        else if (c ~ /[A-Za-z0-9._\/@%+,:-]/) ws = 0
        else if (c == "=" && !ws) ws = 0
        else bad = 1
      } }
    END { exit (bad || st != 0) ? 1 : 0 }'
}

# commit_rev_ok REV -> 0 when REV is a plain rev (letters, digits . _ / @ -, then
# optional ~N suffixes) that resolves to a commit; a blob or tree SHA is denied because
# git show would print its content. The rev reaches the shell unquoted and zsh
# extendedglob treats ^ as negation (HEAD^ expands to matching file names) and ~ as
# exclusion, so ^ is denied outright and every ~ needs digits after it. Even ~N stays a
# pattern word, so git_show_ok allows it only in the --stat/--name-only form, never
# before a ':'.
commit_rev_ok() {
  case "$1" in
    ''|-*) return 1 ;;
  esac
  printf '%s' "$1" | grep -Eq '^[A-Za-z0-9._/@-]+(~[0-9]+)*$' || return 1
  git -C "$CWD" rev-parse -q --verify "$1^{commit}" >/dev/null 2>&1
}

# git_show_ok MASKED -> 0 for "git show --stat|--name-only [REV...]" (no other
# option) or "git show REV:PATH" (one token; PATH under .harness/ or docs/, or
# *.md, no '..' segment, no raw stream). Tokens are plain: no quotes.
git_show_ok() {
  local tok rev path stat=0
  case "$1" in *[\"\']*) return 1 ;; esac
  set -f
  set -- $1
  set +f
  shift; shift   # git show
  [ $# -ge 1 ] || return 1
  if [ $# -eq 1 ]; then
    case "$1" in
      *:*)
        rev=${1%%:*}; path=${1#*:}
        [ -n "$rev" ] && [ -n "$path" ] || return 1
        # ~ / ^ before ':' is a glob under extendedglob: main^:x.md can expand to a
        # file name such as main.go, so the rev:path form takes no ~ or ^ at all
        case "$rev" in *[~^]*) return 1 ;; esac
        commit_rev_ok "$rev" || return 1
        case "$path" in *:*|*[~^]*|/*|..|../*|*/..|*/../*) return 1 ;; esac
        doc_rel_ok "$path" md && return 0
        return 1 ;;
    esac
  fi
  for tok in "$@"; do
    case "$tok" in
      --stat|--name-only) stat=1 ;;
      -*|*:*) return 1 ;;
      *) commit_rev_ok "$tok" || return 1 ;;
    esac
  done
  [ "$stat" -eq 1 ]
}

# task_output_ok PATH -> 0 for a task output file of the calling session:
# /private/tmp/claude-<x>/<slug>/<session_id>/tasks/*.output (absolute, symlinks resolved);
# <x> is non-empty and <slug> is this project's slug: CWD with every character outside
# A-Za-z0-9 turned into '-' (Claude Code's project directory naming)
task_output_ok() {
  local full rest a b c d e slug
  case "$SESSION_ID" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
  case "$1" in /*) ;; *) return 1 ;; esac
  full=$(physical "$1") || return 1
  case "$full" in /private/tmp/claude-*) ;; *) return 1 ;; esac
  rest=${full#/private/tmp/}
  IFS=/ read -r a b c d e <<RESTEOF
$rest
RESTEOF
  case "$a" in claude-?*) ;; *) return 1 ;; esac
  # tr works per byte, so one multibyte UTF-8 character becomes several '-' where Claude Code
  # may write one: such a cwd is falsely denied, never falsely allowed (fail closed)
  slug=$(printf '%s' "$CWD" | tr -c 'A-Za-z0-9' '-')
  [ -n "$b" ] && [ "$b" = "$slug" ] && [ "$c" = "$SESSION_ID" ] && [ "$d" = tasks ] || return 1
  case "$e" in ''|*/*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$e" in *.output) return 0 ;; esac
  return 1
}

# cat_ls_segment_ok MASKED -> 0 when a cat / ls segment needs no quoting,
# expansion or parent-directory access
cat_ls_segment_ok() {
  local tok cmd=${1%% *}
  case "$1" in *[\"\']*|*..*) return 1 ;; esac
  has_expansion "$1" && return 1
  set -f
  set -- $1
  set +f
  case "$1" in
    ls|stat)             # any path: listing and metadata only, never recursive
      shift
      for tok in "$@"; do
        case "$tok" in
          --r*) return 1 ;;            # --recursive (and abbreviations)
          --*) ;;
          -*R*) return 1 ;;            # -R, -laR, ...
        esac
      done ;;
    cat|head|tail)
      shift
      if [ "${1:-}" = -n ] && [ "$cmd" != cat ]; then   # head/tail: optional "-n N" only (no -f)
        case "${2:-}" in ''|*[!0-9]*) return 1 ;; esac
        shift 2
      fi
      [ $# -ge 1 ] || return 1
      for tok in "$@"; do
        case "$tok" in -*) return 1 ;; esac
        # symlink-resolved: .harness/ or docs/ here, a task output file, or a work folder's .harness/
        if canon "$tok" && ! raw_stream_rel "$CANON_PHYS"; then
          case "$CANON_PHYS" in .harness|.harness/*|docs|docs/*) continue ;; esac
        fi
        task_output_ok "$tok" && continue
        lane_harness_path "$tok" && continue
        return 1
      done ;;
  esac
  return 0
}

# bash_ok COMMAND -> 0 when COMMAND is one simple command on the allowlist
bash_ok() {
  local cmd=$1 out seg raw tab
  tab=$(printf '\t')
  [ -n "$cmd" ] || return 1
  cmd=$(printf '%s' "$cmd" | tr '\t' ' ')
  out=$(printf '%s\n' "$cmd" | scan_command) || return 1
  seg=${out%%"$tab"*}
  raw=${out#*"$tab"}
  seg=$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  raw=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -n "$seg" ] || return 1
  # plain shell text only (character allowlist); in a git show segment ~N rev
  # suffixes are exempt here (commit_rev_ok validates them strictly)
  case "$seg" in
    git\ show|git\ show\ *) unquoted_text_ok "$(printf '%s' "$raw" | sed -E 's/([A-Za-z0-9._@-])(~[0-9][0-9]*)+/\1/g')" || return 1 ;;
    *) unquoted_text_ok "$raw" || return 1 ;;
  esac
  # reject '..' path components (but not git ranges like main...HEAD)
  printf ' %s ' "$seg" | grep -Eq '[ /=]\.\.([ /]|$)' && return 1
  case "$seg" in
    git\ show|git\ show\ *) git_show_ok "$seg" || return 1 ;;
    git\ *)          git_segment_ok "$raw" || return 1
                     ;;
    gh|gh\ *)        gh_segment_ok "$seg" "$raw" || return 1 ;;
    cat\ *|head\ *|tail\ *|ls|ls\ *|stat\ *) cat_ls_segment_ok "$seg" || return 1 ;;
  esac
  printf '%s' "$seg" | grep -Eq "$BASH_ALLOW"
}

case "$TOOL" in
  Edit|Write)
    writable "$(field file_path)" || deny "$MSG_WRITE" ;;
  Read)
    readable_or_lane "$(field file_path)" || deny "$MSG_READ" ;;
  Grep)
    GPATH=$(field path)
    readable "$GPATH" || deny "$MSG_READ"
    # a directory search would read the raw streams under .harness/log
    canon "$GPATH" || deny "$MSG_READ"
    case "$CANON_PHYS" in .harness|.harness/log) deny "$MSG_READ" ;; esac ;;
  Glob)
    PATTERN=$(field pattern)
    case "$PATTERN" in *..*|/*|'~'*) deny "$MSG_READ" ;; esac
    GPATH=$(field path)
    if [ -z "$GPATH" ]; then
      # no path: the pattern itself must stay under .harness/ or docs/
      case "$PATTERN" in docs/*|.harness/*) ;; *) deny "$MSG_READ" ;; esac
      GBASE=$CWD
    else
      readable "$GPATH" || deny "$MSG_READ"
      GBASE=$GPATH
      case "$GBASE" in /*) ;; *) GBASE=$CWD/$GBASE ;; esac
    fi
    # resolve the pattern's static directory prefix (up to the first glob char)
    GPRE=${PATTERN%%[\*\?\[\{]*}
    if [ "$GPRE" = "$PATTERN" ]; then GDIR=$PATTERN
    else case "$GPRE" in */*) GDIR=${GPRE%/*} ;; *) GDIR="" ;; esac
    fi
    canon "$GBASE${GDIR:+/$GDIR}" || deny "$MSG_READ"
    case "$CANON_PHYS" in .harness|.harness/*|docs|docs/*) ;; *) deny "$MSG_READ" ;; esac ;;
  Bash)
    BCMD=$(field command)
    printf '%s' "$BCMD" | grep -Eq '^[[:space:]]*harness[[:space:]]+(-C[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)[[:space:]]+)?["'"'"']?watch["'"'"']?([[:space:]]|$)' && deny "$MSG_WATCH"
    bash_ok "$BCMD" || deny "$MSG_BASH" ;;
esac

exit 0
