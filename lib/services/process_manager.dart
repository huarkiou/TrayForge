import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:trayforge/foundation/logger.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/output_pipeline.dart';
import 'package:trayforge/foundation/shlex.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_runner.dart';

// ---------------------------------------------------------------------------
// _ProcessRuntime
// ---------------------------------------------------------------------------

/// Per-process mutable state bundled into a single object.
///
/// [dispose] closes controllers, cancels timers/subscriptions.
/// The output pipeline (buffer, flush timer, ANSI strip, WebUI detection)
/// lives in [BufferedOutputPipeline] instead of being scattered here.
class _ProcessRuntime {
  ProcState state = ProcState.stopped;
  IProcessHandle? handle;
  bool manualStop = false;
  _RestartState? restart;
  BufferedOutputPipeline? pipeline;
  StreamSubscription<void>? outputSubscription;
  StreamController<ProcState>? stateController;

  /// Release all resources held by this runtime entry.
  void dispose() {
    restart?.cooldownTimer?.cancel();
    pipeline?.dispose();
    outputSubscription?.cancel();
    stateController?.close();
  }
}

// ---------------------------------------------------------------------------
// _RestartState
// ---------------------------------------------------------------------------

/// Bundles per-process crash-restart state that always travels together.
class _RestartState {
  DateTime? lastRestartTime;
  int count = 0;
  Timer? cooldownTimer;
}

// ---------------------------------------------------------------------------
// ProcessManager
// ---------------------------------------------------------------------------

/// Manages the lifecycle of configured processes.
///
/// Provides start/stop with full-process-tree kill, merged stdout+stderr
/// output streaming with batching, ANSI stripping, WebUI URL detection,
/// PID file management, and per-process state tracking.
class ProcessManager {
  final ConfigStore _configStore;
  final IProcessRunner _processRunner;
  final String _dataDir;
  final Logger? _logger;

  /// Per-process mutable state, bundled into a single map.
  final Map<String, _ProcessRuntime> _procs = {};

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
    await _autostartAll();
  }

  String get _pidsDir => p.join(_dataDir, 'pids');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns a broadcast stream of processed output lines for [name].
  Stream<String> outputStream(String name) {
    return _ensurePipeline(name).output;
  }

  /// Returns a broadcast stream of WebUI URL detections for [name].
  ///
  /// Each process gets its own detection stream — no relay or name
  /// filtering needed.
  Stream<Uri> webUiStream(String name) {
    return _ensurePipeline(name).onWebUiDetected;
  }

  /// Returns a broadcast stream of [ProcState] transitions for [name].
  Stream<ProcState> stateStream(String name) {
    return (_proc(name).stateController ??=
            StreamController<ProcState>.broadcast(sync: true))
        .stream;
  }

  /// Returns the current [ProcState] for [name], or [ProcState.stopped].
  ProcState getState(String name) => _proc(name).state;

  /// Starts the process named [name] using its current [ProcessConfig].
  ///
  /// Reads the config from [ConfigStore], splits [ProcessConfig.cmd] via
  /// [Shlex.split], launches the process through [IProcessRunner], wires
  /// up the output pipeline, writes a PID file, and transitions state
  /// through `starting` → `running`.
  Future<void> start(String name) async {
    final proc = _proc(name);
    final pipeline = _ensurePipeline(name);

    final procConfig = _lookupConfig(name);
    if (procConfig == null) return;

    // Singleton guard
    if (procConfig.singleton &&
        (proc.state == ProcState.running || proc.state == ProcState.starting)) {
      _pushSystemMessage(name, 'Process is already running (singleton)');
      return;
    }

    _setState(name, ProcState.starting);

    try {
      final args = Shlex.split(procConfig.cmd);
      if (args.isEmpty) {
        _pushSystemMessage(name, 'Cannot start: empty command');
        _setState(name, ProcState.stopped);
        return;
      }

      var executable = args.first;
      final arguments = args.length > 1 ? args.sublist(1) : <String>[];

      // OS-level singleton check
      final executableName = p.basename(executable);
      try {
        final alreadyRunning = await _processRunner.isProcessRunning(
          executableName,
        );
        if (alreadyRunning) {
          _pushSystemMessage(name, 'Process is already running at OS level');
          _setState(name, ProcState.stopped);
          return;
        }
      } catch (_) {
        // Best-effort; proceed with launch if check fails.
      }

      // Kill residual processes from the same working directory before
      // starting.  Matches Python trayforge's `cleanup_cwd` behaviour.
      if (procConfig.cleanupCwd && procConfig.cwd != null) {
        await _cleanupCwd(name, procConfig.cwd!);
      }

      // Delete lock files before start
      _deleteBeforeStartFiles(name, procConfig);

      // Build merged environment
      final env = Map<String, String>.from(Platform.environment);
      env['PYTHONIOENCODING'] = 'utf-8';
      if (procConfig.env != null) {
        env.addAll(procConfig.env!);
      }

      String? workingDirectory;
      if (procConfig.cwd != null && procConfig.cwd!.isNotEmpty) {
        workingDirectory = procConfig.cwd;
      }

      // Resolve relative executable paths against workingDirectory.
      // Dart's Process.start does NOT resolve the executable relative to
      // workingDirectory — it uses the Flutter process's own CWD.
      if (workingDirectory != null && !p.isAbsolute(executable)) {
        if (executable.contains('/') || executable.contains('\\')) {
          // Relative path with separators (e.g. ".\\python_embeded\\python.exe")
          executable = p.canonicalize(p.join(workingDirectory, executable));
        } else {
          // Bare name (e.g. "NapCatWinBootMain.exe"): check if it
          // exists in workingDirectory. If so, resolve to absolute;
          // otherwise leave as-is for PATH lookup (e.g. "bun", "python").
          final candidate = p.join(workingDirectory, executable);
          if (File(candidate).existsSync()) {
            executable = p.canonicalize(candidate);
          }
        }
      }

      _log('Starting $name: $executable ${arguments.join(' ')}');

      final handle = await _processRunner.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: env,
        runInShell: false,
      );

      proc.handle = handle;
      proc.manualStop = false;

      _writePidFile(name, handle.pid);

      _setState(name, ProcState.running);
      _pushSystemMessage(name, 'Process started (PID: ${handle.pid})');

      // Wire output pipeline
      final config = _configStore.load()!;
      final encoding = _resolveEncoding(procConfig.encoding, name);
      // 宽松解码:原生库(torch/CUDA 等)在 Windows 上会直接往 stderr 写
      // ANSI/GBK 字节,严格解码会抛 FormatException 中断输出流;非法字节
      // 一律替换为 U+FFFD,保证输出流不断。
      final decoder = _lenientDecoder(encoding);

      pipeline.configure(
        historyLimit: config.outputHistoryLimit,
        refreshMs: config.outputRefreshMs,
        webuiPattern: procConfig.webuiPattern,
      );

      final merged = _mergeByteStreams(handle.stdout, handle.stderr);
      final subscription = merged
          .transform(decoder)
          .transform(const LineSplitter())
          .listen(
            pipeline.addLine,
            onError: (e) => pipeline.push('[trayforge] Output read error: $e'),
          );
      proc.outputSubscription = subscription;

      pipeline.startFlushTimer();

      // Monitor exit
      handle.exitCode.then((exitCode) {
        final wasManual = proc.manualStop;
        proc.manualStop = false;
        if (!wasManual) {
          _onUnexpectedExit(name, procConfig, exitCode);
        }
        _cleanup(name);
      });
    } on Exception catch (e) {
      _pushSystemMessage(name, 'Start failed: $e');
      _setState(name, ProcState.stopped);
    }
  }

  /// Stops the process named [name].
  ///
  /// Platform-guarded kill: `taskkill /t /f /pid <pid>` on Windows,
  /// `pkill -P <pid>` followed by `SIGKILL` on Linux.
  /// Cleans up the PID file and transitions: `running` → `stopping` → `stopped`.
  Future<void> stop(String name) async {
    final proc = _procs[name];
    if (proc == null || proc.handle == null) return;

    _setState(name, ProcState.stopping);
    proc.manualStop = true;
    final rs = proc.restart;
    if (rs != null) {
      rs.cooldownTimer?.cancel();
      proc.restart = null;
    }
    _pushSystemMessage(name, 'Process stopping...');

    await _processRunner.killPid(proc.handle!.pid);

    _cleanup(name);
    _setState(name, ProcState.stopped);
    _pushSystemMessage(name, 'Process stopped');
  }

  /// Cooldown duration between crash restarts.
  ///
  /// Configurable for testing; defaults to 60 seconds.
  final Duration cooldownDuration;

  /// Releases all resources: timers, subscriptions, controllers.
  void dispose() {
    for (final proc in _procs.values) {
      proc.dispose();
    }
    _onConfigReloadedController.close();
  }

  /// Hot-swaps configuration without restarting already-running processes.
  ///
  /// Starts new processes that have `autostart: true` and are not already
  /// running. Stops processes that are running but no longer present in
  /// the new config. Cleans up stale [_procs] entries for deleted/renamed
  /// processes. Emits [onConfigReloaded] on completion.
  ///
  /// Does **not** write the config to disk — callers must [ConfigStore.save]
  /// beforehand if persistence is desired.
  Future<void> reloadConfig(AppConfig config) async {
    // Determine which processes are currently running.
    final runningNames = _procs.entries
        .where((e) => e.value.state == ProcState.running)
        .map((e) => e.key)
        .toSet();

    final newNames = config.processes.map((p) => p.name).toSet();

    // Stop processes that are no longer in the config.
    for (final name in runningNames.difference(newNames)) {
      await stop(name);
    }

    // Dispose stale _procs entries for deleted/renamed processes that
    // are not currently running (running ones were stopped above).
    final stale = _procs.keys.where((n) => !newNames.contains(n)).toList();
    for (final name in stale) {
      _procs[name]?.dispose();
      _procs.remove(name);
    }

    // Start new autostart processes that aren't already running.
    for (final proc in config.processes) {
      if (proc.autostart && !runningNames.contains(proc.name)) {
        await start(proc.name);
      }
    }

    _onConfigReloadedController.add(null);
  }

  /// Clears the output buffer for [name], discarding any un-flushed lines.
  void clearOutput(String name) {
    _procs[name]?.pipeline?.clear();
  }

  /// Immediately flushes buffered output for [name].
  ///
  /// Exposed so tests can inspect output without waiting for the periodic
  /// flush timer.
  @visibleForTesting
  void flushNow(String name) {
    _procs[name]?.pipeline?.flushNow();
  }

  // ---------------------------------------------------------------------------
  // Private: crash restart
  // ---------------------------------------------------------------------------

  void _onUnexpectedExit(String name, ProcessConfig procConfig, int exitCode) {
    _pushSystemMessage(name, 'Process exited with code $exitCode');

    final maxRestarts = procConfig.maxRestarts;
    if (maxRestarts == null || maxRestarts == 0) {
      _setState(name, ProcState.crashed);
      return;
    }

    final proc = _proc(name);
    proc.restart ??= _RestartState();
    final rs = proc.restart!;

    rs.count++;

    if (rs.count > maxRestarts) {
      _setState(name, ProcState.crashed);
      _pushSystemMessage(
        name,
        '$name: max restarts ($maxRestarts) reached, giving up',
      );
      proc.restart = null;
      return;
    }

    final lastTime = rs.lastRestartTime;
    final now = DateTime.now();

    if (lastTime != null) {
      final elapsed = now.difference(lastTime);
      if (elapsed < cooldownDuration) {
        final remaining = cooldownDuration - elapsed;
        _setState(name, ProcState.cooldown);
        _pushSystemMessage(
          name,
          'Restart cooldown: next attempt in ${remaining.inSeconds}s '
          '(attempt ${rs.count} of $maxRestarts)',
        );
        _scheduleCooldownRestart(name, procConfig, remaining, rs);
        return;
      }
    }

    _doRestart(name, procConfig, maxRestarts, rs);
  }

  void _doRestart(
    String name,
    ProcessConfig procConfig,
    int maxRestarts,
    _RestartState rs,
  ) {
    rs.lastRestartTime = DateTime.now();
    _pushSystemMessage(
      name,
      'Auto-restarting (attempt ${rs.count} of $maxRestarts)...',
    );
    // Fire-and-forget: schedule a microtask restart so the current
    // exit handler can finish cleanup before the next start.
    Future.microtask(() => start(name));
  }

  void _scheduleCooldownRestart(
    String name,
    ProcessConfig procConfig,
    Duration delay,
    _RestartState rs,
  ) {
    rs.cooldownTimer?.cancel();
    rs.cooldownTimer = Timer(delay, () {
      final proc = _procs[name];
      if (proc != null) proc.restart = null;
      _pushSystemMessage(name, 'Cooldown elapsed, retrying...');
      _doRestart(name, procConfig, procConfig.maxRestarts ?? 0, rs);
    });
  }

  // ---------------------------------------------------------------------------
  // Private: helpers
  // ---------------------------------------------------------------------------

  /// Returns the [_ProcessRuntime] for [name], creating one if absent.
  _ProcessRuntime _proc(String name) {
    return _procs.putIfAbsent(name, () => _ProcessRuntime());
  }

  /// Returns the [BufferedOutputPipeline] for [name], creating one if absent.
  BufferedOutputPipeline _ensurePipeline(String name) {
    final proc = _proc(name);
    return proc.pipeline ??= BufferedOutputPipeline();
  }

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

  ProcessConfig? _lookupConfig(String name) {
    final config = _configStore.load();
    if (config == null) {
      _pushSystemMessage(name, 'Cannot start: no configuration loaded');
      return null;
    }
    final match = config.processes.cast<ProcessConfig?>().firstWhere(
      (p) => p!.name == name,
      orElse: () => null,
    );
    if (match == null) {
      _pushSystemMessage(
        name,
        'Cannot start: process "$name" not found in config',
      );
    }
    return match;
  }

  void _cleanup(String name) {
    final proc = _procs[name];
    if (proc == null || proc.handle == null) return;

    proc.pipeline?.stopFlushTimer();
    proc.outputSubscription?.cancel();
    proc.outputSubscription = null;

    // Flush remaining buffered output before removing handle.
    proc.pipeline?.flushNow();

    proc.handle = null;
    _deletePidFile(name);
  }

  void _setState(String name, ProcState state) {
    final proc = _proc(name);
    proc.state = state;
    proc.stateController?.add(state);
  }

  void _pushSystemMessage(String name, String message) {
    final line = '[trayforge] $message';
    _procs[name]?.pipeline?.push(line);
  }

  Encoding _resolveEncoding(String? encodingName, String name) {
    if (encodingName == null) return utf8;
    final encoding = Encoding.getByName(encodingName);
    if (encoding == null) {
      _pushSystemMessage(
        name,
        'Unknown encoding "$encodingName", falling back to UTF-8',
      );
      return utf8;
    }
    return encoding;
  }

  /// 宽松解码器:非法字节替换为 U+FFFD 而非抛异常,避免中断输出流。
  Converter<List<int>, String> _lenientDecoder(Encoding encoding) {
    if (encoding is Utf8Codec) return const Utf8Decoder(allowMalformed: true);
    if (encoding is AsciiCodec) return const AsciiDecoder(allowInvalid: true);
    // latin1 等单字节编码对任意字节均有映射,天然不会抛异常。
    return encoding.decoder;
  }

  // ---------------------------------------------------------------------------
  // Private: streams
  // ---------------------------------------------------------------------------

  /// Merges two byte streams into one.
  ///
  /// The merged stream closes once **both** source streams are done.
  Stream<List<int>> _mergeByteStreams(
    Stream<List<int>> a,
    Stream<List<int>> b,
  ) {
    final controller = StreamController<List<int>>(sync: true);
    var doneCount = 0;

    void onDone() {
      doneCount++;
      if (doneCount == 2) controller.close();
    }

    a.listen(controller.add, onError: controller.addError, onDone: onDone);
    b.listen(controller.add, onError: controller.addError, onDone: onDone);

    return controller.stream;
  }

  // ---------------------------------------------------------------------------
  // Private: cleanup_cwd
  // ---------------------------------------------------------------------------

  /// Kills all processes whose current working directory matches [cwd].
  ///
  /// Mirrors Python trayforge's `_kill_cwd_processes` which used psutil.
  /// The Flutter version uses [IProcessRunner.findPidsByCwd] (FFI on
  /// Windows, /proc on Linux).
  Future<void> _cleanupCwd(String name, String cwd) async {
    _pushSystemMessage(
      name,
      'Cleanup: searching for residual processes '
      'in "$cwd"...',
    );

    try {
      final pids = await _processRunner.findPidsByCwd(cwd);
      if (pids.isEmpty) return;

      for (final pid in pids) {
        _pushSystemMessage(
          name,
          'Cleanup: killing residual process (PID $pid)',
        );
        await _processRunner.killPid(pid);
      }

      // Brief wait for OS to release file handles.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      _pushSystemMessage(
        name,
        'Cleanup: killed ${pids.length} residual process(es)',
      );
    } catch (e) {
      _pushSystemMessage(name, 'Cleanup: error during cwd cleanup: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Private: delete_before_start
  // ---------------------------------------------------------------------------

  /// Deletes files listed in [procConfig.deleteBeforeStart].
  ///
  /// Each path is resolved relative to [ProcessConfig.cwd]. Paths that
  /// escape the cwd subtree are blocked and reported via system messages.
  ///
  /// When a file is locked, [cleanupCwd] is attempted (kill residual
  /// processes) and the delete is retried once — matching Python trayforge's
  /// behaviour.
  void _deleteBeforeStartFiles(String name, ProcessConfig procConfig) {
    final paths = procConfig.deleteBeforeStart;
    if (paths.isEmpty) return;

    final cwd = procConfig.cwd;
    if (cwd == null || cwd.isEmpty) {
      _pushSystemMessage(
        name,
        'delete_before_start requires cwd; skipping file cleanup',
      );
      return;
    }

    final cwdCanonical = p.canonicalize(Directory(cwd).absolute.path);

    for (final relativePath in paths) {
      try {
        final resolved = p.canonicalize(p.join(cwdCanonical, relativePath));

        // Path escape check: resolved must stay within cwd subtree.
        if (!resolved.startsWith(cwdCanonical + p.separator) &&
            resolved != cwdCanonical) {
          _pushSystemMessage(
            name,
            'delete_before_start: path escape blocked for '
            '"$relativePath"',
          );
          continue;
        }

        final file = File(resolved);
        if (file.existsSync()) {
          try {
            file.deleteSync();
            _pushSystemMessage(
              name,
              'delete_before_start: deleted "$relativePath"',
            );
          } catch (_) {
            // File is locked — try killing residual processes and retry.
            _pushSystemMessage(
              name,
              'delete_before_start: "$relativePath" is locked, '
              'attempting cwd cleanup...',
            );

            // Fire cwd cleanup inline and retry the delete.
            _cleanupCwd(name, cwdCanonical).then((_) {
              try {
                if (file.existsSync()) {
                  file.deleteSync();
                  _pushSystemMessage(
                    name,
                    'delete_before_start: deleted "$relativePath" '
                    '(after cwd cleanup)',
                  );
                }
              } catch (_) {
                _pushSystemMessage(
                  name,
                  'delete_before_start: could not delete "$relativePath" '
                  'even after cwd cleanup — file may be locked by an '
                  'external process',
                );
              }
            });
          }
        }
      } catch (e) {
        _pushSystemMessage(
          name,
          'delete_before_start: error processing '
          '"$relativePath": $e',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Private: PID file
  // ---------------------------------------------------------------------------

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

  void _writePidFile(String name, int pid) {
    final dir = Directory(_pidsDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File(
      p.join(_pidsDir, '$name.pid'),
    ).writeAsStringSync(_pidJson(pid), flush: true);
  }

  void _deletePidFile(String name) {
    final file = File(p.join(_pidsDir, '$name.pid'));
    if (file.existsSync()) file.deleteSync();
  }

  String _pidJson(int pid) {
    return '{"pid":$pid,"startTime":"${DateTime.now().toIso8601String()}"}';
  }

  // ---------------------------------------------------------------------------
  // Private: logging
  // ---------------------------------------------------------------------------

  void _log(String message) {
    _logger?.log(message);
  }
}
