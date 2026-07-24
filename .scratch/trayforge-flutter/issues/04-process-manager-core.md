# 04 — ProcessManager Core: 启停 + 输出流

**What to build:** The core process lifecycle engine. Start a configured process, capture its merged stdout/stderr as a stream, stop it killing the full process tree. No crash restart yet — that's ticket 05.

**Blocked by:** 01 — Foundation, 02 — ConfigStore

**Status:** ready-for-agent

- [ ] `ProcessManager.start(name)` — reads `ProcessConfig` from ConfigStore, splits `cmd` via `shlex.split(posix: false)`, launches via `dart:io` `Process.start`
- [ ] Encoding: `Process.start` uses configured encoding for stdout/stderr
- [ ] Environment: merge per-process `env` dict with parent process environment, inject `PYTHONIOENCODING=utf-8`
- [ ] Output stream: stdout+stderr read as `Stream<List<int>>`, decoded, merged into one line stream; lines buffered and batch-emitted at `output_refresh_ms` intervals
- [ ] Output processing: each line → `OutputPipeline.stripAnsi` → `OutputPipeline.tryDetectWebUi` → push to per-process `StreamController<String>`
- [ ] WebUI detection emits an event/callback with (name, url) for the tray and dashboard to consume
- [ ] `ProcessManager.stop(name)` — platform-guarded kill: `taskkill /t /f /pid <pid>` on Windows, `pkill -P <pid>` + `process.kill(ProcessSignal.sigkill)` on Linux, then cleans up PID file
- [ ] System messages (`[TrayForge] Process started`, `[TrayForge] Process stopped`, startup errors) pushed to the output stream
- [ ] Start failures (cmd not found, cwd missing, encoding error) reported via system messages to output stream
- [ ] Per-process state tracking: `ProcState` transitions (`stopped` → `starting` → `running` / `stopping` → `stopped` / `crashed` / `cooldown`)
- [ ] State change callbacks so ViewModels can react
