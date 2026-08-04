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

- [x] Long-press a grid card and drag: tiles reorder with animation
- [x] The new order persists to config.json through the same path as the
      List layout
- [x] Index semantics verified against the resolved package version; the
      settings contract unchanged
- [x] Dragging near the grid edges auto-scrolls
- [x] Widget test: long-press drag reorder in the grid + persistence

## Comments

### 2026-08-04 — code review (minor findings, non-blocking)

Standards axis:
- `flutter_reorderable_grid_view: 5.7.0` is exact-pinned while sibling
  deps use caret ranges — ticket explicitly requires the pin; accepted.
- The grid tests repeat the `configStore` + `dm` + `sm` + `pumpWidget`
  setup block again (third ticket); the duplication across the file has
  now crossed the extraction threshold — addressed by a follow-up:
  `pumpDashboard` helper + merged fakes.
- Two doc-comment inaccuracies (fade-in/index-recording mechanism;
  `longPressDrag` described as List-only): fixed in-place.
- `_FakeConfigStore` and `RecordingConfigStore` overlap as
  `Fake implements ConfigStore`; the private fake is now gone — the
  follow-up uses one recording store everywhere.

Spec axis:
- Index semantics verified against the resolved package source
  (`handleDragEnd` → `newIndex = updatedOrderId`, the final resting
  position; package docs consume it as `removeAt(oldIndex);
  insertAt(newIndex)`): pass-through unchanged, settings seam untouched.
- Long-press drag still only proven via touch-kind gesture simulation;
  mouse-kind reorder tests (both layouts) added in the follow-up.
- Grid card edit / WebUI-copy were asserted by presence only; action
  tests (edit → edit page, copy → snackbar) added in the follow-up.
- Residual risk: if `lockedIndices` is ever enabled, the package emits
  multiple entities per drag and the `for` loop / save semantics must be
  re-verified. Not actionable now.

### 2026-08-04 — follow-up cleanups (this ticket's review findings)

- `pumpDashboard` test harness extracted; `_FakeConfigStore` merged into
  `RecordingConfigStore`; `longPressDrag` gained a pointer-kind
  parameter.
- Mouse-kind long-press reorder tests added for both layouts.
- Grid card action tests added (edit navigates; copy shows the snackbar).
- `spec.md` List-layout paragraph corrected to match the implemented
  `ReorderableDelayedDragStartListener` / `buildDefaultDragHandles: false`
  (was stale `buildDefaultDragHandles: true`).
- Second review (2026-08-04): mouse-kind and grid-action tests verified
  against real widget behavior; all 27 rewritten tests preserved their
  assertions; the unused `sm` field was dropped from the harness record.
- Closed as accepted (already recorded in #2/#3): long-press on a card
  button starts a reorder (quick taps win); `Status:` line stays
  `ready-for-agent`; `ProcessCard`/`ProcessGridCard` shell duplication
  kept for two call sites; layout decision derived twice; unobservable
  `isListLayout` null case.
