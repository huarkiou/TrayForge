# Dashboard layout modes

**Status:** ready-for-agent
**Date:** 2026-08-04

## Problem Statement

The Dashboard shows every configured Process as a full-width card in a long
vertical list. With many processes, the list is hard to scan at a glance, and
users have no way to choose a denser overview. The drag handles on every card
add visual noise and require precise mouse targeting.

## Solution

Add a toggle button in the Dashboard AppBar that switches between two Layout
modes:

- **List layout** (default, unchanged look): wide cards with status dot,
  controls, and output preview.
- **Grid layout**: an adaptive grid of square compact cards — status dot,
  name, WebUI copy, toggle, edit — with the latest five output lines.
  Columns adapt to window width.

The choice persists in config.json (`dashboard_layout`, default `list`), so
the Dashboard opens in the last-used layout after a restart.

Both layouts reorder Processes by **long-press drag**; the per-card drag
handle is removed from the List layout.

## User Stories

1. As a user, I want a button in the Dashboard AppBar that switches between
   List layout and Grid layout, so that I can freely choose how I view my
   processes.
2. As a user, I want the button's icon to reflect the layout I will switch to
   (grid ⇄ list), so that the affordance is unambiguous.
3. As a user, I want my layout choice to persist across app restarts, so that
   I don't have to switch every time I launch.
4. As a user, I want the Dashboard to open in List layout when no preference
   is stored (or the stored value is invalid), so that existing behavior is
   unchanged.
5. As a user, I want the layout toggle hidden when no processes are
   configured, so that the welcome screen stays clean.
6. As a user, I want the Grid layout to show compact square cards with
   status dot, name, WebUI copy, start/stop toggle, and edit, so that I can
   see and control many processes at a glance.
7. As a user, I want grid cards to show the latest five output lines, so
   that I can spot problems at a glance without opening each process —
   without changing the card size, so the overview stays dense and square.
8. As a user, I want grid columns to adapt to the window width, so that the
   grid always fills the window without wastefully large or cramped cards.
9. As a user, I want to tap a grid card to open the process detail page, so
   that I can see output and full controls when I need them.
10. As a user, I want to long-press a grid card and drag it to reorder
    processes, so that I can arrange the grid without switching layouts.
11. As a user, I want to long-press a List-layout card and drag it to reorder
    processes, so that reordering keeps working without drag handles.
12. As a user, I want reordering in either layout to persist to the config,
    so that my order survives restarts.
13. As a user, I want to start/stop, edit, and copy the WebUI URL from grid
    cards directly, so that grid mode is not just a view.
14. As a user, I want the status dot on grid cards to reflect live process
    state, so that I can spot problems at a glance.
15. As a user, I want the Dashboard to open directly in Grid layout when the
    config already has `dashboard_layout: grid`, so that my preference is
    honored from the first frame.

## Implementation Decisions

- **Persistence**: `AppConfig` gains a two-valued layout field serialized as
  `dashboard_layout` (`list` | `grid`), defaulting to `list` when absent or
  invalid. It follows the existing globals pattern
  (`output_refresh_ms` / `output_history_limit`): loaded in the settings
  reload path, saved via the existing globals-only save path (no
  ProcessManager reload).
- **Globals round-trip**: the layout joins the globals set — it is read in
  the settings reload path and carried by **both** save paths (the
  globals-only save and the full save used by reorder/add/edit/duplicate).
  A new global lands in three places; missing one silently resets the
  preference when another global changes or processes are reordered.
- **Settings surface**: `SettingsViewModel` exposes the layout with a getter
  and a setter that persists through the globals path, mirroring the
  existing refresh-interval setting exactly.
- **Toggle button**: a single AppBar icon button on the Dashboard, visible
  only when processes exist and a settings viewmodel is present (same
  condition as the Add/Settings buttons); no duplicate entry in the
  Settings page.
- **List layout**: unchanged rendering; the `ReorderableListView` wraps
  each card in a long-press drag listener
  (`ReorderableDelayedDragStartListener`, `buildDefaultDragHandles: false`)
  so any point on a card can start a reorder drag, and the per-card drag
  handle widget is removed from `ProcessCard` (the `dragHandleIndex`
  parameter, the `ReorderableDragStartListener`, and the handle icon go
  away).
- **Grid layout**: the framework ships no reorderable grid (verified
  against Flutter 3.44.8 — only `ReorderableListView` exists), so the grid
  uses the third-party package **`flutter_reorderable_grid_view` 5.7.0**
  (verified 2026-08-04: score 160/160, 250 likes, ~31.7k downloads in the
  last 30 days, BSD-3, zero dependencies, Dart >=3.3.1 / Flutter >=3.3.0,
  Windows + Linux supported, actively released — 5.7.0 on 2026-05-31).
  The alternative `reorderable_grid_view` was rejected: its stable line is
  dead (2.2.8, 2023-11) with only an alpha branch since.
  The package exposes no `ReorderableGridView` widget — it provides
  `ReorderableBuilder`, which wraps **our own** `GridView` (supports
  `GridView.builder`): we keep the adaptive square grid
  (`maxCrossAxisExtent` ~280, 1:1 `childAspectRatio`) and wrap it in
  `ReorderableBuilder.builder`, sharing one `ScrollController` between the
  builder and the grid. Long-press drag is configured via `longPressDelay`
  (default 500 ms, matching the List layout's long-press); automatic
  scrolling at the grid edges while dragging is built in (~150 px zones),
  so reordering works even with many processes.
- **Index semantics**: the package's `onReorderPositions` delivers
  `ReorderUpdateEntity { oldIndex, newIndex }` pairs — final positions in
  the reordered list (pre-adjusted semantics, same contract the existing
  `reorderItem` expects). The Dashboard passes them through unchanged;
  if the resolved package version's semantics ever differ, indices are
  adapted at the Dashboard boundary so the settings seam stays untouched.
- **Shared actions**: the List card header and the grid card share the
  action button row (copy + toggle + edit). The grid card layers its
  content vertically to fill the square tile — status dot + label on top,
  name (and WebUI URL when present) in the middle, actions at the bottom.
- **Reorder writes back** through the existing settings reorder path; both
  layouts use the same callback and index semantics.
- **Schema ownership**: per ADR 003, the config schema is now
  TrayForge-owned; stale "Python compatible" mentions in the README and the
  config store doc comment are dropped as part of this work.

## Testing Decisions

- Tests assert external behavior only: what the user sees and what is
  persisted — not widget internals or which delegate was used.
- **Seam 1 — Dashboard widget tests** (existing dashboard screen test file):
  with a fake ConfigStore that records `save()` calls, cover: toggle button
  hidden when empty / shown when processes exist; tapping the button
  switches between the two layouts; grid cards render the latest five
  output lines (and nothing when there is no output) with working controls; tapping a grid card opens the detail
  page; long-press drag reorders in both layouts and persists the new order
  plus `dashboard_layout` to the saved config; a stored
  `dashboard_layout: grid` opens the Dashboard in Grid layout.
  Layouts are asserted via their public widget types; the grid package's
  internals are never tested, only the external behavior (order changes,
  persistence). Long-press drag is simulated with gesture timing (press,
  pump past the long-press threshold, move, release).
- **Seam 2 — AppConfig serialization tests** (existing foundation model
  test file): `dashboard_layout` round-trips `list` and `grid`; defaults to
  `list` when absent or invalid.
- **Obsolete tests removed**: the drag-handle assertions in the dashboard
  screen tests and the process card tests (handle shown/hidden cases) are
  replaced by the long-press behavior tests above.
- No new seam; the `SettingsViewModel` getter/setter is thin glue exercised
  through Seam 1, matching how the refresh-interval setting is covered
  today.

## Out of Scope

- Settings-page entry for the layout (single AppBar entry only).
- Configurable card size or column count.
- Configurable output preview length in Grid layout (fixed at five lines).
- Animation/transition polish beyond Flutter's built-in reorder feedback.
- Touch-specific optimizations (this is a desktop app).
- Python trayforge schema parity (dropped by ADR 003).

## Further Notes

- The tray menu, process detail page, and edit flow are unaffected.
- The layout preference lives in the config file, so editing
  `dashboard_layout` manually also works.
- Long-press drag on desktop requires holding the mouse button past the
  long-press threshold before dragging; this is the same interaction in
  both layouts, so there is one mental model.
