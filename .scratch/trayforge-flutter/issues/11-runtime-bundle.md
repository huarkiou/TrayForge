# 11 — Bundle per-process Maps into `_ProcessRuntime`

**What to build:** Refactor the 8 parallel `Map<String, ...>` fields in ProcessManager into a single `Map<String, _ProcessRuntime>`. This was deferred from 04-D6; 05-D2 bundled the restart fields into `_RestartState`, but the remaining maps were left scattered.

**Blocked by:** 10 — Orphan Cleanup (to avoid merge conflicts)

**Status:** needs-triage

---

## Motivation

04-D6 deferred bundling 8 per-process Maps into a `_ProcessRuntime` class:

> "Considered bundling into a _ProcessRuntime class but deferred: 05 will add more per-process fields. Bundling then will have better ROI."

05-D2 bundled the restart-related trio (`_lastRestartTime`, `_restartCount`, `_cooldownTimers`) into `_RestartState`, but the remaining Maps were not bundled.

### Current state (9 Maps for per-process state)

| Map | Value type | Bundled? |
|---|---|---|
| `_states` | `ProcState` | — |
| `_handles` | `IProcessHandle` | — |
| `_manualStopFlags` | `bool` | — |
| `_restart` | `_RestartState` | ✅ 05-D2 |
| `_outputControllers` | `StreamController<String>` | — |
| `_outputBuffers` | `List<String>` | — |
| `_flushTimers` | `Timer` | — |
| `_outputSubscriptions` | `StreamSubscription<void>` | — |
| `_stateControllers` | `StreamController<ProcState>` | — |

### The problem

`_cleanup(String name)` must manually remove from 4 maps individually. A new field added to ProcessManager requires touching `_cleanup` and every place that creates a process entry. Forgetting one map causes resource leaks (unclosed controllers, orphaned timers).

---

## Task List

- [ ] Define `_ProcessRuntime` class holding all 8 unbundled fields + the already-bundled `_RestartState`
- [ ] Replace the 9 maps with a single `Map<String, _ProcessRuntime> _procs`
- [ ] `_cleanup()` calls a single `_procs[name]?.dispose()` that closes controllers, cancels timers/subscriptions, and removes the entry
- [ ] All existing `_states[name]` etc. reads/writes go through `_procs[name]` accessors
- [ ] Tests: existing ProcessManager tests pass without modification (refactor-only, no behavior change)

---

## Notes

- Pure refactor — zero functional change, zero test logic changes
- Wait until issue 10 lands first to avoid merge conflicts on `_cleanupStalePidFiles`
- Follows the same pattern as 05-D2 (`_RestartState`), just doing the rest
