# 14 — Exit Logic: Cursor Spin + Process Lingers

**Symptoms:**

1. Clicking "Exit" causes the mouse cursor to spin (busy/waiting).
2. Exit → immediately restart → exit again causes the main window to hang
   for 10+ seconds before closing.
3. After exit, `trayforge_flutter.exe` lingers in Task Manager for 10+ seconds
   before disappearing.

**Root cause (two bugs):**

1. **`Timer.periodic` never cancelled:** A 1-second periodic timer polls
   `_singleInstance.checkForWakeSignal()`. This timer keeps the Flutter
   event loop alive indefinitely after `windowManager.destroy()`. The
   process remains running as a zombie — no window, but the event loop
   churns, and Windows shows the spinning cursor for the hung process.

2. **`_singleInstance.release()` called too early:** The mutex was released
   *before* `trayManager.destroy()` and `windowManager.destroy()`. A second
   instance could acquire the lock and start while the first was still
   tearing down tray/window resources.

**Status:** done

- [x] Store `Timer` reference from `Timer.periodic`, cancel it at the start of `_exitApp()`
- [x] Move `_singleInstance.release()` after `trayManager.destroy()` and `windowManager.destroy()`
- [x] Add explicit `exit(0)` after all cleanup completes

## Decisions

### D1: `exit(0)` required — Flutter desktop does not auto-exit

Unlike mobile platforms, Flutter on Windows does not terminate the process
when the last window is destroyed. The engine's message loop continues
running. An explicit `exit(0)` (from `dart:io`) is the simplest way to
ensure clean process termination.

### D2: Timer cancellation order

The wake-signal timer is cancelled *first* in `_exitApp()`, before process
stopping or resource cleanup. This prevents any late `_showDashboard()`
call from racing with window destruction.
