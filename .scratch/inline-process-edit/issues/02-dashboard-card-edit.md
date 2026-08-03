# 02 — Dashboard card edit flow

**What to build:** Each process card on the Dashboard gains a pencil edit icon at the right edge of its header row. Tapping it opens the `ProcessEditPage` pre-filled with that process's configuration. After saving, the user returns to the Dashboard. The edit icon does not appear when no `onEditTap` callback is provided.

**Blocked by:** 01 — Prefactors

**Status:** done (`45734c3` — inline process edit feature)

- [ ] `ProcessCard` gains an optional `onEditTap` callback parameter
- [ ] When `onEditTap` is non-null, an `Icons.edit` compact `IconButton` with tooltip "Edit process" is rendered in the `_Header` row after the `ToggleButton`
- [ ] `DashboardScreen` provides the callback: looks up the process index in `SettingsViewModel.processes` by matching name, then navigates to `ProcessEditPage` in edit mode
- [ ] After Save, the user is returned to the Dashboard (pop back from `ProcessEditPage`)
- [ ] Card body tap still navigates to `ProcessDetailPage` — no change to existing `onTap`
- [ ] Tests: edit icon absent when callback is null; present when non-null; tapping icon calls callback; tapping icon navigates to `ProcessEditPage`
