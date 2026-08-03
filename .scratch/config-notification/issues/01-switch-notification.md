# 01 — Switch notification: configChanged → onConfigReloaded + fix leak + clean ConfigStore

**What to build:** Eliminate the reentrant save→reload→rebuild loop by moving config-change notification from ConfigStore to ProcessManager. Repair the stale `_procs` memory leak in `reloadConfig()` along the way.

**Blocked by:** None — can start immediately.

**Status:** done (`44e72eb` — notification moved to ProcessManager.onConfigReloaded; ConfigStore is pure persistence; reloadConfig stale sweep in place)

- [ ] ConfigStore: remove `configChanged` stream, `_configChangedController`, `reload()`, `dispose()`; `save()` no longer broadcasts
- [ ] ProcessManager: add `onConfigReloaded` stream; `reloadConfig()` removes internal `save()`, cleans stale `_procs` entries, emits `onConfigReloaded`; `dispose()` closes the new controller
- [ ] SettingsViewModel: subscribe to `onConfigReloaded` instead of `configChanged`; `_save()` calls `save()` then `reloadConfig()`; `_saveGlobals()` calls `save()` then `notifyListeners()` only (no reloadConfig, globals apply on next start)
- [ ] DashboardViewModel: subscribe to `onConfigReloaded` instead of `configChanged`
- [ ] TrayViewModel: subscribe to `onConfigReloaded`; "Reload Settings" menu item calls `load()` → `reloadConfig()`
- [ ] main.dart: remove `configStore.configChanged.listen` line
- [ ] All 220 tests pass
