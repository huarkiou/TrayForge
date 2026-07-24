import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:trayforge_flutter/foundation/logger.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/foundation/output_pipeline.dart';
import 'package:trayforge_flutter/foundation/shlex.dart';
import 'package:trayforge_flutter/services/config_store.dart';
import 'package:trayforge_flutter/services/process_runner.dart';

/// Event raised when a Web UI URL is detected in process output.
class WebUiEvent {
  final String processName;
  final Uri url;

  const WebUiEvent(this.processName, this.url);
}

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

  // Per-process mutable state
  final Map<String, ProcState> _states = {};
  final Map<String, IProcessHandle> _handles = {};
  final Map<String, bool> _manualStopFlags = {};

  // Output pipeline
  final Map<String, StreamController<String>> _outputControllers = {};
  final Map<String, List<String>> _outputBuffers = {};
  final Map<String, Timer> _flushTimers = {};
  final Map<String, StreamSubscription<void>> _outputSubscriptions = {};

  // State-change callbacks
  final Map<String, StreamController<ProcState>> _stateControllers = {};

  // WebUI detection broadcast
  final StreamController<WebUiEvent> _webuiController;

  /// Broadcast stream of WebUI URL detections.
  Stream<WebUiEvent> get onWebUiDetected => _webuiController.stream;

  ProcessManager({
    required ConfigStore configStore,
    IProcessRunner? processRunner,
    String? dataDir,
    this._logger,
  })  : _configStore = configStore,
        _processRunner = processRunner ?? RealProcessRunner(),
        _dataDir = dataDir ?? Logger.getDataDir(),
        _webuiController = StreamController<WebUiEvent>.broadcast(sync: true);

  String get _pidsDir => p.join(_dataDir, 'pids');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns a broadcast stream of processed output lines for [name].
  Stream<String> outputStream(String name) {
    return _outputControllers
        .putIfAbsent(name, () => StreamController<String>.broadcast(sync: true))
        .stream;
  }

  /// Returns a broadcast stream of [ProcState] transitions for [name].
  Stream<ProcState> stateStream(String name) {
    return _stateControllers
        .putIfAbsent(name, () => StreamController<ProcState>.broadcast(sync: true))
        .stream;
  }

  /// Returns the current [ProcState] for [name], or [ProcState.stopped].
  ProcState getState(String name) =>
      _states[name] ?? ProcState.stopped;

  /// Starts the process named [name] using its current [ProcessConfig].
  ///
  /// Reads the config from [ConfigStore], splits [ProcessConfig.cmd] via
  /// [Shlex.split], launches the process through [IProcessRunner], wires
  /// up the output pipeline, writes a PID file, and transitions state
  /// through `starting` → `running`.
  Future<void> start(String name) async {
    final procConfig = _lookupConfig(name);
    if (procConfig == null) return;

    // Singleton guard
    final current = _states[name] ?? ProcState.stopped;
    if (procConfig.singleton &&
        (current == ProcState.running || current == ProcState.starting)) {
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

      final executable = args.first;
      final arguments =
          args.length > 1 ? args.sublist(1) : <String>[];

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

      _log('Starting $name: $executable ${arguments.join(' ')}');

      final handle = await _processRunner.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: env,
        runInShell: false,
      );

      _handles[name] = handle;
      _manualStopFlags[name] = false;

      _writePidFile(name, handle.pid);

      _setState(name, ProcState.running);
      _pushSystemMessage(name, 'Process started (PID: ${handle.pid})');

      // Wire output pipeline
      final config = _configStore.load()!;
      final encoding = _resolveEncoding(procConfig.encoding, name);
      final webuiPattern = procConfig.webuiPattern;
      final refreshMs = config.outputRefreshMs;
      final historyLimit = config.outputHistoryLimit;

      _outputControllers.putIfAbsent(
          name, () => StreamController<String>.broadcast(sync: true));
      _outputBuffers[name] = [];

      final merged = _mergeByteStreams(handle.stdout, handle.stderr);
      final subscription = merged
          .transform(encoding.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) => _onOutputLine(name, line, webuiPattern, historyLimit),
        onError: (e) =>
            _pushSystemMessage(name, 'Output read error: $e'),
      );
      _outputSubscriptions[name] = subscription;

      _startFlushTimer(name, refreshMs);

      // Monitor exit
      handle.exitCode.then((exitCode) {
        final wasManual = _manualStopFlags[name] == true;
        _manualStopFlags.remove(name);
        if (!wasManual) {
          _setState(name, ProcState.crashed);
          _pushSystemMessage(
              name, 'Process exited with code $exitCode');
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
    final handle = _handles[name];
    if (handle == null) return;

    _setState(name, ProcState.stopping);
    _manualStopFlags[name] = true;
    _pushSystemMessage(name, 'Process stopping...');

    try {
      final pid = handle.pid;
      if (Platform.isWindows) {
        await Process.run(
            'taskkill', ['/t', '/f', '/pid', pid.toString()]);
      } else {
        await Process.run('pkill', ['-P', pid.toString()]);
        handle.kill(signal: ProcessSignal.sigkill);
      }
    } catch (e) {
      _log('Error killing process tree for $name: $e');
      try {
        handle.kill(signal: ProcessSignal.sigkill);
      } catch (_) {
        // Process may have already exited.
      }
    }

    _cleanup(name);
    _setState(name, ProcState.stopped);
    _pushSystemMessage(name, 'Process stopped');
  }

  /// Called when the configuration changes so the manager can react.
  void reloadConfig() {
    // Future tickets (05) will handle auto-restart on config change.
  }

  /// Releases all resources: timers, subscriptions, controllers.
  void dispose() {
    for (final t in _flushTimers.values) {
      t.cancel();
    }
    for (final s in _outputSubscriptions.values) {
      s.cancel();
    }
    for (final c in _outputControllers.values) {
      c.close();
    }
    for (final c in _stateControllers.values) {
      c.close();
    }
    _webuiController.close();
  }

  // ---------------------------------------------------------------------------
  // Private: helpers
  // ---------------------------------------------------------------------------

  ProcessConfig? _lookupConfig(String name) {
    final config = _configStore.load();
    if (config == null) {
      _pushSystemMessage(
          name, 'Cannot start: no configuration loaded');
      return null;
    }
    final match = config.processes.cast<ProcessConfig?>().firstWhere(
          (p) => p!.name == name,
          orElse: () => null,
        );
    if (match == null) {
      _pushSystemMessage(
          name, 'Cannot start: process "$name" not found in config');
    }
    return match;
  }

  void _onOutputLine(
    String name,
    String line,
    String? webuiPattern,
    int historyLimit,
  ) {
    final cleaned = OutputPipeline.stripAnsi(line);

    if (webuiPattern != null) {
      final url = OutputPipeline.tryDetectWebUi(cleaned, webuiPattern);
      if (url != null) {
        _webuiController.add(WebUiEvent(name, url));
      }
    }

    final buffer = _outputBuffers[name]!;
    buffer.add(cleaned);
    while (buffer.length > historyLimit) {
      buffer.removeAt(0);
    }
  }

  void _startFlushTimer(String name, int refreshMs) {
    _flushTimers[name]?.cancel();
    _flushTimers[name] =
        Timer.periodic(Duration(milliseconds: refreshMs), (_) {
      _flushBuffer(name);
    });
  }

  void _flushBuffer(String name) {
    final buffer = _outputBuffers[name];
    final controller = _outputControllers[name];
    if (buffer == null || controller == null || buffer.isEmpty) return;

    for (final line in buffer) {
      controller.add(line);
    }
    buffer.clear();
  }

  void _cleanup(String name) {
    _flushTimers[name]?.cancel();
    _flushTimers.remove(name);
    _outputSubscriptions[name]?.cancel();
    _outputSubscriptions.remove(name);

    // Flush remaining buffered output before removing.
    _flushBuffer(name);

    _handles.remove(name);
    _deletePidFile(name);
  }

  void _setState(String name, ProcState state) {
    _states[name] = state;
    _stateControllers[name]?.add(state);
  }

  void _pushSystemMessage(String name, String message) {
    final line = '[TrayForge] $message';
    _outputControllers[name]?.add(line);
  }

  Encoding _resolveEncoding(String? encodingName, String name) {
    if (encodingName == null) return utf8;
    final encoding = Encoding.getByName(encodingName);
    if (encoding == null) {
      _pushSystemMessage(name,
          'Unknown encoding "$encodingName", falling back to UTF-8');
      return utf8;
    }
    return encoding;
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
    final controller = StreamController<List<int>>();
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
  // Private: PID file
  // ---------------------------------------------------------------------------

  void _writePidFile(String name, int pid) {
    final dir = Directory(_pidsDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File(p.join(_pidsDir, '$name.pid'))
        .writeAsStringSync(_pidJson(pid), flush: true);
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
