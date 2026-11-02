# harness-defaults.sh — the one place for roles and default numbers (sourced by bin/harness
# and bin/harness-verify). Definitions only: no side effects, no commands run at load time.
# Sourced eagerly at the top of the script, never lazily (see docs/wiki: in-place edits).
# Prose copies (usage text, conductor.md, implement/SKILL.md, config template) cannot source
# this file; tests/harness.test.sh checks them against `harness _defaults`.
HARNESS_ROLES="analyst implementer reviewer"
HARNESS_WT_ROLES="analyst reviewer"          # roles that may run `--worktree` asks
HARNESS_DEFAULT_TIMEOUT_MS=3600000           # ask --timeout default: analyst, reviewer = their headless cap below (60 min)
HARNESS_IMPLEMENTER_TIMEOUT_MS=5400000       # same for the implementer = its cap (90 min); a background ask returns when the run ends
HARNESS_VIEWER_DEFAULT=auto                  # viewer (top-level key): auto | pane | none; a herdr pane running `harness watch`
HARNESS_HL_MAX_S_DEFAULT=3600                # headless run wall-clock cap, seconds (analyst, reviewer)
HARNESS_HL_MAX_S_IMPLEMENTER_DEFAULT=5400    # same cap for the implementer: a 3x600 s verify loop plus work (90 min)

# role_in <role> [list] — is <role> in the list (default: all roles)?
role_in() {
  case " ${2-$HARNESS_ROLES} " in *" $1 "*) return 0 ;; esac
  return 1
}
