# 02 — UI tips: config changes don't hot-apply to running processes

**What to build:** When the user edits a running process's config or changes global settings, show a tip that the change takes effect on next process start — not immediately.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] ProcessEditPage: when saving an edited process that is currently running, show snackbar "Process is running — changes will take effect on next start"
- [ ] SettingsPage: add helper text to output refresh and history limit fields noting "Takes effect on next process start"
- [ ] All existing tests pass; new widget test for the snackbar
