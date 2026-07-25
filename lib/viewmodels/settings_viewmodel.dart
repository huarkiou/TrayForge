// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/services/config_store.dart';
import 'package:trayforge_flutter/services/process_manager.dart';

/// ViewModel for the Settings page.
///
/// Holds a mutable copy of [ProcessConfig] items, supports add/edit/delete/
/// copy/reorder operations, validates via [ConfigStore.validate], and
/// persists changes through [ProcessManager.reloadConfig].
class SettingsViewModel extends ChangeNotifier {
  final ConfigStore _configStore;
  final ProcessManager _processManager;

  List<ProcessConfig> _processes = [];
  StreamSubscription<void>? _configSub;

  SettingsViewModel({
    required ConfigStore configStore,
    required ProcessManager processManager,
  })  : _configStore = configStore,
        _processManager = processManager {
    _reload();
    _configSub = configStore.configChanged.listen((_) => _reload());
  }

  /// All process configs in list order.
  List<ProcessConfig> get processes => List.unmodifiable(_processes);

  /// Whether a process with [name] is currently running.
  bool isRunning(String name) {
    final state = _processManager.getState(name);
    return state == ProcState.running || state == ProcState.starting;
  }

  /// Stops a running process by name.
  Future<void> stopProcess(String name) async {
    await _processManager.stop(name);
  }

  /// Adds a new [ProcessConfig] to the end of the list and persists.
  void add(ProcessConfig config) {
    _configStore.validate(config);
    _processes = [..._processes, config];
    _save();
  }

  /// Replaces the config at [index] with [config] and persists.
  void edit(int index, ProcessConfig config) {
    _configStore.validate(config);
    _processes = List<ProcessConfig>.from(_processes);
    _processes[index] = config;
    _save();
  }

  /// Deletes the config at [index] and persists.
  ///
  /// If the process is currently running, caller must stop it first.
  void delete(int index) {
    _processes = List<ProcessConfig>.from(_processes);
    _processes.removeAt(index);
    _save();
  }

  /// Copies the config at [index], appending "(copy)" to the name.
  ///
  /// Handles name collisions by appending a number.
  void copy(int index) {
    final source = _processes[index];
    final baseName = '${source.name} (copy)';
    final newName = _uniqueName(baseName);

    _processes = List<ProcessConfig>.from(_processes);
    _processes.insert(index + 1, source.copyWith(name: newName));
    _save();
  }

  /// Reorders the config list and persists.
  ///
  /// Uses the pre-adjusted newIndex from [ReorderableListView.onReorderItem],
  /// which already accounts for the removed item at oldIndex.
  void reorderItem(int oldIndex, int newIndex) {
    _processes = List<ProcessConfig>.from(_processes);
    final item = _processes.removeAt(oldIndex);
    _processes.insert(newIndex, item);
    _save();
  }

  /// Validates a [ProcessConfig] using [ConfigStore.validate].
  ///
  /// Returns `null` on success, or an error message string on failure.
  String? validateConfig(ProcessConfig config) {
    try {
      _configStore.validate(config);
      return null;
    } on ArgumentError catch (e) {
      return e.message;
    }
  }

  /// Reloads from [ConfigStore] when [configChanged] fires externally.
  void _reload() {
    final config = _configStore.load();
    _processes = config?.processes.toList() ?? [];
    notifyListeners();
  }

  /// Persists the current list and triggers a ProcessManager reload.
  ///
  /// Follows the spec flow:
  ///   1. ConfigStore.save() — fires configChanged → ViewModels rebuild
  ///   2. ProcessManager.reloadConfig() — stops removed, starts new autostart
  void _save() {
    final config = _configStore.load() ?? AppConfig.defaultConfig();
    final newConfig = AppConfig(
      outputHistoryLimit: config.outputHistoryLimit,
      outputRefreshMs: config.outputRefreshMs,
      processes: _processes,
    );
    _configStore.save(newConfig);
    _processManager.reloadConfig(newConfig);
    notifyListeners();
  }

  /// Generates a unique name by appending a counter if needed.
  String _uniqueName(String base) {
    final existing = _processes.map((p) => p.name).toSet();
    if (!existing.contains(base)) return base;

    var counter = 2;
    while (existing.contains('$base ($counter)')) {
      counter++;
    }
    return '$base ($counter)';
  }

  @override
  void dispose() {
    _configSub?.cancel();
    super.dispose();
  }
}
