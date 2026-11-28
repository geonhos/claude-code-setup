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

# --- the real claude binary (never tests/fake-claude on PATH)
REAL=""
for d in $(printf '%s' "$PATH" | tr ':' ' '); do
  case "$d" in *fake-claude*) continue ;; esac
  if [ -x "$d/claude" ]; then REAL="$d/claude"; break; fi
done

if [ -z "$REAL" ]; then
  echo "SKIP claude plugin validate / plugin test: no real claude binary on PATH"
else
  CFG=$(mktemp -d); WORKS="$WORKS $CFG"
  TMP=$(mktemp -d); WORKS="$WORKS $TMP"
  # a copy, so that the engine's generated .claude-plugin/types and the golden fixture stay out of the checkout
  cp -R "$MOD" "$TMP/harness-workers"
  rm -rf "$TMP/harness-workers/.claude-plugin/types"
  {
    printf 'export const golden: string = '; jq -Rs . "$GOLDEN"
    printf 'export const fields: string[] = '; jq -Rsc 'split("\n") | map(select(. != ""))' "$FIELDS"
  } > "$TMP/harness-workers/tests/golden.ts"

  OUT=$(CLAUDE_CONFIG_DIR="$CFG" "$REAL" plugin validate "$TMP/harness-workers" 2>&1); RC=$?
  check "claude plugin validate passes" test "$RC" -eq 0
  check "validate: no TypeScript warning in the mod" not has "error TS"

  OUT=$(CLAUDE_CONFIG_DIR="$CFG" "$REAL" plugin test "$TMP/harness-workers" 2>&1); RC=$?
  check "claude plugin test passes (unit + contract)" test "$RC" -eq 0
  check "plugin test ran the contract file" has "contract.test.ts"
fi

echo "PASS $pass / FAIL $fail"
[ "$fail" -eq 0 ]
