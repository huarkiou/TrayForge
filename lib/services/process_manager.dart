import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:trayforge/foundation/logger.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_controller.dart';
import 'package:trayforge/services/process_runner.dart';

/// Coordinates the lifecycle of configured processes.
///
/// Holds the name→[ProcessController] map (one controller per configured
/// Process), resolves the config once per start and passes the resolved
/// [AppConfig] + [ProcessConfig] as parameters, runs autostart, scans
/// stale pid files at init, and forwards per-Process calls to the
/// controllers. The per-Process state machine, launch sequence, restart,
/// pid file, and output wiring live in [ProcessController].
class ProcessManager {
  final ConfigStore _configStore;
  final IProcessRunner _processRunner;
  final String _dataDir;
  final Logger? _logger;

  /// Per-process controllers, one per configured Process.
  ///
  /// Materialized for every configured name at [init] and [reloadConfig]
  /// (diff-based); unknown names never appear here.
  final Map<String, ProcessController> _controllers = {};

  /// Names configured at the last [init] or [reloadConfig].
  ///
  /// The single source of truth for whether a name may have a controller.
  /// Never refreshed from disk on a miss: unknown and removed names stay
  /// truly inert (no phantom controller can be resurrected for them).
  Set<String> _configuredNames = {};

  // Config reload broadcast
  final StreamController<void> _onConfigReloadedController =
      StreamController<void>.broadcast(sync: true);

  /// A stream that emits whenever the config is reloaded via [reloadConfig].
  Stream<void> get onConfigReloaded => _onConfigReloadedController.stream;

  ProcessManager({
    required ConfigStore configStore,
    IProcessRunner? processRunner,
    String? dataDir,
    this._logger,
    this.cooldownDuration = const Duration(seconds: 60),
  })
    // ignore: prefer_initializing_formals
    : _configStore = configStore,
       _processRunner = processRunner ?? RealProcessRunner(),
       _dataDir = dataDir ?? Logger.getDataDir();

  /// Performs startup operations: stale PID cleanup and autostart.
  ///
  /// Call once after construction, before any other method.
  Future<void> init() async {
    await _cleanupStalePidFiles();
    final config = _configStore.load();
    if (config != null) _materialize(config);
    await _autostartAll();
  }

  String get _pidsDir => p.join(_dataDir, 'pids');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns a broadcast stream of processed output lines for [name].
  ///
  /// Inert (never emits) for names that are not configured.
  Stream<String> outputStream(String name) {
    return _controller(name)?.output ?? Stream<String>.empty();
  }

  /// Returns a broadcast stream of WebUI URL detections for [name].
  ///
  /// Each process gets its own detection stream — no relay or name
  /// filtering needed. Inert (never emits) for names that are not
  /// configured.
  Stream<Uri> webUiStream(String name) {
    return _controller(name)?.webUi ?? Stream<Uri>.empty();
  }

  /// Returns a broadcast stream of [ProcState] transitions for [name].
  ///
  /// Inert (never emits) for names that are not configured.
  Stream<ProcState> stateStream(String name) {
    return _controller(name)?.state ?? Stream<ProcState>.empty();
  }

  /// Returns the current [ProcState] for [name], or [ProcState.stopped].
  ProcState getState(String name) {
    return _controller(name)?.currentState ?? ProcState.stopped;
  }

  /// Starts the process named [name] using its current [ProcessConfig].
  ///
  /// Resolves the config from [ConfigStore] once and passes the resolved
  /// [AppConfig] + [ProcessConfig] to the process's [ProcessController].
  Future<void> start(String name) async {
    final controller = _controller(name);
    if (controller == null) {
      // Unknown name — no controller, no streams to report to. The
      // system-message path below needs a controller, so this is a
      // silent no-op (no phantom state is created).
      _log('Cannot start: process "$name" not found in config');
      return;
    }
    final resolved = _resolveConfigFor(name);
    if (resolved == null) {
      controller.pushSystemMessage(
        'Cannot start: process "$name" not found in config',
      );
      return;
    }

    await controller.start(resolved.config, resolved.procConfig);
  }

  /// Stops the process named [name].
  ///
  /// No-op for names without a materialized controller. Honours a stop
  /// issued while the process is still `starting` (pending-stop).
  Future<void> stop(String name) async {
    final controller = _controllers[name];
    if (controller == null) return;
    await controller.stop();
  }

  /// Toggles the process named [name]: stops if active (`running` |
  /// `starting`), starts if terminal (`stopped` | `crashed` | `cooldown`).
  ///
  /// Resolves the config from [ConfigStore] once (like [start]) and passes
  /// it to the controller, which owns the start/stop decision. Toggle
  /// during `starting` honours the pending-stop from ticket #3.
  Future<void> toggle(String name) async {
    final controller = _controller(name);
    if (controller == null) {
      // Unknown name — see [start]; no phantom state is created.
      _log('Cannot toggle: process "$name" not found in config');
      return;
    }
    final resolved = _resolveConfigFor(name);
    if (resolved == null) {
      controller.pushSystemMessage(
        'Cannot toggle: process "$name" not found in config',
      );
      return;
    }

    await controller.toggle(resolved.config, resolved.procConfig);
  }

  /// Cooldown duration between crash restarts.
  ///
  /// Configurable for testing; defaults to 60 seconds.
  final Duration cooldownDuration;

  /// Releases all resources: timers, subscriptions, controllers.
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _onConfigReloadedController.close();
  }

  /// Hot-swaps configuration without restarting already-running processes.
  ///
  /// Starts new processes that have `autostart: true` and are not already
  /// running, `starting`, or `stopping` — an in-flight launch or stop is
  /// never doubled up. Every removed Process is terminated and cleaned up
  /// via [ProcessController.applyRemoval] regardless of state — running,
  /// starting, cooldown, or mid-stop — so no orphaned OS process or stale
  /// pid file survives a config edit. Emits [onConfigReloaded] on
  /// completion.
  ///
  /// Does **not** write the config to disk — callers must [ConfigStore.save]
  /// beforehand if persistence is desired.
  Future<void> reloadConfig(AppConfig config) async {
    final newNames = config.processes.map((p) => p.name).toSet();

    // Removed names become inert immediately — before the removal loop's
    // first await — so a call into the manager mid-reload cannot
    // materialize a phantom controller for a name being removed (or
    // resurrect its pid file via a phantom launch).
    _configuredNames = newNames;

    // Every removed Process goes through applyRemoval: it terminates the
    // OS process if alive, deletes the pid file, cancels any scheduled
    // restart, and disposes the controller. Idempotent in any state, so
    // running, starting, cooldown, and in-flight-stop removals all end up
    // cleaned up (this is the orphan fix).
    final removed = _controllers.keys
        .where((n) => !newNames.contains(n))
        .toList();
    for (final name in removed) {
      await _controllers[name]?.applyRemoval();
      _controllers.remove(name);
    }

    // Diff-based materialization: refresh the configured-name set and
    // materialize a controller for every configured Process. Kept names
    // keep their live controllers/streams; only new names are created.
    // This completes before autostart and before [onConfigReloaded] fires,
    // so viewmodels always subscribe to real streams.
    _materialize(config);

    // Start new autostart processes. Kept processes that are running or
    // mid-transition are skipped: re-starting them would double-launch or
    // fight an in-flight stop. Only terminal states (stopped/crashed/
    // cooldown) and new names get the autostart; a start from `cooldown`
    // supersedes the scheduled auto-restart inside the controller.
    for (final proc in config.processes) {
      if (!proc.autostart) continue;
      final state = _controllers[proc.name]?.currentState;
      if (state != null && (state.isActive || state == ProcState.stopping)) {
        continue;
      }
      await start(proc.name);
    }

    _onConfigReloadedController.add(null);
  }

  /// Clears the output buffer for [name], discarding any un-flushed lines.
  void clearOutput(String name) {
    _controllers[name]?.clearOutput();
  }

  /// Immediately flushes buffered output for [name].
  ///
  /// Exposed so tests can inspect output without waiting for the periodic
  /// flush timer.
  @visibleForTesting
  void flushNow(String name) {
    _controllers[name]?.flushNow();
  }

  // ---------------------------------------------------------------------------
  // Private: controller lookup
  // ---------------------------------------------------------------------------

  /// Returns the [ProcessController] for a configured [name], creating one
  /// if absent; `null` for unknown names (inert streams, no phantom state).
  ///
  /// Materializes only names in [_configuredNames] — set by [init] and
  /// [reloadConfig]. No disk read: removed names cannot be resurrected.
  ProcessController? _controller(String name) {
    if (!_configuredNames.contains(name)) return null;
    return _controllers.putIfAbsent(
      name,
      () => ProcessController(
        name: name,
        processRunner: _processRunner,
        dataDir: _dataDir,
        logger: _logger,
        cooldownDuration: cooldownDuration,
      ),
    );
  }

  /// Materializes a controller for every Process in [config] and records
  /// the configured names.
  void _materialize(AppConfig config) {
    _configuredNames = config.processes.map((p) => p.name).toSet();
    for (final proc in config.processes) {
      _controller(proc.name);
    }
  }

  /// Loads the config and resolves the [ProcessConfig] for [name].
  ///
  /// Returns `null` when no configuration is loaded or [name] is not
  /// configured — the caller reports the failure. Shared by [start] and
  /// [toggle] so the config is read exactly once per call.
  ({AppConfig config, ProcessConfig procConfig})? _resolveConfigFor(
    String name,
  ) {
    final config = _configStore.load();
    if (config == null) return null;
    final procConfig = config.processes.cast<ProcessConfig?>().firstWhere(
      (p) => p!.name == name,
      orElse: () => null,
    );
    if (procConfig == null) return null;
    return (config: config, procConfig: procConfig);
  }

  // ---------------------------------------------------------------------------
  // Private: startup
  // ---------------------------------------------------------------------------

  /// Starts all processes with `autostart: true` in the current config.
  Future<void> _autostartAll() async {
    final config = _configStore.load();
    if (config == null) return;

    final futures = <Future<void>>[];
    for (final proc in config.processes) {
      if (proc.autostart) {
        futures.add(start(proc.name));
      }
    }

    await Future.wait(futures);
  }

  /// Scans the `pids/` directory and removes stale PID files.
  ///
  /// For each `.pid` file, checks if the process is still alive and whether
  /// its start time matches the recorded value. Stale files (process not
  /// running or PID reused by a different process) are deleted.
  /// Orphaned processes from previous sessions are killed.
  Future<void> _cleanupStalePidFiles() async {
    final dir = Directory(_pidsDir);
    if (!dir.existsSync()) return;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pid'))
        .toList();

    if (files.isEmpty) return;

    await Future.wait(files.map(_cleanupOnePidFile));
  }

  Future<void> _cleanupOnePidFile(File file) async {
    try {
      final content = file.readAsStringSync();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final pid = json['pid'] as int?;
      final recordedStart = json['startTime'] as String?;
      if (pid == null) {
        file.deleteSync();
        return;
      }

      final alive = await _processRunner.isPidAlive(pid);
      if (!alive) {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
        return;
      }

      if (recordedStart != null) {
        final actualStart = await _processRunner.getProcessStartTime(pid);
        if (actualStart == null) return; // can't verify, keep conservatively

        final recorded = DateTime.tryParse(recordedStart);
        if (recorded == null ||
            actualStart.difference(recorded).inSeconds.abs() > 2) {
          // Start time mismatch — PID was reused by a different process.
          try {
            if (file.existsSync()) file.deleteSync();
          } catch (_) {}
          return;
        }

        // Start time match — orphan from a previous trayforge session.
        final procName = p.basenameWithoutExtension(file.path);
        await _processRunner.killPid(pid);
        _log(
          '[trayforge] Process "$procName": killed orphaned '
          'instance from previous session (PID $pid)',
        );
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      // Corrupted PID file — clean it up.
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Private: logging
  // ---------------------------------------------------------------------------

  void _log(String message) {
    _logger?.log(message);
  }
}
