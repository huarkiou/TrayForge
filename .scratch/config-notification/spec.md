# Config notification refactor

## Problem

`ConfigStore.save()` broadcasts `configChanged` to all ViewModels, creating a reentrant loop:

```
SettingsViewModel._save()
  → ConfigStore.save()         → write disk + broadcast configChanged
    → SettingsViewModel._reload()   ← reentrant self-trigger
    → DashboardViewModel._rebuild()
    → TrayViewModel.onConfigChanged()
  → ProcessManager.reloadConfig()   → start/stop + emit state streams
    → DashboardViewModel._rebuild() ← second rebuild on same save
    → TrayViewModel                 ← second rebuild
  → notifyListeners()               ← third notification
```

Problems:
1. **Reentrancy**: `SettingsViewModel._save()` triggers `_reload()` mid-flow via broadcast
2. **Double-save**: `reloadConfig()` internally calls `save()` — config written twice per edit
3. **Stale `_procs` leak**: `reloadConfig()` never disposes runtime entries for deleted/renamed processes

## Design

Move notification responsibility from `ConfigStore` (persistence module) to `ProcessManager` (runtime coordinator). All config changes (including globals) take effect on next process start — no hot-apply needed.

### Path A: process list change (SettingsViewModel._save)

```
SettingsViewModel._save()
  → ConfigStore.save()              → write disk only
  → ProcessManager.reloadConfig()   → stop/start + cleanup stale _procs + emit onConfigReloaded
    → DashboardViewModel._rebuild()
    → TrayViewModel._rebuildSubscriptions()
    → SettingsViewModel._reload()
```

### Path B: globals-only change (SettingsViewModel._saveGlobals)

```
SettingsViewModel._saveGlobals()
  → ConfigStore.save()              → write disk only
  → notifyListeners()               → refresh Settings page
```

No `onConfigReloaded` — globals take effect on next process start, no runtime change needed.

### Path C: external reload (Tray menu)

```
TrayViewModel "Reload Settings"
  → ConfigStore.load()
  → ProcessManager.reloadConfig(loaded)  → stop/start + cleanup + emit onConfigReloaded
    → DashboardViewModel._rebuild()
    → TrayViewModel._rebuildSubscriptions()
    → SettingsViewModel._reload()
```

No disk write — reload only reads.

## Changes

### ConfigStore
- Remove: `configChanged` stream, `_configChangedController`, `reload()`, `dispose()`
- `save()` no longer fires any stream — write + backup + prune only

### ProcessManager
- New `Stream<void> onConfigReloaded` (broadcast, closed in `dispose()`)
- `reloadConfig(config)`: remove internal `save()` call, add stale `_procs` cleanup, emit `onConfigReloaded` at end
- `dispose()`: close `_onConfigReloadedController`

### SettingsViewModel
- Subscribe to `processManager.onConfigReloaded` instead of `configStore.configChanged`
- `_save()`: `configStore.save(newConfig)` → `processManager.reloadConfig(newConfig)` → `notifyListeners()`
- `_saveGlobals()`: `configStore.save(newConfig)` → `notifyListeners()` (no reloadConfig, globals apply on next start)

### DashboardViewModel
- Subscribe to `processManager.onConfigReloaded` instead of `configStore.configChanged`

### TrayViewModel
- Subscribe to `processManager.onConfigReloaded`
- Reload menu: `_configStore.load()` → `_processManager.reloadConfig(result)`

### main.dart
- Remove `configStore.configChanged.listen`

### ProcessEditPage (UI tip)
- When saving an edited process that is currently running, show snackbar:
  "Process is running — changes will take effect on next start"

## Caveats

- `SettingsViewModel._save()`: `reloadConfig()` emits `onConfigReloaded` → `_reload()` reads config it just wrote → `notifyListeners()`, then `_save()` itself calls `notifyListeners()` again. Two `notifyListeners`, harmless.
- Output refresh interval (`outputRefreshMs`) and history limit (`outputHistoryLimit`) only take effect when a process starts. The timer and buffer limit are set at `start()` time and not dynamically reconfigured for already-running processes.
