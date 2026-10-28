---
type: decision
status: active
updated: 2026-10-28
sources: [.harness/implementer-headless-design.md, branch feat/v23-headless-implementer, tests/headless-implementer.test.sh]
verified_by: tests/headless-implementer.test.sh
---
# 0009: Headless implementer (0007 stage C)

**Context.** [0007](0007-headless-runner-pilot.md) piloted `claude -p` for analyst and reviewer: 18 headless asks, 3 abnormal, against 70 pane asks with 29 abnormal. The implementer is still a pane (98 asks, 25 abnormal, p95 1706 s); its failures are the same completion races. It differs in that its Stop hook runs lint and tests (`harness-verify`) and can block the stop.

**Decision.** `runner.implementer: headless` uses the 0007 machinery with these additions.
- Flags: `--permission-mode auto --permission-prompts none` for the implementer runner only; no allowedTools, no bypass. `system/permission_denied` events (fallback `result.permission_denials`) go to `exit.json.denied[]`.
- Exit 2 (all headless roles): no report and denied[] non-empty. The denied tool and reason are printed; nothing to answer, re-ask with a changed brief. A report plus denials is a normal exit (denials noted on stderr).
- Exit map: report + verify pass 0; verify FAIL at the attempt cap 5 `verify: FAIL (<step>, <n> attempts)`; only `<report>.pending` (killed mid-verify) 5 INTERRUPTED; deadline while `.pending` exists 4 "still verifying (Stop hook running)"; no report and no denial 3.
- Auto-resume (amends 0007 D6): if the implementer's last logged exit is non-zero, the next ask uses `--resume <last sid>` and records `resumed:true`. `--fresh` overrides; other roles still need `--keep`.
- Cap: `headless_max_minutes` default 60, implementer 90 (`HARNESS_HL_MAX_S_IMPLEMENTER_DEFAULT`).
- Viewer: Stop-hook blocks show even on exit 0, `permission_denied` is labelled, a failed tool result shows its first line and last 5 lines, "verify (Stop hook)" start and done lines.

**Status.** Active once `runner.implementer` is set; this repo's config is flipped by the conductor after merge.

**Consequences.**
- No deadline-restore race: `claude -p` waits for the Stop hook, so a report is never hidden when the run ends normally.
- `.pending` means verification is in flight or was killed: it blocks the idle TTL reap and makes `harness report` say "still verifying".
- `harness close implementer --force` kills the tree, tests included; the next report is INTERRUPTED (5) and the following ask resumes the session.
- The viewer tail applies to any failed multi-line tool result (the stateless jq stream cannot tell Bash apart); "verify done" carries no seconds.
- Rollback: `runner.implementer` back to `pane`, `harness close implementer --force`.
