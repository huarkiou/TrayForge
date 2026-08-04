import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import '../helpers/test_mocks.dart';

/// Creates an [AppConfig] with a single process for testing with [refreshMs]
/// as the `output_refresh_ms`.
AppConfig _testConfig({
  String name = 'test-svc',
  String cmd = 'test.exe --flag',
  String? webuiPattern,
  int outputRefreshMs = 10,
  int outputHistoryLimit = 100,
  bool singleton = false,
  bool autostart = false,
  String? cwd,
  String? encoding,
  int? maxRestarts,
  List<String>? deleteBeforeStart,
  Map<String, String>? env,
  bool cleanupCwd = false,
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
        autostart: autostart,
        cwd: cwd,
        encoding: encoding,
        maxRestarts: maxRestarts,
        deleteBeforeStart: deleteBeforeStart ?? const [],
        env: env,
        cleanupCwd: cleanupCwd,
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
    late MockProcessRunner mockRunner;
    late ProcessManager pm;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('trayforge_pm_test_');
      configStore = ConfigStore(dataDir: tmpDir.path);
      mockRunner = MockProcessRunner();
      pm = ProcessManager(
        configStore: configStore,
        processRunner: mockRunner,
        dataDir: tmpDir.path,
      );

      // Default config with fast refresh for tests.
      writeConfig(tmpDir, _testConfig());
    });

    tearDown(() {
      pm.dispose();
      tmpDir.deleteSync(recursive: true);
    });

    // ---- start() ----

    group('start', () {
      test('reads config, splits cmd, and launches process', () async {
        final handle = MockProcessHandle();
        mockRunner.nextHandle = handle;

        await pm.start('test-svc');

        expect(mockRunner.starts.length, 1);
        final s = mockRunner.starts.first;
        expect(s.executable, 'test.exe');
        expect(s.arguments, ['--flag']);
        expect(s.runInShell, false);
      });

      test('transitions state starting → running', () async {
        mockRunner.nextHandle = MockProcessHandle();

        final states = <ProcState>[];
        final sub = pm.stateStream('test-svc').listen(states.add);

        await pm.start('test-svc');

        expect(states[0], ProcState.starting);
        expect(states[1], ProcState.running);
        await sub.cancel();
      });

      test('emits system message with PID on start', () async {
        final handle = MockProcessHandle(pid: 99999);
        mockRunner.nextHandle = handle;

        final output = <String>[];
        final sub = pm.outputStream('test-svc').listen(output.add);

        await pm.start('test-svc');

        expect(
          output.any((l) => l.contains('[trayforge] Process started')),
          isTrue,
        );
        expect(output.any((l) => l.contains('PID: 99999')), isTrue);
        await sub.cancel();
      });

      test('writes PID file on start', () async {
        mockRunner.nextHandle = MockProcessHandle(pid: 42);

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

        expect(output.any((l) => l.contains('not found')), isTrue);
      });

      test('returns error when command is empty', () async {
        writeConfig(tmpDir, _testConfig(cmd: ''));
        // Re-create manager with new config
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        await fresh.start('test-svc');

        expect(output.any((l) => l.contains('empty command')), isTrue);
        fresh.dispose();
      });

      test('singleton guard prevents double start', () async {
        mockRunner.nextHandle = MockProcessHandle();

        await pm.start('test-svc');
        expect(pm.getState('test-svc'), ProcState.running);

        final output = <String>[];
        pm.outputStream('test-svc').listen(output.add);

        // Replace config with singleton=true
        writeConfig(tmpDir, _testConfig(singleton: true));
        await pm.start('test-svc');

        expect(output.any((l) => l.contains('already running')), isTrue);
        // No second start attempt
        expect(mockRunner.starts.length, 1);
      });

      test(
        'start failure reports system message and returns to stopped',
        () async {
          mockRunner.throwOnStart = Exception('cmd not found');

          final output = <String>[];
          pm.outputStream('test-svc').listen(output.add);

          await pm.start('test-svc');

          expect(
            output.any(
              (l) => l.contains('[trayforge]') && l.contains('Start failed'),
            ),
            isTrue,
          );
          expect(pm.getState('test-svc'), ProcState.stopped);
        },
      );

      test(
        'merges parent environment with per-process env and PYTHONIOENCODING',
        () async {
          mockRunner.nextHandle = MockProcessHandle();

          writeConfig(tmpDir, _testConfig(env: {'CUSTOM': 'value'}));
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
        },
      );

      test('passes workingDirectory from cwd config', () async {
        mockRunner.nextHandle = MockProcessHandle();

        writeConfig(
          tmpDir,
          _testConfig(cwd: Platform.isWindows ? r'C:\app' : '/app'),
        );
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        await fresh.start('test-svc');

        final s = mockRunner.starts.first;
        expect(s.workingDirectory, Platform.isWindows ? r'C:\app' : '/app');

        fresh.dispose();
      });

      test('falls back to UTF-8 on unknown encoding', () async {
        mockRunner.nextHandle = MockProcessHandle();

        writeConfig(tmpDir, _testConfig(encoding: 'not-a-real-encoding'));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        await fresh.start('test-svc');

        expect(output.any((l) => l.contains('falling back to UTF-8')), isTrue);
        fresh.dispose();
      });
    });

    // ---- stop() ----

    group('stop', () {
      test('transitions running → stopping → stopped', () async {
        mockRunner.nextHandle = MockProcessHandle();
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
        mockRunner.nextHandle = MockProcessHandle();
        await pm.start('test-svc');

        final output = <String>[];
        pm.outputStream('test-svc').listen(output.add);

        await pm.stop('test-svc');

        expect(output.any((l) => l.contains('Process stopping')), isTrue);
        expect(output.any((l) => l.contains('Process stopped')), isTrue);
      });

      test('deletes PID file on stop', () async {
        mockRunner.nextHandle = MockProcessHandle();
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
        final handle = MockProcessHandle();
        mockRunner.nextHandle = handle;

        await pm.start('test-svc');
        final startCount = mockRunner.starts.length;

        final states = <ProcState>[];
        pm.stateStream('test-svc').listen(states.add);

        await pm.stop('test-svc');

        // exitCode future completes with -1 from kill(),
        // but manualStop flag should prevent crashed state.
        // Wait for any async state change.
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Should NOT contain crashed
        expect(states.any((s) => s == ProcState.crashed), isFalse);
        // Should NOT have restarted
        expect(mockRunner.starts.length, startCount);
      });

      test('exit with non-zero code emits crashed state', () async {
        final handle = MockProcessHandle();
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
        expect(states.any((s) => s == ProcState.crashed), isTrue);
      });

      test('stop clears the manual stop flag', () async {
        final handle = MockProcessHandle();
        mockRunner.nextHandle = handle;
        await pm.start('test-svc');
        await pm.stop('test-svc');
        // Starting again should work without any leftover flags
        mockRunner.nextHandle = MockProcessHandle(pid: 2);
        await pm.start('test-svc');
        expect(pm.getState('test-svc'), ProcState.running);
      });
    });

    // ---- stop during starting (pending-stop) ----

    group('stop during starting', () {
      test('kills the launched process and never reaches running', () async {
        final handle = MockProcessHandle(pid: 555);
        mockRunner.nextHandle = handle;

        final states = <ProcState>[];
        final sub = pm.stateStream('test-svc').listen(states.add);

        // start() suspends at its first await while the handle is still
        // null, so a stop() issued in the same turn hits the pending-stop
        // path deterministically.
        final startFuture = pm.start('test-svc');
        await pm.stop('test-svc');

        await startFuture;

        expect(states.contains(ProcState.running), isFalse);
        expect(pm.getState('test-svc'), ProcState.stopped);
        // The launched process was killed.
        expect(mockRunner.killedPids, contains(handle.pid));
        // The aborted launch never wrote a pid file.
        expect(File('${tmpDir.path}/pids/test-svc.pid').existsSync(), isFalse);
        await sub.cancel();
      });

      test(
        'cancels a pending cooldown restart so no relaunch occurs',
        () async {
          writeConfig(tmpDir, _testConfig(maxRestarts: 3));
          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
            cooldownDuration: const Duration(milliseconds: 100),
          );

          // Start, crash, restart once, then crash again into cooldown.
          final handle1 = MockProcessHandle(pid: 600);
          mockRunner.nextHandle = handle1;
          await fresh.start('test-svc');

          final handle2 = MockProcessHandle(pid: 601);
          mockRunner.nextHandle = handle2;
          handle1.closeOutputs();
          handle1.completeExit(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(mockRunner.starts.length, 2);
          expect(fresh.getState('test-svc'), ProcState.running);

          // Crash again immediately — enters cooldown with a restart timer.
          handle2.closeOutputs();
          handle2.completeExit(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(fresh.getState('test-svc'), ProcState.cooldown);

          // Manually start during cooldown, then stop while still starting.
          // The stale cooldown timer must NOT relaunch the process.
          final handle3 = MockProcessHandle(pid: 602);
          mockRunner.nextHandle = handle3;
          final startFuture = fresh.start('test-svc');
          await fresh.stop('test-svc');
          await startFuture;

          expect(fresh.getState('test-svc'), ProcState.stopped);

          // Wait past the cooldown window; no relaunch may occur.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          expect(mockRunner.starts.length, 3);
          expect(fresh.getState('test-svc'), ProcState.stopped);

          fresh.dispose();
        },
      );
    });

    // ---- toggle (centralized start/stop decision) ----

    group('toggle', () {
      test('starts a stopped process', () async {
        mockRunner.nextHandle = MockProcessHandle(pid: 900);

        final states = <ProcState>[];
        final sub = pm.stateStream('test-svc').listen(states.add);

        expect(pm.getState('test-svc'), ProcState.stopped);
        await pm.toggle('test-svc');

        expect(mockRunner.starts.length, 1);
        expect(pm.getState('test-svc'), ProcState.running);
        expect(states, contains(ProcState.starting));
        await sub.cancel();
      });

      test('stops a running process', () async {
        final handle = MockProcessHandle(pid: 901);
        mockRunner.nextHandle = handle;
        await pm.start('test-svc');
        expect(pm.getState('test-svc'), ProcState.running);

        await pm.toggle('test-svc');

        expect(pm.getState('test-svc'), ProcState.stopped);
        expect(mockRunner.killedPids, contains(handle.pid));
        // No new launch from the toggle.
        expect(mockRunner.starts.length, 1);
      });

      test('toggle during starting stops the launch (pending-stop)', () async {
        final handle = MockProcessHandle(pid: 902);
        mockRunner.nextHandle = handle;

        final states = <ProcState>[];
        final sub = pm.stateStream('test-svc').listen(states.add);

        // First toggle starts the launch; it suspends at its first await
        // while the handle is still null, so the second toggle hits the
        // `starting` → pending-stop path deterministically.
        final toggleFuture = pm.toggle('test-svc');
        await pm.toggle('test-svc');
        await toggleFuture;

        expect(states.contains(ProcState.running), isFalse);
        expect(pm.getState('test-svc'), ProcState.stopped);
        expect(mockRunner.killedPids, contains(handle.pid));
        expect(File('${tmpDir.path}/pids/test-svc.pid').existsSync(), isFalse);
        await sub.cancel();
      });

      test('starts a crashed process', () async {
        final handle1 = MockProcessHandle(pid: 903);
        mockRunner.nextHandle = handle1;
        await pm.start('test-svc');

        // Crash with no maxRestarts → crashed (terminal).
        handle1.closeOutputs();
        handle1.completeExit(1);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(pm.getState('test-svc'), ProcState.crashed);

        final handle2 = MockProcessHandle(pid: 904);
        mockRunner.nextHandle = handle2;
        await pm.toggle('test-svc');

        expect(pm.getState('test-svc'), ProcState.running);
        expect(mockRunner.starts.length, 2);
      });

      test(
        'starts a process in cooldown and cancels the scheduled restart',
        () async {
          writeConfig(tmpDir, _testConfig(maxRestarts: 3));
          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
            cooldownDuration: const Duration(milliseconds: 100),
          );

          // Start, crash, restart once, then crash again into cooldown.
          final handle1 = MockProcessHandle(pid: 906);
          mockRunner.nextHandle = handle1;
          await fresh.start('test-svc');

          final handle2 = MockProcessHandle(pid: 907);
          mockRunner.nextHandle = handle2;
          handle1.closeOutputs();
          handle1.completeExit(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(mockRunner.starts.length, 2);
          expect(fresh.getState('test-svc'), ProcState.running);

          // Crash again — cooldown with a scheduled restart timer.
          handle2.closeOutputs();
          handle2.completeExit(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(fresh.getState('test-svc'), ProcState.cooldown);

          // Toggle from cooldown (terminal): manual start supersedes the
          // scheduled auto-restart.
          final handle3 = MockProcessHandle(pid: 908);
          mockRunner.nextHandle = handle3;
          await fresh.toggle('test-svc');
          expect(fresh.getState('test-svc'), ProcState.running);
          expect(mockRunner.starts.length, 3);

          // Wait past the cooldown window: the stale timer must NOT launch a
          // second instance.
          await Future<void>.delayed(const Duration(milliseconds: 200));
          expect(mockRunner.starts.length, 3);
          expect(fresh.getState('test-svc'), ProcState.running);

          fresh.dispose();
        },
      );

      test('toggle during stopping is a no-op', () async {
        mockRunner.nextHandle = MockProcessHandle(pid: 905);
        await pm.start('test-svc');

        // stop() sets `stopping` synchronously and suspends at killPid.
        final stopFuture = pm.stop('test-svc');
        expect(pm.getState('test-svc'), ProcState.stopping);

        await pm.toggle('test-svc');

        await stopFuture;
        expect(pm.getState('test-svc'), ProcState.stopped);
        expect(mockRunner.starts.length, 1);
      });
    });

    // ---- safe dispose (closed-guards) ----

    group('safe dispose', () {
      test('no unhandled error when disposed during in-flight stop', () async {
        mockRunner.nextHandle = MockProcessHandle(pid: 800);
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        await fresh.start('test-svc');

        // stop() suspends at killPid; dispose runs before the continuation
        // resumes, so the stop continuation must guard on the closed
        // controller instead of throwing.
        final stopFuture = fresh.stop('test-svc');
        fresh.dispose();

        await stopFuture;
        // If the continuation threw, the test would fail with an
        // unhandled async error.
      });

      test(
        'no unhandled error when exit handler fires after dispose',
        () async {
          final handle = MockProcessHandle(pid: 801);
          mockRunner.nextHandle = handle;
          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
          );
          await fresh.start('test-svc');
          expect(fresh.getState('test-svc'), ProcState.running);

          fresh.dispose();

          // Late exit after disposal: the exit handler must not throw and
          // must not trigger a restart.
          handle.completeExit(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));

          expect(mockRunner.starts.length, 1);
        },
      );
    });

    // ---- output pipeline ----

    group('output pipeline', () {
      test('strips ANSI codes from output', () async {
        final handle = MockProcessHandle();
        mockRunner.nextHandle = handle;

        final output = <String>[];
        pm.outputStream('test-svc').listen(output.add);

        await pm.start('test-svc');

        handle.emitStdout('\x1B[32mgreen\x1B[0m text\n');
        handle.closeOutputs();

        pm.flushNow('test-svc');

        final nonSystem = output.where((l) => !l.startsWith('[trayforge]'));
        expect(nonSystem.any((l) => l.contains('green text')), isTrue);
        expect(nonSystem.any((l) => l.contains('\x1B')), isFalse);
      });

      test('detects WebUI URL and emits event', () async {
        final handle = MockProcessHandle();
        mockRunner.nextHandle = handle;

        writeConfig(
          tmpDir,
          _testConfig(webuiPattern: r'listening at (http://[\d.:]+)'),
        );
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        Uri? detectedUrl;
        fresh.webUiStream('test-svc').listen((url) => detectedUrl = url);

        await fresh.start('test-svc');

        handle.emitStdout('listening at http://127.0.0.1:8080\n');
        handle.closeOutputs();

        fresh.flushNow('test-svc');

        expect(detectedUrl, isNotNull);
        expect(detectedUrl.toString(), 'http://127.0.0.1:8080');

        fresh.dispose();
      });

      test('does not emit WebUI event when pattern does not match', () async {
        final handle = MockProcessHandle();
        mockRunner.nextHandle = handle;

        writeConfig(
          tmpDir,
          _testConfig(webuiPattern: r'listening at (http://[\d.:]+)'),
        );
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        var eventCount = 0;
        fresh.webUiStream('test-svc').listen((_) => eventCount++);

        await fresh.start('test-svc');

        handle.emitStdout('just some random output\n');
        handle.closeOutputs();

        fresh.flushNow('test-svc');

        expect(eventCount, 0);

        fresh.dispose();
      });

      test('batch-emits output at refresh interval', () async {
        final handle = MockProcessHandle();
        mockRunner.nextHandle = handle;

        // Use a config where we can observe batching.
        writeConfig(tmpDir, _testConfig(outputRefreshMs: 20));
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

        // Buffered, not yet emitted — no await needed since Timer fires async
        final nonSystem1 = output
            .where((l) => !l.startsWith('[trayforge]'))
            .toList();
        expect(nonSystem1, isEmpty);

        fresh.flushNow('test-svc');

        final nonSystem2 = output
            .where((l) => !l.startsWith('[trayforge]'))
            .toList();
        expect(nonSystem2.length, 3);
        expect(nonSystem2[0], 'line1');
        expect(nonSystem2[1], 'line2');
        expect(nonSystem2[2], 'line3');

        handle.closeOutputs();
        fresh.dispose();
      });

      test('trims output buffer to history limit', () async {
        final handle = MockProcessHandle();
        mockRunner.nextHandle = handle;

        writeConfig(
          tmpDir,
          _testConfig(outputHistoryLimit: 3, outputRefreshMs: 10),
        );
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

        fresh.flushNow('test-svc');

        final nonSystem = output
            .where((l) => !l.startsWith('[trayforge]'))
            .toList();
        // Only last 3 lines should be kept
        expect(nonSystem.length, 3);
        expect(nonSystem[0], 'c');
        expect(nonSystem[1], 'd');
        expect(nonSystem[2], 'e');

        fresh.dispose();
      });

      test('merges stdout and stderr', () async {
        final handle = MockProcessHandle();
        mockRunner.nextHandle = handle;

        writeConfig(tmpDir, _testConfig(outputRefreshMs: 10));
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

        fresh.flushNow('test-svc');

        final nonSystem = output
            .where((l) => !l.startsWith('[trayforge]'))
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

      test('getState returns running for a started process', () async {
        mockRunner.nextHandle = MockProcessHandle();
        await pm.start('test-svc');

        // New listener — should NOT replay past states (it's a broadcast,
        // not a BehaviorSubject). Verify current state via getState.
        expect(pm.getState('test-svc'), ProcState.running);
      });
    });

    // ---- crash restart ----

    group('crash restart', () {
      test('auto-restarts process on unexpected exit', () async {
        writeConfig(tmpDir, _testConfig(maxRestarts: 3));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        final handle1 = MockProcessHandle(pid: 100);
        mockRunner.nextHandle = handle1;
        await fresh.start('test-svc');
        expect(mockRunner.starts.length, 1);
        expect(fresh.getState('test-svc'), ProcState.running);

        // Simulate unexpected crash
        final handle2 = MockProcessHandle(pid: 101);
        mockRunner.nextHandle = handle2;
        handle1.closeOutputs();
        handle1.completeExit(1);

        // Wait for restart to complete
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          mockRunner.starts.length,
          2,
          reason: 'process should have been restarted',
        );
        expect(fresh.getState('test-svc'), ProcState.running);
        fresh.dispose();
      });

      test('cooldown prevents instant restart within 60 seconds', () async {
        writeConfig(tmpDir, _testConfig(maxRestarts: 3));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        final handle1 = MockProcessHandle(pid: 200);
        mockRunner.nextHandle = handle1;
        await fresh.start('test-svc');
        expect(mockRunner.starts.length, 1);

        // Simulate crash
        handle1.closeOutputs();
        handle1.completeExit(1);

        // First restart should happen
        final handle2 = MockProcessHandle(pid: 201);
        mockRunner.nextHandle = handle2;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          mockRunner.starts.length,
          2,
          reason: 'first restart should proceed',
        );

        // Crash again immediately — should enter cooldown
        handle2.closeOutputs();
        handle2.completeExit(1);

        await Future<void>.delayed(const Duration(milliseconds: 10));

        // No third start yet — cooldown active
        expect(
          mockRunner.starts.length,
          2,
          reason: 'cooldown should prevent instant restart',
        );
        expect(fresh.getState('test-svc'), ProcState.cooldown);

        fresh.dispose();
      });

      test(
        'max restarts exhausted → crashed state with system message',
        () async {
          writeConfig(tmpDir, _testConfig(maxRestarts: 1));
          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
          );

          final output = <String>[];
          fresh.outputStream('test-svc').listen(output.add);

          final handle1 = MockProcessHandle(pid: 300);
          mockRunner.nextHandle = handle1;
          await fresh.start('test-svc');

          // First crash → restart #1 (max_restarts=1, so this is the only restart)
          final handle2 = MockProcessHandle(pid: 301);
          mockRunner.nextHandle = handle2;
          handle1.closeOutputs();
          handle1.completeExit(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(mockRunner.starts.length, 2);

          // Second crash → max restarts exhausted
          handle2.closeOutputs();
          handle2.completeExit(1);

          await Future<void>.delayed(const Duration(milliseconds: 10));

          expect(fresh.getState('test-svc'), ProcState.crashed);
          expect(
            output.any(
              (l) => l.contains('[trayforge]') && l.contains('max restarts'),
            ),
            isTrue,
          );
          expect(
            mockRunner.starts.length,
            2,
            reason: 'no third start — max restarts reached',
          );

          fresh.dispose();
        },
      );

      test(
        'restart count resets after successful manual stop + restart',
        () async {
          writeConfig(tmpDir, _testConfig(maxRestarts: 3));
          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
          );

          // Start → crash → restart (count=1)
          final handle1 = MockProcessHandle(pid: 400);
          mockRunner.nextHandle = handle1;
          await fresh.start('test-svc');

          final handle2 = MockProcessHandle(pid: 401);
          mockRunner.nextHandle = handle2;
          handle1.closeOutputs();
          handle1.completeExit(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(mockRunner.starts.length, 2);

          // Manual stop resets counter
          await fresh.stop('test-svc');

          // Start fresh → restart count should be 0
          final handle3 = MockProcessHandle(pid: 402);
          mockRunner.nextHandle = handle3;
          await fresh.start('test-svc');
          expect(mockRunner.starts.length, 3);

          // Crash → should restart (count fresh)
          final handle4 = MockProcessHandle(pid: 403);
          mockRunner.nextHandle = handle4;
          handle3.closeOutputs();
          handle3.completeExit(1);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            mockRunner.starts.length,
            4,
            reason: 'restart count should have reset after manual stop',
          );

          fresh.dispose();
        },
      );
    });

    // ---- OS singleton check ----

    group('OS singleton check', () {
      test('skips start when process is already running at OS level', () async {
        mockRunner.isRunning = true;

        final output = <String>[];
        pm.outputStream('test-svc').listen(output.add);

        await pm.start('test-svc');

        expect(
          mockRunner.starts.length,
          0,
          reason: 'should not launch if already running',
        );
        expect(
          output.any(
            (l) => l.contains('[trayforge]') && l.contains('already running'),
          ),
          isTrue,
        );
        expect(pm.getState('test-svc'), ProcState.stopped);
      });

      test('starts normally when process is not running at OS level', () async {
        mockRunner.isRunning = false;
        mockRunner.nextHandle = MockProcessHandle();

        await pm.start('test-svc');

        expect(mockRunner.starts.length, 1);
        expect(pm.getState('test-svc'), ProcState.running);
      });
    });

    // ---- PID file startup cleanup ----

    group('PID file startup cleanup', () {
      test('cleans up stale PID files on construction', () async {
        // Write a stale PID file before constructing ProcessManager.
        final pidsDir = Directory('${tmpDir.path}/pids');
        pidsDir.createSync(recursive: true);
        File('${pidsDir.path}/stale.pid').writeAsStringSync(
          '{"pid":99999,"startTime":"2000-01-01T00:00:00.000"}',
        );

        // Constructing ProcessManager triggers async cleanup.
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        await fresh.init();

        // Stale PID file should be gone.
        expect(File('${pidsDir.path}/stale.pid').existsSync(), isFalse);

        fresh.dispose();
      });

      test(
        'kills orphan with matching startTime and deletes PID file',
        () async {
          // Pre-write a PID file with a start time that matches what the
          // mock returns for PID 12345.
          final pidsDir = Directory('${tmpDir.path}/pids');
          pidsDir.createSync(recursive: true);
          File('${pidsDir.path}/test-svc.pid').writeAsStringSync(
            '{"pid":12345,"startTime":"2025-07-25T12:00:45.000"}',
          );

          // PID 12345 is alive AND startTime matches — orphan from a
          // previous trayforge session.
          mockRunner.alivePids.add(12345);

          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
          );

          await fresh.init();

          // Orphan should be killed and its PID file deleted.
          expect(mockRunner.killedPids, contains(12345));
          expect(File('${pidsDir.path}/test-svc.pid').existsSync(), isFalse);

          fresh.dispose();
        },
      );

      test('deletes PID file on startTime mismatch (PID reuse)', () async {
        // Pre-write a PID file with a startTime that does NOT match
        // what the mock returns for PID 99999.
        final pidsDir = Directory('${tmpDir.path}/pids');
        pidsDir.createSync(recursive: true);
        File('${pidsDir.path}/zombie.pid').writeAsStringSync(
          '{"pid":99999,"startTime":"2024-01-01T00:00:00.000"}',
        );

        // PID 99999 is "alive" but mock returns 2025-07-25T12:00:39.
        // The startTime mismatch → PID reuse detected.
        mockRunner.alivePids.add(99999);

        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        await fresh.init();

        // PID file should be deleted — startTime mismatch indicates reuse.
        expect(File('${pidsDir.path}/zombie.pid').existsSync(), isFalse);

        fresh.dispose();
      });

      test(
        'kills orphan processes on construction (matching startTime)',
        () async {
          // Pre-write a PID file with a startTime that matches the mock.
          // Mock returns DateTime(2025, 7, 25, 12, 0, 42 % 60) = 12:00:42
          // for PID 42.
          final pidsDir = Directory('${tmpDir.path}/pids');
          pidsDir.createSync(recursive: true);
          File('${pidsDir.path}/orphan-svc.pid').writeAsStringSync(
            '{"pid":42,"startTime":"2025-07-25T12:00:42.000"}',
          );

          mockRunner.alivePids.add(42);

          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
          );

          await fresh.init();

          // Orphan should have been killed.
          expect(mockRunner.killedPids, contains(42));
          // PID file should have been deleted after kill.
          expect(File('${pidsDir.path}/orphan-svc.pid').existsSync(), isFalse);

          fresh.dispose();
        },
      );

      test(
        'does not kill non-orphan (different startTime = PID reuse)',
        () async {
          // Pre-write a PID file with a startTime that does NOT match.
          final pidsDir = Directory('${tmpDir.path}/pids');
          pidsDir.createSync(recursive: true);
          File('${pidsDir.path}/reused.pid').writeAsStringSync(
            '{"pid":77777,"startTime":"2024-01-01T00:00:00.000"}',
          );

          // PID 77777 is alive but mock returns 2025-07-25T12:00:17 → mismatch.
          mockRunner.alivePids.add(77777);

          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
          );

          await fresh.init();

          // killPid should NOT have been called — startTime mismatch means
          // PID was reused, not an orphan.
          expect(mockRunner.killedPids, isNot(contains(77777)));
          // PID file should still be deleted (stale entry).
          expect(File('${pidsDir.path}/reused.pid').existsSync(), isFalse);

          fresh.dispose();
        },
      );

      test(
        'delete_before_start succeeds after orphan cleanup kills holder',
        () async {
          // Simulate an orphan that held a lock file, then verify the lock
          // is deletable on start because the orphan was killed at startup.
          final pidsDir = Directory('${tmpDir.path}/pids');
          pidsDir.createSync(recursive: true);

          // Pre-write orphan PID file for a process that we'll later start.
          File('${pidsDir.path}/test-svc.pid').writeAsStringSync(
            '{"pid":99,"startTime":"2025-07-25T12:00:39.000"}',
          );

          // Create a lock file in the cwd.
          final cwdDir = Directory('${tmpDir.path}/app');
          cwdDir.createSync(recursive: true);
          final lockFile = File('${cwdDir.path}/app.lock');
          lockFile.writeAsStringSync('stale lock');

          mockRunner.alivePids.add(99);

          // Construction kills the orphan (PID 99).
          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
          );

          await fresh.init();

          // Orphan was killed.
          expect(mockRunner.killedPids, contains(99));
          expect(File('${pidsDir.path}/test-svc.pid').existsSync(), isFalse);

          // Now configure the process with delete_before_start pointing at
          // the lock file. Since the orphan was killed, the file should be
          // deletable when start() runs.
          writeConfig(
            tmpDir,
            _testConfig(cwd: cwdDir.path, deleteBeforeStart: ['app.lock']),
          );

          mockRunner.nextHandle = MockProcessHandle(pid: 100);
          await fresh.start('test-svc');

          // Lock file should be gone — deleted by delete_before_start since
          // the orphan holder was killed at startup.
          expect(lockFile.existsSync(), isFalse);
          expect(fresh.getState('test-svc'), ProcState.running);

          fresh.dispose();
        },
      );
    });

    // ---- delete_before_start ----

    group('delete_before_start', () {
      test('deletes files before start', () async {
        final cwdDir = Directory('${tmpDir.path}/app');
        cwdDir.createSync(recursive: true);
        final lockFile = File('${cwdDir.path}/app.lock');
        lockFile.writeAsStringSync('stale lock');
        expect(lockFile.existsSync(), isTrue);

        writeConfig(
          tmpDir,
          _testConfig(cwd: cwdDir.path, deleteBeforeStart: ['app.lock']),
        );
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        mockRunner.nextHandle = MockProcessHandle();
        await fresh.start('test-svc');

        expect(
          lockFile.existsSync(),
          isFalse,
          reason: 'delete_before_start file should be deleted',
        );

        fresh.dispose();
      });

      test('blocks path escape attempts', () async {
        writeConfig(
          tmpDir,
          _testConfig(
            cwd: '${tmpDir.path}/app',
            deleteBeforeStart: ['../escape.txt'],
          ),
        );
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        mockRunner.nextHandle = MockProcessHandle();
        await fresh.start('test-svc');

        expect(
          output.any(
            (l) => l.contains('[trayforge]') && l.contains('path escape'),
          ),
          isTrue,
        );

        fresh.dispose();
      });

      test('skips delete_before_start when cwd is null', () async {
        writeConfig(
          tmpDir,
          _testConfig(cwd: null, deleteBeforeStart: ['app.lock']),
        );
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        mockRunner.nextHandle = MockProcessHandle();
        // Should not throw.
        await fresh.start('test-svc');
        expect(fresh.getState('test-svc'), ProcState.running);

        fresh.dispose();
      });
    });

    // ---- autostart ----

    group('autostart', () {
      test('starts autostart processes on construction', () async {
        // Write a config with two processes: one autostart, one not.
        final testConfig = AppConfig(
          outputRefreshMs: 10,
          outputHistoryLimit: 100,
          processes: [
            ProcessConfig(name: 'auto-svc', cmd: 'auto.exe', autostart: true),
            ProcessConfig(name: 'manual-svc', cmd: 'manual.exe'),
            ProcessConfig(name: 'also-auto', cmd: 'also.exe', autostart: true),
          ],
        );

        // Write config via ConfigStore so load() returns it.
        writeConfig(tmpDir, testConfig);

        mockRunner.enqueueHandles([
          MockProcessHandle(pid: 10),
          MockProcessHandle(pid: 11),
        ]);

        // Construction triggers autostart.
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        await fresh.init();

        expect(mockRunner.starts.length, 2);
        final started = mockRunner.starts.map((s) => s.executable).toSet();
        expect(started, contains('auto.exe'));
        expect(started, contains('also.exe'));
        expect(started, isNot(contains('manual.exe')));

        fresh.dispose();
      });

      test('skips autostart when no config is loaded', () async {
        // Don't write any config.
        final emptyDir = Directory.systemTemp.createTempSync(
          'trayforge_pm_empty_',
        );
        final emptyStore = ConfigStore(dataDir: emptyDir.path);

        final fresh = ProcessManager(
          configStore: emptyStore,
          processRunner: mockRunner,
          dataDir: emptyDir.path,
        );

        await fresh.init();

        expect(mockRunner.starts.length, 0, reason: 'no config → no autostart');

        fresh.dispose();
        emptyDir.deleteSync(recursive: true);
      });
    });

    // ---- reloadConfig ----

    group('reloadConfig', () {
      test('starts new autostart processes and stops removed ones', () async {
        writeConfig(tmpDir, _testConfig(name: 'keep-me', autostart: true));

        mockRunner.nextHandle = MockProcessHandle(pid: 800);
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        await fresh.init();
        expect(mockRunner.starts.length, 1);
        expect(fresh.getState('keep-me'), ProcState.running);

        // Reload: remove 'keep-me', add 'new-svc' with autostart.
        // Save the new config to disk so _lookupConfig can find it.
        final newConfig = AppConfig(
          outputRefreshMs: 10,
          outputHistoryLimit: 100,
          processes: [
            ProcessConfig(name: 'new-svc', cmd: 'new.exe', autostart: true),
          ],
        );
        writeConfig(tmpDir, newConfig);

        mockRunner.nextHandle = MockProcessHandle(pid: 801);
        await fresh.reloadConfig(newConfig);

        // 'keep-me' should have been stopped.
        expect(fresh.getState('keep-me'), ProcState.stopped);
        // 'new-svc' should have been started.
        expect(fresh.getState('new-svc'), ProcState.running);
        // Total starts: 1 (autostart) + 1 (reload new-svc) = 2
        expect(mockRunner.starts.length, 2);

        fresh.dispose();
      });

      test('leaves running processes untouched on reload', () async {
        writeConfig(tmpDir, _testConfig(name: 'svc1', autostart: true));

        mockRunner.nextHandle = MockProcessHandle(pid: 900);
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        await fresh.init();
        expect(fresh.getState('svc1'), ProcState.running);

        // Reload with same config — svc1 should stay running.
        final output = <String>[];
        fresh.outputStream('svc1').listen(output.add);

        final sameConfig = AppConfig(
          outputRefreshMs: 10,
          outputHistoryLimit: 100,
          processes: [
            ProcessConfig(name: 'svc1', cmd: 'svc1.exe', autostart: true),
          ],
        );
        writeConfig(tmpDir, sameConfig);

        mockRunner.nextHandle = MockProcessHandle(pid: 901);
        await fresh.reloadConfig(sameConfig);

        expect(fresh.getState('svc1'), ProcState.running);
        // No second start call.
        expect(mockRunner.starts.length, 1);

        fresh.dispose();
      });

      test('emits onConfigReloaded after processing', () async {
        writeConfig(tmpDir, _testConfig(name: 'svc1', autostart: true));

        mockRunner.nextHandle = MockProcessHandle(pid: 700);
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        await fresh.init();

        final events = <void>[];
        final sub = fresh.onConfigReloaded.listen((_) => events.add(null));

        final config = AppConfig(
          outputRefreshMs: 10,
          outputHistoryLimit: 100,
          processes: [
            ProcessConfig(name: 'svc1', cmd: 'svc1.exe', autostart: true),
          ],
        );
        writeConfig(tmpDir, config);
        await fresh.reloadConfig(config);

        expect(events.length, 1);

        await sub.cancel();
        fresh.dispose();
      });

      test('cleans up stale _procs entries for deleted processes', () async {
        // Start a process so it has a _ProcsRuntime entry.
        writeConfig(tmpDir, _testConfig(name: 'will-be-removed'));
        mockRunner.nextHandle = MockProcessHandle(pid: 600);

        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );
        await fresh.start('will-be-removed');

        // Verify the entry exists.
        expect(fresh.getState('will-be-removed'), ProcState.running);

        // Reload without the process.
        final newConfig = AppConfig(
          outputRefreshMs: 10,
          outputHistoryLimit: 100,
          processes: [],
        );
        writeConfig(tmpDir, newConfig);
        await fresh.reloadConfig(newConfig);

        // The runtime entry should be cleaned up.
        expect(fresh.getState('will-be-removed'), ProcState.stopped);

        fresh.dispose();
      });
    });

    // ---- cleanup_cwd ----

    group('cleanup_cwd', () {
      test('kills processes with matching cwd before start', () async {
        final cwdDir = Directory('${tmpDir.path}/app');
        cwdDir.createSync(recursive: true);

        writeConfig(tmpDir, _testConfig(cwd: cwdDir.path, cleanupCwd: true));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        // Two residual PIDs in the same cwd.
        mockRunner.pidsByCwd.addAll([100, 200]);
        mockRunner.nextHandle = MockProcessHandle(pid: 300);

        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        await fresh.start('test-svc');

        // Both residuals should have been killed.
        expect(mockRunner.killedPids, contains(100));
        expect(mockRunner.killedPids, contains(200));
        expect(
          output.any(
            (l) => l.contains('[trayforge]') && l.contains('residual process'),
          ),
          isTrue,
        );
        // Process should have started normally after cleanup.
        expect(fresh.getState('test-svc'), ProcState.running);

        fresh.dispose();
      });

      test('skips cleanup when cleanup_cwd is false', () async {
        final cwdDir = Directory('${tmpDir.path}/app');
        cwdDir.createSync(recursive: true);

        writeConfig(tmpDir, _testConfig(cwd: cwdDir.path, cleanupCwd: false));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        mockRunner.pidsByCwd.addAll([100, 200]);
        mockRunner.nextHandle = MockProcessHandle(pid: 300);

        await fresh.start('test-svc');

        // No PIDs should have been killed — cleanup_cwd is disabled.
        expect(mockRunner.killedPids, isNot(contains(100)));
        expect(mockRunner.killedPids, isNot(contains(200)));
        expect(fresh.getState('test-svc'), ProcState.running);

        fresh.dispose();
      });

      test('does nothing when no residual processes found', () async {
        final cwdDir = Directory('${tmpDir.path}/app');
        cwdDir.createSync(recursive: true);

        writeConfig(tmpDir, _testConfig(cwd: cwdDir.path, cleanupCwd: true));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        // No PIDs in pidsByCwd — empty cwd.
        mockRunner.nextHandle = MockProcessHandle(pid: 300);

        await fresh.start('test-svc');

        // No kills, no errors.
        expect(mockRunner.killedPids, isEmpty);
        expect(fresh.getState('test-svc'), ProcState.running);

        fresh.dispose();
      });

      test(
        'skips cleanup when cwd is null (even if cleanup_cwd is true)',
        () async {
          writeConfig(tmpDir, _testConfig(cwd: null, cleanupCwd: true));
          final fresh = ProcessManager(
            configStore: configStore,
            processRunner: mockRunner,
            dataDir: tmpDir.path,
          );

          mockRunner.nextHandle = MockProcessHandle(pid: 300);

          // Should not throw — cleanup is skipped when cwd is null.
          await fresh.start('test-svc');

          expect(mockRunner.killedPids, isEmpty);
          expect(fresh.getState('test-svc'), ProcState.running);

          fresh.dispose();
        },
      );

      test('emits system message with kill count', () async {
        final cwdDir = Directory('${tmpDir.path}/app');
        cwdDir.createSync(recursive: true);

        writeConfig(tmpDir, _testConfig(cwd: cwdDir.path, cleanupCwd: true));
        final fresh = ProcessManager(
          configStore: configStore,
          processRunner: mockRunner,
          dataDir: tmpDir.path,
        );

        mockRunner.pidsByCwd.addAll([10, 20, 30]);
        mockRunner.nextHandle = MockProcessHandle(pid: 40);

        final output = <String>[];
        fresh.outputStream('test-svc').listen(output.add);

        await fresh.start('test-svc');

        expect(
          output.any(
            (l) => l.contains('[trayforge]') && l.contains('killed 3 residual'),
          ),
          isTrue,
        );

        fresh.dispose();
      });
    });
  });
}
