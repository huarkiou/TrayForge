import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/process_edit_page.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

/// Fake [ProcessManager] that reports a single named process as running.
class _RunningFakePM extends Fake implements ProcessManager {
  final String _runningName;

  _RunningFakePM(this._runningName);

  @override
  Stream<ProcState> stateStream(String name) => const Stream<ProcState>.empty();

  @override
  Stream<String> outputStream(String name) => const Stream<String>.empty();

  @override
  Stream<Uri> webUiStream(String name) => const Stream<Uri>.empty();

  @override
  Stream<void> get onConfigReloaded => const Stream<void>.empty();

  @override
  ProcState getState(String name) =>
      name == _runningName ? ProcState.running : ProcState.stopped;

  @override
  Future<void> reloadConfig(AppConfig config) async {}
}

/// Fake [ConfigStore] that holds a single [AppConfig].
class _FakeConfigStore extends Fake implements ConfigStore {
  AppConfig _config;

  _FakeConfigStore(this._config);

  @override
  AppConfig? load() => _config;

  @override
  void save(AppConfig config) {
    _config = config;
  }

  @override
  void validate(ProcessConfig config) {}
}

void main() {
  group('ProcessEditPage', () {
    // ---- Snackbar on save of running process ----

    testWidgets('shows snackbar when saving an edited running process', (
      tester,
    ) async {
      const name = 'test-svc';
      final config = AppConfig(
        processes: [const ProcessConfig(name: name, cmd: 'echo hi')],
      );

      final vm = SettingsViewModel(
        configStore: _FakeConfigStore(config),
        processManager: _RunningFakePM(name),
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProcessEditPage(
            settingsViewModel: vm,
            initial: config.processes[0],
            editIndex: 0,
          ),
        ),
      );

      // Fill a valid command so form validates.
      // The form already has the initial values from ProcessConfig.

      // Tap Save in the AppBar.
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      // Snackbar should appear before the page pops.
      expect(
        find.text(
          'Process is running — changes will take effect on next start',
        ),
        findsOneWidget,
      );
    });

    // ---- No snackbar when saving a stopped process ----

    testWidgets('shows no snackbar when saving a stopped process', (
      tester,
    ) async {
      const name = 'test-svc';
      final config = AppConfig(
        processes: [const ProcessConfig(name: name, cmd: 'echo hi')],
      );

      // _StoppedFakePM returns ProcState.stopped for everything.
      final vm = SettingsViewModel(
        configStore: _FakeConfigStore(config),
        processManager: _StoppedFakePM(),
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProcessEditPage(
            settingsViewModel: vm,
            initial: config.processes[0],
            editIndex: 0,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      expect(
        find.text(
          'Process is running — changes will take effect on next start',
        ),
        findsNothing,
      );
    });
  });
}

/// Fake [ProcessManager] where getState always returns stopped.
class _StoppedFakePM extends Fake implements ProcessManager {
  @override
  Stream<ProcState> stateStream(String name) => const Stream<ProcState>.empty();

  @override
  Stream<String> outputStream(String name) => const Stream<String>.empty();

  @override
  Stream<Uri> webUiStream(String name) => const Stream<Uri>.empty();

  @override
  Stream<void> get onConfigReloaded => const Stream<void>.empty();

  @override
  ProcState getState(String name) => ProcState.stopped;

  @override
  Future<void> reloadConfig(AppConfig config) async {}
}
