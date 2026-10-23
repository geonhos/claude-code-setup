#!/bin/bash
# conductor-gate.sh — PreToolUse hook for the Fable conductor.
# Spec: docs/superpowers/specs/2026-10-12-herdr-conductor-setup-design.md
#
# Role:   HARNESS_ROLE=worker  -> allow everything (herdr workers, manual escape hatch)
#         HERDR_ENV != 1       -> allow everything (not in a herdr pane: harness
#                                 cannot delegate there, so gating would only
#                                 strand the session; decision 0005)
#         anything else        -> conductor rules below
# Output: nothing (allow) or a PreToolUse deny JSON on stdout. Always exit 0.
set -u

if [ "${HARNESS_ROLE:-conductor}" = "worker" ]; then
  exit 0
fi

if [ "${HERDR_ENV:-}" != 1 ]; then
  exit 0
fi

INPUT=$(cat)

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

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] || CWD=$PWD
CWD=${CWD%/}

# Fixed strings: never interpolate per-call data (keeps the prompt cache stable).
MSG_WRITE="Conductor cannot edit source. Delegate with the /implement skill (implementer worker). Direct writes are allowed only under docs/**/*.md and .harness/."
MSG_READ="Conductor does not read source. Delegate with the /analyze skill (analyst worker) and read its report. Direct reads are allowed only under .harness/, docs/, and *.md files."
MSG_AGENT="Native subagents are disabled for the conductor; delegate through the skills so work is visible in herdr panes and logged. Use /analyze (analyst), /implement (implementer) or /review (reviewer) instead."
MSG_BASH="Conductor shell is limited to: harness; gh (pr/issue/run/repo view-style subcommands, pr create, no api); herdr read-only (status, pane list|get|layout|current, agent list|get|wait|explain, workspace list, tab list); read-only git (status / log / diff --stat / branch list / show --stat); cat or ls (no -R) under .harness/ and docs/; jq as a pipe consumer. Delegate command execution with the /implement skill (implementer worker)."

deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

field() { printf '%s' "$INPUT" | jq -r ".tool_input.$1 // empty" 2>/dev/null; }

# rel PATH -> prints the path relative to CWD, or returns 1 when the path is
# empty, outside CWD, or contains a '..' segment.
rel() {
  local p=$1
  [ -n "$p" ] || return 1
  case "$p" in
    ..|../*|*/..|*/../*|'~'*) return 1 ;;
  esac
  case "$p" in
    "$CWD")   p="." ;;
    "$CWD"/*) p=${p#"$CWD"/} ;;
    /*)       return 1 ;;
    ./*)      p=${p#./} ;;
  esac
  printf '%s' "$p"
}

# physrel PATH -> prints the symlink-resolved path relative to the resolved CWD
# ("." for CWD itself); returns 1 when it resolves outside CWD, loops, or
# exceeds 16 symlink hops. Needs only cd -P / pwd -P / readlink (bash 3.2, BSD).
# A path that does not exist yet resolves through its nearest existing ancestor.
physrel() {
  local p=$1 root full
  root=$(physical "$CWD") || return 1
  case "$p" in /*) ;; *) p=$CWD/$p ;; esac
  full=$(physical "$p") || return 1
  case "$full" in
    "$root") printf '.' ;;
    "$root"/*) printf '%s' "${full#"$root"/}" ;;
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
# holds source the conductor must not see (ADR 0007)
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

# readable PATH -> 0 when the conductor may read it (lexically and after
# resolving symlinks)
readable() {
  local p
  p=$(rel "$1") || return 1
  readable_rel "$p" || return 1
  p=$(physrel "$1") || return 1
  readable_rel "$p"
}

# writable PATH -> 0 when the conductor may write it (lexically and after
# resolving symlinks)
writable() {
  local p
  p=$(rel "$1") || return 1
  writable_rel "$p" || return 1
  p=$(physrel "$1") || return 1
  writable_rel "$p"
}

# split_segments -> reads a command on stdin, scans it left to right like the
# shell (single quotes, double quotes, backslash escapes), and prints one line
# per command segment: "<masked><TAB><raw>". <masked> is the segment with the
# contents of every '...' / "..." removed (quote chars kept); <raw> is the
# segment text as written. Segments end at unquoted ; & | (so && and ||) and
# newlines. Exits 1 on an unterminated quote; on an unquoted < > or # (comments
# could hide quotes from this scanner); on an unquoted $' or $" (ANSI-C /
# locale quoting); and on ` or $( unquoted or inside double quotes (command
# substitution; inside single quotes they are literal). Process substitution
# and here-strings are covered by the unquoted < > rule.
# Input must not contain tabs (callers normalize them to spaces).
split_segments() {
  awk '
    function flush() { if (m != "" || r != "") print m "\t" r; m = ""; r = "" }
    BEGIN { st = 0; bad = 0; m = ""; r = "" }   # st: 0 unquoted, 1 single, 2 double
    {
      line = $0; n = length(line)
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1); nx = substr(line, i + 1, 1)
        if (st == 0) {
          if (c == "\\") { c = c substr(line, i + 1, 1); i++; m = m c; r = r c }
          else if (c == ";" || c == "&" || c == "|") flush()
          else if (c == "<" || c == ">" || c == "#" || c == "`") bad = 1
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
      if (st == 0) flush(); else r = r " "
    }
    END { flush(); if (st != 0 || bad) exit 1 }
  '
}

# --- Bash allow/deny lists ---------------------------------------------------
# Each piece below is one alternative; they are joined with | into one regex.

# Commands the conductor may run (matched against a whole masked segment).
BASH_ALLOW='harness( .*)?'                                        # delegation CLI
BASH_ALLOW="$BASH_ALLOW|"'herdr status( .*)?'                     # herdr, read-only state ...
BASH_ALLOW="$BASH_ALLOW|"'herdr pane (list|get|layout|current)( .*)?'
BASH_ALLOW="$BASH_ALLOW|"'herdr agent (list|get|wait|explain)( .*)?'
BASH_ALLOW="$BASH_ALLOW|"'herdr (workspace|tab) list( .*)?'
BASH_ALLOW="$BASH_ALLOW|"'gh( .*)?'                               # GitHub CLI (see gh_segment_ok)
BASH_ALLOW="$BASH_ALLOW|"'git status( .*)?'                       # read-only git ...
BASH_ALLOW="$BASH_ALLOW|"'git log( .*)?'
BASH_ALLOW="$BASH_ALLOW|"'git diff --stat( .*)?'                  # ... summaries only
BASH_ALLOW="$BASH_ALLOW|"'git branch( .*)?'
BASH_ALLOW="$BASH_ALLOW|"'git show --stat( .*)?'
BASH_ALLOW="$BASH_ALLOW|"'cat (\.harness|docs)(/[^ ]*)?'          # reports and docs
BASH_ALLOW="$BASH_ALLOW|"'ls( -[A-Za-z]+)*( (\.harness|docs)(/[^ ]*)?)?' # top level, reports, docs
BASH_ALLOW="^($BASH_ALLOW)\$"

# git long options that are denied anywhere in a git segment.
GIT_DENY_LONG='output'                                            # writes files
GIT_DENY_LONG="$GIT_DENY_LONG|delete|move|copy"                   # mutates branches
GIT_DENY_LONG="$GIT_DENY_LONG|patch|unified|cc|binary|remerge-diff|dd|diff-merges|raw|check" # prints diff content

# Initials of git short-flag groups that are denied (e.g. -D, -Df, -U3):
#   o = --output (writes files)
#   d D m M c C = branch delete / move / copy (mutates branches)
#   p u U = patch / unified context (prints diff content)
GIT_DENY_SHORT='odDmMcCpuU'

GIT_DENY="--($GIT_DENY_LONG)| -[$GIT_DENY_SHORT][A-Za-z0-9]* "

# jq options that read files or take extra positional arguments.
JQ_DENY=' -[A-Za-z]*[fL][A-Za-z]* | --(from-file|rawfile|slurpfile|args|jsonargs)[ =]'

# has_expansion TEXT -> 0 when TEXT contains a character that the shell would
# expand or glob ($ { } * ? [ ] ~ \)
has_expansion() {
  case "$1" in
    *[\$\{\}\*\?\[\]~\\]*) return 0 ;;
  esac
  return 1
}

# jq_segment_ok N MASKED RAW -> 0 when a jq segment is safe: not the first
# segment (so it reads piped input), a single filter argument, no file flags,
# no paths, no env access, no unquoted expansions or globs
jq_segment_ok() {
  [ "$1" -gt 1 ] || return 1
  case "$3" in */*|*..*|*env*|*ENV*) return 1 ;; esac
  has_expansion "$2" && return 1
  printf ' %s ' "$2" | grep -Eq -- "$JQ_DENY" && return 1
  printf '%s' "$2" | grep -Eq '^jq( --?[A-Za-z-]+)*( [^ -][^ ]*)?$'
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

# bodyfile_ok VALUE -> 0 when a gh --body-file / -F value is a path that stays
# (symlinks resolved) under .harness/ or docs/. "-" (stdin) is denied.
bodyfile_ok() {
  local v=$1 p
  [ -n "$v" ] && [ "$v" != - ] || return 1
  plain_tok "$v" || return 1
  has_expansion "$v" && return 1
  p=$(rel "$v") || return 1
  p=$(physrel "$v") || return 1
  raw_stream_rel "$p" && return 1
  case "$p" in .harness/*|docs/*) return 0 ;; esac
  return 1
}

# gh_segment_ok MASKED RAW -> 0 only for allowlisted gh subcommands (spec 1):
# pr create|view|list|status|checks|comment|edit|merge (merge without -d),
# issue view|list|create|comment, run list|view (no --log*), repo view,
# auth status (no --show-token), browse. Global flags -R/--repo/--hostname (and
# --x=y) may precede the group. Everything up to and including the subcommand
# is read from the MASKED segment and must be plain unquoted tokens, so quoting
# cannot make this parser disagree with gh. --body-file/-F values must be
# plain paths under .harness/ or docs/. Flag checks on the rest of the segment
# use the raw text with quoting removed, so "--log" == --log.
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
  group=$1; sub=-
  shift
  if [ "$group" != browse ]; then
    [ $# -ge 1 ] || return 1
    sub=$1
    shift
    plain_tok "$sub" || return 1
  fi
  case "$group $sub" in
    'pr create'|'pr view'|'pr list'|'pr status'|'pr checks'|'pr comment'|'pr edit'|'pr merge') ;;
    'issue view'|'issue list'|'issue create'|'issue comment') ;;
    'run list'|'run view'|'repo view'|'auth status'|'browse -') ;;
    *) return 1 ;;
  esac
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
      --log*)          [ "$group $sub" != 'run view' ] || return 1 ;;
      --delete-branch|--delete-branch=*) [ "$group $sub" != 'pr merge' ] || return 1 ;;
      --show-token|--show-token=*) [ "$group $sub" != 'auth status' ] || return 1 ;;
      --*) ;;
      -*F*) nflag=$((nflag + 1)) ;;
    esac
    case "$tok" in
      --*) ;;
      -*d*) [ "$group $sub" != 'pr merge' ] || return 1 ;;
      -*t*) [ "$group $sub" != 'auth status' ] || return 1 ;;
    esac
  done
  [ "$nflag" -le "$mflag" ] || return 1
  return 0
}

# git_branch_ok RAW -> 0 when `git branch ...` only lists (spec 2). Any quote
# or backslash denies, so token splitting cannot disagree with git.
git_branch_ok() {
  local tok listing=0
  plain_tok "$1" || return 1
  set -f
  set -- $1
  set +f
  shift 2   # git branch
  for tok in "$@"; do
    case "$tok" in
      --list|--merged|--no-merged|--contains|--no-contains|--points-at) listing=1 ;;
      -a|-r|-v|-vv|--all|--remotes|--show-current|--sort=*) ;;
      -*) return 1 ;;
      *) [ "$listing" -eq 1 ] || return 1 ;;
    esac
  done
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

# cat_ls_segment_ok MASKED -> 0 when a cat / ls segment needs no quoting,
# expansion or parent-directory access
cat_ls_segment_ok() {
  local tok p
  case "$1" in *[\"\']*|*..*) return 1 ;; esac
  has_expansion "$1" && return 1
  set -f
  set -- $1
  set +f
  case "$1" in
    ls)
      shift
      for tok in "$@"; do
        case "$tok" in
          --r*) return 1 ;;            # --recursive (and abbreviations)
          --*) ;;
          -*R*) return 1 ;;            # -R, -laR, ...
          -*) ;;
          *)  p=$(physrel "$tok") || return 1   # symlink-resolved path argument
              case "$p" in .harness|.harness/*|docs|docs/*) ;; *) return 1 ;; esac ;;
        esac
      done ;;
    cat)
      shift
      for tok in "$@"; do        # symlink-resolved: must stay in .harness/ or docs/
        p=$(physrel "$tok") || return 1
        raw_stream_rel "$p" && return 1
        case "$p" in .harness|.harness/*|docs|docs/*) ;; *) return 1 ;; esac
      done ;;
  esac
  return 0
}

# bash_ok COMMAND -> 0 when the command has at least one segment and every
# segment is on the allowlist
bash_ok() {
  local cmd=$1 segs seg raw n=0 tab
  tab=$(printf '\t')
  [ -n "$cmd" ] || return 1
  cmd=$(printf '%s' "$cmd" | tr '\t' ' ')
  # tolerate a standalone 2>&1 word; split_segments rejects any other redirect
  segs=$(printf '%s\n' "$cmd" \
    | sed -E 's/(^|[[:space:]])2>&1([[:space:];&|]|$)/\1\2/g' \
    | split_segments) || return 1
  while IFS="$tab" read -r seg raw; do
    seg=$(printf '%s' "$seg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    raw=$(printf '%s' "$raw" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$seg" ] || continue
    n=$((n + 1))
    # plain shell text only (character allowlist), in any command
    unquoted_text_ok "$raw" || return 1
    # reject '..' path components (but not git ranges like main...HEAD)
    printf ' %s ' "$seg" | grep -Eq '[ /=]\.\.([ /]|$)' && return 1
    case "$seg" in
      jq|jq\ *)       jq_segment_ok "$n" "$seg" "$raw" || return 1; continue ;;
      git\ *)         git_segment_ok "$raw" || return 1
                      case "$seg" in git\ branch|git\ branch\ *) git_branch_ok "$raw" || return 1 ;; esac ;;
      gh|gh\ *)       gh_segment_ok "$seg" "$raw" || return 1 ;;
      cat\ *|ls|ls\ *) cat_ls_segment_ok "$seg" || return 1 ;;
    esac
    printf '%s' "$seg" | grep -Eq "$BASH_ALLOW" || return 1
  done <<EOF
$segs
EOF
  [ "$n" -gt 0 ]
}

case "$TOOL" in
  Edit|Write)
    writable "$(field file_path)" || deny "$MSG_WRITE" ;;
  NotebookEdit)
    writable "$(field notebook_path)" || deny "$MSG_WRITE" ;;
  Read)
    readable "$(field file_path)" || deny "$MSG_READ" ;;
  Grep)
    readable "$(field path)" || deny "$MSG_READ"
    # a directory search would read the raw streams under .harness/log
    GRP=$(physrel "$(field path)") || deny "$MSG_READ"
    case "$GRP" in .harness|.harness/log) deny "$MSG_READ" ;; esac ;;
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
    GP=$(physrel "$GBASE${GDIR:+/$GDIR}") || deny "$MSG_READ"
    case "$GP" in .harness|.harness/*|docs|docs/*) ;; *) deny "$MSG_READ" ;; esac ;;
  Agent|Workflow)
    deny "$MSG_AGENT" ;;
  Bash)
    bash_ok "$(field command)" || deny "$MSG_BASH" ;;
  Monitor)
    deny "$MSG_BASH" ;;
  mcp__filesystem__read_text_file|mcp__filesystem__read_file|\
  mcp__filesystem__search_files|mcp__filesystem__list_directory|\
  mcp__filesystem__list_directory_with_sizes|mcp__filesystem__directory_tree|\
  mcp__filesystem__get_file_info|mcp__filesystem__read_media_file)
    readable "$(field path)" || deny "$MSG_READ" ;;
  mcp__filesystem__read_multiple_files)
    # every path must be readable; an empty list is denied
    PATHS=$(printf '%s' "$INPUT" | jq -r '.tool_input.paths[]? // empty' 2>/dev/null)
    [ -n "$PATHS" ] || deny "$MSG_READ"
    while IFS= read -r P; do
      readable "$P" || deny "$MSG_READ"
    done <<EOF
$PATHS
EOF
    ;;
  mcp__filesystem__write_file|mcp__filesystem__edit_file|\
  mcp__filesystem__create_directory)
    writable "$(field path)" || deny "$MSG_WRITE" ;;
  mcp__filesystem__move_file)
    writable "$(field source)" && writable "$(field destination)" || deny "$MSG_WRITE" ;;
esac

exit 0
