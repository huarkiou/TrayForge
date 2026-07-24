import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// File-based logger with rotation.
///
/// Writes UTF-8 log entries to [logPath]. When the file exceeds [maxBytes]
/// (default 1 MB), rotates through up to [maxBackups] (default 3) backup files.
class Logger {
  final String logPath;
  final int maxBytes;
  final int maxBackups;

  Logger({
    String? logPath,
    this.maxBytes = 1024 * 1024,
    this.maxBackups = 3,
  }) : logPath = logPath ?? p.join(getDataDir(), 'logs', 'trayforge.log');

  /// Resolves the TrayForge data directory.
  ///
  /// Checks the [TRAYFORGE_DATA_DIR] environment variable first,
  /// then falls back to platform-specific defaults:
  /// - Windows: `%LOCALAPPDATA%/TrayForge`
  /// - Linux: `$XDG_DATA_HOME/TrayForge` or `~/.local/share/TrayForge`
  static String getDataDir() {
    final envDir = Platform.environment['TRAYFORGE_DATA_DIR'];
    if (envDir != null && envDir.isNotEmpty) {
      return envDir;
    }

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return p.join(localAppData, 'TrayForge');
      }
      // Fallback: use USERPROFILE
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null && userProfile.isNotEmpty) {
        return p.join(userProfile, 'AppData', 'Local', 'TrayForge');
      }
      return p.join(Directory.current.path, 'data');
    }

    // Linux / macOS
    final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
    if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
      return p.join(xdgDataHome, 'TrayForge');
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, '.local', 'share', 'TrayForge');
    }

    return p.join(Directory.current.path, 'data');
  }

  /// Appends [message] to the log file with a timestamp.
  ///
  /// Automatically rotates the log file if it exceeds [maxBytes].
  void log(String message) {
    _rotateIfNeeded();

    final dir = Directory(p.dirname(logPath));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String();
    final entry = '[$timestamp] $message\n';

    final file = File(logPath);
    file.writeAsStringSync(entry,
        mode: FileMode.append, encoding: utf8, flush: true);
  }

  void _rotateIfNeeded() {
    final file = File(logPath);
    if (!file.existsSync()) return;

    final size = file.lengthSync();
    if (size < maxBytes) return;

    // Delete oldest backup
    final oldestBackup = File('$logPath.$maxBackups');
    if (oldestBackup.existsSync()) {
      oldestBackup.deleteSync();
    }

    // Shift backups: .2 → .3, .1 → .2
    for (var i = maxBackups - 1; i >= 1; i--) {
      final src = File('$logPath.$i');
      if (src.existsSync()) {
        src.renameSync('$logPath.${i + 1}');
      }
    }

    // Rename current log to .1
    file.renameSync('$logPath.1');
  }
}
