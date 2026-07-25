# ADR 002: Tray icon click behavior

## Status

Accepted

## Date

2025-07-21

## Context

The tray icon initially used double-click to open the dashboard and right-click for the context menu. Two issues emerged:

1. **Double-click discoverability is poor** — users don't expect hidden desktop apps to require double-click on the tray icon. Single-click toggle is more common (e.g., Windows system tray for battery, volume, network).

2. **Context menu won't auto-dismiss** — clicking outside the app after opening the right-click menu did not close it. This is a known Windows shell requirement: `SetForegroundWindow` must be called before `TrackPopupMenu`, otherwise the menu fails to capture mouse input outside the app window.

## Decision

1. **Replace double-click with single-click toggle.** Single-click calls `windowManager.isVisible()` and toggles between `show()`/`hide()`. Double-click detection logic is removed entirely.

2. **Always call `SetForegroundWindow` before popup.** Pass `bringAppToFront: true` to `trayManager.popUpContextMenu()`. This has no visible side-effect (the window stays hidden) but satisfies the Windows shell requirement.

## Consequences

- Tray interaction is now simpler: one click = toggle, right-click = menu.
- Context menu behaves correctly on Windows (auto-dismisses on outside click).
- The `bringAppToFront: true` parameter is required due to a limitation in `tray_manager` 0.5.3 where `SetForegroundWindow` is gated behind that flag. If a future version of `tray_manager` always calls `SetForegroundWindow`, this parameter can be dropped.
