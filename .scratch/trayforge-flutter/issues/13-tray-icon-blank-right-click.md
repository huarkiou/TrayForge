# 13 — Tray Icon Blank + Right-Click Dead

**What to fix:** Tray icon displays blank (empty space), and right-clicking the tray icon shows no context menu. Left-click / double-click works (opens Dashboard).

**Root cause:**

1. **Blank icon:** `tray_manager` Windows plugin uses `LoadImage(..., IMAGE_ICON, LR_LOADFROMFILE)` which only supports `.ico` files. The app was passing `.png` paths — `LoadImage` returns NULL, `nid.hIcon` is NULL, `Shell_NotifyIcon` registers an empty icon.

2. **Right-click dead:** The plugin fires `onTrayIconRightMouseDown` on `WM_RBUTTONUP`, but does NOT auto-pop the context menu. The app must call `trayManager.popUpContextMenu()` in response. `_AppTrayListener` did not override `onTrayIconRightMouseDown`.

**Status:** done

- [x] `scripts/gen_icons.py` — generate `.ico` with 4 sizes (16/32/48/64) via Pillow
- [x] `pubspec.yaml` — register `.ico` assets
- [x] `lib/viewmodels/tray_viewmodel.dart` — `iconPath` returns `.ico` paths
- [x] `lib/main.dart` — `_AppTrayListener.onTrayIconRightMouseDown()` calls `trayManager.popUpContextMenu()`

## Decisions

### D1: ICO format required by Win32 `LoadImage`

`tray_manager_plugin.cpp` line 199:

```cpp
nid.hIcon = static_cast<HICON>(
    LoadImage(nullptr, iconPath.c_str(),
              IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
              GetSystemMetrics(SM_CYSMICON), LR_LOADFROMFILE));
```

`IMAGE_ICON` parameter only loads `.ico` files. `.png` fails silently (NULL handle).
Switched tray icons from `.png` to `.ico`. PNGs kept for potential preview use.

### D2: Context menu is opt-in, not automatic

`tray_manager` plugin does NOT show the context menu on right-click — it only fires
`onTrayIconRightMouseDown`. The app must explicitly call `trayManager.popUpContextMenu()`.
This is by design (the Dart side controls when/if to show).
