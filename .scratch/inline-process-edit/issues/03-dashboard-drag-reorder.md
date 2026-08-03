# 03 — Dashboard drag-to-reorder

**What to build:** Users can long-press and drag process cards on the Dashboard to reorder them. A drag handle icon appears on the left side of each card header. Reordering persists immediately and does not clear accumulated output (ensured by ticket 01).

**Blocked by:** 01 — Prefactors

**Status:** done (`45734c3` — inline process edit feature)

- [ ] `DashboardScreen._buildDashboardBody` replaces `ListView.builder` with `ReorderableListView.builder`; each item receives `key: ValueKey(vm.name)`
- [ ] `onReorder` delegates to `SettingsViewModel.reorderItem`
- [ ] `ProcessCard` gains an optional `dragHandleIndex` parameter; when non-null, a `ReorderableDragStartListener` wrapping an `Icons.drag_handle` icon is rendered at the start of the `_Header` row before the `StatusDot`
- [ ] Dashboard passes `dragHandleIndex` from the builder index
- [ ] Drag handle is absent when `dragHandleIndex` is null (safe for non-reorderable contexts)
- [ ] Tests: drag handle present when index is non-null; absent when null; reorder triggers `SettingsViewModel.reorderItem`; output is preserved after reorder
