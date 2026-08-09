import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:desktop_tray/desktop_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'package:trayforge/foundation/logger.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/dashboard_screen.dart';
import 'package:trayforge/services/autostart.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/services/single_instance.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';
import 'package:trayforge/viewmodels/tray_viewmodel.dart';

// ---------------------------------------------------------------------------
// Manual DI -- Program.cs style
// ---------------------------------------------------------------------------

late final Logger _logger;
late final SingleInstance _singleInstance;
late final ConfigStore _configStore;
late final ProcessManager _processManager;
late final TrayViewModel _trayViewModel;
late final DashboardViewModel _dashboardViewModel;
late final Autostart _autostart;
late final SettingsViewModel _settingsViewModel;
Timer? _wakeTimer;

/// Whether a system tray (StatusNotifierWatcher on Linux) is available.
///
/// Determined once at startup; on non-Linux platforms this is always true.
/// When false the app must not rely on the tray icon for window recovery:
/// the Dashboard shows at startup and closing the window exits the app.
bool _trayAvailable = true;

/// Guards [_exitApp] against re-entry: destroying the window fires
/// [WindowListener.onWindowClose] again, which (without a tray) calls
/// [_exitApp] a second time.
bool _exiting = false;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Configure window properties without showing it -- tray-only startup.
  await windowManager.setTitle('trayforge');
  await windowManager.setSize(const Size(800, 600));
  await windowManager.center();

  // ---- Services ----

  _logger = Logger();
  _logger.log('trayforge starting');

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

  _processManager = ProcessManager(configStore: _configStore, logger: _logger);
  await _processManager.init();

  _autostart = Autostart(logger: _logger);

  // ---- ViewModels ----

  _dashboardViewModel = DashboardViewModel(
    configStore: _configStore,
    processManager: _processManager,
    configCorrupted: configCorrupted,
  );

  _settingsViewModel = SettingsViewModel(
    configStore: _configStore,
    processManager: _processManager,
    autostart: _autostart,
  );

  _trayViewModel = TrayViewModel(
    configStore: _configStore,
    processManager: _processManager,
    onShowDashboard: _showDashboard,
    onExit: _exitApp,
  );

  // Tray state changes -> update icon and menu.
  _trayViewModel.addListener(_onTrayStateChanged);

  // ---- Window setup ----

  await windowManager.setPreventClose(true);
  await windowManager.setTitle(DashboardViewModel.appTitle);

  // Set window icon (reused from Python trayforge).
  try {
    await windowManager.setIcon('assets/icon.ico');
  } catch (_) {
    // Icon may not be available on all platforms.
  }

  windowManager.addListener(_AppWindowListener());

  // ---- Tray setup ----

  // Probe for a system tray first: with no tray area (e.g. a desktop
  // environment without StatusNotifierWatcher on Linux) the tray icon is
  // invisible and the Dashboard must stay reachable on its own.
  _trayAvailable = await DesktopTray.instance.checkAvailable();
  _logger.log('System tray available: $_trayAvailable');

  await DesktopTray.instance.setIcon(_trayViewModel.iconPath);
  await DesktopTray.instance.setToolTip('trayforge');
  await DesktopTray.instance.setContextMenu(_trayViewModel.buildMenu());
  DesktopTray.instance.addListener(_AppTrayListener());

  // ---- Window visibility ----

  // Tray-only startup when the tray exists; otherwise show the Dashboard
  // so the user always has a way back into the app.
  if (_trayAvailable) {
    await windowManager.hide();
  } else {
    await _showDashboard();
  }

  // ---- Wake signal polling (second instance -> show dashboard) ----

  _wakeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (_singleInstance.checkForWakeSignal()) {
      _showDashboard();
    }
  });

  // ---- Go ----

  runApp(const _trayforgeApp());
}

// ---------------------------------------------------------------------------
// App lifecycle
// ---------------------------------------------------------------------------

Future<void> _showDashboard() async {
  await windowManager.show();
  await windowManager.focus();
}

void _hideDashboard() {
  windowManager.hide();
}

Future<void> _exitApp() async {
  if (_exiting) return;
  _exiting = true;
  _logger.log('trayforge shutting down');

  // Stop the wake-signal polling timer immediately so the event loop
  // can wind down after the window is destroyed.
  _wakeTimer?.cancel();
  _wakeTimer = null;

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
  await DesktopTray.instance.destroy();
  await windowManager.destroy();

  // Release the single-instance lock last -- only after all cleanup is
  // complete.  This prevents a second instance from starting while this
  // process is still tearing down tray / window resources.
  _singleInstance.release();

  // Flutter desktop does not auto-exit after the last window closes;
  // terminate the process explicitly.
  exit(0);
}

void _onTrayStateChanged() {
  // Fire-and-forget: update tray icon and menu when state changes.
  DesktopTray.instance
      .setIcon(_trayViewModel.iconPath)
      .catchError((e) => _logger.log('Tray setIcon failed: $e'));
  DesktopTray.instance
      .setContextMenu(_trayViewModel.buildMenu())
      .catchError((e) => _logger.log('Tray setContextMenu failed: $e'));
}

// ---------------------------------------------------------------------------
// Listeners
// ---------------------------------------------------------------------------

/// Handles window events, primarily intercepting close to hide instead.
class _AppWindowListener extends WindowListener {
  @override
  void onWindowClose() {
    if (_trayAvailable) {
      // Tray-only mode: closing hides to the tray.
      _hideDashboard();
    } else {
      // No tray to restore the window from — closing must exit.
      _exitApp();
    }
  }
}

/// Handles tray events: menu clicks and icon clicks.
///
/// Menu item actions are routed by key to [TrayViewModel.handleMenuAction];
/// this listener handles icon clicks and the right-click context menu.
class _AppTrayListener extends DesktopTrayListener {
  @override
  void onTrayMenuItemClick(TrayMenuItem item) {
    final key = item.key;
    if (key != null) {
      _trayViewModel.handleMenuAction(key);
    }
  }

  @override
  void onTrayIconMouseDown() {
    // Single-click toggles Dashboard visibility.
    windowManager.isVisible().then((visible) {
      if (visible) {
        _hideDashboard();
      } else {
        _showDashboard();
      }
    });
  }

  @override
  void onTrayIconRightMouseDown() {
    // Show the native context menu on right-click.
    // The desktop_tray plugin fires this event but does NOT
    // auto-pop the menu -- the app must call popUpContextMenu.
    DesktopTray.instance.popUpContextMenu();
  }
}

// ---------------------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------------------

class _trayforgeApp extends StatelessWidget {
  const _trayforgeApp();

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
