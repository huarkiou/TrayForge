# 05 — Dashboard "+" + welcome page + DetailPage edit + force-return

**What to build:** Three new entry points and one unifying navigation rule. (1) A `+` icon button in the Dashboard AppBar opens the process edit form in add mode. (2) The welcome page "Add Process" button opens the same add form directly instead of going to Settings. (3) The process detail page gains an edit pencil icon in its AppBar. (4) All edit flows (Save, Delete, Duplicate) now force-return to the Dashboard via `pushAndRemoveUntil`, ensuring no intermediate page can hold a disposed ViewModel.

**Blocked by:** 04 — ProcessEditPage Delete + Duplicate

**Status:** ready-for-agent

- [ ] Dashboard AppBar gains `Icons.add` `IconButton` to the left of the Settings gear, tooltip "Add process". Opens `ProcessEditPage` in add mode. Visible on both dashboard and welcome screen
- [ ] Welcome page "Add Process" button navigates to `ProcessEditPage` in add mode instead of `SettingsPage`
- [ ] `ProcessDetailPage` gains an optional `onEditTap` callback. When non-null, an `Icons.edit` `IconButton` with tooltip "Edit process" is added to AppBar actions before the existing clear-output, search, and toggle buttons
- [ ] `DashboardScreen` provides the `onEditTap` callback for `ProcessDetailPage`: same name-based index lookup, same `ProcessEditPage` navigation
- [ ] **Force-return-to-Dashboard (A)**: All `onEditTap` callbacks (card and detail page) use `Navigator.pushAndRemoveUntil` so that after Save, Delete, or Duplicate, the user always lands on Dashboard — no intermediate pages remain on the stack
- [ ] After adding a new process and saving, user returns to Dashboard and sees the new card
- [ ] Tests: `+` button navigates to `ProcessEditPage` in add mode; welcome page Add navigates to add mode; DetailPage edit icon navigates to `ProcessEditPage`; after save from DetailPage edit, user is back on Dashboard; `pushAndRemoveUntil` clears intermediate pages
