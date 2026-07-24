# 08 — Process Detail Page: 全量输出 + 搜索 + 自动滚动

**What to build:** Tapping a process card opens a full detail page with the complete output log. New lines auto-scroll to the bottom unless the user manually scrolls up. A search bar lets users filter output text.

**Blocked by:** 07 — Dashboard Cards

**Status:** ready-for-agent

- [ ] `ProcessDetailPage` with `AppBar` showing process name + status dot + Start/Stop button + Copy WebUI button (when URL available, copies to clipboard)
- [ ] Full output displayed in a scrollable, read-only, monospace text body
- [ ] Auto-scroll: when new output arrives and user is within ~100px of the bottom, auto-scroll to the latest line
- [ ] Scroll lock: if user manually scrolls up beyond the auto-scroll threshold, pause auto-scrolling; resume when user scrolls back near bottom
- [ ] Search bar: `IconButton` in AppBar toggles a search `TextField`; typing filters the displayed output lines to only those containing the search text (case-insensitive)
- [ ] Search bar dismissal clears the filter and shows all lines again
- [ ] Output is preserved when switching between cards and returning to the same detail page (ProcessViewModel holds the buffer, not the widget)
