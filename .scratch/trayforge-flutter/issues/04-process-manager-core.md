# 04 — ProcessManager Core: 启停 + 输出流

**What to build:** The core process lifecycle engine. Start a configured process, capture its merged stdout/stderr as a stream, stop it killing the full process tree. No crash restart yet — that's ticket 05.

**Blocked by:** 01 — Foundation, 02 — ConfigStore

**Status:** done

- [x] `ProcessManager.start(name)` — reads `ProcessConfig` from ConfigStore, splits `cmd` via `shlex.split(posix: false)`, launches via `dart:io` `Process.start`
- [x] Encoding: `Process.start` uses configured encoding for stdout/stderr
- [x] Environment: merge per-process `env` dict with parent process environment, inject `PYTHONIOENCODING=utf-8`
- [x] Output stream: stdout+stderr read as `Stream<List<int>>`, decoded, merged into one line stream; lines buffered and batch-emitted at `output_refresh_ms` intervals
- [x] Output processing: each line → `OutputPipeline.stripAnsi` → `OutputPipeline.tryDetectWebUi` → push to per-process `StreamController<String>`
- [x] WebUI detection emits an event/callback with (name, url) for the tray and dashboard to consume
- [x] `ProcessManager.stop(name)` — platform-guarded kill: `taskkill /t /f /pid <pid>` on Windows, `pkill -P <pid>` + `process.kill(ProcessSignal.sigkill)` on Linux, then cleans up PID file
- [x] System messages (`[TrayForge] Process started`, `[TrayForge] Process stopped`, startup errors) pushed to the output stream
- [x] Start failures (cmd not found, cwd missing, encoding error) reported via system messages to output stream
- [x] Per-process state tracking: `ProcState` transitions (`stopped` → `starting` → `running` / `stopping` → `stopped` / `crashed` / `cooldown`)
- [x] State change callbacks so ViewModels can react

## Decisions

> Recorded 2025-07-25 during implementation and code review.

### D1: Broadcast controllers use `sync: true`

All `StreamController.broadcast()` instances in ProcessManager use `sync: true` so
events are delivered synchronously to listeners. Without this, state transitions
and system messages arrived in a later microtask, breaking tests that asserted
immediately after `await start()`.

### D2: `_mergeByteStreams` controller is sync

The internal merge controller for stdout+stderr also uses `sync: true`.
Production behaviour is unchanged (real process streams are async, and the sync
controller merely avoids an extra microtask inside the pipeline). Tests benefit
because mock controllers can now deliver bytes synchronously through the entire
transform chain.

### D3: System messages bypass output buffer

`_pushSystemMessage` writes directly to the `StreamController`, not through the
`_outputBuffers` / flush-timer path. Rationale: system messages are control-plane
events (start/stop/crash) that should appear immediately, not be batched at
`output_refresh_ms` intervals with process output.

### D4: `reloadConfig()` removed

Was a no-op stub. Belongs to ticket 05. Added when needed.

### D5: `IProcessRunner` / `IProcessHandle` kept as abstract classes

Spec explicitly requires the `IProcessRunner` abstraction for testability.
Not speculative generality — the testing strategy depends on it.

### D6: Per-process state tracked via parallel Maps

8 `Map<String, ...>` fields (`_states`, `_handles`, `_manualStopFlags`,
`_outputControllers`, `_outputBuffers`, `_flushTimers`, `_outputSubscriptions`,
`_stateControllers`). Considered bundling into a `_ProcessRuntime` class but
deferred: 05 will add more per-process fields. Bundling then will have better ROI.

### D7: `delete_before_start` model type fixed here

Changed `bool` → `List<String>` (bug from ticket 01). Runtime deletion logic
belongs to ticket 05.

### D8: Output history limit enforced in ProcessManager

Spec says "avoids Shell's internal unbounded memory accumulation". This is a
service-level memory-safety concern, not just a UI display preference.

### D9: No PID-reuse guard yet

PID file includes `startTime` in JSON, ready for verification. The guard itself
(cross-session stale PID detection) is a crash-restart concern — ticket 05.

### D10: Mock stream controllers use `sync: true` + `flushNow()`

Test mock stdout/stderr controllers are sync, so `emitStdout`/`emitStderr`
deliver bytes synchronously through the pipeline. A `@visibleForTesting
flushNow()` method replaces `Future.delayed` waits for the flush timer — tests
are deterministic and instant.
