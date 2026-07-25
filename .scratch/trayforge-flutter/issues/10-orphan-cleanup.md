# 10 — Orphan Cleanup: 启动时 kill 上次残留的子进程

**What to build:** When trayforge starts, detect and kill child processes left behind from a previous crash/non-clean exit. This single fix closes two deferred gaps from issue 05.

**Blocked by:** 05 — ProcessManager Resilience

**Status:** done

---

## Motivation

Issue 05 deferred two things:

- **05-D5**: `delete_before_start` locked-file kill+retry — if the file to delete is held by a process, the current code logs a message and skips. The lock holder is almost certainly a trayforge child from a previous run.
- **05-D9**: Kill stale zombies — `_cleanupStalePidFiles` detects orphans (process alive + startTime matches our PID file) but only deletes the `.pid` file; it never kills the process.

These are the same root cause: previous trayforge crash → child processes live on → next launch can't clean up. Fixing one fixes both.

No external tools are needed. The PID files already have all the info (pid + startTime). `ProcessRunner` already has `isPidAlive()` and `getProcessStartTime()`. The same `taskkill /t /f` / `pkill -P` that `stop()` uses can do the kill.

---

## Task List

- [x] **`_cleanupStalePidFiles`: kill matched orphans.** When a PID file has `pid` alive AND `startTime` matches (within 2s tolerance, same as existing check), kill the process with the same platform dispatch `stop()` uses — don't just delete the file.
- [x] **Remove the stale `.pid` file after kill** (already done for the non-alive and PID-reuse cases).
- [x] **System message** logged when an orphan is killed, e.g. `[trayforge] Process "X": killed orphaned instance from previous session (PID <n>)`.
- [x] **Update `_deleteBeforeStartFiles`**: after the orphan kill runs during startup, locked files for deleted orphans are naturally released. Add a note in code that the locked-file case is now handled by the startup orphan cleanup; keep the existing log-and-continue as a safety net for truly external lock holders.
- [x] **Tests**: verify orphans are killed on startup, non-orphans (different startTime) are left alone, and `delete_before_start` files from killed orphans are deletable.

---

## Notes

- This closes both 05-D5 and 05-D9.
- No new dependencies, no bundled tools. Everything needed is already in `ProcessManager` and `ProcessRunner`.
- The `_cleanupStalePidFiles` fire-and-forget async pattern (manual `pending` counter) is already in place; the kill call slots into the existing `.then()` chain.
