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
