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
/// Rebuilds the list whenever [ProcessManager.onConfigReloaded] fires. Exposes
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
  }) : _configStore = configStore,
       _processManager = processManager,
       _configCorrupted = configCorrupted {
    _rebuild();
    _configSub = processManager.onConfigReloaded.listen((_) => _rebuild());
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
    final config = _configStore.load();
    final processes = config?.processes ?? <ProcessConfig>[];
    final outputHistoryLimit = config?.outputHistoryLimit ?? 1000;

    // Build a name→VM map from existing instances for reuse.
    final existingByName = <String, ProcessViewModel>{};
    for (final vm in _processViewModels) {
      existingByName[vm.name] = vm;
    }

    final newVms = <ProcessViewModel>[];
    for (final proc in processes) {
      final existing = existingByName.remove(proc.name);
      if (existing != null) {
        newVms.add(existing);
      } else {
        newVms.add(
          ProcessViewModel(
            name: proc.name,
            processManager: _processManager,
            outputHistoryLimit: outputHistoryLimit,
          ),
        );
      }
    }

    // Dispose VMs for processes that no longer exist.
    for (final vm in existingByName.values) {
      vm.dispose();
    }

    _processViewModels
      ..clear()
      ..addAll(newVms);

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
