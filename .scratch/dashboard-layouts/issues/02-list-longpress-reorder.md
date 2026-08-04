# 02 — List layout long-press reorder (drop drag handles)

**What to build:** List layout cards no longer show a drag handle. Any point
on a card can be long-pressed and dragged to reorder it, matching the
interaction the Grid layout will use. Reordering persists through the
existing settings reorder path. The obsolete drag-handle tests are replaced
by long-press behavior tests.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [x] No drag handle icon is rendered on List layout cards
- [x] Long-press + drag reorders processes in the List layout
- [x] The reordered order persists to config.json, asserted via a recording
      config-store fake introduced as a shared test helper (the existing
      fake only stubs `load()`, so it cannot verify persistence)
- [x] Tapping a card still opens the detail page; the toggle/edit/copy
      buttons still work (no interaction regression)
- [x] Drag-handle assertions replaced by long-press behavior tests

## Comments

### 2026-08-04 — code review (minor findings, non-blocking)

Standards axis:
- Mild Duplicated Code: `_FakeConfigStore` (dashboard_screen_test.dart) and
  `RecordingConfigStore` (test/helpers) overlap as `Fake implements
  ConfigStore`; left separate to keep the diff minimal.
- Mild Speculative Generality: `RecordingConfigStore.saved` / `lastSaved`
  used by only one test; `saved` list kept as the helper's core contract.
- `longPressDrag` helper is single-use but kept — it documents a
  non-obvious gesture sequence (nudge before move, per SDK behavior).

Spec axis:
- Long-press drag is only proven via touch-kind gesture simulation; the
  SDK's delayed recognizer accepts mouse devices, but no mouse-kind test
  exists yet.
- A long-press that starts on the toggle/edit button begins a reorder
  instead of pressing the button — matches "any point on a card"; quick
  taps still win.
