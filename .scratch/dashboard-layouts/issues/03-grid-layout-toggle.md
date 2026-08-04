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

- [ ] Toggle button visible only when processes exist (same visibility rule
      as the Add/Settings buttons); absent on the welcome screen
- [ ] Tapping the button switches between List and Grid layout; the icon
      shows the target layout
- [ ] Grid renders square compact cards: status dot, name, WebUI copy,
      toggle, edit; no output preview; columns adapt to window width
- [ ] Tapping a grid card opens the detail page; card controls work
- [ ] Layout choice persists; Dashboard opens in the stored layout on
      startup
- [ ] Changing the layout does not reset other stored globals (refresh
      interval / history limit survive a toggle), asserted via the
      recording config-store fake
- [ ] Widget tests cover button visibility, switching, grid rendering,
      tap-to-detail, and persistence (external behavior only)
