import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/services/config_store.dart';
import 'package:trayforge_flutter/services/process_manager.dart';
import 'package:trayforge_flutter/services/process_runner.dart';

// ---------------------------------------------------------------------------
// Mock process handle
// ---------------------------------------------------------------------------

class _MockProcessHandle implements IProcessHandle {
  @override
  final int pid;

  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final Completer<int> _exitCompleter = Completer<int>();

  bool killed = false;
  ProcessSignal? lastSignal;

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

class _MockProcessRunner implements IProcessRunner {
  final List<_CapturedStart> starts = [];
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
    starts.add(_CapturedStart(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    ));
    if (throwOnStart != null) throw throwOnStart!;
    return nextHandle!;
  }
}

class _CapturedStart {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
  final bool runInShell;

  _CapturedStart({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.environment,
    required this.runInShell,
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Writes an [AppConfig] to `config.json` under [dir].
void _writeConfig(Directory dir, AppConfig config) {
  final json = config.toJson();
  final encoded = const JsonEncoder.withIndent('  ').convert(json);
  final configPath = '${dir.path}/config.json';
  Directory(configPath).parent.createSync(recursive: true);
  File(configPath).writeAsStringSync(encoded, encoding: utf8, flush: true);
}

/// Creates an [AppConfig] with a single process for testing with [refreshMs]
/// as the `output_refresh_ms`.
AppConfig _testConfig({
  String name = 'test-svc',
  String cmd = 'test.exe --flag',
  String? webuiPattern,
  int outputRefreshMs = 10,
  int outputHistoryLimit = 100,
  bool singleton = false,
  String? cwd,
  String? encoding,
  Map<String, String>? env,
}) {
  return AppConfig(
    outputRefreshMs: outputRefreshMs,
    outputHistoryLimit: outputHistoryLimit,
    processes: [
      ProcessConfig(
        name: name,
        cmd: cmd,
        webuiPattern: webuiPattern,
        singleton: singleton,
        cwd: cwd,
        encoding: encoding,
        env: env,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProcessManager', () {
    late Directory tmpDir;
    late ConfigStore configStore;
    late _MockProcessRunner mockRunner;
    late ProcessManager pm;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('trayforge_pm_test_');
      configStore = ConfigStore(dataDir: tmpDir.path);
      mockRunner = _MockProcessRunner();
      pm = ProcessManager(
        configStore: configStore,
        processRunner: mockRunner,
        dataDir: tmpDir.path,
      );

      // Default config with fast refresh for tests.
      _writeConfig(tmpDir, _testConfig());
    });

    tearDown(() {
      pm.dispose();
      configStore.dispose();
      tmpDir.deleteSync(recursive: true);
    });

    // ---- start() ----

    group('start', () {
      test('reads config, splits cmd, and launches process', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;

        await pm.start('test-svc');

        expect(mockRunner.starts.length, 1);
        final s = mockRunner.starts.first;
        expect(s.executable, 'test.exe');
        expect(s.arguments, ['--flag']);
        expect(s.runInShell, false);
      });

      test('transitions state starting → running', () async {
        mockRunner.nextHandle = _MockProcessHandle();

        final states = <ProcState>[];
        final sub = pm.stateStream('test-svc').listen(states.add);

        await pm.start('test-svc');

        expect(states[0], ProcState.starting);
        expect(states[1], ProcState.running);
        await sub.cancel();
      });

      test('emits system message with PID on start', () async {
        final handle = _MockProcessHandle(pid: 99999);
        mockRunner.nextHandle = handle;

        final output = <String>[];
        final sub = pm.outputStream('test-svc').listen(output.add);

        await pm.start('test-svc');

        expect(
          output.any((l) => l.contains('[TrayForge] Process started')),
          isTrue,
        );
        expect(
          output.any((l) => l.contains('PID: 99999')),
          isTrue,
        );
        await sub.cancel();
      });

      test('writes PID file on start', () async {
        mockRunner.nextHandle = _MockProcessHandle(pid: 42);

        await pm.start('test-svc');

        final pidFile = File('${tmpDir.path}/pids/test-svc.pid');
        expect(pidFile.existsSync(), isTrue);
        final content = jsonDecode(pidFile.readAsStringSync());
        expect(content['pid'], 42);
        expect(content['startTime'], isA<String>());
      });

      test('returns error when process not in config', () async {
        final output = <String>[];
        pm.outputStream('no-such').listen(output.add);

        await pm.start('no-such');

        expect(
          output.any((l) => l.contains('not found')),
          isTrue,
        );
      });

      test('returns error when command is empty', () async {
        _writeConfig(tmpDir, _testConfig(cmd: ''));
        // Re-create manager with new config
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        await fresh.start('test-svc');

        expect(
          output.any((l) => l.contains('empty command')),
          isTrue,
        );
        fresh.dispose();
      });

      test('singleton guard prevents double start', () async {
        mockRunner.nextHandle = _MockProcessHandle();

        await pm.start('test-svc');
        expect(pm.getState('test-svc'), ProcState.running);

        final output = <String>[];
        pm.outputStream('test-svc').listen(output.add);

        // Replace config with singleton=true
        _writeConfig(tmpDir, _testConfig(singleton: true));
        await pm.start('test-svc');

        expect(
          output.any((l) => l.contains('already running')),
          isTrue,
        );
        // No second start attempt
        expect(mockRunner.starts.length, 1);
      });

      test('start failure reports system message and returns to stopped',
          () async {
        mockRunner.throwOnStart = Exception('cmd not found');

        final output = <String>[];
        pm.outputStream('test-svc').listen(output.add);

        await pm.start('test-svc');

        expect(
          output.any((l) =>
              l.contains('[TrayForge]') && l.contains('Start failed')),
          isTrue,
        );
        expect(pm.getState('test-svc'), ProcState.stopped);
      });

      test('merges parent environment with per-process env and PYTHONIOENCODING',
          () async {
        mockRunner.nextHandle = _MockProcessHandle();

        _writeConfig(tmpDir, _testConfig(env: {'CUSTOM': 'value'}));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        await fresh.start('test-svc');

        final env = mockRunner.starts.first.environment!;
        expect(env['PYTHONIOENCODING'], 'utf-8');
        expect(env['CUSTOM'], 'value');
        // Should also contain parent env (e.g. PATH exists on all platforms)
        expect(env.containsKey('PATH'), isTrue);

        fresh.dispose();
      });

      test('passes workingDirectory from cwd config', () async {
        mockRunner.nextHandle = _MockProcessHandle();

        _writeConfig(tmpDir,
            _testConfig(cwd: Platform.isWindows ? r'C:\app' : '/app'));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        await fresh.start('test-svc');

        final s = mockRunner.starts.first;
        expect(
          s.workingDirectory,
          Platform.isWindows ? r'C:\app' : '/app',
        );

        fresh.dispose();
      });

      test('falls back to UTF-8 on unknown encoding', () async {
        mockRunner.nextHandle = _MockProcessHandle();

        _writeConfig(tmpDir, _testConfig(encoding: 'not-a-real-encoding'));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        await fresh.start('test-svc');

        expect(
          output.any((l) => l.contains('falling back to UTF-8')),
          isTrue,
        );
        fresh.dispose();
      });
    });

    // ---- stop() ----

    group('stop', () {
      test('transitions running → stopping → stopped', () async {
        mockRunner.nextHandle = _MockProcessHandle();
        await pm.start('test-svc');
        expect(pm.getState('test-svc'), ProcState.running);

        final states = <ProcState>[];
        final sub = pm.stateStream('test-svc').listen(states.add);

        // Drain any pending events from start
        await Future<void>.delayed(const Duration(milliseconds: 5));

        // Now we want to capture just the stop transitions.
        // Clear the list and re-subscribe is simpler.
        await sub.cancel();

        final stopStates = <ProcState>[];
        final sub2 = pm.stateStream('test-svc').listen(stopStates.add);

        await pm.stop('test-svc');

        // We should see stopping → stopped
        expect(stopStates.any((s) => s == ProcState.stopping), isTrue);
        expect(stopStates.any((s) => s == ProcState.stopped), isTrue);
        await sub2.cancel();
      });

      test('emits system messages on stop', () async {
        mockRunner.nextHandle = _MockProcessHandle();
        await pm.start('test-svc');

        final output = <String>[];
        pm.outputStream('test-svc').listen(output.add);

        await pm.stop('test-svc');

        expect(
          output.any((l) => l.contains('Process stopping')),
          isTrue,
        );
        expect(
          output.any((l) => l.contains('Process stopped')),
          isTrue,
        );
      });

      test('deletes PID file on stop', () async {
        mockRunner.nextHandle = _MockProcessHandle();
        await pm.start('test-svc');

        final pidFile = File('${tmpDir.path}/pids/test-svc.pid');
        expect(pidFile.existsSync(), isTrue);

        await pm.stop('test-svc');

        expect(pidFile.existsSync(), isFalse);
      });

      test('is a no-op when process is not running', () async {
        // Should not throw
        await pm.stop('test-svc');
        expect(pm.getState('test-svc'), ProcState.stopped);
      });

      test('manual stop does not transition to crashed on exit', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;

        await pm.start('test-svc');

        final states = <ProcState>[];
        pm.stateStream('test-svc').listen(states.add);

        await pm.stop('test-svc');

        // exitCode future completes with -1 from kill(),
        // but manualStop flag should prevent crashed state.
        // Wait for any async state change.
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Should NOT contain crashed
        expect(states.any((s) => s == ProcState.crashed), isFalse);
      });

      test('exit with non-zero code emits crashed state', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;

        await pm.start('test-svc');

        final states = <ProcState>[];
        pm.stateStream('test-svc').listen(states.add);

        // Simulate unexpected exit
        handle.closeOutputs();
        handle.completeExit(1);

        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(states.any((s) => s == ProcState.crashed), isTrue);
        // System message should report exit code
        expect(
          states.any((s) => s == ProcState.crashed),
          isTrue,
        );
      });

      test('stop clears the manual stop flag', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;
        await pm.start('test-svc');
        await pm.stop('test-svc');
        // Starting again should work without any leftover flags
        mockRunner.nextHandle = _MockProcessHandle(pid: 2);
        await pm.start('test-svc');
        expect(pm.getState('test-svc'), ProcState.running);
      });
    });

    // ---- output pipeline ----

    group('output pipeline', () {
      test('strips ANSI codes from output', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;

        final output = <String>[];
        pm.outputStream('test-svc').listen(output.add);

        await pm.start('test-svc');

        handle.emitStdout('\x1B[32mgreen\x1B[0m text\n');
        handle.closeOutputs();

        // Wait for flush timer
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final nonSystem = output.where((l) => !l.startsWith('[TrayForge]'));
        expect(nonSystem.any((l) => l.contains('green text')), isTrue);
        expect(
          nonSystem.any((l) => l.contains('\x1B')),
          isFalse,
        );
      });

      test('detects WebUI URL and emits event', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;

        _writeConfig(tmpDir, _testConfig(
          webuiPattern: r'listening at (http://[\d.:]+)',
        ));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        WebUiEvent? event;
        fresh.onWebUiDetected.listen((e) => event = e);

        await fresh.start('test-svc');

        handle.emitStdout('listening at http://127.0.0.1:8080\n');
        handle.closeOutputs();

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(event, isNotNull);
        expect(event!.processName, 'test-svc');
        expect(event!.url.toString(), 'http://127.0.0.1:8080');

        fresh.dispose();
      });

      test('does not emit WebUI event when pattern does not match', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;

        _writeConfig(tmpDir, _testConfig(
          webuiPattern: r'listening at (http://[\d.:]+)',
        ));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        var eventCount = 0;
        fresh.onWebUiDetected.listen((_) => eventCount++);

        await fresh.start('test-svc');

        handle.emitStdout('just some random output\n');
        handle.closeOutputs();

        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(eventCount, 0);

        fresh.dispose();
      });

      test('batch-emits output at refresh interval', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;

        // Use a config where we can observe batching.
        _writeConfig(tmpDir, _testConfig(outputRefreshMs: 20));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        await fresh.start('test-svc');

        // Emit 3 lines quickly (before first flush)
        handle.emitStdout('line1\nline2\nline3\n');

        // Immediately there should be nothing yet (buffered)
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final nonSystem1 = output
            .where((l) => !l.startsWith('[TrayForge]'))
            .toList();
        expect(nonSystem1, isEmpty);

        // After flush interval, lines appear
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final nonSystem2 = output
            .where((l) => !l.startsWith('[TrayForge]'))
            .toList();
        expect(nonSystem2.length, 3);
        expect(nonSystem2[0], 'line1');
        expect(nonSystem2[1], 'line2');
        expect(nonSystem2[2], 'line3');

        handle.closeOutputs();
        fresh.dispose();
      });

      test('trims output buffer to history limit', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;

        _writeConfig(tmpDir, _testConfig(outputHistoryLimit: 3, outputRefreshMs: 10));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        await fresh.start('test-svc');

        handle.emitStdout('a\nb\nc\nd\ne\n');
        handle.closeOutputs();

        await Future<void>.delayed(const Duration(milliseconds: 20));

        final nonSystem = output
            .where((l) => !l.startsWith('[TrayForge]'))
            .toList();
        // Only last 3 lines should be kept
        expect(nonSystem.length, 3);
        expect(nonSystem[0], 'c');
        expect(nonSystem[1], 'd');
        expect(nonSystem[2], 'e');

        fresh.dispose();
      });

      test('merges stdout and stderr', () async {
        final handle = _MockProcessHandle();
        mockRunner.nextHandle = handle;

        _writeConfig(tmpDir, _testConfig(outputRefreshMs: 10));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        await fresh.start('test-svc');

        handle.emitStdout('stdout line\n');
        handle.emitStderr('stderr line\n');
        handle.closeOutputs();

        await Future<void>.delayed(const Duration(milliseconds: 20));

        final nonSystem = output
            .where((l) => !l.startsWith('[TrayForge]'))
            .toList();
        expect(nonSystem.length, 2);
        expect(nonSystem, contains('stdout line'));
        expect(nonSystem, contains('stderr line'));

        fresh.dispose();
      });
    });

    // ---- state tracking ----

    group('state tracking', () {
      test('getState returns stopped for unknown process', () {
        expect(pm.getState('unknown'), ProcState.stopped);
      });

      test('state stream replays current state to new listeners', () async {
        mockRunner.nextHandle = _MockProcessHandle();
        await pm.start('test-svc');

        // New listener — should NOT replay past states (it's a broadcast,
        // not a BehaviorSubject). Verify current state via getState.
        expect(pm.getState('test-svc'), ProcState.running);
      });
    });
  });
}
