import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';

/// Three-colour tray icon state.
enum TrayColor { green, yellow, red }

/// ViewModel for tray icon state, menu, and interactions.
///
/// Listens to [ProcessManager] state changes to compute the overall tray
/// colour and rebuild the context menu. Exposes callbacks for window
/// visibility and app exit.
class TrayViewModel extends ChangeNotifier {
  final ConfigStore _configStore;
  final ProcessManager _processManager;

  /// Called when the user requests the Dashboard window.
  final VoidCallback onShowDashboard;

  /// Called when the user requests app exit.
  final Future<void> Function() onExit;

  TrayColor _color = TrayColor.red;
  final Map<String, ProcState> _states = {};
  final List<StreamSubscription<void>> _subscriptions = [];

  TrayViewModel({
    required this._configStore,
    required this._processManager,
    required this.onShowDashboard,
    required this.onExit,
  }) {
    _rebuildSubscriptions();
  }

  // ---- Public API ----

  /// Current tray colour based on process states.
  TrayColor get color => _color;

  /// Returns the icon asset path for the current colour.
  ///
  /// Uses .ico on Windows (Win32 LoadImage with IMAGE_ICON does not
  /// support PNG) and .png on Linux (libappindicator / StatusNotifierItem).
  String get iconPath {
    final ext = Platform.isWindows ? 'ico' : 'png';
    switch (_color) {
      case TrayColor.green:
        return 'assets/icons/icon-green.$ext';
      case TrayColor.yellow:
        return 'assets/icons/icon-yellow.$ext';
      case TrayColor.red:
        return 'assets/icons/icon-red.$ext';
    }
  }

  /// Builds the tray context menu from the current process list.
  Menu buildMenu() {
    final config = _configStore.load();
    final processes = config?.processes ?? <ProcessConfig>[];

    final items = <MenuItem>[];

    // Dynamic process items — onClick closure captures name directly,
    // compile-time safe vs string-key dispatch.
    for (final proc in processes) {
      final name = proc.name;
      final state = _states[name] ?? ProcState.stopped;
      final isRunning = state.isActive;
      final label = isRunning ? '\u2713 $name' : '   $name';
      items.add(
        MenuItem(
          key: 'proc:$name',
          label: label,
          onClick: (_) => _toggleProcess(name),
        ),
      );
    }

    if (items.isNotEmpty) {
      items.add(MenuItem.separator());
    }

    // Fixed items
    items.add(
      MenuItem(
        key: 'reload',
        label: 'Reload Settings',
        onClick: (_) => _configStore.reload(),
      ),
    );
    items.add(
      MenuItem(
        key: 'dashboard',
        label: 'Dashboard',
        onClick: (_) => onShowDashboard(),
      ),
    );
    items.add(MenuItem(key: 'exit', label: 'Exit', onClick: (_) => onExit()));

    return Menu(items: items);
  }

  /// Called when the process list changes (config reload).
  void onConfigChanged() {
    _rebuildSubscriptions();
    notifyListeners();
  }

  /// Releases subscriptions.
  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    super.dispose();
  }

  // ---- Private ----

  void _rebuildSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _states.clear();

    final config = _configStore.load();
    final processes = config?.processes ?? <ProcessConfig>[];

    if (processes.isEmpty) {
      _color = TrayColor.red;
      return;
    }

    for (final proc in processes) {
      final name = proc.name;
      // Seed from ProcessManager synchronously so the colour is correct
      // before the first async stateStream event fires.
      _states[name] = _processManager.getState(name);
      _subscriptions.add(
        _processManager.stateStream(name).listen((state) {
          _states[name] = state;
          _recomputeColor(processes);
          notifyListeners();
        }),
      );
    }

    _recomputeColor(processes);
  }

  void _recomputeColor(List<ProcessConfig> processes) {
    if (processes.isEmpty) {
      _color = TrayColor.red;
      return;
    }

    var runningCount = 0;
    for (final proc in processes) {
      final state = _states[proc.name] ?? ProcState.stopped;
      if (state == ProcState.running) {
        runningCount++;
      }
    }

    if (runningCount == processes.length) {
      _color = TrayColor.green;
    } else if (runningCount > 0) {
      _color = TrayColor.yellow;
    } else {
      _color = TrayColor.red;
    }
  }

  void _toggleProcess(String name) {
    final state = _states[name] ?? ProcState.stopped;
    if (state.isActive) {
      _processManager.stop(name);
    } else {
      _processManager.start(name);
    }
  }
}
