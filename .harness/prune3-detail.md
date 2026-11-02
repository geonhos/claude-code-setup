# prune step 3 detail
## HARNESS_* names: 53 -> 32 (grep -o 'HARNESS_[A-Z_]*' | sort -u over bin lib claude tests install.sh)
Deleted (21): HARNESS_CLEAR_IDLE_POLLS HARNESS_CLEAR_INTERVAL HARNESS_CLEAR_POLLS HARNESS_CLEAR_RETRY_POLLS HARNESS_CLOSE_AFTER_ASK_ANALYST HARNESS_CLOSE_AFTER_ASK_IMPLEMENTER HARNESS_CLOSE_AFTER_DEFAULT HARNESS_CLOSE_INTERVAL HARNESS_CLOSE_POLLS HARNESS_CTX_RESET HARNESS_CTX_RESET_DEFAULT HARNESS_IDLE_GRACE HARNESS_IDLE_TTL_DEFAULT HARNESS_IDLE_TTL_MIN HARNESS_PROJECTS_DIR HARNESS_RUNNER_DEFAULT HARNESS_RUNNER_IMPLEMENTER HARNESS_RUNNER_REVIEWER HARNESS_RUN_VIEW HARNESS_SPAWN_RETRIES HARNESS_SPAWN_RETRY_S 
Remaining 32, grouped:
- not reads: bare HARNESS_ (grep artefact); CLOSE_AFTER_ASK_, IDLE_TTL_MINUTES, NO_AUTOCLOSE (only inside the byte-exact v1 config template used for migration); RUNNER_, RUNNER_ANALYST (only the "env ignored" regression test + one test line)
- internal constants in lib/harness-defaults.sh: ROLES, WT_ROLES, DEFAULT_TIMEOUT_MS, IMPLEMENTER_TIMEOUT_MS, VIEWER_DEFAULT, HL_MAX_S_DEFAULT, HL_MAX_S_IMPLEMENTER_DEFAULT
- test seams: HL_NO_PERL, NOW, TESTS_DIR, TEST_SERIAL, TEST_TIMEOUT, LIB
- tunables read by code that stays until step 4: LOCK_MAX_S, LOCK_STALE_S, LOG_DAYS, LOG_KEEP, JSONL_MAX, ROUTE_LOG, MAX_PARALLEL, WT_ROOT, HL_MAX_S, HL_START_S, POLL_SEC, VIEWER, ROLE
## Behaviour changes
- fixed 30 min wt_reap for non-workers on ask|status (was idle TTL config)
- role-slot session expiry after idle TTL gone; no more 'clear' jsonl field (metrics clear rows kept: they read historical progress.jsonl)
- status ctx column only from exit.json; ctx_tokens/project_dir_name/HARNESS_PROJECTS_DIR dropped
- late-report archive gone (late 'report <ask-id>' still queues a retro candidate)
- worktree lock-takeover warning (HARNESS_LOCK_MAX_S) no longer visible: base showed it for the registry lock .harness/panes.lock (uncaptured); the only lock now is wt_git's, whose stderr is captured by callers. Test asserts lock release instead.
- viewer: run starts in background, then a pane running 'harness watch' is split; closed when the run ends. Split/run failure falls back to background + note.
