---
type: how-to
status: active
updated: 2026-11-27
sources: ["#291", 26c4f92, install.sh, tests/uninstall.test.sh]
verified_by: tests/uninstall.test.sh (install and uninstall parts only; the Claude Code state steps are unverified)
---
# Move or rename the harness checkout

`install.sh` links point into the checkout by absolute path, and Claude Code keeps session, memory and trust state keyed by the folder path. A plain `mv` leaves dangling links, stale hooks and orphaned state. Do the steps in this order.

## Steps

1. **Quit every Claude Code session that runs in this checkout or uses the harness, and check no run is alive** (`ps -axo command= | grep harness-run`). The gate and `harness-verify` live in the old path; a running conductor loses its gate hook and a running worker loses `harness-verify`. `./install.sh --uninstall` refuses while a `harness-run` is alive.
2. **Optional: `./install.sh --uninstall --dry-run`, then `./install.sh --uninstall`** in the old folder. Since #291 install prunes by itself (step 4), so this is only needed to remove the harness from the machine or to clear a half-broken state. It removes links and hooks of this checkout, keeps `*.bak.<ts>` files and keeps links and hooks of another existing checkout.
3. **`mv old new`.**
4. **`./install.sh` in the new folder.** It replaces dangling harness links without a backup, removes hook entries whose harness-shaped path is gone, and adds the new ones. A link or hook of another checkout that still exists is kept with a warning (two gates would run until you run that checkout's `--uninstall`).
5. **Move `~/.claude/projects/<old-encoded-path>` to `~/.claude/projects/<new-encoded-path>`** (the encoded name is the absolute path with `/` and `.` replaced by `-`; check the directory name Claude Code created for the old folder). Why: Claude Code keys sessions (`--resume`) and auto-memory (`memory/MEMORY.md`) by the project path. Without this the new folder starts empty and the old directory is orphaned. `install.sh` does not touch `~/.claude/projects`.
6. **Start an interactive `claude` once in the new folder and accept the trust prompt.** Why: Claude Code stores trust per path and a headless worker (`claude -p`) cannot answer the prompt. What an untrusted folder does to the first `harness ask` is unverified.
7. **`git worktree repair` for live lanes** (`harness lane ls`): run `git worktree repair <lane-path>...` from the moved checkout, or `git worktree repair` there if the lanes did not move. Why: a work folder's `.git` file and the main repo's `worktrees/<n>/gitdir` store absolute paths in both directions; after the move each side points at the old location. If the lanes also moved, pass their new paths.

## Unverified

- Whether Claude Code reloads `settings.json` hooks in a session that is already open is not confirmed here. Step 1 assumes it does not and asks for a restart.
- The `/` and `.` to `-` encoding of the project directory name matches what was seen on this machine only; compare with `ls ~/.claude/projects` before moving.
