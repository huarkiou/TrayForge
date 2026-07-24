# 03 — Platform Services: SingleInstance + Autostart

**What to build:** Two platform-level services that operate independently. Single instance prevents double-launch. Autostart lets the user configure TrayForge to launch at OS boot.

**Blocked by:** 01 — Foundation (needs Logger)

**Status:** ready-for-agent

- [ ] `SingleInstance.tryAcquire()` — Windows: named mutex `Global\TrayForge_SingleInstance`; Linux: file lock on `{data_dir}/instance.lock`. Returns `true` if first instance, `false` if already running
- [ ] `SingleInstance.release()` — cleanly release the lock on exit
- [ ] `Autostart.isEnabled()` — Windows: check `HKCU\...\Run\TrayForge` registry value; Linux: check `~/.config/autostart/TrayForge.desktop` exists
- [ ] `Autostart.enable()` — write autostart entry pointing to current executable
- [ ] `Autostart.disable()` — remove autostart entry, no error if already absent
- [ ] All platform-specific code guarded with `Platform.isWindows` / `Platform.isLinux`
