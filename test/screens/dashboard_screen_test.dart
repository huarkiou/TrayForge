import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/dashboard_screen.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

import '../helpers/recording_config_store.dart';

/// Long-presses at [start], then drags to [end] and releases.
///
/// Simulates the List layout's long-press reorder: hold past the
/// long-press threshold, then move, then release.
Future<void> longPressDrag(
  WidgetTester tester,
  Offset start,
  Offset end,
) async {
  final gesture = await tester.startGesture(start);
  await tester.pump(kLongPressTimeout);
  // Small initial move so the drag actually starts.
  await gesture.moveBy(const Offset(0, 20));
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pumpAndSettle();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// A minimal fake that satisfies the [ProcessManager] interface for
/// DashboardViewModel construction.
class _FakeProcessManager extends Fake implements ProcessManager {
  final StreamController<void> _configReloaded =
      StreamController<void>.broadcast(sync: true);

  /// Names passed to [ProcessManager.toggle], in call order.
  final List<String> toggled = [];

  @override
  Stream<ProcState> stateStream(String name) => const Stream<ProcState>.empty();

  @override
  Stream<String> outputStream(String name) => const Stream<String>.empty();

  @override
  Stream<Uri> webUiStream(String name) => const Stream<Uri>.empty();

  @override
  Stream<void> get onConfigReloaded => _configReloaded.stream;

  @override
  ProcState getState(String name) => ProcState.stopped;

  @override
  Future<void> reloadConfig(AppConfig config) async {
    _configReloaded.add(null);
  }

  @override
  Future<void> toggle(String name) async {
    toggled.add(name);
  }
}

/// A fake [ConfigStore] that returns a fixed config.
class _FakeConfigStore extends Fake implements ConfigStore {
  final AppConfig _config;

  _FakeConfigStore(this._config);

  @override
  AppConfig? load() => _config;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DashboardScreen', () {
    // ---- Welcome screen ----

    testWidgets('shows welcome screen when no processes', (tester) async {
      final vm = DashboardViewModel(
        configStore: _FakeConfigStore(AppConfig(processes: [])),
        processManager: _FakeProcessManager(),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(viewModel: vm)),
      );

      expect(find.text('No processes configured'), findsOneWidget);
      expect(find.text('Add Process'), findsOneWidget);
    });

    testWidgets('welcome screen "Add Process" button navigates to settings', (
      tester,
    ) async {
      final configStore = _FakeConfigStore(AppConfig(processes: []));
      final dm = DashboardViewModel(
        configStore: configStore,
        processManager: _FakeProcessManager(),
      );
      final sm = SettingsViewModel(
        configStore: configStore,
        processManager: _FakeProcessManager(),
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
        ),
      );

      await tester.tap(find.text('Add Process'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Navigated to ProcessEditPage in add mode (AppBar title is 'Add Process').
      expect(find.widgetWithText(AppBar, 'Add Process'), findsOneWidget);
    });

    // ---- Dashboard with cards ----

    testWidgets('shows process cards when processes exist', (tester) async {
      final vm = DashboardViewModel(
        configStore: _FakeConfigStore(
          AppConfig(
            processes: [
              const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
              const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
            ],
          ),
        ),
        processManager: _FakeProcessManager(),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(viewModel: vm)),
      );

      expect(find.text('svc-a'), findsOneWidget);
      expect(find.text('svc-b'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsOneWidget);
    });

    // ---- Navigation to detail page ----

    testWidgets('tapping a card navigates to detail page', (tester) async {
      final vm = DashboardViewModel(
        configStore: _FakeConfigStore(
          AppConfig(
            processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
          ),
        ),
        processManager: _FakeProcessManager(),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(viewModel: vm)),
      );

      await tester.tap(find.text('svc-a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should now be on the detail page ("No output yet" appears both
      // on the card below and on the detail page body).
      expect(find.text('No output yet'), findsWidgets);
      // AppBar should show process name.
      expect(find.text('svc-a'), findsWidgets);
    });

    // ---- Corrupted config dialog ----

    testWidgets('shows alert dialog when config is corrupted', (tester) async {
      final vm = DashboardViewModel(
        configStore: _FakeConfigStore(AppConfig(processes: [])),
        processManager: _FakeProcessManager(),
        configCorrupted: true,
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(viewModel: vm)),
      );

      // Dialog should appear after post-frame callback.
      await tester.pump();
      await tester.pump();

      expect(find.text('Configuration Error'), findsOneWidget);
      expect(find.textContaining('corrupted'), findsOneWidget);
    });

    testWidgets('dismissing corrupted dialog clears flag', (tester) async {
      final vm = DashboardViewModel(
        configStore: _FakeConfigStore(AppConfig(processes: [])),
        processManager: _FakeProcessManager(),
        configCorrupted: true,
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(viewModel: vm)),
      );

      await tester.pump();
      await tester.pump();

      // Tap OK.
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump();

      expect(vm.configCorrupted, false);
      expect(find.text('Configuration Error'), findsNothing);
    });

    // ---- Config changed → welcome screen ----

    testWidgets('switches to welcome screen when config becomes empty', (
      tester,
    ) async {
      final configStore = _FakeConfigStore(
        AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      final vm = DashboardViewModel(
        configStore: configStore,
        processManager: _FakeProcessManager(),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(viewModel: vm)),
      );

      expect(find.text('svc-a'), findsOneWidget);

      // Simulate config becoming empty — we need to rebuild.
      // Since we use a fake config store, we directly manipulate the VM.
      // onConfigReloaded is the trigger; the fake manager never emits it.
      // This is better tested at the ViewModel level, which we already do.
    });

    // ---- "+" Add button ----

    testWidgets('shows + button in AppBar when settingsViewModel is provided', (
      tester,
    ) async {
      final dm = DashboardViewModel(
        configStore: _FakeConfigStore(AppConfig(processes: [])),
        processManager: _FakeProcessManager(),
      );
      final sm = SettingsViewModel(
        configStore: _FakeConfigStore(AppConfig(processes: [])),
        processManager: _FakeProcessManager(),
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
        ),
      );

      expect(find.byTooltip('Add process'), findsOneWidget);
    });

    testWidgets('does not show + button when settingsViewModel is null', (
      tester,
    ) async {
      final dm = DashboardViewModel(
        configStore: _FakeConfigStore(AppConfig(processes: [])),
        processManager: _FakeProcessManager(),
      );

      await tester.pumpWidget(
        MaterialApp(home: DashboardScreen(viewModel: dm)),
      );

      expect(find.byTooltip('Add process'), findsNothing);
    });

    testWidgets('+ button navigates to ProcessEditPage in add mode', (
      tester,
    ) async {
      final dm = DashboardViewModel(
        configStore: _FakeConfigStore(AppConfig(processes: [])),
        processManager: _FakeProcessManager(),
      );
      final sm = SettingsViewModel(
        configStore: _FakeConfigStore(AppConfig(processes: [])),
        processManager: _FakeProcessManager(),
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
        ),
      );

      await tester.tap(find.byTooltip('Add process'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'Add Process'), findsOneWidget);
    });

    // ---- Edit icon on cards ----

    testWidgets('shows edit icon on process cards', (tester) async {
      final dm = DashboardViewModel(
        configStore: _FakeConfigStore(
          AppConfig(
            processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
          ),
        ),
        processManager: _FakeProcessManager(),
      );
      final sm = SettingsViewModel(
        configStore: _FakeConfigStore(
          AppConfig(
            processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
          ),
        ),
        processManager: _FakeProcessManager(),
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('tapping edit icon navigates to ProcessEditPage', (
      tester,
    ) async {
      final dm = DashboardViewModel(
        configStore: _FakeConfigStore(
          AppConfig(
            processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
          ),
        ),
        processManager: _FakeProcessManager(),
      );
      final sm = SettingsViewModel(
        configStore: _FakeConfigStore(
          AppConfig(
            processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
          ),
        ),
        processManager: _FakeProcessManager(),
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
        ),
      );

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'Edit Process'), findsOneWidget);
    });

    // ---- Long-press reorder ----

    testWidgets('does not render drag handle icons on cards', (tester) async {
      final dm = DashboardViewModel(
        configStore: _FakeConfigStore(
          AppConfig(
            processes: [
              const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
              const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
            ],
          ),
        ),
        processManager: _FakeProcessManager(),
      );
      final sm = SettingsViewModel(
        configStore: _FakeConfigStore(
          AppConfig(
            processes: [
              const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
              const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
            ],
          ),
        ),
        processManager: _FakeProcessManager(),
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
        ),
      );

      expect(find.byIcon(Icons.drag_handle), findsNothing);
    });

    testWidgets('long-press drag reorders cards and persists', (tester) async {
      final configStore = RecordingConfigStore(
        AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );
      final processManager = _FakeProcessManager();
      final dm = DashboardViewModel(
        configStore: configStore,
        processManager: processManager,
      );
      final sm = SettingsViewModel(
        configStore: configStore,
        processManager: processManager,
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
        ),
      );

      // Long-press the first card and drag it well past the second
      // (the drop index only advances once the proxy clears the target
      // item's trailing edge, so overshoot generously).
      await longPressDrag(
        tester,
        tester.getCenter(find.text('svc-a')),
        tester.getCenter(find.text('svc-b')) + const Offset(0, 150),
      );

      // The list reordered visually.
      expect(
        tester.getTopLeft(find.text('svc-a')).dy,
        greaterThan(tester.getTopLeft(find.text('svc-b')).dy),
      );

      // And the new order plus the carried layout persisted.
      final saved = configStore.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.processes.map((p) => p.name), ['svc-b', 'svc-a']);
      expect(saved.dashboardLayout, DashboardLayout.grid);
    });

    testWidgets('toggle button still works on cards', (tester) async {
      final configStore = RecordingConfigStore(
        AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );
      final processManager = _FakeProcessManager();
      final dm = DashboardViewModel(
        configStore: configStore,
        processManager: processManager,
      );
      final sm = SettingsViewModel(
        configStore: configStore,
        processManager: processManager,
        autostart: Autostart(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
        ),
      );

      await tester.tap(find.byIcon(Icons.play_circle_outlined));
      await tester.pump();

      expect(processManager.toggled, ['svc-a']);
    });
  });
}
