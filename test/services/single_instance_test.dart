import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/services/single_instance.dart';

void main() {
  group('SingleInstance', () {
    late Directory tmpDir;
    late SingleInstance si;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('trayforge_si_test_');
      si = SingleInstance(dataDir: tmpDir.path);
    });

    tearDown(() {
      si.release();
      tmpDir.deleteSync(recursive: true);
    });

    group('on Linux', () {
      test('tryAcquire returns true on first call', () {
        if (!Platform.isLinux) return;
        expect(si.tryAcquire(), isTrue);
      });

      test('tryAcquire returns false when another instance holds the lock', () {
        if (!Platform.isLinux) return;

        expect(si.tryAcquire(), isTrue);

        // Simulate a second instance using the same data dir.
        final si2 = SingleInstance(dataDir: tmpDir.path);
        try {
          expect(si2.tryAcquire(), isFalse);
        } finally {
          si2.release();
        }
      });

      test('release then tryAcquire returns true again', () {
        if (!Platform.isLinux) return;

        expect(si.tryAcquire(), isTrue);
        si.release();

        final si2 = SingleInstance(dataDir: tmpDir.path);
        try {
          expect(si2.tryAcquire(), isTrue);
        } finally {
          si2.release();
        }
      });

      test('release is safe to call multiple times', () {
        if (!Platform.isLinux) return;

        si.release(); // before acquire
        expect(si.tryAcquire(), isTrue);
        si.release(); // first
        si.release(); // second
        // No exception → pass
      });

      test('tryAcquire cleans up stale lock (non-existent PID)', () {
        if (!Platform.isLinux) return;

        // Write a lock file with a non-existent PID.
        final lockFile = File('${tmpDir.path}/instance.lock');
        lockFile.writeAsStringSync('99999999', flush: true);

        expect(si.tryAcquire(), isTrue);
        // Lock file should now contain our PID instead.
        expect(lockFile.readAsStringSync().trim(), isNot('99999999'));
      });

      test('tryAcquire handles corrupted lock file', () {
        if (!Platform.isLinux) return;

        final lockFile = File('${tmpDir.path}/instance.lock');
        lockFile.writeAsStringSync('not-a-number', flush: true);

        expect(si.tryAcquire(), isTrue);
      });
    });

    group('on Windows', () {
      test('tryAcquire returns true on first call', () {
        if (!Platform.isWindows) return;
        final si = SingleInstance(
          dataDir: tmpDir.path,
          mutexName: 'Local\\trayforge_Test_FirstCall',
        );
        try {
          expect(si.tryAcquire(), isTrue);
        } finally {
          si.release();
        }
      });

      test(
        'tryAcquire returns false when another instance holds the mutex',
        () {
          if (!Platform.isWindows) return;

          final mutexName =
              'Local\\trayforge_Test_${DateTime.now().microsecondsSinceEpoch}';
          final si1 = SingleInstance(
            dataDir: tmpDir.path,
            mutexName: mutexName,
          );
          try {
            expect(si1.tryAcquire(), isTrue);

            final si2 = SingleInstance(
              dataDir: tmpDir.path,
              mutexName: mutexName,
            );
            try {
              expect(si2.tryAcquire(), isFalse);
            } finally {
              si2.release();
            }
          } finally {
            si1.release();
          }
        },
      );

      test('release is safe to call multiple times', () {
        if (!Platform.isWindows) return;

        final si = SingleInstance(
          dataDir: tmpDir.path,
          mutexName: 'Local\\trayforge_Test_MultiRelease',
        );

        si.release();
        expect(si.tryAcquire(), isTrue);
        si.release();
        si.release();
      });
    });

    group('cross-platform', () {
      test('tryAcquire succeeds on non-Windows/non-Linux', () {
        if (Platform.isWindows || Platform.isLinux) return;
        expect(si.tryAcquire(), isTrue);
      });
    });

    group('wake signal', () {
      test('checkForWakeSignal returns false when no signal', () {
        expect(si.checkForWakeSignal(), isFalse);
      });

      test('signalFirstInstance writes a wake signal', () {
        si.signalFirstInstance();

        final signalFile = File('${tmpDir.path}/wake_signal');
        expect(signalFile.existsSync(), isTrue);
      });

      test('checkForWakeSignal sees and clears the signal', () {
        si.signalFirstInstance();

        expect(si.checkForWakeSignal(), isTrue);
        // Signal is consumed.
        expect(si.checkForWakeSignal(), isFalse);

        final signalFile = File('${tmpDir.path}/wake_signal');
        expect(signalFile.existsSync(), isFalse);
      });

      test('second instance can signal first instance', () {
        if (!Platform.isLinux) return;

        // First instance acquires.
        expect(si.tryAcquire(), isTrue);

        // Second instance tries and fails.
        final si2 = SingleInstance(dataDir: tmpDir.path);
        try {
          expect(si2.tryAcquire(), isFalse);
          // Second instance signals.
          si2.signalFirstInstance();
        } finally {
          si2.release();
        }

        // First instance sees the signal.
        expect(si.checkForWakeSignal(), isTrue);
      });
    });
  });
}
