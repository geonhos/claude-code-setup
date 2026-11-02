---
type: troubleshooting
status: superseded
updated: 2026-11-02
sources: [.harness/review-critique-detail.md §1.2, commit bc6095b, commit b310af4]
verified_by: tests/harness.test.sh (exit 6, sibling-prefix, symlink cases)
---
# herdr agent names are global across repos

> Superseded 2026-11-02 by [0011](../decisions/0011-single-runner-headless.md): workers are no longer herdr agents, so there are no global names or exit 6; the viewer pane is not addressed by name.

**Symptom.** A conductor in repo A sends work to the `implementer` running in repo B's pane, and repo B gets edited or committed.

**Cause.** herdr agent names are unique per herdr server, not per directory. The old harness used bare `analyst|implementer|reviewer` names and never checked the worker's cwd.

**Fix.** Names are `<role>-<repo8>` (sha1 of the repo top-level). After every `agent get`, the worker's resolved cwd must be the repo or a subdir; otherwise exit 6 and nothing is sent. A subdir conductor works: the Stop hook finds the subdir's `.harness/asks/` (see [harness root lookup](harness-root-lookup.md)).
