import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:desktop_tray/desktop_tray.dart';
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
    _subscriptions.add(
      _processManager.onConfigReloaded.listen((_) => onConfigChanged()),
    );
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
  TrayMenu buildMenu() {
    final config = _configStore.load();
    final processes = config?.processes ?? <ProcessConfig>[];

    final items = <TrayMenuItem>[];

    // Dynamic process items — the key routes the click back here via
    // [handleMenuAction]; desktop_tray has no per-item onClick closure.
    for (final proc in processes) {
      final name = proc.name;
      final state = _states[name] ?? ProcState.stopped;
      final isRunning = state.isActive;
      final label = isRunning ? '\u2713 $name' : '   $name';
      items.add(TrayMenuItem(key: 'proc:$name', label: label));
    }

    if (items.isNotEmpty) {
      items.add(TrayMenuItem.separator());
    }

    // Fixed items
    items.add(TrayMenuItem(key: 'reload', label: 'Reload Settings'));
    items.add(TrayMenuItem(key: 'dashboard', label: 'Dashboard'));
    items.add(TrayMenuItem(key: 'exit', label: 'Exit'));

    return TrayMenu(items: items);
  }

  /// Routes a tray menu click to the action behind its [key].
  ///
  /// The keys are the same ones [buildMenu] attaches: `proc:<name>` toggles
  /// that process, `reload` / `dashboard` / `exit` map to the fixed items.
  void handleMenuAction(String key) {
    if (key.startsWith('proc:')) {
      _toggleProcess(key.substring('proc:'.length));
      return;
    }
    switch (key) {
      case 'reload':
        _reloadConfig();
      case 'dashboard':
        onShowDashboard();
      case 'exit':
        onExit();
    }
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
    // The start/stop decision lives in ProcessController.toggle — the
    // tray only routes the click through the facade.
    _processManager.toggle(name);
  }

  /// Reloads settings from disk and applies them (Path C from spec).
  void _reloadConfig() {
    final config = _configStore.load();
    if (config != null) {
      _processManager.reloadConfig(config);
    }
  }
}
