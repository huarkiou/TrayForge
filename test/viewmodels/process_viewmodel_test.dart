import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';
import '../helpers/test_mocks.dart';

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
// Recording fake — proves the viewmodel routes through manager.toggle
// ---------------------------------------------------------------------------

/// A ProcessManager fake that records which lifecycle method was called.
///
/// The VM must call `toggle(name)` — never `start`/`stop` directly — so the
/// start/stop decision stays in ProcessController.
class _RecordingManager extends Fake implements ProcessManager {
  int toggleCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  ProcState state = ProcState.stopped;

  final Map<String, StreamController<ProcState>> _stateControllers = {};
  final Map<String, StreamController<String>> _outputControllers = {};
  final Map<String, StreamController<Uri>> _webuiControllers = {};

  @override
  Stream<ProcState> stateStream(String name) {
    return _stateControllers
        .putIfAbsent(
          name,
          () => StreamController<ProcState>.broadcast(sync: true),
        )
        .stream;
  }

  @override
  Stream<String> outputStream(String name) {
    return _outputControllers
        .putIfAbsent(name, () => StreamController<String>.broadcast(sync: true))
        .stream;
  }

  @override
  Stream<Uri> webUiStream(String name) {
    return _webuiControllers
        .putIfAbsent(name, () => StreamController<Uri>.broadcast(sync: true))
        .stream;
  }

  @override
  ProcState getState(String name) => state;

  @override
  Future<void> toggle(String name) async {
    toggleCalls++;
  }

  @override
  Future<void> start(String name) async {
    startCalls++;
  }

  @override
  Future<void> stop(String name) async {
    stopCalls++;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProcessViewModel', () {
    late Directory tmpDir;
    late ConfigStore configStore;
    late MockProcessRunner mockRunner;
    late MockProcessHandle mockHandle;
    late ProcessManager manager;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('tf_test_');
      configStore = ConfigStore(dataDir: tmpDir.path);
      mockRunner = MockProcessRunner();
      mockHandle = MockProcessHandle(pid: 42);
      mockRunner.nextHandle = mockHandle;
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    Future<ProcessManager> createManager() async {
      final manager = ProcessManager(
        configStore: configStore,
        processRunner: mockRunner,
        dataDir: tmpDir.path,
      );
      // Materialize controllers for configured names; the manager
      // no longer lazily reads the config from disk on a miss.
      await manager.init();
      return manager;
    }

    // ---- State mirroring ----

    test('mirrors initial state from ProcessManager', () async {
      writeConfig(tmpDir, _testConfig());
      manager = await createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      expect(vm.state, ProcState.stopped);
    });

    test('mirrors state transitions from ProcessManager', () async {
      writeConfig(tmpDir, _testConfig());
      mockRunner.nextHandle = MockProcessHandle(pid: 52);
      manager = await createManager();

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
      writeConfig(tmpDir, _testConfig(outputRefreshMs: 10));
      final handle = MockProcessHandle(pid: 53);
      mockRunner.nextHandle = handle;
      manager = await createManager();

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
      writeConfig(
        tmpDir,
        _testConfig(outputRefreshMs: 10, outputHistoryLimit: 5),
      );
      final handle = MockProcessHandle(pid: 54);
      mockRunner.nextHandle = handle;
      manager = await createManager();

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
      writeConfig(
        tmpDir,
        _testConfig(outputRefreshMs: 10, webuiPattern: r'(http://[\d.:]+)'),
      );
      final handle = MockProcessHandle(pid: 55);
      mockRunner.nextHandle = handle;
      manager = await createManager();

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
      writeConfig(
        tmpDir,
        AppConfig(
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
        ),
      );
      manager = await createManager();

      final vmB = ProcessViewModel(
        name: 'svc-b',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      // Start svc-a, emit a WebUI line — svc-b should not see it.
      final mockHandleA = MockProcessHandle(pid: 1);
      mockRunner.nextHandle = mockHandleA;
      await manager.start('svc-a');
      mockHandleA.emitStdout('WebUI at http://127.0.0.1:3000\n');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(vmB.webuiUrl, isNull);
    });

    // ---- Optimistic toggle ----

    test('toggle starts stopped process', () async {
      writeConfig(tmpDir, _testConfig());
      mockRunner.nextHandle = MockProcessHandle(pid: 42);
      manager = await createManager();

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
      writeConfig(tmpDir, _testConfig());
      mockRunner.nextHandle = MockProcessHandle(pid: 43);
      manager = await createManager();

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
      writeConfig(tmpDir, _testConfig());
      mockRunner.nextHandle = MockProcessHandle(pid: 44);
      manager = await createManager();

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

    // ---- Toggle routing (decision lives in the controller) ----

    test('toggle routes through ProcessManager.toggle, never start/stop', () {
      final recording = _RecordingManager()..state = ProcState.stopped;
      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: recording,
        outputHistoryLimit: 100,
      );

      vm.toggle();

      expect(recording.toggleCalls, 1);
      expect(recording.startCalls, 0);
      expect(recording.stopCalls, 0);
    });

    test('toggle from running also routes through toggle only', () {
      final recording = _RecordingManager()..state = ProcState.running;
      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: recording,
        outputHistoryLimit: 100,
      );

      vm.toggle();

      expect(recording.toggleCalls, 1);
      expect(recording.startCalls, 0);
      expect(recording.stopCalls, 0);
    });

    test('toggle while transitioning is guarded (single manager call)', () {
      final recording = _RecordingManager()..state = ProcState.stopped;
      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: recording,
        outputHistoryLimit: 100,
      );

      vm.toggle();
      vm.toggle();
      vm.toggle();

      expect(recording.toggleCalls, 1);
      expect(vm.isTransitioning, isTrue);
    });

    test('isTransitioning clears once a terminal state arrives', () async {
      writeConfig(tmpDir, _testConfig());
      mockRunner.nextHandle = MockProcessHandle(pid: 45);
      manager = await createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      vm.toggle();
      // Intermediate state keeps the spinner visible.
      expect(vm.state, ProcState.starting);
      expect(vm.isTransitioning, isTrue);

      await Future.delayed(const Duration(milliseconds: 50));

      expect(vm.state, ProcState.running);
      expect(vm.isTransitioning, isFalse);
    });

    // ---- dispose ----

    test('dispose cancels subscriptions', () async {
      writeConfig(tmpDir, _testConfig());
      manager = await createManager();

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

    test('outputLines returns an unmodifiable list', () async {
      writeConfig(tmpDir, _testConfig());
      manager = await createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      expect(() => vm.outputLines.add('test'), throwsUnsupportedError);
    });

    // ---- Safe dispose ----

    test('addListener is no-op after dispose', () async {
      writeConfig(tmpDir, _testConfig());
      manager = await createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      vm.dispose();

      // addListener after dispose should not throw.
      var called = false;
      expect(() {
        vm.addListener(() => called = true);
      }, returnsNormally);

      // The listener should never be called.
      expect(called, false);
    });

    test('removeListener is no-op after dispose', () async {
      writeConfig(tmpDir, _testConfig());
      manager = await createManager();

      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: manager,
        outputHistoryLimit: 100,
      );

      // Add a listener first.
      final listener = () {};
      vm.addListener(listener);

      vm.dispose();

      // removeListener after dispose should not throw.
      expect(() => vm.removeListener(listener), returnsNormally);
    });
  });
}
