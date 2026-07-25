import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/logger.dart';

void main() {
  group('Logger.getDataDir', () {
    test('returns path containing trayforge', () {
      final dir = Logger.getDataDir();
      expect(dir, contains('trayforge'));
    });

    test('returns a valid path on the current platform', () {
      // The fallback logic produces a platform-appropriate path.
      final dir = Logger.getDataDir();
      expect(dir, isNotEmpty);
      expect(Directory(dir).parent.existsSync(), isTrue);
    });
  });

  group('Logger', () {
    late Directory tmpDir;
    late String logPath;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('trayforge_test_');
      logPath = '${tmpDir.path}/trayforge.log';
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('creates log directory if needed', () {
      final logger = Logger(logPath: logPath);
      logger.log('test message');

      final file = File(logPath);
      expect(file.existsSync(), isTrue);
    });

    test('writes message with timestamp', () {
      final logger = Logger(logPath: logPath);
      logger.log('hello');

      final content = File(logPath).readAsStringSync();
      expect(content, contains('[20'));
      expect(content, contains('hello'));
      expect(content, endsWith('\n'));
    });

    test('appends to existing file', () {
      final logger = Logger(logPath: logPath);
      logger.log('first');
      logger.log('second');

      final lines = File(logPath).readAsLinesSync();
      expect(lines.length, 2);
      expect(lines[0], contains('first'));
      expect(lines[1], contains('second'));
    });

    test('rotates when file exceeds maxBytes', () {
      final logger = Logger(logPath: logPath, maxBytes: 100, maxBackups: 3);

      // Write enough to exceed 100 bytes
      for (var i = 0; i < 20; i++) {
        logger.log('line $i');
      }

      // Current log should exist and be under maxBytes (though
      // one write may overshoot since we rotate before writing)
      expect(File(logPath).existsSync(), isTrue);

      // Backup .1 should exist
      expect(File('$logPath.1').existsSync(), isTrue);
    });

    test('rotates through all backup slots', () {
      final logger = Logger(logPath: logPath, maxBytes: 10, maxBackups: 2);

      // Write many lines to trigger multiple rotations
      for (var i = 0; i < 100; i++) {
        logger.log('x' * 50);
      }

      // Should have log + backups .1 and .2
      expect(File(logPath).existsSync(), isTrue);
      expect(File('$logPath.1').existsSync(), isTrue);
      expect(File('$logPath.2').existsSync(), isTrue);
      // No .3 since maxBackups is 2
      expect(File('$logPath.3').existsSync(), isFalse);
    });

    test('default log path is under getDataDir', () {
      final logger = Logger();
      final dataDir = Logger.getDataDir();
      expect(logger.logPath, contains(dataDir));
    });
  });
}
