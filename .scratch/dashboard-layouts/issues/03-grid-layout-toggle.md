# 03 — Grid layout + toggle button

**What to build:** A toggle button in the Dashboard AppBar switches between
List layout and Grid layout; its icon reflects the layout the user will
switch to. It is visible only when processes are configured. The Grid layout
renders square compact cards — status dot, name, WebUI copy, start/stop
toggle, edit; no output preview — in an adaptive grid (max tile extent about
280px, 1:1 aspect). Tapping a card opens the detail page; all card controls
work. The choice persists through the layout-persistence API and the
Dashboard opens in the stored layout on startup. The List card header and the
grid card share one header widget. Grid reordering is out of scope here —
order is fixed until the next ticket.

**Blocked by:** 01 (persistence API), 02 (handle-free shared header; both
tickets touch the same Dashboard screen and its tests)

**Status:** ready-for-agent

- [x] Toggle button visible only when processes exist (same visibility rule
      as the Add/Settings buttons); absent on the welcome screen
- [x] Tapping the button switches between List and Grid layout; the icon
      shows the target layout
- [x] Grid renders square compact cards: status dot, name, WebUI copy,
      toggle, edit; no output preview; columns adapt to window width
- [x] Tapping a grid card opens the detail page; card controls work
- [x] Layout choice persists; Dashboard opens in the stored layout on
      startup
- [x] Changing the layout does not reset other stored globals (refresh
      interval / history limit survive a toggle), asserted via the
      recording config-store fake
- [x] Widget tests cover button visibility, switching, grid rendering,
      tap-to-detail, and persistence (external behavior only)

## Comments

### 2026-08-04 — code review (minor findings, non-blocking)

Standards axis:
- Mild Duplicated Code: `ProcessCard.build` and `ProcessGridCard.build`
  share the whole `ListenableBuilder → Card → InkWell → Padding` shell
  (only margin/child differ). Left separate — the spec shares only the
  header widget; extracting a card shell would add abstraction for two
  call sites.
- Mild Duplicated Code (test): the new grid tests repeat the
  `configStore` + `dm` + `sm` + `pumpWidget` setup block ~8 times
  (~160 lines). Matches the file's established inline style; not
  extracted.
- Mild Repeated Switches: the layout decision is derived twice from the
  same source (`isListLayout` ternary in the AppBar;
  `layout == DashboardLayout.grid` in `_buildDashboardBody`). Two sites,
  same condition; harmless.
- Ticket `Status:` line left as `ready-for-agent` — matches how #1/#2
  were closed (checkboxes ticked, status untouched).

Spec axis:
- "Card controls work" is only partially exercised: start/stop action is
  tested; edit and WebUI-copy are asserted by presence only. All three
  share the already-covered `ProcessCardHeader` code path, so risk is
  low.
- Spec parenthetical "same condition as the Add/Settings buttons" is
  internally inconsistent — Add/Settings show even when empty; the
  toggle adds `!isEmpty`. Implementation follows the ticket's explicit
  visibility rule.
- `isListLayout` reads as `false` when `settingsViewModel == null`, but
  the button is hidden in that case — unobservable in practice.
- Pre-existing (from #2, already reviewed): spec prescribes
  `buildDefaultDragHandles: true` for the List layout; the committed
  code uses `ReorderableDelayedDragStartListener` with
  `buildDefaultDragHandles: false` — functionally equivalent long-press
  drag.
