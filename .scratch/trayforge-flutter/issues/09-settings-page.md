# 09 — Settings Page: 进程配置 CRUD

**What to build:** A settings page accessible from the Dashboard gear icon. Users can add, edit, delete, copy, and reorder process configurations. Changes are validated and persisted through ConfigStore, triggering a ProcessManager reload.

**Blocked by:** 02 — ConfigStore, 04 — ProcessManager Core

**Status:** done

- [x] Dashboard gear icon → `Navigator.push` to `SettingsPage`
- [x] Process list: reorderable list showing each process name with edit/delete actions
- [x] Add process: FAB → `ProcessEditPage` with empty form
- [x] Edit process: tap process name → `ProcessEditPage` pre-filled with current values
- [x] Copy process: button on each row → duplicate the config with "(copy)" appended to name
- [x] Delete process: swipe-to-delete or delete button; if process is currently running, show dialog: "Stop and delete?" → Stop + Delete / Cancel; if stopped, direct delete with confirmation dialog
- [x] Reorder: drag handle on each row to move up/down in list
- [x] `ProcessEditPage` form fields: `name` (required, validated no `/` `\`), `cwd` (directory path), `cmd` (single-line text), `encoding` (dropdown or text: utf-8, gbk), `singleton` (checkbox), `autostart` (checkbox), `webui_pattern` (text, validated as compilable regex), `delete_before_start` (multi-line, one file per line), `max_restarts` (number), `env` (key-value table, add/remove rows)
- [x] Save triggers `ConfigStore.save()` → `configChanged` event → `ProcessManager.reloadConfig()`, which stops removed processes and starts new autostart processes
- [x] Form validation errors displayed inline; save button disabled until valid

## Decisions

> Recorded 2025-07-25 during implementation and code review.

### D1: Save/Reload chain: save first, then reload

Spec says `ConfigStore.save()` → `configChanged` → `ProcessManager.reloadConfig()`.
Implementation calls `_configStore.save(newConfig)` before `_processManager.reloadConfig(newConfig)`
in `_save()`. `reloadConfig()` internally also saves (needed by `_lookupConfig()` during `start()`),
making the second save idempotent and harmless. Adding a `configChanged` → `reloadConfig` listener
in `main.dart` would cause a circular re-entry because `reloadConfig` saves internally.
This approach matches the spec's intent (save triggers reload) without the circularity.

### D2: Delete uses button, not swipe-to-delete

Spec says "swipe-to-delete or delete button". The delete button satisfies the
"or" clause. Swipe-to-delete on a `ReorderableListView` row with a drag handle
creates ambiguous gesture zones — a horizontal swipe could be interpreted as
reorder initiation or dismiss. Keeping delete as an explicit button avoids
this conflict.

### D3: Copy name collision resolution beyond spec

Spec says append "(copy)". Implementation adds `_uniqueName()`: first copy
gets "(copy)", subsequent copies get "(copy) (2)", "(copy) (3)", etc.
Without this, copying the same config twice would produce duplicate names
and fail validation on save. Defensive, not speculative.

### D4: Every mutation persists immediately — no draft/save pattern

`SettingsViewModel.add()`, `edit()`, `delete()`, `copy()`, and `reorderItem()`
all create a new list, validate, and call `_save()` synchronously. There is no
"dirty" flag, no cancel button, and no batch-save. This follows the spec's
"Save triggers persistence" model: every change is a save. The `ProcessEditPage`
form is the only exception — its changes only commit when the user taps Save
in the AppBar.

### D5: `_EnvRow` private class owns its own controllers

The env table is a dynamic list of key-value pairs. Each row owns its own
`TextEditingController` instances rather than sharing controllers across
an index-managed list. `_EnvRow.dispose()` mirrors the form's disposal
discipline, called both on row removal and in the page's `dispose()`.

### D6: `reorderItem` uses `onReorderItem` (new API), not deprecated `onReorder`

Flutter ≥3.41 deprecated `ReorderableListView.onReorder` in favor of
`onReorderItem`, which pre-adjusts `newIndex` for the removed item at
`oldIndex`. Our `reorderItem(int oldIndex, int newIndex)` method accepts
the pre-adjusted index directly — no manual `if (newIndex > oldIndex)`
correction needed.

### D7: Delete dialog extracted to `_showDeleteDialog` helper

Code review flagged Duplicated Code in `_confirmDelete`: the running-process
dialog and stopped-process dialog shared identical `showDialog<bool>` +
`AlertDialog` + Cancel/`FilledButton` skeletons. Extracted into a single
`_showDeleteDialog({title, content, confirmLabel})` method. The two call
sites differ only in their confirmation strings and post-dialog logic.

### D8: `cmd` field validated as required

Spec lists `cmd` as "single-line text" (not explicitly "required" like `name`).
An empty command is meaningless — `ProcessManager.start()` would fail
immediately with "Cannot start: empty command". Validating at form level
provides earlier, clearer feedback than a runtime system message.

### D9: Welcome screen "Add Process" → `SettingsPage`, not SnackBar

Before this feature, the welcome screen's "Add Process" button showed a
"Settings not yet implemented" SnackBar as a placeholder. Now that
`SettingsPage` exists, the button navigates to it directly when
`settingsViewModel` is wired. When `settingsViewModel` is null (no DI),
the button is a no-op — this avoids a crash while still providing the
intended path in normal operation.
