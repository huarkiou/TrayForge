import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/tray_viewmodel.dart';
import '../helpers/test_mocks.dart';

AppConfig _testConfig({String name = 'test-svc'}) {
  return AppConfig(
    processes: [ProcessConfig(name: name, cmd: 'test.exe')],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TrayViewModel', () {
    late Directory tmpDir;
    late ConfigStore configStore;
    late MockProcessRunner mockRunner;
    late ProcessManager manager;

    setUp(() async {
      tmpDir = Directory.systemTemp.createTempSync('tf_tray_test_');
      configStore = ConfigStore(dataDir: tmpDir.path);
      mockRunner = MockProcessRunner();
      manager = ProcessManager(
        configStore: configStore,
        processRunner: mockRunner,
        dataDir: tmpDir.path,
      );
      writeConfig(tmpDir, _testConfig());

      // Materialize controllers for configured names; the manager no
      // longer lazily reads the config from disk on a miss.
      await manager.init();
    });

    tearDown(() {
      manager.dispose();
      tmpDir.deleteSync(recursive: true);
    });

    TrayViewModel createTrayVm() {
      return TrayViewModel(
        configStore: configStore,
        processManager: manager,
        onShowDashboard: () {},
        onExit: () async {},
      );
    }

    test('menu click on stopped process starts it via toggle', () async {
      mockRunner.nextHandle = MockProcessHandle(pid: 1000);
      final vm = createTrayVm();

      final item = vm.buildMenu().getMenuItem('proc:test-svc')!;
      item.onClick!(item);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(manager.getState('test-svc'), ProcState.running);
      expect(mockRunner.starts.length, 1);
    });

    test('menu click on running process stops it via toggle', () async {
      final handle = MockProcessHandle(pid: 1001);
      mockRunner.nextHandle = handle;
      await manager.start('test-svc');
      expect(manager.getState('test-svc'), ProcState.running);

      final vm = createTrayVm();
      final item = vm.buildMenu().getMenuItem('proc:test-svc')!;
      item.onClick!(item);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(manager.getState('test-svc'), ProcState.stopped);
      expect(mockRunner.killedPids, contains(handle.pid));
      // Toggling a running process must not launch a new one.
      expect(mockRunner.starts.length, 1);
    });
  });
}
