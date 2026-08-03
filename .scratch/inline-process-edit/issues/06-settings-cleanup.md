# 06 — Settings page cleanup

**What to build:** The Settings page no longer needs process management — all CRUD has moved to the Dashboard and process edit form. Remove the process list (reorderable rows with edit/copy/delete actions) and the FAB. Keep the global settings: output refresh interval, history limit, and autostart toggle.

**Blocked by:** 05 — Dashboard "+" + welcome page + DetailPage edit + force-return

**Status:** done (`45734c3` — Settings page no longer renders the process list; `_ProcessRow` removed)

- [ ] `SettingsPage` no longer renders the `ReorderableListView` of `_ProcessRow` widgets
- [ ] The `FloatingActionButton` ("Add Process") is removed
- [ ] The `_ProcessRow` widget class and its `_confirmDelete` / `_openEditPage` / `_openAddPage` helper methods are removed
- [ ] Global settings fields (output refresh ms, history limit) remain functional
- [ ] Autostart toggle remains functional
- [ ] Settings page AppBar title remains "Settings"
- [ ] Tests: process list is absent; FAB is absent; global settings fields still render and accept input; autostart toggle still works
