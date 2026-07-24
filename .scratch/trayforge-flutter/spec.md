# TrayForge Flutter — Spec

Status: `ready-for-agent`

## Problem Statement

TrayForge 的 Python/tkinter 版本 UI 丑陋、开发效率低、难以调试。Avalonia (C#) 重写因 MVVM 样板代码过多和调试体验差而夭折。需要一套开发效率高、调试友好的跨平台方案，功能对标现有 Python 版，UX 推倒重来。

## Solution

用 Flutter + Dart 全量重写。关键生态组件：`tray_manager`（系统托盘）、`window_manager`（窗口管理）。Windows + Linux 双平台，交互模型为托盘优先 + Dashboard 窗口。配置文件兼容 Python 版 JSON schema，用户可平滑迁移。

## User Stories

### 托盘交互
1. As a user, I want a tray icon that changes colour (green/yellow/red) based on process states, so that I can see system health at a glance
2. As a user, I want to right-click the tray icon to see a menu with each process name as a quick toggle (start/stop), so that I can control processes without opening the dashboard
3. As a user, I want the tray menu to include a "Dashboard" item to open the main window, so that I can inspect details when needed
4. As a user, I want the tray menu to include an "Exit" item, so that I can quit the application cleanly and stop all managed processes
5. As a user, I want to double-click the tray icon to open the Dashboard, so that I have a fast way to access details

### Dashboard — 进程卡片
6. As a user, I want the Dashboard to show a card for each configured process, so that I can see all processes at once
7. As a user, I want each card to display the process name and a running/stopped status indicator, so that I know the state immediately
8. As a user, I want each card to show the last N lines of process output, so that I can monitor recent activity without opening a detail view
9. As a user, I want each card to have a Start/Stop toggle button, so that I can control the process from the Dashboard
10. As a user, I want each card to show a "Open WebUI" button when a WebUI URL is detected, so that I can jump to the web interface in one click
11. As a user, I want to tap a card to expand it into a detail page, so that I can see full output and interact more deeply

### 进程详情页
12. As a user, I want the detail page to display the full output log of a process, so that I can review all historical output
13. As a user, I want new output to auto-scroll to the bottom, so that I can watch live output without manual intervention
14. As a user, I want auto-scrolling to pause when I manually scroll up, so that I can read older output without being pushed to the bottom
15. As a user, I want to search/filter the output log (Ctrl+F), so that I can find specific lines quickly

### Settings
16. As a user, I want to open Settings from the Dashboard (gear icon), so that I can manage process configurations
17. As a user, I want to add a new process with name, CWD, command line, and optional fields, so that I can bring new services under management
18. As a user, I want to edit an existing process configuration, so that I can adjust parameters as my setup changes
19. As a user, I want to delete a process configuration, so that I can remove services I no longer manage
20. As a user, I want to copy a process configuration as a starting point for a new one, so that I don't have to re-enter everything
21. As a user, I want to reorder processes (move up/down), so that they appear in my preferred order on the Dashboard

### 进程管理能力
22. As a user, I want processes to auto-restart on crash (with cooldown and max restart limit), so that my services stay online without manual intervention
23. As a user, I want singleton protection to prevent starting a process that is already running, so that I don't create duplicate instances
24. As a user, I want the application to detect WebUI URLs from process output using regex patterns, so that I can open web interfaces quickly
25. As a user, I want to specify files to delete before starting a process (e.g. lock files), so that stale locks don't block startup
26. As a user, I want to configure custom environment variables per process, so that I can pass credentials or other settings
27. As a user, I want to set per-process character encoding for output capture, so that non-UTF-8 programs (e.g. GBK on Chinese Windows) display correctly
28. As a user, I want to mark a process to auto-start when TrayForge launches, so that my essential services come up automatically

### 配置管理
29. As a user, I want my configuration to be saved to JSON (compatible with Python TrayForge), so that I can migrate without manual conversion
30. As a user, I want configuration to be backed up automatically before each save, so that I can recover from mistakes
31. As a user, I want old backups to be pruned when the backup directory exceeds 10MB, so that disk space is not wasted

### 应用生命周期
32. As a user, I want the application to start minimised to the tray (no window flash), so that it stays out of my way
33. As a user, I want the application to prevent running multiple instances, so that I don't accidentally start a second copy
34. As a user, I want optional autostart with the operating system, so that my processes are managed from boot
35. As a user, I want the application to write its own operational log to `trayforge.log`, so that I can debug TrayForge itself if something goes wrong

## Implementation Decisions

### Architecture
- **No state management framework** — plain Dart `ChangeNotifier` + `ListenableBuilder`. No BLoC, no Riverpod, no Provider
- **Manual DI** — `Program.cs`-style main function wires services → ViewModels → Views. No DI container
- **ViewModels** own the state; Views are thin Widget build functions that bind to ViewModel properties
- **ConfigStore** emits a change notification; ProcessManager subscribes and calls `reloadConfig`

### ProcessManager
- Start: `dart:io` `Process.start` with `workingDirectory`, `environment`, `runInShell: false`, `PYTHONIOENCODING=utf-8` injected
- `cmd` is a string in config; split via `shlex.split(posix=False)` before passing to `Process.start` (exact same logic as Python TrayForge)
- Stdout/stderr read as `Stream<List<int>>`, decoded with configured encoding, merged into one line stream (same behaviour as Python `stderr=subprocess.STDOUT`)
- Output buffering: lines accumulated in per-process buffer, emitted in batches at `output_refresh_ms` intervals (matching Python's drain/flush pattern) — prevents high-frequency UI updates and avoids Shell's internal unbounded memory accumulation
- Kill: platform-guarded inline commands — `taskkill /t /f /pid <pid>` on Windows (1 line), `pkill -P <pid>` + `process.kill(ProcessSignal.sigkill)` on Linux (2 lines). 3 lines total in ProcessManager, no external dependency
- Output pipeline: strip ANSI codes → detect WebUI URL via regex → push to per-process `StreamController`
- Crash restart: `proc.exitCode` future → check manual stop flag → check max restarts + cooldown → auto restart
- PID file: write `{data_dir}/pids/{name}.pid` (JSON with pid + startTime). Clean up on stop. Verify startTime on launch to prevent PID-reuse false positives

### Tray Management
- `tray_manager` 0.5.3 for all tray operations
- Three PNG assets: `icon-red.png`, `icon-yellow.png`, `icon-green.png` (reuse Python icon assets, resized)
- Tray menu built dynamically from process list + fixed items
- Color rule: all running → green; some running → yellow; none running → red
- Double-click tray: `trayManager.addListener(TrayListener(...onTrayIconMouseDown...))` → show Dashboard

### Window Management
- `window_manager` 0.5.2 for window control
- Main window: `windowManager.hide()` at launch → only tray visible
- Show Dashboard: `windowManager.show()` + `windowManager.focus()`
- Close button behaviour: intercept close → hide instead of quit
- Exit from tray menu: `windowManager.destroy()` + stop all processes

### Process Configuration Schema
- Compatible with Python TrayForge JSON (`name`, `cwd`, `cmd`, `encoding`, `singleton`, `autostart`, `webui_pattern`, `delete_before_start`, `max_restarts`, `env`)
- `cmd` is string (not array) — split via `shlex.split(posix=False)` before launch, same logic as Python TrayForge
- Global fields: `output_history_limit` (default 1000), `output_refresh_ms` (default 500)
- No `poll_interval_ms` — event-driven, no polling
- No `cleanup_cwd` — no CWD scanning in Flutter

### Dashboard Layout
- Scrollable vertical list of `ProcessCard` widgets
- Each card: material `Card` with `ListTile` for name + status dot + toggle button
- Card body: `Text` widget with last N lines (capped at ~15 lines), monospace font, `maxLines` with ellipsis
- WebUI button: `TextButton.icon` (content_copy icon) visible only when URL is detected; copies URL to clipboard via `Clipboard.setData`
- Tap card → `Navigator.push` to `ProcessDetailPage`

### Process Detail Page
- `AppBar` with process name + status + Start/Stop button + Copy WebUI button (clipboard)
- Body: `TextField`-style scrollable text area, monospace, read-only
- Search: `FloatingActionButton` or `IconButton` in AppBar to toggle search bar
- Auto-scroll logic: track `ScrollController.position.pixels` vs `maxScrollExtent`; if user scrolls up > 100px from bottom, lock; new output resets lock if near bottom

### Settings Page
- `Navigator.push` from Dashboard gear icon → `SettingsPage`
- Process list: reorderable `ListView` with swipe-to-delete
- Add button: FAB that pushes `ProcessEditPage`
- Each row: name + arrow → tap to `ProcessEditPage` for editing
- Process edit form: all fields as `TextFormField` with validation
- Save writes through `ConfigStore.save()`, which triggers `ProcessManager.reloadConfig()`

### Output Pipeline
- ANSI stripping: regex `\x1b\[[0-9;]*[a-zA-Z]` → replace with empty
- WebUI detection: user's configured regex, capture group 1 → URL
- System messages (start success, crash, restart limit reached): prefixed with `[TrayForge] ` and pushed to the same output stream

### Logging
- Application-level log only: `trayforge.log` written to `{data_dir}/logs/`
- Rotation: max 1MB per file, keep 3 backups
- No per-process log files — all process output is in-memory (viewable in Dashboard)

### Empty & Error States
- **No config file** (first launch): `ConfigStore.load()` returns null → show welcome screen: "No processes configured" + "Add Process" button → opens Settings
- **Corrupted config**: JSON parse error or schema mismatch → alert dialog "Config file is corrupted" + OK button → backup corrupted file to `backups/config.<timestamp>.corrupted.json`, fall back to welcome screen
- **All processes deleted**: after Settings save, if processes list is empty, Dashboard switches to welcome screen (same behaviour as first launch)
- **Process start failure** (cmd not found, cwd missing): error pushed to output stream as `[TrayForge]` system message — visible in the process card on Dashboard

### Configuration Storage
- Read/write from `TRAYFORGE_DATA_DIR` env var, fallback to platform defaults:
  - Windows: `%LOCALAPPDATA%/TrayForge/config.json`
  - Linux: `$XDG_DATA_HOME/TrayForge/config.json` or `~/.local/share/TrayForge/config.json`
- Backup before write: `backups/config.<timestamp>.json`
- Corrupted config backup: `backups/config.<timestamp>.corrupted.json`
- Prune: delete oldest files until total < 10MB
- Validation: name no `/` `\`; webui_pattern compiles as regex

### Single Instance
- Windows: named mutex
- Linux: file lock on `{data_dir}/instance.lock`

### Autostart
- Windows: registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- Linux: XDG `~/.config/autostart/TrayForge.desktop`

### Cross-Platform
- `Platform.isWindows` / `Platform.isLinux` guards for platform-specific paths, single instance, autostart
- Font: `Consolas` on Windows, system monospace fallback on Linux
- Kill process: platform-guarded inline commands — `taskkill /t /f /pid <pid>` on Windows (1 line), `pkill -P <pid>` + `process.kill(ProcessSignal.sigkill)` on Linux (2 lines). 3 lines total, no external dependency

### Removed vs Python Version
- No CLI mode — only GUI (tray + dashboard)
- No headless mode — only GUI
- No HTTP server
- No `cleanup_cwd`
- No `poll_interval_ms`
- No per-process independent log files — only `trayforge.log` for application-level logging

## Testing Decisions

### What makes a good test
- Test external behaviour, not implementation details
- Test at the highest seam possible
- ViewModels tested synchronously without Flutter widget tree
- Services tested against real filesystem or mocked external dependencies

### Modules tested
| Module | Technology | Mock |
|---|---|---|
| `ConfigStore` | xUnit-style Dart test + `test` package | Real temp filesystem |
| `OutputPipeline` | Dart test | Pure functions, no mock needed |
| `ProcessManager` | Dart test | Mock `IProcessRunner` abstraction over `dart:io` `Process.start` |
| `ProcessViewModel` | Dart test | Mock `ProcessManager` |
| `TrayViewModel` | Dart test | Mock `tray_manager` channel |
| `SettingsViewModel` | Dart test | Mock `ConfigStore` |

### Prior art
- Python TrayForge has 134 pytest tests (services + CLI + integration)
- Testing approach mirrors the Avalonia design's strategy: pure-logic services at unit level, ViewModels synchronous

### Not tested
- Widget/rendering tests (too brittle for this project size)
- Integration tests against real processes (run manually during development)

## Out of Scope
- CPU / memory monitoring
- Output timestamping or log-level colouring
- Per-process independent windows
- CLI / headless mode
- macOS support
- Search/filter preference persistence
- Per-process independent log files
- `cleanup_cwd` (CWD-based zombie cleanup)

## Further Notes
- The existing Python TrayForge codebase at `D:\Projects\Program\TrayForge` serves as functional reference
- The Avalonia design documents (`docs/superpowers/specs/2025-06-28-avalonia-rewrite-design.md`) serve as architectural reference for ProcessManager and service layer design
- Three-colour tray icons should reuse or replicate the existing Python `icon.py` generated icons
- Configuration JSON schema must remain backward-compatible so users can switch between Python and Flutter versions freely
