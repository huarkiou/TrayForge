import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'package:trayforge_flutter/foundation/logger.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/screens/dashboard_screen.dart';
import 'package:trayforge_flutter/services/config_store.dart';
import 'package:trayforge_flutter/services/process_manager.dart';
import 'package:trayforge_flutter/services/single_instance.dart';
import 'package:trayforge_flutter/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge_flutter/viewmodels/settings_viewmodel.dart';
import 'package:trayforge_flutter/viewmodels/tray_viewmodel.dart';

// ---------------------------------------------------------------------------
// Manual DI — Program.cs style
// ---------------------------------------------------------------------------

late final Logger _logger;
late final SingleInstance _singleInstance;
late final ConfigStore _configStore;
late final ProcessManager _processManager;
late final TrayViewModel _trayViewModel;
late final DashboardViewModel _dashboardViewModel;
late final SettingsViewModel _settingsViewModel;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Configure window before showing anything.
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      title: 'TrayForge',
      size: Size(800, 600),
      center: true,
    ),
  );

  // ---- Services ----

  _logger = Logger();
  _logger.log('TrayForge starting');

  _singleInstance = SingleInstance(logger: _logger);
  if (!_singleInstance.tryAcquire()) {
    _singleInstance.signalFirstInstance();
    return; // Another instance is already running.
  }

  _configStore = ConfigStore();

  // Detect corrupted config before ProcessManager constructs.
  final configFile = File(p.join(_configStore.dataDir, 'config.json'));
  final configExists = configFile.existsSync();
  final config = _configStore.load();
  final configCorrupted = configExists && config == null;

  _processManager = ProcessManager(
    configStore: _configStore,
    logger: _logger,
  );

  // ---- ViewModels ----

  _dashboardViewModel = DashboardViewModel(
    configStore: _configStore,
    processManager: _processManager,
    configCorrupted: configCorrupted,
  );

  _settingsViewModel = SettingsViewModel(
    configStore: _configStore,
    processManager: _processManager,
  );

  _trayViewModel = TrayViewModel(
    configStore: _configStore,
    processManager: _processManager,
    onShowDashboard: _showDashboard,
    onExit: _exitApp,
  );

  // Config changes should refresh the tray.
  _configStore.configChanged.listen((_) {
    _trayViewModel.onConfigChanged();
  });

  // Tray state changes → update icon and menu.
  _trayViewModel.addListener(_onTrayStateChanged);

  // ---- Window setup ----

  await windowManager.setPreventClose(true);
  await windowManager.setTitle(DashboardViewModel.appTitle);

  // Set window icon (reused from Python TrayForge).
  try {
    await windowManager.setIcon('assets/icon.ico');
  } catch (_) {
    // Icon may not be available on all platforms.
  }

  windowManager.addListener(_AppWindowListener());

  // ---- Tray setup ----

  await trayManager.setIcon(_trayViewModel.iconPath);
  await trayManager.setToolTip('TrayForge');
  await trayManager.setContextMenu(_trayViewModel.buildMenu());
  trayManager.addListener(_AppTrayListener());

  // ---- Hide window at startup (tray only) ----

  await windowManager.hide();

  // ---- Wake signal polling (second instance → show dashboard) ----

  Timer.periodic(const Duration(seconds: 1), (_) {
    if (_singleInstance.checkForWakeSignal()) {
      _showDashboard();
    }
  });

  // ---- Go ----

  runApp(const _TrayForgeApp());
}

// ---------------------------------------------------------------------------
// App lifecycle
// ---------------------------------------------------------------------------

Future<void> _showDashboard() async {
  await windowManager.show();
  await windowManager.focus();
}

Future<void> _exitApp() async {
  _logger.log('TrayForge shutting down');

  // Stop all running processes.
  final config = _configStore.load();
  if (config != null) {
    for (final proc in config.processes) {
      final state = _processManager.getState(proc.name);
      if (state == ProcState.running || state == ProcState.starting) {
        await _processManager.stop(proc.name);
      }
    }
  }

  _trayViewModel.removeListener(_onTrayStateChanged);
  _trayViewModel.dispose();
  _dashboardViewModel.dispose();
  _settingsViewModel.dispose();
  _processManager.dispose();
  _configStore.dispose();
  _singleInstance.release();
  await trayManager.destroy();
  await windowManager.destroy();
}

void _onTrayStateChanged() {
  // Fire-and-forget: update tray icon and menu when state changes.
  trayManager.setIcon(_trayViewModel.iconPath)
      .catchError((e) => _logger.log('Tray setIcon failed: $e'));
  trayManager.setContextMenu(_trayViewModel.buildMenu())
      .catchError((e) => _logger.log('Tray setContextMenu failed: $e'));
}

// ---------------------------------------------------------------------------
// Listeners
// ---------------------------------------------------------------------------

/// Handles window events, primarily intercepting close to hide instead.
class _AppWindowListener extends WindowListener {
  @override
  void onWindowClose() {
    // Hide to tray instead of quitting.
    windowManager.hide();
  }
}

/// Handles tray events: menu clicks and double-click.
///
/// Menu item actions are handled by onClick closures set in
/// [TrayViewModel.buildMenu]; this listener only handles
/// double-click detection on the tray icon itself.
class _AppTrayListener extends TrayListener {
  DateTime? _lastMouseDown;

  @override
  void onTrayIconMouseDown() {
    // Double-click detection: two clicks within 400ms open Dashboard.
    final now = DateTime.now();
    final last = _lastMouseDown;
    _lastMouseDown = now;

    if (last != null && now.difference(last) < const Duration(milliseconds: 400)) {
      _showDashboard();
    }
  }
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class _TrayForgeApp extends StatelessWidget {
  const _TrayForgeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: DashboardViewModel.appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: DashboardScreen(
        viewModel: _dashboardViewModel,
        settingsViewModel: _settingsViewModel,
      ),
    );
  }
}
