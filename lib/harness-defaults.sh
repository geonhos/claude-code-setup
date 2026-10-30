# harness-defaults.sh — the one place for roles and default numbers (sourced by bin/harness
# and bin/harness-verify). Definitions only: no side effects, no commands run at load time.
# Sourced eagerly at the top of the script, never lazily (see docs/wiki: in-place edits).
# Prose copies (usage text, conductor.md, implement/SKILL.md, config template) cannot source
# this file; tests/harness.test.sh checks them against `harness _defaults`.
HARNESS_ROLES="analyst implementer reviewer"
HARNESS_WT_ROLES="analyst reviewer"          # roles that may run `--worktree` asks
HARNESS_DEFAULT_TIMEOUT_MS=600000            # ask --timeout: analyst, reviewer
HARNESS_IMPLEMENTER_TIMEOUT_MS=1740000       # ask --timeout: implementer (Stop-hook verify can take 10 min)
HARNESS_CTX_RESET_DEFAULT=120000             # tokens: analyst/reviewer are cleared above this
HARNESS_IDLE_TTL_DEFAULT=30                  # idle_ttl_minutes (0 = off)
HARNESS_CLOSE_AFTER_DEFAULT=never            # close_after_ask.<role>
HARNESS_RUNNER_DEFAULT=pane                  # runner.<role>: pane | headless
HARNESS_VIEWER_DEFAULT=auto                  # viewer (top-level key): auto | pane | none; where a headless run is shown
HARNESS_HL_MAX_S_DEFAULT=3600                # headless run wall-clock cap, seconds (analyst, reviewer)
HARNESS_HL_MAX_S_IMPLEMENTER_DEFAULT=5400    # same cap for the implementer: a 3x600 s verify loop plus work (90 min)

# role_in <role> [list] — is <role> in the list (default: all roles)?
role_in() {
  case " ${2-$HARNESS_ROLES} " in *" $1 "*) return 0 ;; esac
  return 1
}
