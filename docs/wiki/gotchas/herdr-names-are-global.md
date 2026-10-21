---
type: gotcha
status: active
updated: 2026-10-21
sources: [.harness/review-critique-detail.md §1.2, commit bc6095b, commit b310af4]
verified_by: tests/harness.test.sh (exit 6, sibling-prefix, symlink cases)
---
# herdr agent names are global across repos

**Symptom.** A conductor in repo A sends work to the `implementer` running in repo B's pane, and repo B gets edited or committed.

**Cause.** herdr agent names are unique per herdr server, not per directory. The old harness used bare `analyst|implementer|reviewer` names and never checked the worker's cwd.

**Fix.** Names are `<role>-<repo8>` (sha1 of the repo top-level). After every `agent get`, the worker's resolved cwd must be the repo or a subdir; otherwise exit 6 and nothing is sent. If a subdir conductor's `.harness/` lives in the subdir but the worker writes to the root `.harness/`, the result is exit 3 (known, not fixed).
