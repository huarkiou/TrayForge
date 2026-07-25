import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/services/process_runner.dart';

// ---------------------------------------------------------------------------
// Mock process handle
// ---------------------------------------------------------------------------

class MockProcessHandle implements IProcessHandle {
  @override
  final int pid;

  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>(sync: true);
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>(sync: true);
  final Completer<int> _exitCompleter = Completer<int>();

  bool killed = false;
  ProcessSignal? lastSignal;

  MockProcessHandle({this.pid = 12345});

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  bool kill({ProcessSignal signal = ProcessSignal.sigkill}) {
    killed = true;
    lastSignal = signal;
    // Simulate process exiting after kill
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(-1);
    }
    return true;
  }

  // Test helpers ----------------------------------------------------------

  void emitStdout(String text) {
    _stdoutController.add(utf8.encode(text));
  }

  void emitStderr(String text) {
    _stderrController.add(utf8.encode(text));
  }

  void closeOutputs() {
    _stdoutController.close();
    _stderrController.close();
  }

  void completeExit(int code) {
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(code);
    }
  }
}

// ---------------------------------------------------------------------------
// Mock process runner
// ---------------------------------------------------------------------------

class MockProcessRunner implements IProcessRunner {
  final List<CapturedStart> starts = [];
  MockProcessHandle? nextHandle;
  final List<MockProcessHandle> _handleQueue = [];
  Exception? throwOnStart;
  bool isRunning = false;
  final Set<int> alivePids = {};
  final List<int> killedPids = [];
  bool killPidResult = true;
  final Set<int> pidsByCwd = {}; // PIDs returned by findPidsByCwd

  /// Enqueue handles for successive start() calls. Falls back to
  /// [nextHandle] when the queue is exhausted.
  void enqueueHandles(List<MockProcessHandle> handles) {
    _handleQueue.addAll(handles);
  }

  @override
  Future<IProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    starts.add(CapturedStart(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    ));
    if (throwOnStart != null) throw throwOnStart!;
    if (_handleQueue.isNotEmpty) return _handleQueue.removeAt(0);
    return nextHandle!;
  }

  @override
  Future<bool> isProcessRunning(String executableName) async {
    return isRunning;
  }

  @override
  Future<bool> isPidAlive(int pid) async {
    return alivePids.contains(pid);
  }

  @override
  Future<DateTime?> getProcessStartTime(int pid) async {
    // Return a fixed start time for alive PIDs; null otherwise.
    // Use the PID to generate a deterministic start time so tests can
    // pre-write matching PID files.
    if (alivePids.contains(pid)) {
      return DateTime(2025, 7, 25, 12, 0, pid % 60);
    }
    return null;
  }

  @override
  Future<bool> killPid(int pid) async {
    killedPids.add(pid);
    // Simulate: after kill, the PID is no longer alive.
    alivePids.remove(pid);
    return killPidResult;
  }

  @override
  Future<Set<int>> findPidsByCwd(String cwd) async {
    return pidsByCwd.toSet();
  }
}

class CapturedStart {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool runInShell;

  CapturedStart({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.environment,
    required this.runInShell,
  });
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Writes an [AppConfig] to `config.json` under [dir].
void writeConfig(Directory dir, AppConfig config) {
  final json = config.toJson();
  final encoded = const JsonEncoder.withIndent('  ').convert(json);
  final configPath = '${dir.path}/config.json';
  Directory(configPath).parent.createSync(recursive: true);
  File(configPath).writeAsStringSync(encoded, encoding: utf8, flush: true);
}
