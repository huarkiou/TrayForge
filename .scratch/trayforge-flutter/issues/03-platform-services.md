# 03 — Platform Services: SingleInstance + Autostart

**What to build:** Two platform-level services that operate independently. Single instance prevents double-launch. Autostart lets the user configure trayforge to launch at OS boot.

**Blocked by:** 01 — Foundation (needs Logger)

**Status:** done

- [x] `SingleInstance.tryAcquire()` — Windows: named mutex `Local\trayforge_SingleInstance` (no elevation needed; `Global\` requires `SeCreateGlobalPrivilege`); Linux: PID-based file lock on `{data_dir}/instance.lock` with `kill -0` stale detection. Returns `true` if first instance, `false` if already running
- [x] `SingleInstance.release()` — cleanly release the lock on exit
- [x] `SingleInstance.signalFirstInstance()` / `checkForWakeSignal()` — second instance writes wake marker; first instance polls to bring window to foreground
- [x] `Autostart.isEnabled()` — Windows: check `HKCU\...\Run\trayforge` registry value; Linux: check `~/.config/autostart/trayforge.desktop` exists
- [x] `Autostart.enable()` — write autostart entry pointing to current executable
- [x] `Autostart.disable()` — remove autostart entry, no error if already absent
- [x] All platform-specific code guarded with `Platform.isWindows` / `Platform.isLinux`
