# 05 — ProcessManager Resilience: 崩溃重启 + 防护

**What to build:** Crash recovery and safety guards on top of the core ProcessManager. Processes that die unexpectedly auto-restart (with limits). Duplicate launches are prevented. Lock files are cleaned before start. Processes can be marked to auto-start when TrayForge launches.

**Blocked by:** 04 — ProcessManager Core

**Status:** ready-for-agent

- [ ] Crash detection: when a process exits unexpectedly (not via manual `stop()`), trigger restart logic
- [ ] Restart with cooldown: 60-second cooldown between restarts; track `_lastRestartTime` per process
- [ ] Max restarts: respect `max_restarts` field; once exhausted, set state to `crashed` and emit system message `[TrayForge] NapCat: max restarts (3) reached, giving up`
- [ ] Manual stop flag: `stop()` sets `_manualStop = true` so the exit handler skips auto-restart
- [ ] Singleton check before start: `Process.getProcessesByName(executableName)` — if already running, log system message and skip
- [ ] PID file: on start, write `{data_dir}/pids/{name}.pid` as JSON `{"pid": 1234, "startTime": "2026-..."}`; on stop, delete file; on TrayForge launch, read PID files, verify startTime to prevent PID-reuse false positives, kill stale zombies
- [ ] `delete_before_start`: delete each file in list (relative to cwd), path escape check (resolved path must be within cwd subtree). If file is locked by a process, kill that process (by matching PID file) then retry delete
- [ ] Per-process autostart: when ProcessManager initializes or config is reloaded, iterate processes with `autostart: true` and call `start(name)`
- [ ] `ProcessManager.reloadConfig(config)` — hot-swap configuration without restarting already-running processes; start new autostart processes, stop processes no longer in config
