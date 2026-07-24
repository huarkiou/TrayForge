# 07 — Dashboard Cards: 进程卡片 + 启停 + 输出预览

**What to build:** The main dashboard fills with real process data. Each process gets a card showing status, last N output lines, and action buttons. Cards are navigable — tap one to push the detail page (even if detail page is not yet implemented, the navigation target can be a stub).

**Blocked by:** 06 — Tray + Window Shell, 05 — ProcessManager Resilience

**Status:** ready-for-agent

- [ ] `DashboardViewModel` (ChangeNotifier): holds list of `ProcessViewModel` instances, one per configured process
- [ ] `ProcessViewModel` (ChangeNotifier): mirrors `ProcState` from ProcessManager, exposes bounded output buffer (last N lines, limited by `output_history_limit`), exposes WebUI URL when detected, exposes toggle start/stop command
- [ ] Dashboard widget: if no processes configured, show welcome screen: "No processes configured" + "Add Process" button → opens Settings; if processes exist, show scrollable `ListView` of `ProcessCard` widgets
- [ ] Each ProcessCard: Material `Card` with name + status dot (green/grey/red circle) + start/stop toggle `IconButton`
- [ ] Card body: monospace text widget showing last ~15 lines of output, ellipsis at `maxLines`
- [ ] WebUI button: appears only when URL is detected, copies URL to clipboard via `Clipboard.setData`; shows brief snackbar "URL copied"
- [ ] Tap card → `Navigator.push` to detail page (stub `ProcessDetailPage` with just name in AppBar, "Coming soon" body)
- [ ] New output from ProcessManager stream pushes to ProcessViewModel's output buffer; trim old lines when exceeding `output_history_limit`
- [ ] Card toggle button: immediate visual feedback — stop button shows `stopping` state (spinner), start button shows `starting` state; reverts to actual state on ProcessManager callback (success or failure)
- [ ] When ConfigStore.configChanged fires and processes list becomes empty after reload, switch to welcome screen
- [ ] When corrupted config is detected on startup, alert dialog before showing welcome screen
