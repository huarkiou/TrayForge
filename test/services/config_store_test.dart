import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/services/config_store.dart';

void main() {
  group('ConfigStore', () {
    late Directory tmpDir;
    late ConfigStore store;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('trayforge_cs_test_');
      store = ConfigStore(dataDir: tmpDir.path, maxBackupBytes: 10000);
    });

    tearDown(() {
      store.dispose();
      tmpDir.deleteSync(recursive: true);
    });

    // ---- load() ----

    group('load', () {
      test('returns null when config file does not exist', () {
        expect(store.load(), isNull);
      });

      test('returns AppConfig for a valid config file', () {
        final config = AppConfig(
          outputHistoryLimit: 500,
          outputRefreshMs: 200,
          processes: [
            ProcessConfig(name: 'app', cmd: 'run.exe'),
          ],
        );
        _writeConfig(tmpDir, config);

        final result = store.load();
        expect(result, isNotNull);
        expect(result!.outputHistoryLimit, 500);
        expect(result.outputRefreshMs, 200);
        expect(result.processes.length, 1);
        expect(result.processes[0].name, 'app');
      });

      test('returns config with correct Python TrayForge JSON keys', () {
        final config = AppConfig(
          outputHistoryLimit: 250,
          outputRefreshMs: 50,
          processes: [
            ProcessConfig(
              name: 'svc',
              cwd: '/work',
              cmd: 'svc --verbose',
              encoding: 'gbk',
              singleton: true,
              autostart: true,
              webuiPattern: r'http://[\d.:]+',
              deleteBeforeStart: true,
              maxRestarts: 3,
              env: {'KEY': 'val'},
            ),
          ],
        );
        _writeConfig(tmpDir, config);

        final result = store.load()!;
        final p = result.processes[0];
        expect(p.name, 'svc');
        expect(p.cwd, '/work');
        expect(p.cmd, 'svc --verbose');
        expect(p.encoding, 'gbk');
        expect(p.singleton, true);
        expect(p.autostart, true);
        expect(p.webuiPattern, r'http://[\d.:]+');
        expect(p.deleteBeforeStart, true);
        expect(p.maxRestarts, 3);
        expect(p.env, {'KEY': 'val'});
      });

      test('on JSON parse error, backs up corrupted file and returns null', () {
        final configPath = '${tmpDir.path}/config.json';
        File(configPath).writeAsStringSync('not { valid json', flush: true);

        final result = store.load();
        expect(result, isNull);

        final backupsDir = Directory('${tmpDir.path}/backups');
        expect(backupsDir.existsSync(), isTrue);

        final backups = backupsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.corrupted.json'))
            .toList();
        expect(backups.length, 1);
        expect(backups[0].readAsStringSync(), 'not { valid json');
      });

      test('on type error (not a map), backs up and returns null', () {
        final configPath = '${tmpDir.path}/config.json';
        File(configPath).writeAsStringSync('["just", "an", "array"]',
            flush: true);

        final result = store.load();
        expect(result, isNull);

        final backupsDir = Directory('${tmpDir.path}/backups');
        final backups = backupsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.corrupted.json'))
            .toList();
        expect(backups.length, 1);
      });
    });

    // ---- save() ----

    group('save', () {
      test('writes config to config.json with indented JSON', () {
        final config = AppConfig(
          processes: [
            ProcessConfig(name: 'test', cmd: 'echo'),
          ],
        );

        store.save(config);

        final file = File('${tmpDir.path}/config.json');
        expect(file.existsSync(), isTrue);

        final content = file.readAsStringSync();
        expect(content, contains('  ')); // indented
        expect(content, contains('"name": "test"'));
      });

      test('uses Python TrayForge JSON keys (snake_case)', () {
        final config = AppConfig(
          outputHistoryLimit: 42,
          outputRefreshMs: 7,
          processes: [
            ProcessConfig(
              name: 'svc',
              cwd: '/app',
              cmd: 'run',
              encoding: 'utf-8',
              singleton: true,
              autostart: false,
              webuiPattern: r'http://.*',
              deleteBeforeStart: true,
              maxRestarts: 5,
              env: {'A': 'B'},
            ),
          ],
        );

        store.save(config);

        final content = File('${tmpDir.path}/config.json').readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;

        // Top-level keys
        expect(json.containsKey('output_history_limit'), isTrue);
        expect(json.containsKey('output_refresh_ms'), isTrue);
        expect(json.containsKey('processes'), isTrue);

        // Process-level keys
        final proc = (json['processes'] as List).first as Map<String, dynamic>;
        expect(proc.containsKey('webui_pattern'), isTrue);
        expect(proc.containsKey('delete_before_start'), isTrue);
        expect(proc.containsKey('max_restarts'), isTrue);

        // No camelCase keys
        expect(content.contains('webuiPattern'), isFalse);
        expect(content.contains('outputHistoryLimit'), isFalse);
      });

      test('creates data directory if it does not exist', () {
        final nested = '${tmpDir.path}/nested/sub';
        final nestedStore =
            ConfigStore(dataDir: nested, maxBackupBytes: 300);

        nestedStore.save(AppConfig());
        expect(File('$nested/config.json').existsSync(), isTrue);

        nestedStore.dispose();
      });

      test('backs up existing config before overwriting', () {
        // First save
        store.save(AppConfig(processes: [
          ProcessConfig(name: 'first', cmd: 'f'),
        ]));

        // Second save
        store.save(AppConfig(processes: [
          ProcessConfig(name: 'second', cmd: 's'),
        ]));

        // Check backup exists
        final backupsDir = Directory('${tmpDir.path}/backups');
        final backups = backupsDir
            .listSync()
            .whereType<File>()
            .where((f) => !f.path.contains('.corrupted'))
            .toList();
        expect(backups.length, 1);

        // Backup should contain the first config
        final backupContent = backups[0].readAsStringSync();
        expect(backupContent, contains('"name": "first"'));

        // Current config should be the second
        final currentContent =
            File('${tmpDir.path}/config.json').readAsStringSync();
        expect(currentContent, contains('"name": "second"'));
      });

      test('does not backup when no existing config', () {
        store.save(AppConfig());

        final backupsDir = Directory('${tmpDir.path}/backups');
        if (backupsDir.existsSync()) {
          final backups = backupsDir
              .listSync()
              .whereType<File>()
              .where((f) => !f.path.contains('.corrupted'))
              .toList();
          expect(backups, isEmpty);
        }
      });

      test('multiple saves create sequential backup files', () {
        for (var i = 0; i < 3; i++) {
          store.save(AppConfig(processes: [
            ProcessConfig(name: 'v$i', cmd: 'c$i'),
          ]));
        }

        final backupsDir = Directory('${tmpDir.path}/backups');
        // 3 saves = 2 backups (the third save backs up the second, etc.)
        // Actually: save1 (no backup), save2 (backs up v0), save3 (backs up v1)
        final backups = backupsDir
            .listSync()
            .whereType<File>()
            .where((f) => !f.path.contains('.corrupted'))
            .toList();
        expect(backups.length, 2);
        // Names should be sorted by timestamp
        expect(backups.length, greaterThanOrEqualTo(2));
      });
    });

    // ---- prune ----

    group('prune', () {
      test('deletes oldest backups when backups dir exceeds maxBackupBytes',
          () {
        final tinyStore =
            ConfigStore(dataDir: tmpDir.path, maxBackupBytes: 200);

        // Create a backup directory so _backupExisting finds something
        final backupsDir = Directory('${tmpDir.path}/backups');
        backupsDir.createSync(recursive: true);

        // Manually create backup files — oldest first by name
        File('${backupsDir.path}/config.20200101_000000.json')
            .writeAsStringSync('x' * 150, flush: true);
        File('${backupsDir.path}/config.20200101_000001.json')
            .writeAsStringSync('x' * 120, flush: true);

        // Also create a current config so save() backs up
        _writeConfig(tmpDir, AppConfig(processes: [
          ProcessConfig(name: 'x', cmd: 'x'),
        ]));

        // Total is 270 which exceeds 200. Save should prune oldest.
        tinyStore.save(AppConfig(processes: [
          ProcessConfig(name: 'y', cmd: 'y'),
        ]));

        // Oldest backup (20200101_000000) should be deleted
        expect(
          File('${backupsDir.path}/config.20200101_000000.json')
              .existsSync(),
          isFalse,
        );

        // Remaining should be <= 200
        final remaining = backupsDir
            .listSync()
            .whereType<File>()
            .where((f) => !f.path.contains('.corrupted'))
            .toList();
        final totalSize =
            remaining.fold<int>(0, (sum, f) => sum + f.lengthSync());
        expect(totalSize, lessThanOrEqualTo(200));

        tinyStore.dispose();
      });

      test('no-op when backups dir does not exist', () {
        // Save without any existing config → no backups dir
        store.save(AppConfig());
        // Should not throw
      });
    });

    // ---- validate() ----

    group('validate', () {
      test('rejects name containing forward slash', () {
        expect(
          () => store.validate(ProcessConfig(name: 'a/b', cmd: 'c')),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('/'),
          )),
        );
      });

      test('rejects empty name', () {
        expect(
          () => store.validate(ProcessConfig(name: '', cmd: 'c')),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('empty'),
          )),
        );
      });

      test('rejects whitespace-only name', () {
        expect(
          () => store.validate(ProcessConfig(name: '   ', cmd: 'c')),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('empty'),
          )),
        );
      });

      test('rejects name containing backslash', () {
        expect(
          () => store.validate(ProcessConfig(name: r'a\b', cmd: 'c')),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains(r'\'),
          )),
        );
      });

      test('rejects invalid webui_pattern regex', () {
        expect(
          () => store.validate(ProcessConfig(
              name: 'valid', cmd: 'c', webuiPattern: '[unclosed')),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('webui_pattern'),
          )),
        );
      });

      test('accepts valid config', () {
        expect(
          () => store.validate(ProcessConfig(name: 'hello', cmd: 'echo')),
          returnsNormally,
        );
      });

      test('accepts null webuiPattern', () {
        expect(
          () => store.validate(ProcessConfig(name: 'svc', cmd: 'run')),
          returnsNormally,
        );
      });

      test('accepts valid webuiPattern regex', () {
        expect(
          () => store.validate(ProcessConfig(
              name: 'web', cmd: 'run', webuiPattern: r'http://[\d.:]+')),
          returnsNormally,
        );
      });
    });

    // ---- configChanged stream ----

    group('configChanged', () {
      test('emits when save is called', () async {
        final events = <void>[];
        final sub = store.configChanged.listen((_) => events.add(null));

        store.save(AppConfig(processes: [
          ProcessConfig(name: 'a', cmd: 'a'),
        ]));

        // Allow microtask to process
        await Future<void>.delayed(Duration.zero);
        expect(events.length, 1);

        store.save(AppConfig(processes: [
          ProcessConfig(name: 'b', cmd: 'b'),
        ]));

        await Future<void>.delayed(Duration.zero);
        expect(events.length, 2);

        await sub.cancel();
      });
    });
  });
}

/// Helper: writes a config to the temp directory's config.json.
void _writeConfig(Directory tmpDir, AppConfig config) {
  final json = config.toJson();
  final encoded = const JsonEncoder.withIndent('  ').convert(json);
  final configPath = '${tmpDir.path}/config.json';
  final dir = Directory(configPath).parent;
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File(configPath).writeAsStringSync(encoded, encoding: utf8, flush: true);
}
