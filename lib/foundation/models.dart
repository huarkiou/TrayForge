/// Core data types for the trayforge application.
library;

import 'package:flutter/material.dart';

/// The lifecycle state of a managed process.
enum ProcState {
  stopped,
  starting,
  running,
  stopping,
  crashed,
  cooldown,
}

/// Extension on [ProcState] providing derived semantics.
extension ProcStateX on ProcState {
  /// Whether the process is actively running or starting.
  bool get isActive => this == ProcState.running || this == ProcState.starting;

  /// Whether the process is in a terminal (non-transitioning) state.
  bool get isTerminal => this != ProcState.starting && this != ProcState.stopping;

  /// Returns a colour representing the process state.
  Color get statusColor {
    switch (this) {
      case ProcState.running:
        return Colors.green;
      case ProcState.crashed:
        return Colors.red;
      case ProcState.stopped:
      case ProcState.starting:
      case ProcState.stopping:
      case ProcState.cooldown:
        return Colors.grey;
    }
  }
}

/// Configuration for a single managed process.
class ProcessConfig {
  final String name;
  final String? cwd;
  final String cmd;
  final String? encoding;
  final bool singleton;
  final bool autostart;
  final String? webuiPattern;
  final List<String> deleteBeforeStart;
  final int? maxRestarts;
  final Map<String, String>? env;
  final bool cleanupCwd;

  const ProcessConfig({
    required this.name,
    this.cwd,
    required this.cmd,
    this.encoding,
    this.singleton = false,
    this.autostart = false,
    this.webuiPattern,
    this.deleteBeforeStart = const [],
    this.maxRestarts,
    this.env,
    this.cleanupCwd = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (cwd != null) 'cwd': cwd,
        'cmd': cmd,
        if (encoding != null) 'encoding': encoding,
        'singleton': singleton,
        'autostart': autostart,
        if (webuiPattern != null) 'webui_pattern': webuiPattern,
        'delete_before_start': deleteBeforeStart,
        if (maxRestarts != null) 'max_restarts': maxRestarts,
        if (env != null) 'env': env,
        'cleanup_cwd': cleanupCwd,
      };

  factory ProcessConfig.fromJson(Map<String, dynamic> json) {
    return ProcessConfig(
      name: json['name'] as String,
      cwd: json['cwd'] as String?,
      cmd: json['cmd'] as String,
      encoding: json['encoding'] as String?,
      singleton: json['singleton'] as bool? ?? false,
      autostart: json['autostart'] as bool? ?? false,
      webuiPattern: json['webui_pattern'] as String?,
      deleteBeforeStart: _parseStringList(json['delete_before_start']),
      maxRestarts: json['max_restarts'] as int?,
      env: (json['env'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
      cleanupCwd: json['cleanup_cwd'] as bool? ?? false,
    );
  }

  /// Parses a JSON value that should be a list of strings.
  ///
  /// Accepts a [List] (Python trayforge format). Returns `[]` for
  /// any other type (e.g. old Flutter `bool` format) or when missing.
  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  ProcessConfig copyWith({
    String? name,
    String? cwd,
    String? cmd,
    String? encoding,
    bool? singleton,
    bool? autostart,
    String? webuiPattern,
    List<String>? deleteBeforeStart,
    int? maxRestarts,
    Map<String, String>? env,
    bool? cleanupCwd,
  }) {
    return ProcessConfig(
      name: name ?? this.name,
      cwd: cwd ?? this.cwd,
      cmd: cmd ?? this.cmd,
      encoding: encoding ?? this.encoding,
      singleton: singleton ?? this.singleton,
      autostart: autostart ?? this.autostart,
      webuiPattern: webuiPattern ?? this.webuiPattern,
      deleteBeforeStart: deleteBeforeStart ?? this.deleteBeforeStart,
      maxRestarts: maxRestarts ?? this.maxRestarts,
      env: env ?? this.env,
      cleanupCwd: cleanupCwd ?? this.cleanupCwd,
    );
  }
}

/// Application-level configuration.
class AppConfig {
  final int outputHistoryLimit;
  final int outputRefreshMs;
  final List<ProcessConfig> processes;

  const AppConfig({
    this.outputHistoryLimit = 1000,
    this.outputRefreshMs = 500,
    this.processes = const [],
  });

  /// Default configuration with example processes: NapCat + AstrBot.
  factory AppConfig.defaultConfig() {
    return AppConfig(
      outputHistoryLimit: 1000,
      outputRefreshMs: 500,
      processes: [
        const ProcessConfig(
          name: 'NapCat',
          cwd: r'C:\NapCat',
          cmd: r'napcat.exe',
          singleton: true,
          autostart: true,
          webuiPattern: r'WebUI started at (http://[\d.:]+)',
          maxRestarts: 3,
        ),
        const ProcessConfig(
          name: 'AstrBot',
          cwd: r'C:\AstrBot',
          cmd: r'astrbot.exe',
          singleton: true,
          autostart: true,
          webuiPattern: r'WebUI started at (http://[\d.:]+)',
          maxRestarts: 3,
        ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'output_history_limit': outputHistoryLimit,
        'output_refresh_ms': outputRefreshMs,
        'processes': processes.map((p) => p.toJson()).toList(),
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      outputHistoryLimit:
          json['output_history_limit'] as int? ?? 1000,
      outputRefreshMs: json['output_refresh_ms'] as int? ?? 500,
      processes: (json['processes'] as List<dynamic>?)
              ?.map((e) =>
                  ProcessConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
