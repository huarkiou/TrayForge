import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/services/config_store.dart';
import 'package:trayforge_flutter/services/process_manager.dart';
import 'package:trayforge_flutter/services/process_runner.dart';
import 'package:trayforge_flutter/viewmodels/dashboard_viewmodel.dart';

// ---------------------------------------------------------------------------
// Mock process runner
// ---------------------------------------------------------------------------

class _MockProcessRunner implements IProcessRunner {
  @override
  Future<IProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    throw UnimplementedError();
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DashboardViewModel', () {
    late Directory tmpDir;
    late ConfigStore configStore;
    late ProcessManager manager;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('tf_test_');
      configStore = ConfigStore(dataDir: tmpDir.path);
      manager = ProcessManager(
        configStore: configStore,
        processRunner: _MockProcessRunner(),
        dataDir: tmpDir.path,
      );
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    // ---- Empty state ----

    test('isEmpty is true when no config exists', () {
      final vm = DashboardViewModel(
        configStore: configStore,
        processManager: manager,
      );

      expect(vm.isEmpty, true);
      expect(vm.processViewModels, isEmpty);
    });

    test('isEmpty is true when config has no processes', () {
      _writeConfig(tmpDir, AppConfig(processes: []));
      // Reload config since manager already loaded during setup.
      final configStore2 = ConfigStore(dataDir: tmpDir.path);

      final vm = DashboardViewModel(
        configStore: configStore2,
        processManager: manager,
      );

      expect(vm.isEmpty, true);
    });

    // ---- Populated state ----

    test('creates ProcessViewModel for each configured process', () {
      _writeConfig(
        tmpDir,
        AppConfig(
          outputHistoryLimit: 500,
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );
      final configStore2 = ConfigStore(dataDir: tmpDir.path);

      final vm = DashboardViewModel(
        configStore: configStore2,
        processManager: manager,
      );

      expect(vm.isEmpty, false);
      expect(vm.processViewModels.length, 2);
      expect(vm.processViewModels[0].name, 'svc-a');
      expect(vm.processViewModels[1].name, 'svc-b');
    });

    // ---- Config changed ----

    test('rebuilds when configChanged fires', () async {
      _writeConfig(
        tmpDir,
        AppConfig(processes: [
          const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
        ]),
      );
      final configStore2 = ConfigStore(dataDir: tmpDir.path);

      final vm = DashboardViewModel(
        configStore: configStore2,
        processManager: manager,
      );

      expect(vm.processViewModels.length, 1);

      // Save new config with additional process.
      configStore2.save(AppConfig(processes: [
        const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
        const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
      ]));

      // ConfigStore broadcasts asynchronously.
      await Future.delayed(Duration.zero);

      expect(vm.processViewModels.length, 2);
      expect(vm.processViewModels[1].name, 'svc-b');
    });

    test('switches to empty when config removes all processes', () async {
      _writeConfig(
        tmpDir,
        AppConfig(processes: [
          const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
        ]),
      );
      final configStore2 = ConfigStore(dataDir: tmpDir.path);

      final vm = DashboardViewModel(
        configStore: configStore2,
        processManager: manager,
      );

      expect(vm.isEmpty, false);

      configStore2.save(AppConfig(processes: []));

      // ConfigStore broadcasts asynchronously.
      await Future.delayed(Duration.zero);

      expect(vm.isEmpty, true);
    });

    // ---- Corrupted config flag ----

    test('configCorrupted defaults to false', () {
      _writeConfig(tmpDir, AppConfig(processes: []));
      final configStore2 = ConfigStore(dataDir: tmpDir.path);

      final vm = DashboardViewModel(
        configStore: configStore2,
        processManager: manager,
      );

      expect(vm.configCorrupted, false);
    });

    test('configCorrupted is true when passed', () {
      final vm = DashboardViewModel(
        configStore: configStore,
        processManager: manager,
        configCorrupted: true,
      );

      expect(vm.configCorrupted, true);
    });

    test('clearCorruptedFlag clears the flag', () {
      final vm = DashboardViewModel(
        configStore: configStore,
        processManager: manager,
        configCorrupted: true,
      );

      vm.clearCorruptedFlag();
      expect(vm.configCorrupted, false);
    });

    // ---- Dispose ----

    test('dispose disposes child view models', () {
      _writeConfig(
        tmpDir,
        AppConfig(processes: [
          const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
        ]),
      );
      final configStore2 = ConfigStore(dataDir: tmpDir.path);

      final vm = DashboardViewModel(
        configStore: configStore2,
        processManager: manager,
      );

      // Should not throw.
      vm.dispose();
    });

    // ---- appTitle ----

    test('appTitle is TrayForge', () {
      expect(DashboardViewModel.appTitle, 'TrayForge');
    });
  });
}
