#!/bin/bash
# Tests for the harness-workers mod (mods/harness-workers). Run: /bin/bash tests/mod.test.sh
# Always: jq checks of the manifests and a field-path check of the mod's parser against the golden.
# Only with the real `claude` binary: `claude plugin validate` and `claude plugin test` (unit and
# contract tests). No network, no model session; claude runs with a temp CLAUDE_CONFIG_DIR.
set -u
. "$(dirname "$0")/harness-lib.sh"
ROOT=$(cd "$HERE/.." && pwd)
MOD="$ROOT/mods/harness-workers"
GOLDEN="$ROOT/tests/fixtures/status-v1.json"
FIELDS="$MOD/hooks/fields.txt"
OUT=""
has() { printf '%s\n' "$OUT" | grep -qF -- "$1"; }

# --- manifests (always)
check "plugin.json name" jqt '.name == "harness-workers" and (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and (.description | length > 0)' "$MOD/.claude-plugin/plugin.json"
check "plugin.json types file exists" test -f "$MOD/$(jq -r '.types' "$MOD/.claude-plugin/plugin.json")"
check "hooks.json names one module" jqt '.modules == ["./register.tsx"]' "$MOD/hooks/hooks.json"
check "hooks module exists" test -f "$MOD/hooks/register.tsx"
check "marketplace lists the mod" jqt '.name == "my-claude-harness" and (.plugins | map(select(.name == "harness-workers" and .source == "./mods/harness-workers")) | length == 1)' "$ROOT/.claude-plugin/marketplace.json"

# --- every field path the parser reads exists in the golden (always)
# Paths look like `folders[].workers[].exit.rc`; `[]` is any element, and at least one element must have it.
check "field list is not empty" test "$(grep -c . "$FIELDS")" -gt 5
missing=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if ! jq -e --arg p "$path" '
        def has_path($parts):
          if ($parts | length) == 0 then true
          else ($parts[0]) as $h
            | if ($h | endswith("[]")) then
                ($h | .[0:-2]) as $k
                | (type == "object" and has($k) and (.[$k] | type == "array") and (.[$k] | any(has_path($parts[1:]))))
              else
                (type == "object" and has($h) and (.[$h] | has_path($parts[1:])))
              end
          end;
        has_path($p | split("."))' "$GOLDEN" >/dev/null 2>&1; then
    missing="$missing $path"
  fi
done < "$FIELDS"
check "every field path exists in the golden (missing:${missing:- none})" test -z "$missing"

# --- the Claude Code version gate: the mod API needs MIN_CLAUDE (the one place; the READMEs must name it)
MIN_CLAUDE=2.1.332
check "mod README names the minimum Claude Code version" grep -qF "$MIN_CLAUDE" "$MOD/README.md"
check "root README names the minimum Claude Code version" grep -qF "$MIN_CLAUDE" "$ROOT/README.md"

# claude_gate BIN -> 0 when `BIN --version` reports >= MIN_CLAUDE; else 1 with GATE_MSG set (older or unparsable)
GATE_MSG=""
claude_gate() {
  local v
  v=$("$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
  if [ -z "$v" ]; then GATE_MSG="unparsable version"; return 1; fi
  if [ "$(printf '%s\n%s\n' "$MIN_CLAUDE" "$v" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" != "$MIN_CLAUDE" ]; then
    GATE_MSG="claude $v is older than $MIN_CLAUDE"
    return 1
  fi
  return 0
}

# claude_checks BIN: `plugin validate` and `plugin test` of a copy of the mod, or SKIP lines.
claude_checks() {
  local bin=$1 cfg tmp rc
  if ! claude_gate "$bin"; then
    echo "SKIP claude plugin validate: $GATE_MSG"
    echo "SKIP claude plugin test: $GATE_MSG"
    return 0
  fi
  cfg=$(mktemp -d); WORKS="$WORKS $cfg"
  tmp=$(mktemp -d); WORKS="$WORKS $tmp"
  # a copy, so that the engine's generated .claude-plugin/types and the golden fixture stay out of the checkout
  cp -R "$MOD" "$tmp/harness-workers"
  rm -rf "$tmp/harness-workers/.claude-plugin/types"
  {
    printf 'export const golden: string = '; jq -Rs . "$GOLDEN"
    printf 'export const fields: string[] = '; jq -Rsc 'split("\n") | map(select(. != ""))' "$FIELDS"
  } > "$tmp/harness-workers/tests/golden.ts"

  OUT=$(CLAUDE_CONFIG_DIR="$cfg" "$bin" plugin validate "$tmp/harness-workers" 2>&1); rc=$?
  check "claude plugin validate passes" test "$rc" -eq 0
  check "validate: no TypeScript warning in the mod" not has "error TS"

  OUT=$(CLAUDE_CONFIG_DIR="$cfg" "$bin" plugin test "$tmp/harness-workers" 2>&1); rc=$?
  check "claude plugin test passes (unit + contract)" test "$rc" -eq 0
  check "plugin test ran the contract file" has "contract.test.ts"
}

# --- self-checks of the gate with stub claude binaries (they reject `plugin`, so a run would fail)
STUBS=$(mktemp -d); WORKS="$WORKS $STUBS"
mkstub() { # NAME VERSION-OUTPUT
  mkdir -p "$STUBS/$1"
  printf '#!/bin/sh\ncase "$1" in\n  --version) echo "%s" ;;\n  *) echo "plugin: unknown command" >&2; echo "$*" >> "%s/%s.calls"; exit 1 ;;\nesac\n' "$2" "$STUBS" "$1" > "$STUBS/$1/claude"
  chmod +x "$STUBS/$1/claude"
}
mkstub old "2.1.300 (Claude Code)"
mkstub garbage "not a version"
mkstub new "2.1.332 (Claude Code)"
claude_checks "$STUBS/old/claude" > "$STUBS/old.out"
claude_checks "$STUBS/garbage/claude" > "$STUBS/garbage.out"
cat "$STUBS/old.out" "$STUBS/garbage.out"
check "gate: claude 2.1.300 prints SKIP lines" grep -q '^SKIP claude plugin validate: claude 2.1.300 is older than' "$STUBS/old.out"
check "gate: claude 2.1.300 never ran plugin" test ! -e "$STUBS/old.calls"
check "gate: a garbage version prints SKIP (unparsable)" grep -q '^SKIP claude plugin test: unparsable version' "$STUBS/garbage.out"
check "gate: a garbage version never ran plugin" test ! -e "$STUBS/garbage.calls"
check "gate: 2.1.332 passes the gate" claude_gate "$STUBS/new/claude"

# --- the real claude binary (never tests/fake-claude on PATH)
REAL=""
for d in $(printf '%s' "$PATH" | tr ':' ' '); do
  case "$d" in *fake-claude*) continue ;; esac
  if [ -x "$d/claude" ]; then REAL="$d/claude"; break; fi
done

if [ -z "$REAL" ]; then
  echo "SKIP claude plugin validate / plugin test: no real claude binary on PATH"
else
  claude_checks "$REAL"
fi

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
