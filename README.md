# TrayForge

[![Test](https://github.com/huarkiou/TrayForge/actions/workflows/test.yml/badge.svg)](https://github.com/huarkiou/TrayForge/actions/workflows/test.yml)

A Flutter desktop app that manages background processes from the system tray.
Define your processes in a JSON config, and TrayForge keeps them running — auto-start,
auto-restart on crash, and colour-coded tray icon at a glance.

## Features

- **System tray icon** — green when all processes are running, yellow when partially
  running, red when none are. Single-click the tray icon to toggle the management
  window; right-click for the context menu.
- **Start / stop processes** from the tray menu or the dashboard.
- **Dashboard layouts** — switch between a list of wide cards and a grid of
  compact square cards from the dashboard AppBar; reorder cards by long-press
  drag in either layout.
- **Inline process editing** — add, edit, duplicate, delete, and reorder processes
  directly from the Dashboard — no need to open Settings.
- **Auto-start** — processes with `autostart: true` launch when TrayForge starts.
- **Crash recovery** — configurable `max_restarts` with cooldown periods. Gives up
  after the limit and marks the process as crashed.
- **Output viewer** — merged stdout + stderr with ANSI-stripping, per-process
  scrollable output, and copy-to-clipboard.
- **Follow-latest log view** — the detail page tracks the newest output and
  scrolls along with it; scrolling up detaches the view, and scrolling back down
  resumes following.
- **WebUI detection** — set a `webui_pattern` regex and TrayForge captures the URL
  when your process prints it. Copy it from the process detail page.
- **Singleton enforcement** — prevent duplicate process instances (per-process or
  OS-level).
- **Working directory cleanup** — `cleanup_cwd` kills residual processes from the
  same working directory before starting a new instance.
- **Delete-before-start** — delete lock/persistent files before launching.
- **Single-instance app** — only one TrayForge runs at a time; starting a second
  instance brings the existing one to the foreground.
- **Corrupted config recovery** — detects corrupted `config.json`, backs it up, and
  alerts you instead of crashing.
- **Cross-platform** — Windows and Linux.

## Screenshots

**List layout** — wide cards with status, controls, and an output preview.

![Dashboard in list layout](docs/screenshots/dashboard-list.png)

**Grid layout** — compact square cards with the latest five output lines.

![Dashboard in grid layout](docs/screenshots/dashboard-grid.png)

**Detail page** — full output log with status and controls.

![Process detail page](docs/screenshots/detail-page.png)

## Configuration

TrayForge stores its config in `config.json` under the app data directory
（`%APPDATA%/trayforge/` on Windows, `~/.local/share/trayforge/` on Linux）.

### Example `config.json`

```json
{
  "output_history_limit": 1000,
  "output_refresh_ms": 500,
  "dashboard_layout": "list",
  "processes": [
    {
      "name": "NapCat",
      "cwd": "C:\\NapCat",
      "cmd": "napcat.exe",
      "singleton": true,
      "autostart": true,
      "webui_pattern": "WebUI started at (http://[\\d.:]+)",
      "max_restarts": 3
    },
    {
      "name": "AstrBot",
      "cwd": "C:\\AstrBot",
      "cmd": "astrbot.exe",
      "singleton": true,
      "autostart": true,
      "webui_pattern": "WebUI started at (http://[\\d.:]+)",
      "max_restarts": 3
    },
    {
      "name": "Redis",
      "cwd": "C:\\Redis",
      "cmd": "redis-server.exe",
      "singleton": true,
      "autostart": true,
      "cleanup_cwd": true,
      "delete_before_start": ["dump.rdb"]
    }
  ]
}
```

### Process fields

| Field                  | Type              | Description                                                                                        |
|------------------------|-------------------|----------------------------------------------------------------------------------------------------|
| `name`                 | `string`          | Display name. Must not contain `/` or `\`.                                                         |
| `cmd`                  | `string`          | Shell command to run. Split with shlex rules（quotes, escapes）.                                   |
| `cwd`                  | `string?`         | Working directory. Relative executables in `cmd` are resolved against this.                          |
| `autostart`            | `bool`            | Start this process when TrayForge launches.                                                        |
| `singleton`            | `bool`            | Prevent launching a second copy while one is running.                                              |
| `max_restarts`         | `int?`            | Max crash restarts before giving up. Cooldown between restarts is 60 seconds.                      |
| `webui_pattern`        | `string?`         | Regex to detect a Web UI URL in stdout/stderr. First capture group is the URL.                     |
| `cleanup_cwd`          | `bool`            | Kill residual processes from the same working directory before starting（uses FFI on Windows）.     |
| `delete_before_start`  | `string[]`        | Delete these files (relative to `cwd`) before launching. Path-escape safe.                         |
| `env`                  | `object?`         | Extra environment variables（merged on top of system env）.                                       |
| `encoding`             | `string?`         | Process output encoding. Defaults to UTF-8.                                                        |

### App-level fields

| Field                  | Type    | Default  | Description                                   |
|------------------------|---------|----------|-----------------------------------------------|
| `output_history_limit` | `int`    | `1000`   | Max output lines buffered per process.           |
| `output_refresh_ms`    | `int`    | `500`    | Interval (ms) for batching output line flushes.  |
| `dashboard_layout`     | `string` | `list`   | Dashboard arrangement: `list` (wide cards) or `grid` (compact square cards). |

## Usage

### Managing processes

All process management happens on the **Dashboard**:

- **Add** — click the `+` button in the AppBar or "Add Process" on the welcome screen
- **Edit** — click the pencil icon on any process card or in the detail page AppBar
- **Duplicate** — open edit form and click "Duplicate" to copy a process
- **Delete** — open edit form and click "Delete" (requires confirmation; warns if running)
- **Reorder** — long-press and drag a card to a new position
- **Start/Stop** — toggle button on each card or in the detail page

### Settings

The Settings page (gear icon) contains only global options:

- **Output refresh (ms)** — batch interval for output display (100ms steps, 100–5000)
- **History limit** — max output lines per process (500-line steps, 100–100000)
- **Dashboard layout** — arrange cards as a list or a grid
- **Launch at startup** — register TrayForge for OS-level autostart

## Build & Run

### Prerequisites

- Flutter SDK ≥ 3.12.2
- Windows: Visual Studio 2022 with "Desktop development with C++"
- Linux: `gtk3`, `libappindicator` (or similar tray support)

### Run in debug mode

```bash
flutter run -d windows
```

### Build release

```bash
# Windows
flutter build windows

# Linux
flutter build linux
```

Build output lands in `build/windows/x64/runner/Release/` (Windows) or
`build/linux/x64/release/bundle/` (Linux).

## Project structure

```
lib/
├── main.dart                          # Entry point, DI, window/tray lifecycle
├── foundation/
│   ├── models.dart                    # ProcState, ProcessConfig, AppConfig
│   ├── logger.dart                    # File-backed logger
│   ├── output_pipeline.dart           # ANSI stripping, WebUI URL detection
│   ├── shlex.dart                     # Shell-like command splitting
│   ├── process_cwd.dart               # FFI binding for process-cwd lookup
│   ├── process_cwd_win32.dart         # Windows: NtQuerySystemInformation
│   └── process_cwd_linux.dart         # Linux: /proc/<pid>/cwd
├── services/
│   ├── config_store.dart              # config.json read/write with backups
│   ├── process_controller.dart        # Per-process lifecycle state machine
│   ├── process_manager.dart           # Process lifecycle (start/stop/restart)
│   ├── process_runner.dart            # IProcessRunner + real + mock impls
│   ├── single_instance.dart           # Named mutex / lock file
│   └── autostart.dart                 # OS autostart registration
├── viewmodels/
│   ├── dashboard_viewmodel.dart
│   ├── tray_viewmodel.dart
│   ├── process_viewmodel.dart
│   └── settings_viewmodel.dart
├── screens/
│   ├── dashboard_screen.dart
│   ├── process_detail_screen.dart
│   ├── process_edit_page.dart
│   └── settings_page.dart
└── widgets/
    ├── process_card.dart
    ├── status_dot.dart
    ├── toggle_button.dart
    └── copy_snackbar.dart
```

## License

MIT
