import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/services/config_store.dart';
import 'package:trayforge_flutter/services/process_manager.dart';
import 'package:trayforge_flutter/services/process_runner.dart';
import 'package:trayforge_flutter/viewmodels/process_viewmodel.dart';

// ---------------------------------------------------------------------------
// Mock process handle (copied from process_manager_test)
// ---------------------------------------------------------------------------

class _MockProcessHandle implements IProcessHandle {
  @override
  final int pid;

  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>(sync: true);
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>(sync: true);
  final Completer<int> _exitCompleter = Completer<int>();

  bool killed = false;

  _MockProcessHandle({this.pid = 12345});

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  bool kill({ProcessSignal signal = ProcessSignal.sigkill}) {
    killed = true;
    if (!_exitCompleter.isCompleted) {
      _exitCompleter.complete(-1);
    }
    return true;
  }

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

class _MockProcessRunner implements IProcessRunner {
  _MockProcessHandle? nextHandle;
  Exception? throwOnStart;

  @override
  Future<IProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    if (throwOnStart != null) throw throwOnStart!;
    return nextHandle!;
  }

  @override
  Future<bool> isProcessRunning(String executableName) async => false;

  @override
  Future<bool> isPidAlive(int pid) async => false;

  @override
  Future<DateTime?> getProcessStartTime(int pid) async => null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _writeConfig(Directory dir, AppConfig config) {
  final encoded =
      const JsonEncoder.withIndent('  ').convert(config.toJson());
  File('${dir.path}/config.json')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(encoded, encoding: utf8, flush: true);
}

AppConfig _testConfig({
  String name = 'test-svc',
  int outputRefreshMs = 100,
  int outputHistoryLimit = 200,
  String? webuiPattern,
  bool singleton = false,
}) {
  return AppConfig(
    outputRefreshMs: outputRefreshMs,
    outputHistoryLimit: outputHistoryLimit,
    processes: [
      ProcessConfig(
        name: name,
        cmd: 'test.exe',
        singleton: singleton,
        webuiPattern: webuiPattern,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProcessViewModel', () {
    late Directory tmpDir;
    late ConfigStore configStore;
    late _MockProcessRunner mockRunner;
    late _MockProcessHandle mockHandle;
    late ProcessManager manager;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('tf_test_');
      configStore = ConfigStore(dataDir: tmpDir.path);
      mockRunner = _MockProcessRunner();
      mockHandle = _MockProcessHandle(pid: 42);
      mockRunner.nextHandle = mockHandle;
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    ProcessManager createManager() {
      return ProcessManager(
        configStore: configStore,
        processRunner: mockRunner,
        dataDir: tmpDir.path,
      );
    }

    // ---- State mirroring ----

    test('mirrors initial state from ProcessManager', () {
      _writeConfig(tmpDir, _testConfig());
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      expect(vm.state, ProcState.stopped);
    });

    test('mirrors state transitions from ProcessManager', () async {
      _writeConfig(tmpDir, _testConfig());
      mockRunner.nextHandle = _MockProcessHandle(pid: 52);
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      await manager.start('test-svc');

      // After start, state should be running.
      expect(vm.state, ProcState.running);

      await manager.stop('test-svc');

      expect(vm.state, ProcState.stopped);
    });

    // ---- Output accumulation ----

    test('accumulates output lines from ProcessManager', () async {
      _writeConfig(tmpDir, _testConfig(outputRefreshMs: 10));
      final handle = _MockProcessHandle(pid: 53);
      mockRunner.nextHandle = handle;
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      await manager.start('test-svc');
      handle.emitStdout('line 1\n');
      handle.emitStdout('line 2\n');
      handle.emitStderr('err 1\n');

      // Wait for flush timer.
      await Future.delayed(const Duration(milliseconds: 50));

      expect(vm.outputLines, contains('line 1'));
      expect(vm.outputLines, contains('line 2'));
      expect(vm.outputLines, contains('err 1'));
    });

    test('trims output buffer when exceeding history limit', () async {
      _writeConfig(tmpDir, _testConfig(
        outputRefreshMs: 10,
        outputHistoryLimit: 5,
      ));
      final handle = _MockProcessHandle(pid: 54);
      mockRunner.nextHandle = handle;
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 5,
      );

      await manager.start('test-svc');

      // Emit 10 lines.
      for (var i = 0; i < 10; i++) {
        handle.emitStdout('line $i\n');
      }

      await Future.delayed(const Duration(milliseconds: 50));

      // Only last 5 lines should remain.
      expect(vm.outputLines.length, lessThanOrEqualTo(5));
      expect(vm.outputLines.last, 'line 9');
    });

    // ---- WebUI detection ----

    test('detects WebUI URL from ProcessManager events', () async {
      _writeConfig(tmpDir, _testConfig(
        outputRefreshMs: 10,
        webuiPattern: r'(http://[\d.:]+)',
      ));
      final handle = _MockProcessHandle(pid: 55);
      mockRunner.nextHandle = handle;
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      await manager.start('test-svc');
      handle.emitStdout('WebUI started at http://127.0.0.1:8080\n');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(vm.webuiUrl, isNotNull);
      expect(vm.webuiUrl.toString(), 'http://127.0.0.1:8080');
    });

    test('ignores WebUI events for other processes', () async {
      _writeConfig(tmpDir, AppConfig(
        outputRefreshMs: 10,
        outputHistoryLimit: 100,
        processes: [
          const ProcessConfig(
            name: 'svc-a',
            cmd: 'a.exe',
            webuiPattern: r'(http://[\d.:]+)',
          ),
          const ProcessConfig(
            name: 'svc-b',
            cmd: 'b.exe',
            webuiPattern: r'(http://[\d.:]+)',
          ),
        ],
      ));
      manager = createManager();

      final vmB = ProcessViewModel(
        name: 'svc-b',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      // Start svc-a, emit a WebUI line — svc-b should not see it.
      final mockHandleA = _MockProcessHandle(pid: 1);
      mockRunner.nextHandle = mockHandleA;
      await manager.start('svc-a');
      mockHandleA.emitStdout('WebUI at http://127.0.0.1:3000\n');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(vmB.webuiUrl, isNull);
    });

    // ---- Optimistic toggle ----

    test('toggle starts stopped process', () async {
      _writeConfig(tmpDir, _testConfig());
      mockRunner.nextHandle = _MockProcessHandle(pid: 42);
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      // Initially stopped.
      expect(vm.state, ProcState.stopped);

      vm.toggle();

      // ProcessManager emits starting synchronously, which clears
      // the optimistic state. The ProcessViewModel should reflect
      // the real ProcessManager state.
      expect(vm.state, ProcState.starting);

      // Allow process manager to complete.
      await Future.delayed(const Duration(milliseconds: 50));

      expect(vm.state, ProcState.running);
    });

    test('toggle stops running process', () async {
      _writeConfig(tmpDir, _testConfig());
      mockRunner.nextHandle = _MockProcessHandle(pid: 43);
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      // Start first.
      await manager.start('test-svc');
      expect(vm.state, ProcState.running);

      // Toggle to stop.
      vm.toggle();

      // ProcessManager emits stopping synchronously.
      expect(vm.state, ProcState.stopping);
    });

    test('toggle is idempotent while starting', () async {
      _writeConfig(tmpDir, _testConfig());
      mockRunner.nextHandle = _MockProcessHandle(pid: 44);
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      vm.toggle();
      expect(vm.state, ProcState.starting);

      // Another toggle while already starting should be a no-op.
      vm.toggle();
      expect(vm.state, ProcState.starting);
    });

    // ---- dispose ----

    test('dispose cancels subscriptions', () async {
      _writeConfig(tmpDir, _testConfig());
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      vm.dispose();

      // After dispose, further state changes should not cause issues.
      // (No listener to check, just ensure no errors.)
    });

    // ---- outputLines is unmodifiable ----

    test('outputLines returns an unmodifiable list', () {
      _writeConfig(tmpDir, _testConfig());
      manager = createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      expect(
        () => vm.outputLines.add('test'),
        throwsUnsupportedError,
      );
    });
  });
}
