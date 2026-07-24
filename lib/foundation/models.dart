/// Core data types for the TrayForge application.
library;

/// The lifecycle state of a managed process.
enum ProcState {
  stopped,
  starting,
  running,
  stopping,
  crashed,
  cooldown,
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
  final bool deleteBeforeStart;
  final int? maxRestarts;
  final Map<String, String>? env;

  const ProcessConfig({
    required this.name,
    this.cwd,
    required this.cmd,
    this.encoding,
    this.singleton = false,
    this.autostart = false,
    this.webuiPattern,
    this.deleteBeforeStart = false,
    this.maxRestarts,
    this.env,
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
      deleteBeforeStart: json['delete_before_start'] as bool? ?? false,
      maxRestarts: json['max_restarts'] as int?,
      env: (json['env'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as String),
      ),
    );
  }

  ProcessConfig copyWith({
    String? name,
    String? cwd,
    String? cmd,
    String? encoding,
    bool? singleton,
    bool? autostart,
    String? webuiPattern,
    bool? deleteBeforeStart,
    int? maxRestarts,
    Map<String, String>? env,
    bool clearCwd = false,
    bool clearEncoding = false,
    bool clearWebuiPattern = false,
    bool clearMaxRestarts = false,
    bool clearEnv = false,
  }) {
    return ProcessConfig(
      name: name ?? this.name,
      cwd: clearCwd ? null : (cwd ?? this.cwd),
      cmd: cmd ?? this.cmd,
      encoding: clearEncoding ? null : (encoding ?? this.encoding),
      singleton: singleton ?? this.singleton,
      autostart: autostart ?? this.autostart,
      webuiPattern:
          clearWebuiPattern ? null : (webuiPattern ?? this.webuiPattern),
      deleteBeforeStart: deleteBeforeStart ?? this.deleteBeforeStart,
      maxRestarts:
          clearMaxRestarts ? null : (maxRestarts ?? this.maxRestarts),
      env: clearEnv ? null : (env ?? this.env),
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
    this.outputRefreshMs = 100,
    this.processes = const [],
  });

  /// Default configuration with example processes: NapCat + AstrBot.
  factory AppConfig.defaultConfig() {
    return AppConfig(
      outputHistoryLimit: 1000,
      outputRefreshMs: 100,
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
      outputRefreshMs: json['output_refresh_ms'] as int? ?? 100,
      processes: (json['processes'] as List<dynamic>?)
              ?.map((e) =>
                  ProcessConfig.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
