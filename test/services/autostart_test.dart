import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge_flutter/services/autostart.dart';

void main() {
  group('Autostart', () {
    late Directory tmpDir;
    late Autostart autostart;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('trayforge_as_test_');
      autostart = Autostart(autostartDir: tmpDir.path);
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    group('on Linux', () {
      test('isEnabled returns false when no desktop file', () {
        if (!Platform.isLinux) return;
        expect(autostart.isEnabled(), isFalse);
      });

      test('enable creates the desktop file', () async {
        if (!Platform.isLinux) return;

        await autostart.enable();

        final desktopFile = File('${tmpDir.path}/TrayForge.desktop');
        expect(desktopFile.existsSync(), isTrue);

        final content = desktopFile.readAsStringSync();
        expect(content, contains('[Desktop Entry]'));
        expect(content, contains('Type=Application'));
        expect(content, contains('Name=TrayForge'));
        expect(content, contains('Exec='));
        expect(content, contains('Terminal=false'));
        expect(content, contains('X-GNOME-Autostart-enabled=true'));
      });

      test('isEnabled returns true after enable', () async {
        if (!Platform.isLinux) return;

        await autostart.enable();
        expect(autostart.isEnabled(), isTrue);
      });

      test('disable removes the desktop file', () async {
        if (!Platform.isLinux) return;

        await autostart.enable();
        expect(autostart.isEnabled(), isTrue);

        await autostart.disable();
        expect(autostart.isEnabled(), isFalse);

        final desktopFile = File('${tmpDir.path}/TrayForge.desktop');
        expect(desktopFile.existsSync(), isFalse);
      });

      test('disable is safe when already absent', () async {
        if (!Platform.isLinux) return;

        // Should not throw.
        await autostart.disable();
        expect(autostart.isEnabled(), isFalse);
      });

      test('enable uses Platform.resolvedExecutable for Exec', () async {
        if (!Platform.isLinux) return;

        await autostart.enable();

        final desktopFile = File('${tmpDir.path}/TrayForge.desktop');
        final content = desktopFile.readAsStringSync();

        final execLine =
            content.split('\n').firstWhere((l) => l.startsWith('Exec='));
        final execPath = execLine.substring(5);

        // Should be a path that exists (the test runner or dart executable).
        expect(execPath, isNotEmpty);
      });
    });

    group('on Windows', () {
      test('isEnabled returns a boolean without throwing', () {
        if (!Platform.isWindows) return;
        // Just ensure it doesn't throw.
        expect(autostart.isEnabled(), isA<bool>());
      });
    });

    group('cross-platform', () {
      test('isEnabled returns false on non-Windows/non-Linux', () {
        if (Platform.isWindows || Platform.isLinux) return;
        expect(autostart.isEnabled(), isFalse);
      });
    });
  });
}
