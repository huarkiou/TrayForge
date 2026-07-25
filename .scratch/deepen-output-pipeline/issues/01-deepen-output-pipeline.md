# 01 — Create BufferedOutputPipeline + switch ProcessManager & ProcessViewModel

**What to build:** A new `BufferedOutputPipeline` module that owns the full output processing chain (ANSI strip, WebUI detection, buffering, timed flush), replacing the scattered logic in ProcessManager's `_ProcessRuntime` and `_onOutputLine` / `_startFlushTimer`. ProcessViewModel subscribes directly to its pipeline's WebUI stream instead of a global relay.

**Blocked by:** None — can start immediately.

**Status:** done

- [x] `BufferedOutputPipeline` class in `foundation/output_pipeline.dart` with full interface (output stream, WebUI stream, addLine, push, flush control, clear, dispose)
- [x] Unit tests for `BufferedOutputPipeline`: ANSI strip, WebUI detection, buffer trimming, flush timer, clear, push bypasses buffer
- [x] `_ProcessRuntime` simplified: three fields + one method → one `pipeline` field
- [x] `outputStream`, `clearOutput`, `flushNow` delegate to pipeline
- [x] `start()`: create pipeline before `_lookupConfig`, configure with fresh config, wire process output to pipeline.addLine
- [x] Remove `_onOutputLine`, `_startFlushTimer`, `_webuiController`, `WebUiEvent` class
- [x] New `webUiStream(String name)` on ProcessManager
- [x] ProcessViewModel subscribes to `webUiStream(name)` instead of `onWebUiDetected`; no name filtering
- [x] All 234 tests pass
