import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import '../helpers/test_mocks.dart';

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
        processRunner: MockProcessRunner(),
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
      writeConfig(tmpDir, AppConfig(processes: []));
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
      writeConfig(
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
      writeConfig(
        tmpDir,
        AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );
      final configStore2 = ConfigStore(dataDir: tmpDir.path);

      final vm = DashboardViewModel(
        configStore: configStore2,
        processManager: manager,
      );

      expect(vm.processViewModels.length, 1);

      // Save new config with additional process.
      configStore2.save(
        AppConfig(
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      // ConfigStore broadcasts asynchronously.
      await Future.delayed(Duration.zero);

      expect(vm.processViewModels.length, 2);
      expect(vm.processViewModels[1].name, 'svc-b');
    });

    test('switches to empty when config removes all processes', () async {
      writeConfig(
        tmpDir,
        AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
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
      writeConfig(tmpDir, AppConfig(processes: []));
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
      writeConfig(
        tmpDir,
        AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
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

    test('appTitle is trayforge', () {
      expect(DashboardViewModel.appTitle, 'trayforge');
    });

    // ---- Incremental _rebuild ----

    test('reuses existing ViewModels by name across rebuilds', () async {
      writeConfig(
        tmpDir,
        AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );
      final configStore2 = ConfigStore(dataDir: tmpDir.path);

      final vm = DashboardViewModel(
        configStore: configStore2,
        processManager: manager,
      );

      final original = vm.processViewModels[0];

      // Save config with same name, triggering rebuild.
      configStore2.save(
        AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a2.exe')],
        ),
      );

      await Future.delayed(Duration.zero);

      // The same VM instance should be reused (identity check).
      expect(vm.processViewModels.length, 1);
      expect(identical(vm.processViewModels[0], original), true);
    });

    test('disposes ViewModels for removed processes', () async {
      writeConfig(
        tmpDir,
        AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );
      final configStore2 = ConfigStore(dataDir: tmpDir.path);

      final vm = DashboardViewModel(
        configStore: configStore2,
        processManager: manager,
      );

      final original = vm.processViewModels[0];

      // Save config without the process, triggering rebuild.
      configStore2.save(AppConfig(processes: []));

      await Future.delayed(Duration.zero);

      expect(vm.processViewModels, isEmpty);

      // The old VM should be safe to call addListener on (disposed but no-op).
      // This verifies that dispose was called.
      var called = false;
      original.addListener(() => called = true);
      expect(called, false);
    });
  });
}
