import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:trayforge_flutter/foundation/logger.dart';

/// Manages OS-level autostart registration so TrayForge launches at boot.
///
/// On Windows, reads/writes the registry key
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\TrayForge`
/// via `reg.exe` commands.
///
/// On Linux, manages the XDG autostart desktop file at
/// `~/.config/autostart/TrayForge.desktop`.
class Autostart {
  final Logger? logger;
  final String? _autostartDir;

  /// Creates an [Autostart] instance.
  ///
  /// [autostartDir] overrides the Linux autostart directory for testing.
  /// On Windows this parameter is ignored.
  Autostart({this.logger, this._autostartDir});

  // ---- public API ----

  /// Returns `true` if TrayForge is registered for autostart.
  bool isEnabled() {
    if (Platform.isWindows) return _isEnabledWindows();
    if (Platform.isLinux) return _isEnabledLinux();
    return false;
  }

  /// Registers TrayForge for autostart.
  ///
  /// Points to the current executable path via [Platform.resolvedExecutable].
  Future<void> enable() async {
    if (Platform.isWindows) {
      await _enableWindows();
    } else if (Platform.isLinux) {
      await _enableLinux();
    }
  }

  /// Removes the autostart registration.
  ///
  /// Does nothing if the entry is already absent (no error).
  Future<void> disable() async {
    if (Platform.isWindows) {
      await _disableWindows();
    } else if (Platform.isLinux) {
      await _disableLinux();
    }
  }

  // ---- Windows (registry) ----

  static const String _regPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _regValue = 'TrayForge';

  bool _isEnabledWindows() {
    try {
      final result = Process.runSync('reg', [
        'query',
        _regPath,
        '/v',
        _regValue,
      ]);
      return result.exitCode == 0;
    } catch (e) {
      logger?.log('Autostart: error checking registry: $e');
      return false;
    }
  }

  Future<void> _enableWindows() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final result = await Process.run('reg', [
        'add',
        _regPath,
        '/v',
        _regValue,
        '/d',
        exePath,
        '/f',
      ]);
      if (result.exitCode != 0) {
        final stderr = (result.stderr as String).trim();
        logger?.log('Autostart: reg add failed (exit ${result.exitCode}): $stderr');
      } else {
        logger?.log('Autostart: registry entry added ($exePath)');
      }
    } catch (e) {
      logger?.log('Autostart: error enabling autostart: $e');
    }
  }

  Future<void> _disableWindows() async {
    try {
      final result = await Process.run('reg', [
        'delete',
        _regPath,
        '/v',
        _regValue,
        '/f',
      ]);
      // exitCode 0 = deleted, 1 = not found (both are OK)
      if (result.exitCode == 0) {
        logger?.log('Autostart: registry entry removed');
      } else if (result.exitCode == 1) {
        // Value not found — already absent, no-op.
      } else {
        final stderr = (result.stderr as String).trim();
        logger?.log(
            'Autostart: reg delete failed (exit ${result.exitCode}): $stderr');
      }
    } catch (e) {
      logger?.log('Autostart: error disabling autostart: $e');
    }
  }

  // ---- Linux (XDG autostart .desktop file) ----

  String get _desktopFilePath {
    if (_autostartDir != null) {
      return p.join(_autostartDir, 'TrayForge.desktop');
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME environment variable not set');
    }
    return p.join(home, '.config', 'autostart', 'TrayForge.desktop');
  }

  bool _isEnabledLinux() {
    try {
      return File(_desktopFilePath).existsSync();
    } catch (e) {
      logger?.log('Autostart: error checking desktop file: $e');
      return false;
    }
  }

  Future<void> _enableLinux() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final desktopDir = p.dirname(_desktopFilePath);
      await Directory(desktopDir).create(recursive: true);

      final content = '''[Desktop Entry]
Type=Application
Name=TrayForge
Comment=TrayForge system tray application
Exec="$exePath"
Terminal=false
X-GNOME-Autostart-enabled=true
''';

      await File(_desktopFilePath).writeAsString(content, encoding: utf8);
      logger?.log('Autostart: desktop file created ($_desktopFilePath)');
    } catch (e) {
      logger?.log('Autostart: error writing desktop file: $e');
    }
  }

  Future<void> _disableLinux() async {
    try {
      final file = File(_desktopFilePath);
      if (await file.exists()) {
        await file.delete();
        logger?.log('Autostart: desktop file removed');
      }
    } catch (e) {
      logger?.log('Autostart: error removing desktop file: $e');
    }
  }
}
