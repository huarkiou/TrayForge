import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:trayforge/foundation/logger.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/foundation/output_pipeline.dart';
import 'package:trayforge/foundation/shlex.dart';
import 'package:trayforge/services/process_runner.dart';

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
// ProcessController
// ---------------------------------------------------------------------------

/// Owns the full lifecycle of a single managed [Process].
///
/// The deep per-process module: state machine, launch sequence (shlex,
/// env merge, cwd-relative exe resolution, singleton guards, cleanupCwd,
/// deleteBeforeStart, lenient decode), kill-tree stop, crash restart +
/// cooldown, pid file, output wiring, and the per-process streams
/// (`output`, `webUi`, `state`).
///
/// Configuration is passed in as a parameter — the controller never reads
/// the [ConfigStore] — so `start(appConfig, procConfig)` receives the
/// resolved configs from the coordinator ([ProcessManager]).
class ProcessController {
  final String name;
  final IProcessRunner _processRunner;
  final String _pidsDir;
  final Logger? _logger;

  /// Cooldown duration between crash restarts.
  ///
  /// Configurable for testing; defaults to 60 seconds.
  final Duration cooldownDuration;

  ProcState _state = ProcState.stopped;
  IProcessHandle? _handle;
  bool _manualStop = false;

  /// Set by [stop] while the launch sequence is still in flight (state
  /// `starting`): the sequence checks this flag right after obtaining the
  /// handle and kills immediately, so the Process never reaches `running`.
  bool _pendingStop = false;

  /// Set by [applyRemoval] before any teardown: the launch sequence checks
  /// it before every side-effecting step, so an in-flight [start] can't
  /// resurrect the pid file or touch a disposed pipeline after removal.
  bool _removed = false;

  /// Once true, the controller is disposed and every later continuation
  /// (in-flight stop, exit handler, cooldown timer) becomes a no-op.
  bool _disposed = false;

  _RestartState? _restart;
  BufferedOutputPipeline? _pipeline;
  StreamSubscription<void>? _outputSubscription;
  StreamController<ProcState>? _stateController;

  /// Config captured at the last [start]; reused by crash restarts.
  AppConfig _appConfig = const AppConfig();
  ProcessConfig? _procConfig;

  ProcessController({
    required this.name,
    required IProcessRunner processRunner,
    required String dataDir,
    Logger? logger,
    required this.cooldownDuration,
  })
    // ignore: prefer_initializing_formals
    : _processRunner = processRunner,
       _pidsDir = p.join(dataDir, 'pids'),
       // ignore: prefer_initializing_formals
       _logger = logger;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  /// Cleaned, timed-flushed output lines for this process.
  Stream<String> get output => pipeline.output;

  /// WebUI URL detections for this process.
  Stream<Uri> get webUi => pipeline.onWebUiDetected;

  /// Broadcast stream of [ProcState] transitions for this process.
  Stream<ProcState> get state {
    _stateController ??= StreamController<ProcState>.broadcast(sync: true);
    return _stateController!.stream;
  }

  /// The current [ProcState].
  ProcState get currentState => _state;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Starts the process using the resolved [procConfig].
  ///
  /// Splits [ProcessConfig.cmd] via [Shlex.split], launches the process
  /// through [IProcessRunner], wires up the output pipeline, writes a PID
  /// file, and transitions state through `starting` → `running`.
  ///
  /// Honours a pending stop: if [stop] was called while this launch was
  /// in flight, the launched process is killed right after the handle is
  /// obtained and the state never reaches `running`. The same applies if
  /// [applyRemoval] ran while launching — the process is killed and no
  /// side effect (pid write, pipeline wiring, exit listener) happens.
  Future<void> start(AppConfig appConfig, ProcessConfig procConfig) async {
    if (_disposed || _removed) return;
    _appConfig = appConfig;
    _procConfig = procConfig;

    // Materialize the pipeline early so system messages always land.
    final pipeline = this.pipeline;

    // Singleton guard
    if (procConfig.singleton &&
        (_state == ProcState.running || _state == ProcState.starting)) {
      _pushSystemMessage('Process is already running (singleton)');
      return;
    }

    _setState(ProcState.starting);
    _pendingStop = false;

    // Supersede any scheduled cooldown restart: a fresh start must not be
    // followed by the stale timer launching a second instance. No-op on the
    // auto-restart path (the timer callback has already cleared `_restart`).
    _restart?.cooldownTimer?.cancel();

    try {
      final args = Shlex.split(procConfig.cmd);
      if (args.isEmpty) {
        _pushSystemMessage('Cannot start: empty command');
        _setState(ProcState.stopped);
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
          _pushSystemMessage('Process is already running at OS level');
          _setState(ProcState.stopped);
          return;
        }
      } catch (_) {
        // Best-effort; proceed with launch if check fails.
      }

      if (_disposed) return;

      // Kill residual processes from the same working directory before
      // starting.  Matches Python trayforge's `cleanup_cwd` behaviour.
      if (procConfig.cleanupCwd && procConfig.cwd != null) {
        await _cleanupCwd(procConfig.cwd!);
      }

      if (_disposed) return;

      // Delete lock files before start
      _deleteBeforeStartFiles(procConfig);

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

      _handle = handle;

      // Pending-stop or removal while launching: kill immediately — the
      // Process never reaches `running`, no pid file is written, and a
      // disposed pipeline is never touched. The `removed` flag is checked
      // before each side-effecting step so an in-flight start can't
      // resurrect anything after applyRemoval.
      if (_pendingStop || _removed || _disposed) {
        _manualStop = true;
        await _processRunner.killPid(handle.pid);
        if (_removed || _disposed) {
          // Removal/dispose owns the teardown; the launched process is
          // already dead, so just bail.
          _cleanup();
          return;
        }
        _cleanup();
        _setState(ProcState.stopped);
        _pushSystemMessage('Process stopped');
        return;
      }

      _manualStop = false;

      if (_removed || _disposed) return;

      _writePidFile(handle.pid);

      _setState(ProcState.running);
      _pushSystemMessage('Process started (PID: ${handle.pid})');

      // Wire output pipeline
      final encoding = _resolveEncoding(procConfig.encoding);
      // 宽松解码:原生库(torch/CUDA 等)在 Windows 上会直接往 stderr 写
      // ANSI/GBK 字节,严格解码会抛 FormatException 中断输出流;非法字节
      // 一律替换为 U+FFFD,保证输出流不断。
      final decoder = _lenientDecoder(encoding);

      pipeline.configure(
        historyLimit: _appConfig.outputHistoryLimit,
        refreshMs: _appConfig.outputRefreshMs,
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
      _outputSubscription = subscription;

      pipeline.startFlushTimer();

      // Monitor exit
      handle.exitCode.then((exitCode) {
        if (_disposed) return;
        final wasManual = _manualStop;
        _manualStop = false;
        if (!wasManual) {
          _onUnexpectedExit(exitCode);
        }
        _cleanup();
      });
    } on Exception catch (e) {
      _pushSystemMessage('Start failed: $e');
      _setState(ProcState.stopped);
    }
  }

  /// Toggles the process: active (`running` | `starting`) → stop;
  /// terminal (`stopped` | `crashed` | `cooldown`) → start.
  ///
  /// The start/stop decision lives here and nowhere else — callers (the
  /// [ProcessManager] facade and the viewmodels) never re-decide. A toggle
  /// while `stopping` is a no-op (neither active nor terminal).
  Future<void> toggle(AppConfig appConfig, ProcessConfig procConfig) async {
    if (_disposed || _removed) return;
    if (_state.isActive) {
      await stop();
    } else if (_state.isTerminal) {
      await start(appConfig, procConfig);
    }
  }

  /// Stops the process: `running` → `stopping` → `stopped`.
  ///
  /// Platform-guarded kill: `taskkill /t /f /pid <pid>` on Windows,
  /// `pkill -P <pid>` followed by `SIGKILL` on Linux. Cleans up the PID
  /// file.
  ///
  /// While the launch sequence is still in flight (state `starting`, no
  /// handle yet), this is a **pending stop**: the flag is set and the
  /// launch sequence kills the process as soon as the handle arrives.
  ///
  /// After [applyRemoval] this is a no-op — the removal owns the teardown.
  Future<void> stop() async {
    if (_disposed || _removed) return;

    final handle = _handle;
    if (handle == null) {
      if (_state == ProcState.starting) {
        // Cancel any pending cooldown restart: this launch is being
        // aborted and must not be relaunched by a stale timer.
        final rs = _restart;
        if (rs != null) {
          rs.cooldownTimer?.cancel();
          _restart = null;
        }
        _pendingStop = true;
        _manualStop = true;
        _pushSystemMessage('Process stopping...');
      }
      return;
    }

    _setState(ProcState.stopping);
    _manualStop = true;
    final rs = _restart;
    if (rs != null) {
      rs.cooldownTimer?.cancel();
      _restart = null;
    }
    _pushSystemMessage('Process stopping...');

    await _processRunner.killPid(handle.pid);

    if (_disposed || _removed) return;
    _cleanup();
    _setState(ProcState.stopped);
    _pushSystemMessage('Process stopped');
  }

  /// Removes this process from management entirely.
  ///
  /// Terminates the OS process if alive, deletes the pid file, cancels any
  /// scheduled crash-restart, and disposes the controller. Idempotent in
  /// any state — running, starting, cooldown, mid-stop, or stopped.
  ///
  /// Sets the manual-stop flag first (a late exit handler won't restart)
  /// and the `removed` flag (the launch sequence checks it before every
  /// side-effecting step, so an in-flight [start] can't resurrect the pid
  /// file or touch a disposed pipeline).
  Future<void> applyRemoval() async {
    if (_disposed) return;
    _removed = true;
    _manualStop = true;

    // Cancel any scheduled crash restart: nothing may relaunch after removal.
    final rs = _restart;
    if (rs != null) {
      rs.cooldownTimer?.cancel();
      _restart = null;
    }

    final handle = _handle;
    if (handle != null) {
      await _processRunner.killPid(handle.pid);
    }

    _cleanup();
    _deletePidFile();
    dispose();
  }

  /// Discards all buffered (un-flushed) output lines.
  void clearOutput() {
    _pipeline?.clear();
  }

  /// Immediately flushes buffered output.
  ///
  /// Exposed so the coordinator can forward it to tests.
  void flushNow() {
    _pipeline?.flushNow();
  }

  /// Releases all resources: timers, subscriptions, controllers.
  ///
  /// Safe against late continuations: after this call, [start]/[stop]
  /// continuations, the exit handler, and the cooldown timer all become
  /// no-ops instead of throwing on closed streams or a disposed pipeline.
  void dispose() {
    _disposed = true;
    _restart?.cooldownTimer?.cancel();
    _pipeline?.dispose();
    _outputSubscription?.cancel();
    _stateController?.close();
  }

  // ---------------------------------------------------------------------------
  // System messages
  // ---------------------------------------------------------------------------

  /// Pushes a system message line to the output stream.
  ///
  /// Materializes the output pipeline if needed, mirroring the historical
  /// behaviour where [start] always ensured a pipeline before emitting
  /// lookup errors. No-op after [dispose].
  void pushSystemMessage(String message) {
    if (_disposed) return;
    pipeline.push('[trayforge] $message');
  }

  void _pushSystemMessage(String message) {
    if (_disposed) return;
    _pipeline?.push('[trayforge] $message');
  }

  // ---------------------------------------------------------------------------
  // Crash restart
  // ---------------------------------------------------------------------------

  void _onUnexpectedExit(int exitCode) {
    _pushSystemMessage('Process exited with code $exitCode');

    final procConfig = _procConfig;
    if (procConfig == null) return;
    final maxRestarts = procConfig.maxRestarts;
    if (maxRestarts == null || maxRestarts == 0) {
      _setState(ProcState.crashed);
      return;
    }

    _restart ??= _RestartState();
    final rs = _restart!;

    rs.count++;

    if (rs.count > maxRestarts) {
      _setState(ProcState.crashed);
      _pushSystemMessage(
        '$name: max restarts ($maxRestarts) reached, giving up',
      );
      _restart = null;
      return;
    }

    final lastTime = rs.lastRestartTime;
    final now = DateTime.now();

    if (lastTime != null) {
      final elapsed = now.difference(lastTime);
      if (elapsed < cooldownDuration) {
        final remaining = cooldownDuration - elapsed;
        _setState(ProcState.cooldown);
        _pushSystemMessage(
          'Restart cooldown: next attempt in ${remaining.inSeconds}s '
          '(attempt ${rs.count} of $maxRestarts)',
        );
        _scheduleCooldownRestart(remaining, rs);
        return;
      }
    }

    _doRestart(maxRestarts, rs);
  }

  void _doRestart(int maxRestarts, _RestartState rs) {
    if (_disposed) return;
    rs.lastRestartTime = DateTime.now();
    _pushSystemMessage(
      'Auto-restarting (attempt ${rs.count} of $maxRestarts)...',
    );
    // Fire-and-forget: schedule a microtask restart so the current
    // exit handler can finish cleanup before the next start.
    Future.microtask(() => start(_appConfig, _procConfig!));
  }

  void _scheduleCooldownRestart(Duration delay, _RestartState rs) {
    rs.cooldownTimer?.cancel();
    rs.cooldownTimer = Timer(delay, () {
      if (_disposed) return;
      _restart = null;
      _pushSystemMessage('Cooldown elapsed, retrying...');
      _doRestart(_procConfig?.maxRestarts ?? 0, rs);
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  BufferedOutputPipeline get pipeline => _pipeline ??= BufferedOutputPipeline();

  void _cleanup() {
    if (_disposed) return;
    if (_handle == null) return;

    _pipeline?.stopFlushTimer();
    _outputSubscription?.cancel();
    _outputSubscription = null;

    // Flush remaining buffered output before removing handle.
    _pipeline?.flushNow();

    _handle = null;
    _deletePidFile();
  }

  void _setState(ProcState state) {
    if (_disposed) return;
    _state = state;
    _stateController?.add(state);
  }

  Encoding _resolveEncoding(String? encodingName) {
    if (encodingName == null) return utf8;
    final encoding = Encoding.getByName(encodingName);
    if (encoding == null) {
      _pushSystemMessage(
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
  // cleanup_cwd
  // ---------------------------------------------------------------------------

  /// Kills all processes whose current working directory matches [cwd].
  ///
  /// Mirrors Python trayforge's `_kill_cwd_processes` which used psutil.
  /// The Flutter version uses [IProcessRunner.findPidsByCwd] (FFI on
  /// Windows, /proc on Linux).
  Future<void> _cleanupCwd(String cwd) async {
    _pushSystemMessage(
      'Cleanup: searching for residual processes in "$cwd"...',
    );

    try {
      final pids = await _processRunner.findPidsByCwd(cwd);
      if (pids.isEmpty) return;

      for (final pid in pids) {
        _pushSystemMessage('Cleanup: killing residual process (PID $pid)');
        await _processRunner.killPid(pid);
      }

      // Brief wait for OS to release file handles.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      _pushSystemMessage('Cleanup: killed ${pids.length} residual process(es)');
    } catch (e) {
      _pushSystemMessage('Cleanup: error during cwd cleanup: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // delete_before_start
  // ---------------------------------------------------------------------------

  /// Deletes files listed in [procConfig.deleteBeforeStart].
  ///
  /// Each path is resolved relative to [ProcessConfig.cwd]. Paths that
  /// escape the cwd subtree are blocked and reported via system messages.
  ///
  /// When a file is locked, [cleanupCwd] is attempted (kill residual
  /// processes) and the delete is retried once — matching Python trayforge's
  /// behaviour.
  void _deleteBeforeStartFiles(ProcessConfig procConfig) {
    final paths = procConfig.deleteBeforeStart;
    if (paths.isEmpty) return;

    final cwd = procConfig.cwd;
    if (cwd == null || cwd.isEmpty) {
      _pushSystemMessage(
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
            'delete_before_start: path escape blocked for "$relativePath"',
          );
          continue;
        }

        final file = File(resolved);
        if (file.existsSync()) {
          try {
            file.deleteSync();
            _pushSystemMessage('delete_before_start: deleted "$relativePath"');
          } catch (_) {
            // File is locked — try killing residual processes and retry.
            _pushSystemMessage(
              'delete_before_start: "$relativePath" is locked, '
              'attempting cwd cleanup...',
            );

            // Fire cwd cleanup inline and retry the delete.
            _cleanupCwd(cwdCanonical).then((_) {
              try {
                if (file.existsSync()) {
                  file.deleteSync();
                  _pushSystemMessage(
                    'delete_before_start: deleted "$relativePath" '
                    '(after cwd cleanup)',
                  );
                }
              } catch (_) {
                _pushSystemMessage(
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
          'delete_before_start: error processing "$relativePath": $e',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PID file
  // ---------------------------------------------------------------------------

  void _writePidFile(int pid) {
    final dir = Directory(_pidsDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File(
      p.join(_pidsDir, '$name.pid'),
    ).writeAsStringSync(_pidJson(pid), flush: true);
  }

  void _deletePidFile() {
    final file = File(p.join(_pidsDir, '$name.pid'));
    if (file.existsSync()) file.deleteSync();
  }

  String _pidJson(int pid) {
    return '{"pid":$pid,"startTime":"${DateTime.now().toIso8601String()}"}';
  }

  // ---------------------------------------------------------------------------
  // Logging
  // ---------------------------------------------------------------------------

  void _log(String message) {
    _logger?.log(message);
  }
}
