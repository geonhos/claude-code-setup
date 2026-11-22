---
type: decision
status: active
updated: 2026-11-22
sources: ["#177", issue #165, issue #162, issue #166, commit feat/165-init-deny-rules, bin/harness:settings_merge]
verified_by: tests/harness.test.sh, tests/lane.test.sh
---
# 0014: `harness init` writes worker deny rules; `harness ask` warns when they are missing

**Context.** Workers run in auto mode for every role since #166, and no settings file carried `permissions.deny`. The audit (#162 §2) flagged this, and a control run showed the auto-mode classifier allows `git reset --hard` and `cat .env` in a repo; only prompt prose stopped them. With a local deny file, the same commands, `Read .env` and `cat .env` all landed in `permission_denials`. Deny rules from project and local files apply without workspace trust, and a deny in any scope wins.

**Decision.** (user, 2026-11-19)
- D1: the rules always go to `.claude/settings.local.json` (untracked) of the checkout where `harness init` ran. `--shared` moves only the `agent` key to the committed `settings.json`; `--no-agent` skips only the key. Rules exist only where init ran.
- D2: no opt-out flag; every init run re-adds any missing rule.
- D3: the set, in order: `Bash(git reset *--hard*)`, `Bash(git clean *)`, `Bash(git push *--force*)`, `Bash(git push -f*)`, `Bash(git push * -f*)`, `Read(.env)`, `Read(.env.*)`, `Read(~/.ssh/**)`, `Read(~/.aws/**)`. One constant, `HARNESS_DENY_RULES` in `bin/harness`.
- D4: the command names live only in the rules; the implementer prompt says "never rewrite history or discard uncommitted changes you did not make". The analyst prompt keeps its no-delete line (rm/mv/stash are covered by no rule).
- D5: `require_checkout` (once per ask, one jq call) prints one stderr warning naming the checkout path when the local file lacks any rule (missing file, no `permissions.deny`, partial set). The ask proceeds.
- D6: one `.bak`, never overwritten; the added rules are printed. `settings_merge` replaced `settings_set_agent` (one read, one write only on change).

**Why local only.** A committed rule would bind teammates who never ran init and would surprise them; a user-scope rule would reach every project. Local-only keeps the rule next to the opt-in that makes the checkout a harness checkout. A lane runs `cmd_init` in its worktree, so it gets its own copy.

**Why no `rm -rf` rules.** `*` spans `/`, so `Bash(rm -rf /*)` blocks every `rm -rf /tmp/...` cleanup. `rm -rf /` and `rm -rf ~` are built-in critical-path denials in auto mode.

**Status.** Active.

**Consequences.**
- The rules are a seatbelt, not a sandbox: `git -C . reset --hard`, `sh -c '...'`, absolute `git` paths and `git push origin +HEAD:main` are not matched; `git restore` and `git checkout -- <file>` are not blocked.
- `Read(.env.*)` also blocks editing `.env.example` and `.env.sample`; a deny cannot be overridden by an allow.
- One matching subcommand denies the whole compound call (`;` too: `head -50; git clean -nd` was denied), and the model sees only "Permission to use Bash with command <whole chain> has been denied.", no rule name (runs a-T3-2/b-T3-2, .harness/deny-bypass-experiment-detail.md:7). A harmless command chained to a denied one is blocked with it (`git commit --amend && git push --force-with-lease`).
- Checkouts initialised before #165 have no rules until `harness init` runs again; `harness ask` warns meanwhile.
- A denied call is counted in exit.json `denials`, but `denied[]` is partial: with both a Bash and a Read denial in one run it lists only the Bash one (`bin/harness-run:144-149`, pre-existing, separate issue).
- Rules apply to the conductor's own Bash and to `--agent solo` too.
- A settings file init must write that is unmergeable (invalid or empty JSON, top level not an object, `permissions` not an object, `permissions.deny` not an array) makes init fail (exit 1): checked first, nothing created, file untouched, no `.bak`. A different existing `agent` value is not an error. `harness lane` reports "harness init failed in <dir>" and carries on.
