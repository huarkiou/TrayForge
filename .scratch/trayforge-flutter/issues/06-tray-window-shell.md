# 06 — Tray + Window Shell: 托盘图标 + 窗口骨架

**What to build:** The first UI ticket. TrayForge launches silently to the system tray. The tray icon shows green/yellow/red based on process health. Right-click menu lets users toggle processes and open the dashboard. The main window exists but shows no process data yet — just a placeholder.

**Blocked by:** 04 — ProcessManager Core, 02 — ConfigStore

**Status:** ready-for-agent

- [ ] App starts with `windowManager.hide()` — no window flash, only tray icon visible
- [ ] Tray icon works: three colour states (red/yellow/green), determined by process states — all running → green, some running → yellow, none running → red
- [ ] Three static PNG assets loaded from `assets/icons/`: `icon-red.png`, `icon-yellow.png`, `icon-green.png` (generate from Python `icon.py` logic)
- [ ] App window icon set to `assets/icon.ico` (reused from Python TrayForge)
- [ ] Right-click tray menu: dynamic process name list (each item = start/stop toggle with current state indicator), then "Dashboard", then "Exit"
- [ ] Clicking a process name in tray menu toggles start/stop
- [ ] "Dashboard" opens the main window (`windowManager.show()` + `windowManager.focus()`)
- [ ] "Exit" stops all running processes, cleans up, then quits
- [ ] Double-click tray icon opens Dashboard
- [ ] Close button on window intercepts → hide to tray instead of quitting
- [ ] Dashboard window shows app title "TrayForge" and placeholder body
- [ ] Tray tooltip set to "TrayForge" with `trayManager.setToolTip()`
