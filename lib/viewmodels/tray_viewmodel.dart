import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/services/config_store.dart';
import 'package:trayforge_flutter/services/process_manager.dart';

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

  /// Timestamp of the last left-click for double-click detection.
  DateTime? _lastClickTime;

  /// Duration window for double-click detection.
  static const _doubleClickWindow = Duration(milliseconds: 400);

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
  String get iconPath {
    switch (_color) {
      case TrayColor.green:
        return 'assets/icons/icon-green.png';
      case TrayColor.yellow:
        return 'assets/icons/icon-yellow.png';
      case TrayColor.red:
        return 'assets/icons/icon-red.png';
    }
  }

  /// Builds the tray context menu from the current process list.
  Menu buildMenu() {
    final config = _configStore.load();
    final processes = config?.processes ?? <ProcessConfig>[];

    final items = <MenuItem>[];

    // Dynamic process items
    for (final proc in processes) {
      final state = _states[proc.name] ?? ProcState.stopped;
      final isRunning = state == ProcState.running;
      final label = isRunning ? '\u2713 ${proc.name}' : '   ${proc.name}';
      items.add(MenuItem(
        key: 'proc:${proc.name}',
        label: label,
      ));
    }

    if (items.isNotEmpty) {
      items.add(MenuItem.separator());
    }

    // Fixed items
    items.add(MenuItem(key: 'dashboard', label: 'Dashboard'));
    items.add(MenuItem(key: 'exit', label: 'Exit'));

    return Menu(items: items);
  }

  /// Handles a menu item click from the tray context menu.
  void handleMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';

    if (key == 'dashboard') {
      onShowDashboard();
    } else if (key == 'exit') {
      onExit();
    } else if (key.startsWith('proc:')) {
      final name = key.substring(5);
      _toggleProcess(name);
    }
  }

  /// Handles a left-click on the tray icon for double-click detection.
  ///
  /// Two clicks within [_doubleClickWindow] open the Dashboard.
  void handleIconMouseDown() {
    final now = DateTime.now();
    final last = _lastClickTime;

    if (last != null && now.difference(last) < _doubleClickWindow) {
      _lastClickTime = null;
      onShowDashboard();
    } else {
      _lastClickTime = now;
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

    final config = _configStore.load();
    final processes = config?.processes ?? <ProcessConfig>[];

    if (processes.isEmpty) {
      _color = TrayColor.red;
      return;
    }

    for (final proc in processes) {
      final name = proc.name;
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
    if (state == ProcState.running) {
      _processManager.stop(name);
    } else {
      _processManager.start(name);
    }
  }
}
