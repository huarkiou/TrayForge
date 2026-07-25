# Deepen OutputPipeline

## Problem

`OutputPipeline` is two static functions (`stripAnsi`, `tryDetectWebUi`) — interface equals implementation. Meanwhile, the buffering, history-limit trimming, flush-timer, and WebUI relay logic lives scattered across ProcessManager's private methods (`_onOutputLine`, `_startFlushTimer`, `_cleanup`) and `_ProcessRuntime` fields (`outputBuffer`, `outputController`, `flushTimer`, `flushBuffer`).

This is the wrong module boundary. The "output pipeline" concept should own everything from raw line to clean, buffered, timed stream — including WebUI detection.

## Design

### New: `BufferedOutputPipeline` (foundation/output_pipeline.dart)

A stateful module that owns the full output processing chain:

```
raw line → strip ANSI → detect WebUI → buffer (history limit) → flush timer → clean stream
```

Interface:
- `Stream<String> output` — cleaned, timed-flushed lines
- `Stream<Uri> onWebUiDetected` — per-pipeline WebUI detection, no relay needed
- `void addLine(String rawLine)` — strip + detect + trim
- `void push(String systemMessage)` — bypasses buffer, immediate emit
- `void startFlushTimer()` / `void stopFlushTimer()` — periodic flush control
- `void flushNow()` — drain buffer immediately
- `void clear()` — discard buffer
- `void dispose()` — close all streams

Configurable: `historyLimit`, `refreshMs`, `webuiPattern` (set before `addLine`).

### ProcessManager changes

**Remove:**
- `_onOutputLine` method
- `_startFlushTimer` method
- `_webuiController` field and `onWebUiDetected` stream
- `WebUiEvent` class

**`_ProcessRuntime`:**
- Replace `outputController` + `outputBuffer` + `flushTimer` + `flushBuffer()`
- With single `BufferedOutputPipeline? pipeline` field

**`outputStream`, `clearOutput`, `flushNow`:** delegate to pipeline.

**New `Stream<Uri> webUiStream(String name)`:** returns `pipeline.onWebUiDetected`.

**`start()`:** create pipeline before `_lookupConfig`; configure with fresh config; wire process output to `pipeline.addLine`.

**`_cleanup()`:** `pipeline.stopFlushTimer()` + `pipeline.flushNow()`.

**`_pushSystemMessage()`:** `pipeline?.push(...)`.

**`dispose()`:** remove `_webuiController.close()`.

### ProcessViewModel changes

- Subscribe to `processManager.webUiStream(name)` instead of `processManager.onWebUiDetected`
- Accept `Uri?` instead of `WebUiEvent`; no name filtering needed

### Design advantages

No relay → no `webuiRelaySub` field → no subscription leak on restart. Each ProcessViewModel subscribes directly to its own pipeline. When pipeline is disposed, subscription auto-completes.

## Restart behavior

Process crashes → `_cleanup()`:
1. `pipeline.stopFlushTimer()` — timer stopped
2. `pipeline.flushNow()` — drain remaining buffer
3. Pipeline survives, stream still open for ProcessViewModel

Crash restart → `start()`:
1. Pipeline already exists (created by `outputStream` in ProcessViewModel constructor)
2. `configure()` with fresh config values
3. `pipeline.startFlushTimer()` — new timer
4. Wire process output → `pipeline.addLine`
5. ProcessViewModel already subscribed to `webUiStream(name)` — live stream, no re-sub needed

No leaks, no dangling subscriptions, no silent message drops.
