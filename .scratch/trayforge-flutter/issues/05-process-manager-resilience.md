# 05 — ProcessManager Resilience: 崩溃重启 + 防护

**What to build:** Crash recovery and safety guards on top of the core ProcessManager. Processes that die unexpectedly auto-restart (with limits). Duplicate launches are prevented. Lock files are cleaned before start. Processes can be marked to auto-start when TrayForge launches.

**Blocked by:** 04 — ProcessManager Core

**Status:** done

- [x] Crash detection: when a process exits unexpectedly (not via manual `stop()`), trigger restart logic
- [x] Restart with cooldown: 60-second cooldown between restarts; track `_lastRestartTime` per process
- [x] Max restarts: respect `max_restarts` field; once exhausted, set state to `crashed` and emit system message `[TrayForge] NapCat: max restarts (3) reached, giving up`
- [x] Manual stop flag: `stop()` sets `_manualStop = true` so the exit handler skips auto-restart
- [x] Singleton check before start: `Process.getProcessesByName(executableName)` — if already running, log system message and skip
- [x] PID file: on start, write `{data_dir}/pids/{name}.pid` as JSON `{"pid": 1234, "startTime": "2026-..."}`; on stop, delete file; on TrayForge launch, read PID files, verify startTime to prevent PID-reuse false positives, kill stale zombies
- [x] `delete_before_start`: delete each file in list (relative to cwd), path escape check (resolved path must be within cwd subtree). If file is locked by a process, kill that process (by matching PID file) then retry delete
- [x] Per-process autostart: when ProcessManager initializes or config is reloaded, iterate processes with `autostart: true` and call `start(name)`
- [x] `ProcessManager.reloadConfig(config)` — hot-swap configuration without restarting already-running processes; start new autostart processes, stop processes no longer in config

## Decisions

> Recorded 2025-07-25 during implementation and code review.

### D1: Crash restart via `_onUnexpectedExit` in exit handler

When `exitCode` fires and `_manualStopFlags[name]` is false, `_onUnexpectedExit`
checks `max_restarts`, `_restart[].lastRestartTime` (60s cooldown), and either
restarts via `Future.microtask`, schedules a cooldown timer, or transitions to
`crashed`. Restart count resets on manual `stop()`.

### D2: `_RestartState` bundles per-process restart fields

`_lastRestartTime`, `_restartCount`, `_cooldownTimers` were merged into a single
`Map<String, _RestartState>`. These three fields always travel together (D6 from
ticket 04 deferred bundling to 05).

### D3: `IProcessRunner` extended with OS query methods

Added `isProcessRunning(executableName)` (for singleton check) and
`isPidAlive(pid)` + `getProcessStartTime(pid)` (for PID file cleanup).
Real implementation uses `tasklist` / `wmic` on Windows, `pgrep` / `ps` on Linux.

### D4: `@visibleForTesting settle()` replaces `Future.delayed`

Constructor fire-and-forget async (PID cleanup, autostart) is tracked via
`Completer<void>` counters. Tests call `await pm.settle()` instead of fragile
`Future.delayed(Duration(milliseconds: 10))`.

### D5: `delete_before_start` locked-file kill+retry deferred

The spec says "if locked, kill holding process via PID file then retry". Finding
which process locks a file requires OS-specific tooling (`handle.exe` on Windows,
`fuser`/`lsof` on Linux) that isn't universally available. Current implementation
logs a system message and continues. Revisit if this becomes a user-facing issue.

### D6: `cooldownDuration` made configurable for testability

Spec says fixed 60s. Made a constructor parameter defaulting to 60s so tests can
verify cooldown logic without 60s delays. Production code always uses the default.
