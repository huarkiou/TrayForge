# 06 — Tray + Window Shell: 托盘图标 + 窗口骨架

**What to build:** The first UI ticket. TrayForge launches silently to the system tray. The tray icon shows green/yellow/red based on process health. Right-click menu lets users toggle processes and open the dashboard. The main window exists but shows no process data yet — just a placeholder.

**Blocked by:** 04 — ProcessManager Core, 02 — ConfigStore

**Status:** done (commit `80b8522`)

- [x] App starts with `windowManager.hide()` — no window flash, only tray icon visible
- [x] Tray icon works: three colour states (red/yellow/green), determined by process states — all running → green, some running → yellow, none running → red
- [x] Three static PNG assets loaded from `assets/icons/`: `icon-red.png`, `icon-yellow.png`, `icon-green.png` (generate from Python `icon.py` logic)
- [x] App window icon set to `assets/icon.ico` (reused from Python TrayForge)
- [x] Right-click tray menu: dynamic process name list (each item = start/stop toggle with current state indicator), then "Dashboard", then "Exit"
- [x] Clicking a process name in tray menu toggles start/stop
- [x] "Dashboard" opens the main window (`windowManager.show()` + `windowManager.focus()`)
- [x] "Exit" stops all running processes, cleans up, then quits
- [x] Double-click tray icon opens Dashboard
- [x] Close button on window intercepts → hide to tray instead of quitting
- [x] Dashboard window shows app title "TrayForge" and placeholder body
- [x] Tray tooltip set to "TrayForge" with `trayManager.setToolTip()`

## Decisions

> Recorded 2025-07-25 during implementation and code review.

### D1: Manual DI with `late final` module-level globals

Services and ViewModels are stored as `late final` top-level variables in
`main.dart`, initialised in the async `main()` function. This is the
Program.cs style mandated by the spec — no DI container, no service locator.
The `late final` pattern gives compile-time null safety while allowing
initialisation order to depend on async setup.

### D2: Double-click detection lives in `_AppTrayListener`, not `TrayViewModel`

`tray_manager` has no built-in double-click event. Detection (two
`onTrayIconMouseDown` within 400ms) is implemented in the platform listener
class `_AppTrayListener`, not the ViewModel. Rationale: double-click is a
platform-level input event, not application state. It was originally
duplicated in `TrayViewModel.handleIconMouseDown()` but removed during
code review — dead code with no callers.

### D3: Tray colour computed reactively from state streams

`TrayViewModel` subscribes to `ProcessManager.stateStream(name)` for each
configured process. On any state transition, `_recomputeColor()` counts
running processes: all → green, some → yellow, none → red. The
`ChangeNotifier` fires, and the listener in `main.dart` pushes the new icon
and menu to `trayManager`. No polling.

### D4: `_showDashboard()` awaits show → focus in order

`windowManager.show()` and `windowManager.focus()` are both async. The
original fire-and-forget (`void _showDashboard()`) could race — `focus()`
might complete before `show()`. Changed to `async` with sequential `await`
to guarantee correct ordering. Low-risk in practice but zero-cost to fix.

### D5: `onExit()` fire-and-forget is correct by platform design

`handleMenuItemClick()` calls `onExit()` (which returns `Future<void>`)
without `await`. This is not a bug: `TrayManager._methodCallHandler` does
not await listener callbacks, so adding `await` in the ViewModel wouldn't
block the platform channel. `_exitApp()` runs to completion independently
and calls `windowManager.destroy()` at the end.

### D6: `_states` map cleared + seeded from `getState()` on config reload

When `_rebuildSubscriptions()` runs (config change), `_states` is now
cleared to remove stale entries for deleted processes. Each entry is then
immediately seeded via `_processManager.getState(name)` — a synchronous
call that gives the authoritative current state. This prevents both a
memory leak (stale entries) and a brief colour flash (all-red until the
first async `stateStream` event fires).

### D7: `DashboardViewModel` is a plain class until ticket 07

Originally extended `ChangeNotifier` but never called `notifyListeners()`.
Removed during code review — the class has only a `static const appTitle`
and no instance state. Will add `ChangeNotifier` back when ticket 07
introduces process card management state.

### D8: Window close intercepted via `setPreventClose` + `WindowListener`

`windowManager.setPreventClose(true)` prevents the native close button from
destroying the window. `_AppWindowListener.onWindowClose()` calls
`windowManager.hide()` instead. The `_AppWindowListener` is a named class
(rather than anonymous) because `WindowListener` is a mixin — Dart does not
allow anonymous mixin application.

### D9: Tray menu dispatched by string key prefix

Menu items use key prefixes: `proc:<name>` for process toggles, `dashboard`
for show, `exit` for quit. String matching with `startsWith('proc:')` is
simpler than an enum or lookup table for 3 item categories. The `proc:`
prefix avoids collisions with future fixed items.

### D10: `icon-app.png` removed — scope creep

The Python `gen_icons.py` originally generated a blue `icon-app.png` from
`icon.py`'s `get_app_icon()` function. Removed during code review: the spec
only asks for three colour PNGs (green/yellow/red) plus `icon.ico` for the
window. AGENTS.md: "No features beyond what was asked."

### D11: Menu dispatch via `onClick` closures, not string-key matching

Originally `handleMenuItemClick()` dispatched by `menuItem.key` prefix
(`'proc:'`, `'dashboard'`, `'exit'`). Replaced with `onClick` closures
set in `buildMenu()` — each `MenuItem` carries its own callback, captured
at construction time. This eliminates a 14-line dispatch method, removes
the `onTrayMenuItemClick` listener override (the `tray_manager` already
calls `menuItem.onClick` before the listener), and makes the binding
compile-time safe — a typo in a closure capture is a Dart analyser error,
while a typo in a string prefix is a silent runtime no-op. The `_AppTrayListener`
now handles only double-click detection; menu actions are self-contained
in the MenuItems themselves.

### D12: Tray update errors logged via `.catchError`, not silently swallowed

`_onTrayStateChanged()` calls `trayManager.setIcon()` and `setContextMenu()`
without `await` (fire-and-forget — correct, since the platform channel
doesn't await listener callbacks). Previously, if either call failed
(e.g. platform channel disconnected during exit), the error was silently
swallowed as an unhandled future exception. Now each call chains
`.catchError((e) => _logger.log(...))` so failures appear in `trayforge.log`.
Non-critical — tray updates are cosmetic — but zero-cost observability for
production debugging.

### D13: No config caching in `buildMenu()` — premature optimization

`buildMenu()` calls `_configStore.load()` on every invocation (each tray
state change). Considered caching the `AppConfig` in a field and
invalidating on `configChanged`, but rejected: the config file is small
(a few KB), `load()` is a synchronous JSON parse from disk, and tray menu
rebuilds are infrequent (process start/stop/config reload). Adding a cache
layer with invalidation logic would be more code than the optimization
saves. Revisit only if profiling shows measurable latency.
