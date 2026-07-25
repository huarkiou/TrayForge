// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/config_store.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';

/// ViewModel for the Dashboard window.
///
/// Holds a list of [ProcessViewModel] instances, one per configured process.
/// Rebuilds the list whenever [ConfigStore.configChanged] fires. Exposes
/// an [isEmpty] flag so the UI can show a welcome screen when no processes
/// are configured.
class DashboardViewModel extends ChangeNotifier {
  final ConfigStore _configStore;
  final ProcessManager _processManager;

  final List<ProcessViewModel> _processViewModels = [];
  bool _configCorrupted;
  StreamSubscription<void>? _configSub;

  /// App title shown in the window title bar and Dashboard header.
  static const String appTitle = 'trayforge';

  DashboardViewModel({
    required ConfigStore configStore,
    required ProcessManager processManager,
    bool configCorrupted = false,
  })  : _configStore = configStore,
        _processManager = processManager,
        _configCorrupted = configCorrupted {
    _rebuild();
    _configSub = configStore.configChanged.listen((_) => _rebuild());
  }

  /// All process view models, in config order.
  List<ProcessViewModel> get processViewModels =>
      List.unmodifiable(_processViewModels);

  /// Whether the list of process view models is empty.
  bool get isEmpty => _processViewModels.isEmpty;

  /// Whether a corrupted config was detected at startup.
  bool get configCorrupted => _configCorrupted;

  /// Clears the corrupted flag after the dialog has been shown.
  void clearCorruptedFlag() {
    _configCorrupted = false;
  }

  void _rebuild() {
    for (final vm in _processViewModels) {
      vm.dispose();
    }
    _processViewModels.clear();

    final config = _configStore.load();
    final processes = config?.processes ?? <ProcessConfig>[];

    for (final proc in processes) {
      _processViewModels.add(ProcessViewModel(
        name: proc.name,
        processManager: _processManager,
        outputHistoryLimit: config?.outputHistoryLimit ?? 1000,
      ));
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _configSub?.cancel();
    for (final vm in _processViewModels) {
      vm.dispose();
    }
    super.dispose();
  }
}
