import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:trayforge/foundation/logger.dart';
import 'package:trayforge/foundation/models.dart';

/// Configuration persistence layer.
///
/// Reads and writes [AppConfig] to `config.json` under [dataDir],
/// with automatic backup and validation. Compatible with Python
/// trayforge JSON schema.
class ConfigStore {
  final String dataDir;
  final int maxBackupBytes;

  final StreamController<void> _configChangedController =
      StreamController<void>.broadcast();

  /// A stream that emits whenever the config is saved.
  Stream<void> get configChanged => _configChangedController.stream;

  ConfigStore({
    String? dataDir,
    this.maxBackupBytes = 10 * 1024 * 1024,
  }) : dataDir = dataDir ?? Logger.getDataDir();

  String get _configPath => p.join(dataDir, 'config.json');
  String get _backupsDir => p.join(dataDir, 'backups');

  /// Loads the configuration from disk.
  ///
  /// Returns an [AppConfig] parsed from `config.json`.
  /// Returns `null` if the file does not exist.
  /// On JSON parse or type error, backs up the corrupted file to
  /// `backups/config.<timestamp>.corrupted.json` and returns `null`.
  AppConfig? load() {
    final file = File(_configPath);
    if (!file.existsSync()) return null;

    try {
      final content = file.readAsStringSync(encoding: utf8);
      final json = jsonDecode(content) as Map<String, dynamic>;
      return AppConfig.fromJson(json);
    } on FormatException {
      _backupCorrupted(file);
      return null;
    } on TypeError {
      _backupCorrupted(file);
      return null;
    }
  }

  /// Saves [config] to `config.json`.
  ///
  /// Creates the data directory if needed. Backs up the existing config
  /// file to `backups/config.<timestamp>.json` before overwriting, then
  /// prunes old backup files if the backup directory exceeds [maxBackupBytes].
  /// Fires [configChanged] after writing.
  void save(AppConfig config) {
    _backupExisting();

    final dir = Directory(dataDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final json = config.toJson();
    final encoded = const JsonEncoder.withIndent('  ').convert(json);
    File(_configPath).writeAsStringSync(encoded, encoding: utf8, flush: true);

    _prune();
    _configChangedController.add(null);
  }

  /// Reloads the configuration from disk and fires [configChanged]
  /// so all listeners refresh. Useful when config.json is replaced
  /// externally at runtime.
  void reload() {
    _configChangedController.add(null);
  }

  /// Validates a single [ProcessConfig].
  ///
  /// Throws [ArgumentError] if:
  /// - [ProcessConfig.name] is empty or whitespace-only
  /// - [ProcessConfig.name] contains `/` or `\`
  /// - [ProcessConfig.webuiPattern] is non-null and not a valid regex
  void validate(ProcessConfig config) {
    if (config.name.trim().isEmpty) {
      throw ArgumentError('Process name must not be empty');
    }

    if (config.name.contains('/') || config.name.contains('\\')) {
      throw ArgumentError(
        'Process name "${config.name}" must not contain / or \\',
      );
    }

    if (config.webuiPattern != null) {
      try {
        RegExp(config.webuiPattern!);
      } on FormatException catch (e) {
        throw ArgumentError(
          'Invalid webui_pattern regex: ${e.message}',
        );
      }
    }
  }

  /// Releases resources held by the [configChanged] stream.
  void dispose() {
    _configChangedController.close();
  }

  // ---- Private helpers ----

  void _backupCorrupted(File file) {
    _ensureBackupsDir();
    final dest = p.join(_backupsDir, 'config.${_timestamp()}.corrupted.json');
    file.copySync(dest);
  }

  void _backupExisting() {
    final file = File(_configPath);
    if (!file.existsSync()) return;

    _ensureBackupsDir();
    final dest = p.join(_backupsDir, 'config.${_timestamp()}.json');
    file.copySync(dest);
  }

  void _ensureBackupsDir() {
    final dir = Directory(_backupsDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  void _prune() {
    final dir = Directory(_backupsDir);
    if (!dir.existsSync()) return;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('config.'))
        .toList();

    // Sort by name (timestamp embedded in name), oldest first.
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    var totalSize = files.fold<int>(0, (sum, f) => sum + f.lengthSync());

    for (final file in files) {
      if (totalSize <= maxBackupBytes) break;
      final size = file.lengthSync();
      file.deleteSync();
      totalSize -= size;
    }
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}${_pad(now.month)}${_pad(now.day)}'
        '_${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}'
        '.${_pad(now.millisecond)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
