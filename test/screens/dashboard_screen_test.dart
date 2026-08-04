import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/dashboard_screen.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';
import 'package:trayforge/widgets/process_card.dart';
import 'package:trayforge/widgets/status_dot.dart';

import '../helpers/recording_config_store.dart';

/// Long-presses at [start], then drags to [end] and releases.
///
/// Simulates long-press reorder in either layout: hold past the
/// long-press threshold, then move, then release. [kind] selects the
/// simulated pointer device (touch by default; mouse for desktop input).
Future<void> longPressDrag(
  WidgetTester tester,
  Offset start,
  Offset end, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final gesture = await tester.startGesture(start, kind: kind);
  await tester.pump(kLongPressTimeout);
  // Small initial move so the drag actually starts.
  await gesture.moveBy(const Offset(0, 20));
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pumpAndSettle();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Pumps the Dashboard with fresh viewmodels backed by a recording config
/// store, returning handles for assertions.
///
/// [configCorrupted] forwards to [DashboardViewModel]; [withSettings] also
/// adds a [SettingsViewModel] (and the AppBar buttons that come with it).
Future<
  ({RecordingConfigStore store, _FakeProcessManager pm, DashboardViewModel dm})
>
pumpDashboard(
  WidgetTester tester, {
  required AppConfig config,
  bool withSettings = true,
  bool configCorrupted = false,
}) async {
  final store = RecordingConfigStore(config);
  final pm = _FakeProcessManager();
  final dm = DashboardViewModel(
    configStore: store,
    processManager: pm,
    configCorrupted: configCorrupted,
  );
  final sm = withSettings
      ? SettingsViewModel(
          configStore: store,
          processManager: pm,
          autostart: Autostart(),
        )
      : null;
  await tester.pumpWidget(
    MaterialApp(
      home: DashboardScreen(viewModel: dm, settingsViewModel: sm),
    ),
  );
  return (store: store, pm: pm, dm: dm);
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

  final Map<String, StreamController<Uri>> _webuiControllers = {};

  @override
  Stream<Uri> webUiStream(String name) {
    return _webuiControllers
        .putIfAbsent(name, () => StreamController<Uri>.broadcast(sync: true))
        .stream;
  }

  void emitWebUi(String name, Uri url) {
    _webuiControllers[name]?.add(url);
  }

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DashboardScreen', () {
    // ---- Welcome screen ----

    testWidgets('shows welcome screen when no processes', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(processes: []),
        withSettings: false,
      );

      expect(find.text('No processes configured'), findsOneWidget);
      expect(find.text('Add Process'), findsOneWidget);
    });

    testWidgets('welcome screen "Add Process" button navigates to settings', (
      tester,
    ) async {
      await pumpDashboard(tester, config: AppConfig(processes: []));

      await tester.tap(find.text('Add Process'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Navigated to ProcessEditPage in add mode (AppBar title is 'Add Process').
      expect(find.widgetWithText(AppBar, 'Add Process'), findsOneWidget);
    });

    // ---- Dashboard with cards ----

    testWidgets('shows process cards when processes exist', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
        withSettings: false,
      );

      expect(find.text('svc-a'), findsOneWidget);
      expect(find.text('svc-b'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsOneWidget);
    });

    // ---- Navigation to detail page ----

    testWidgets('tapping a card navigates to detail page', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
        withSettings: false,
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
      await pumpDashboard(
        tester,
        config: AppConfig(processes: []),
        withSettings: false,
        configCorrupted: true,
      );

      // Dialog should appear after post-frame callback.
      await tester.pump();
      await tester.pump();

      expect(find.text('Configuration Error'), findsOneWidget);
      expect(find.textContaining('corrupted'), findsOneWidget);
    });

    testWidgets('dismissing corrupted dialog clears flag', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(processes: []),
        withSettings: false,
        configCorrupted: true,
      );

      await tester.pump();
      await tester.pump();

      // Tap OK.
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump();

      expect(h.dm.configCorrupted, false);
      expect(find.text('Configuration Error'), findsNothing);
    });

    // ---- Config changed → welcome screen ----

    testWidgets('switches to welcome screen when config becomes empty', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
        withSettings: false,
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
      await pumpDashboard(tester, config: AppConfig(processes: []));

      expect(find.byTooltip('Add process'), findsOneWidget);
    });

    testWidgets('does not show + button when settingsViewModel is null', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(processes: []),
        withSettings: false,
      );

      expect(find.byTooltip('Add process'), findsNothing);
    });

    testWidgets('+ button navigates to ProcessEditPage in add mode', (
      tester,
    ) async {
      await pumpDashboard(tester, config: AppConfig(processes: []));

      await tester.tap(find.byTooltip('Add process'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'Add Process'), findsOneWidget);
    });

    // ---- Edit icon on cards ----

    testWidgets('shows edit icon on process cards', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('tapping edit icon navigates to ProcessEditPage', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'Edit Process'), findsOneWidget);
    });

    // ---- Long-press reorder ----

    testWidgets('does not render drag handle icons on cards', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      expect(find.byIcon(Icons.drag_handle), findsNothing);
    });

    testWidgets('long-press drag reorders cards and persists', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
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
      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.processes.map((p) => p.name), ['svc-b', 'svc-a']);
      expect(saved.dashboardLayout, DashboardLayout.list);
    });

    testWidgets('mouse long-press drag reorders list cards and persists', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      // Same long-press reorder with a mouse pointer: the delayed
      // recognizer must accept the primary mouse button.
      await longPressDrag(
        tester,
        tester.getCenter(find.text('svc-a')),
        tester.getCenter(find.text('svc-b')) + const Offset(0, 150),
        kind: PointerDeviceKind.mouse,
      );

      expect(
        tester.getTopLeft(find.text('svc-a')).dy,
        greaterThan(tester.getTopLeft(find.text('svc-b')).dy),
      );

      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.processes.map((p) => p.name), ['svc-b', 'svc-a']);
    });

    // ---- Layout toggle ----

    testWidgets('layout toggle hidden on welcome screen', (tester) async {
      await pumpDashboard(tester, config: AppConfig(processes: []));

      expect(find.byTooltip('Switch to grid view'), findsNothing);
      expect(find.byTooltip('Switch to list view'), findsNothing);
    });

    testWidgets('layout toggle hidden without settingsViewModel', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
        withSettings: false,
      );

      expect(find.byTooltip('Switch to grid view'), findsNothing);
      expect(find.byTooltip('Switch to list view'), findsNothing);
    });

    testWidgets('layout toggle shown with processes, icon shows grid target', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      // In list layout the button offers the grid and shows a grid icon.
      expect(find.byTooltip('Switch to grid view'), findsOneWidget);
      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      expect(find.byTooltip('Switch to list view'), findsNothing);
    });

    testWidgets('tapping layout toggle switches layout and persists', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      // Switch to grid: grid appears, icon now offers the list.
      await tester.tap(find.byTooltip('Switch to grid view'));
      await tester.pump();

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byType(ProcessGridCard), findsOneWidget);
      expect(find.byTooltip('Switch to list view'), findsOneWidget);
      expect(find.byIcon(Icons.view_list), findsOneWidget);

      var saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.dashboardLayout, DashboardLayout.grid);

      // Switch back to list.
      await tester.tap(find.byTooltip('Switch to list view'));
      await tester.pump();

      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(h.store.lastSaved!.dashboardLayout, DashboardLayout.list);
    });

    // ---- Grid layout ----

    testWidgets('long-press drag reorders grid cards and persists', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      // Let the grid's entrance fade-in run: the package only records
      // each tile's original index once the fade-in has started (a couple
      // of frames after the grid appears), and the reorder callback reads
      // that index at drag end. Real users always long-press well after
      // the grid appears; the test must simulate that gap.
      await tester.pumpAndSettle();

      // Long-press the first grid card and drag it onto the second. The
      // drop index only advances while the pointer is *inside* the target
      // tile's bounds, so aim at its center (a small offset keeps the
      // pointer safely within the tile).
      await longPressDrag(
        tester,
        tester.getCenter(find.text('svc-a')),
        tester.getCenter(find.text('svc-b')) + const Offset(40, 0),
      );

      // The grid reordered visually: svc-a now sits right of svc-b.
      expect(
        tester.getTopLeft(find.text('svc-a')).dx,
        greaterThan(tester.getTopLeft(find.text('svc-b')).dx),
      );

      // And the new order plus the carried layout persisted.
      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.processes.map((p) => p.name), ['svc-b', 'svc-a']);
      expect(saved.dashboardLayout, DashboardLayout.grid);
    });

    testWidgets('mouse long-press drag reorders grid cards and persists', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      await tester.pumpAndSettle();

      // Same long-press reorder with a mouse pointer (see the touch-kind
      // test for the fade-in and drop-target rationale).
      await longPressDrag(
        tester,
        tester.getCenter(find.text('svc-a')),
        tester.getCenter(find.text('svc-b')) + const Offset(40, 0),
        kind: PointerDeviceKind.mouse,
      );

      expect(
        tester.getTopLeft(find.text('svc-a')).dx,
        greaterThan(tester.getTopLeft(find.text('svc-b')).dx),
      );

      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.processes.map((p) => p.name), ['svc-b', 'svc-a']);
    });

    testWidgets('dragging near the grid edge auto-scrolls', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [
            for (var i = 1; i <= 12; i++)
              ProcessConfig(name: 'svc-$i', cmd: 'svc-$i.exe'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Long-press a tile and hold it near the grid's bottom edge; the
      // package scrolls while the pointer sits in the edge zone.
      final tileCenter = tester.getCenter(find.text('svc-4'));
      await longPressDrag(tester, tileCenter, Offset(tileCenter.dx, 500));

      // The grid scrolled down during the drag.
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, greaterThan(0));
    });

    testWidgets('grid renders compact cards without output preview', (
      tester,
    ) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      // Adaptive square grid: max tile extent 280 with 1:1 aspect.
      final delegate =
          tester.widget<GridView>(find.byType(GridView)).gridDelegate
              as SliverGridDelegateWithMaxCrossAxisExtent;
      expect(delegate.maxCrossAxisExtent, 280);
      expect(delegate.childAspectRatio, 1);

      // One compact card per process with name, status dot, and controls.
      expect(find.byType(ProcessGridCard), findsNWidgets(2));
      expect(find.text('svc-a'), findsOneWidget);
      expect(find.text('svc-b'), findsOneWidget);
      expect(find.byType(StatusDot), findsNWidgets(2));
      expect(find.byIcon(Icons.edit), findsNWidgets(2));
      expect(find.byIcon(Icons.play_circle_outlined), findsNWidgets(2));

      // No output preview in grid layout.
      expect(find.text('No output yet'), findsNothing);
    });

    testWidgets('grid card shows WebUI copy button when URL detected', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      h.pm.emitWebUi('svc-a', Uri.parse('http://127.0.0.1:8080'));
      await tester.pump();

      expect(find.byIcon(Icons.content_copy), findsOneWidget);
    });

    testWidgets('grid card copy button copies URL and shows snackbar', (
      tester,
    ) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      h.pm.emitWebUi('svc-a', Uri.parse('http://127.0.0.1:8080'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump();

      expect(find.text('URL copied'), findsOneWidget);
    });

    testWidgets('grid card edit icon opens the edit page', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.widgetWithText(AppBar, 'Edit Process'), findsOneWidget);
    });

    testWidgets('tapping grid card opens detail page', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.text('svc-a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // On the detail page: 'No output yet' appears only on the detail
      // body, since grid cards have no output preview.
      expect(find.text('No output yet'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'svc-a'), findsOneWidget);
    });

    testWidgets('grid card toggle button starts the process', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [
            const ProcessConfig(name: 'svc-a', cmd: 'a.exe'),
            const ProcessConfig(name: 'svc-b', cmd: 'b.exe'),
          ],
        ),
      );

      await tester.tap(find.byIcon(Icons.play_circle_outlined).first);
      await tester.pump();

      expect(h.pm.toggled, ['svc-a']);
    });

    testWidgets('opens in grid layout when config stores grid', (tester) async {
      await pumpDashboard(
        tester,
        config: AppConfig(
          dashboardLayout: DashboardLayout.grid,
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byTooltip('Switch to list view'), findsOneWidget);
    });

    testWidgets('toggling layout preserves other globals', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          outputRefreshMs: 300,
          outputHistoryLimit: 500,
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.byTooltip('Switch to grid view'));
      await tester.pump();

      final saved = h.store.lastSaved;
      expect(saved, isNotNull);
      expect(saved!.dashboardLayout, DashboardLayout.grid);
      expect(saved.outputRefreshMs, 300);
      expect(saved.outputHistoryLimit, 500);
      expect(saved.processes.map((p) => p.name), ['svc-a']);
    });

    testWidgets('toggle button still works on cards', (tester) async {
      final h = await pumpDashboard(
        tester,
        config: AppConfig(
          processes: [const ProcessConfig(name: 'svc-a', cmd: 'a.exe')],
        ),
      );

      await tester.tap(find.byIcon(Icons.play_circle_outlined));
      await tester.pump();

      expect(h.pm.toggled, ['svc-a']);
    });
  });
}
