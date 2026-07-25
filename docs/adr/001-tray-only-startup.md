# ADR 001: Tray-only startup (no dashboard window on launch)

**Status:** Accepted  
**Date:** 2026-07-03

## Context

trayforge is a system-tray process manager. The primary interaction is via the
tray icon: start/stop processes, view state via color-coded icon, and
occasionally open the dashboard. Showing the dashboard window on every launch
is noise — the user launched the app to manage background processes, not to
see a window.

## Decision

The window is created hidden at the native level. It only becomes visible when
the user explicitly requests it (double-click tray icon or "Dashboard" menu
item).

### Implementation

**Root cause workaround removed.** Flutter's Windows embedder calls
`ShowWindow(hwnd, SW_SHOWNORMAL)` after the first frame via
`SetNextFrameCallback` in `flutter_window.cpp`. This was deleted:

```diff
- flutter_controller_->engine()->SetNextFrameCallback([&]() {
-     this->Show();
- });
```

With this callback removed, the native `Win32Window` is created but never
automatically shown. The `window_manager` Dart plugin controls visibility
via `windowManager.show()` / `windowManager.hide()`.

### Dashboard widget tree is always present

The `DashboardScreen` widget tree is built at startup and remains in the
widget tree for the lifetime of the process. It is hidden (window not shown)
but fully functional — state listeners, output buffering, everything runs.

**Why not lazy-load the dashboard?**

Attempted and reverted. The savings were negligible:

- The dashboard's widget tree is ~dozen lightweight widgets (Scaffold,
  AppBar, ProcessCards). Memory cost is a few KB.
- The heavy parts (ProcessManager, ProcessViewModel instances, output
  stream buffers, process handles) live at the service layer and exist
  regardless of dashboard visibility.
- Flutter skips painting for hidden windows, so the GPU cost is zero.
- Lazy-loading added a `ValueListenableBuilder` + widget swapping at the
  `MaterialApp.home` level. This caused layout corruption when swapping
  between structurally different widget trees (placeholder vs full
  Scaffold). The fix would require keeping an isomorphic Scaffold
  placeholder, which defeats the purpose — you'd be maintaining a
  parallel widget just to save a few widgets.

**No "delayed destroy" feature.** Also attempted and reverted for the
same reason. A tray app running 24/7 doesn't benefit from freeing a few
KB of widget memory after a timeout.

## Consequences

- `flutter_window.cpp` is modified from Flutter template — must be
  re-applied if the file is regenerated (e.g., Flutter upgrade).
- Future contributors might expect the window to be lazy-loaded. This
  ADR documents the intentional choice to keep it always present.
- If trayforge ever grows a very heavy dashboard (e.g., embedded WebView
  per process), this decision should be revisited.
