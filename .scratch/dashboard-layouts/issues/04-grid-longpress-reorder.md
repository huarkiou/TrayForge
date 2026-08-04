# 04 — Grid long-press reorder

**What to build:** Grid layout supports long-press drag reordering with
animations, writing back through the existing reorder path so the order
persists exactly like the List layout's. Adds the third-party package
`flutter_reorderable_grid_view` (pinned 5.7.0 — actively maintained, zero
dependencies, verified 2026-08-04). The grid is wrapped in the package's
builder, sharing a scroll controller with the grid. Long-press delay stays at
the package default (500 ms, matching the List layout). Dragging near the
grid edges auto-scrolls. The package's `onReorderPositions` index semantics
are verified against the resolved package version; if they differ from the
existing pre-adjusted contract, indices are adapted at the Dashboard
boundary so the settings seam stays untouched.

**Blocked by:** 03 (the grid must exist before it can be made draggable)

**Status:** ready-for-agent

- [ ] Long-press a grid card and drag: tiles reorder with animation
- [ ] The new order persists to config.json through the same path as the
      List layout
- [ ] Index semantics verified against the resolved package version; the
      settings contract unchanged
- [ ] Dragging near the grid edges auto-scrolls
- [ ] Widget test: long-press drag reorder in the grid + persistence
