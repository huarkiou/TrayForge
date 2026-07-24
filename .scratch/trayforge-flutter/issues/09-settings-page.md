# 09 — Settings Page: 进程配置 CRUD

**What to build:** A settings page accessible from the Dashboard gear icon. Users can add, edit, delete, copy, and reorder process configurations. Changes are validated and persisted through ConfigStore, triggering a ProcessManager reload.

**Blocked by:** 02 — ConfigStore, 04 — ProcessManager Core

**Status:** ready-for-agent

- [ ] Dashboard gear icon → `Navigator.push` to `SettingsPage`
- [ ] Process list: reorderable list showing each process name with edit/delete actions
- [ ] Add process: FAB → `ProcessEditPage` with empty form
- [ ] Edit process: tap process name → `ProcessEditPage` pre-filled with current values
- [ ] Copy process: button on each row → duplicate the config with "(copy)" appended to name
- [ ] Delete process: swipe-to-delete or delete button; if process is currently running, show dialog: "Stop and delete?" → Stop + Delete / Cancel; if stopped, direct delete with confirmation dialog
- [ ] Reorder: drag handle on each row to move up/down in list
- [ ] `ProcessEditPage` form fields: `name` (required, validated no `/` `\`), `cwd` (directory path), `cmd` (single-line text), `encoding` (dropdown or text: utf-8, gbk), `singleton` (checkbox), `autostart` (checkbox), `webui_pattern` (text, validated as compilable regex), `delete_before_start` (multi-line, one file per line), `max_restarts` (number), `env` (key-value table, add/remove rows)
- [ ] Save triggers `ConfigStore.save()` → `configChanged` event → `ProcessManager.reloadConfig()`, which stops removed processes and starts new autostart processes
- [ ] Form validation errors displayed inline; save button disabled until valid
