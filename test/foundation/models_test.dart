import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';

void main() {
  group('ProcState', () {
    test('has six states', () {
      expect(ProcState.values.length, 6);
      expect(ProcState.values, [
        ProcState.stopped,
        ProcState.starting,
        ProcState.running,
        ProcState.stopping,
        ProcState.crashed,
        ProcState.cooldown,
      ]);
    });
  });

  group('ProcessConfig', () {
    test('creates with required fields', () {
      final config = ProcessConfig(name: 'test', cmd: 'echo hello');
      expect(config.name, 'test');
      expect(config.cmd, 'echo hello');
      expect(config.cwd, isNull);
      expect(config.encoding, isNull);
      expect(config.singleton, false);
      expect(config.autostart, false);
      expect(config.webuiPattern, isNull);
      expect(config.deleteBeforeStart, isEmpty);
      expect(config.maxRestarts, isNull);
      expect(config.env, isNull);
    });

    test('creates with all fields', () {
      final config = ProcessConfig(
        name: 'full',
        cwd: '/tmp',
        cmd: 'run.sh --verbose',
        encoding: 'utf-8',
        singleton: true,
        autostart: true,
        webuiPattern: r'http://[\d.:]+',
        deleteBeforeStart: ['file.lock'],
        maxRestarts: 5,
        env: {'KEY': 'value'},
      );
      expect(config.name, 'full');
      expect(config.cwd, '/tmp');
      expect(config.cmd, 'run.sh --verbose');
      expect(config.encoding, 'utf-8');
      expect(config.singleton, true);
      expect(config.autostart, true);
      expect(config.webuiPattern, r'http://[\d.:]+');
      expect(config.deleteBeforeStart, ['file.lock']);
      expect(config.maxRestarts, 5);
      expect(config.env, {'KEY': 'value'});
    });

    group('toJson', () {
      test('serializes with only non-null optional fields', () {
        final config = ProcessConfig(name: 'minimal', cmd: 'app.exe');
        final json = config.toJson();
        expect(json['name'], 'minimal');
        expect(json['cmd'], 'app.exe');
        expect(json.containsKey('cwd'), false);
        expect(json.containsKey('encoding'), false);
        expect(json.containsKey('webui_pattern'), false);
        expect(json.containsKey('max_restarts'), false);
        expect(json.containsKey('env'), false);
      });

      test('serializes all fields', () {
        final config = ProcessConfig(
          name: 'full',
          cwd: '/app',
          cmd: 'run',
          encoding: 'latin1',
          singleton: true,
          autostart: true,
          webuiPattern: r'http://.*',
          deleteBeforeStart: ['a.lock', 'b.lock'],
          maxRestarts: 3,
          env: {'A': '1'},
        );
        final json = config.toJson();
        expect(json['name'], 'full');
        expect(json['cwd'], '/app');
        expect(json['cmd'], 'run');
        expect(json['encoding'], 'latin1');
        expect(json['singleton'], true);
        expect(json['autostart'], true);
        expect(json['webui_pattern'], r'http://.*');
        expect(json['delete_before_start'], ['a.lock', 'b.lock']);
        expect(json['max_restarts'], 3);
        expect(json['env'], {'A': '1'});
      });
    });

    group('fromJson', () {
      test('deserializes minimal json', () {
        final json = {'name': 'test', 'cmd': 'app.exe'};
        final config = ProcessConfig.fromJson(json);
        expect(config.name, 'test');
        expect(config.cmd, 'app.exe');
        expect(config.cwd, isNull);
        expect(config.singleton, false);
      });

      test('deserializes full json with snake_case keys', () {
        final json = {
          'name': 'full',
          'cwd': '/app',
          'cmd': 'run',
          'encoding': 'utf-8',
          'singleton': true,
          'autostart': true,
          'webui_pattern': r'http://.*',
          'delete_before_start': ['lock.file'],
          'max_restarts': 3,
          'env': {'KEY': 'val'},
        };
        final config = ProcessConfig.fromJson(json);
        expect(config.name, 'full');
        expect(config.cwd, '/app');
        expect(config.cmd, 'run');
        expect(config.encoding, 'utf-8');
        expect(config.singleton, true);
        expect(config.autostart, true);
        expect(config.webuiPattern, r'http://.*');
        expect(config.deleteBeforeStart, ['lock.file']);
        expect(config.maxRestarts, 3);
        expect(config.env, {'KEY': 'val'});
      });

      test('deserializes with defaults for missing fields', () {
        final json = {'name': 'min', 'cmd': 'run'};
        final config = ProcessConfig.fromJson(json);
        expect(config.singleton, false);
        expect(config.autostart, false);
        expect(config.deleteBeforeStart, isEmpty);
        expect(config.maxRestarts, isNull);
      });

      test('migrates old bool delete_before_start to empty list', () {
        final json = {
          'name': 'old',
          'cmd': 'run',
          'delete_before_start': true, // old Flutter format
        };
        final config = ProcessConfig.fromJson(json);
        expect(config.deleteBeforeStart, isEmpty);
      });
    });

    group('copyWith', () {
      test('returns new instance with changed fields', () {
        final original = ProcessConfig(
          name: 'orig',
          cwd: '/tmp',
          cmd: 'cmd',
        );
        final copy = original.copyWith(name: 'new');
        expect(copy.name, 'new');
        expect(copy.cwd, '/tmp');
        expect(copy.cmd, 'cmd');
      });

    });
  });

  group('AppConfig', () {
    test('creates with defaults', () {
      final config = AppConfig();
      expect(config.outputHistoryLimit, 1000);
      expect(config.outputRefreshMs, 500);
      expect(config.processes, isEmpty);
    });

    test('creates with custom values', () {
      final processes = [
        ProcessConfig(name: 'p1', cmd: 'c1'),
      ];
      final config = AppConfig(
        outputHistoryLimit: 500,
        outputRefreshMs: 50,
        processes: processes,
      );
      expect(config.outputHistoryLimit, 500);
      expect(config.outputRefreshMs, 50);
      expect(config.processes, processes);
    });

    test('defaultConfig provides NapCat and AstrBot', () {
      final config = AppConfig.defaultConfig();
      expect(config.outputHistoryLimit, 1000);
      expect(config.outputRefreshMs, 500);
      expect(config.processes.length, 2);

      final napcat = config.processes[0];
      expect(napcat.name, 'NapCat');
      expect(napcat.cmd, r'napcat.exe');
      expect(napcat.singleton, true);
      expect(napcat.autostart, true);
      expect(napcat.maxRestarts, 3);

      final astrbot = config.processes[1];
      expect(astrbot.name, 'AstrBot');
      expect(astrbot.cmd, r'astrbot.exe');
      expect(astrbot.singleton, true);
      expect(astrbot.autostart, true);
      expect(astrbot.maxRestarts, 3);
    });

    group('toJson', () {
      test('serializes config with processes', () {
        final config = AppConfig(
          outputHistoryLimit: 200,
          outputRefreshMs: 50,
          processes: [
            ProcessConfig(name: 'p1', cmd: 'c1'),
          ],
        );
        final json = config.toJson();
        expect(json['output_history_limit'], 200);
        expect(json['output_refresh_ms'], 50);
        expect(json['processes'], isA<List>());
        expect((json['processes'] as List).length, 1);
      });
    });

    group('fromJson', () {
      test('deserializes with defaults', () {
        final json = <String, dynamic>{};
        final config = AppConfig.fromJson(json);
        expect(config.outputHistoryLimit, 1000);
        expect(config.outputRefreshMs, 500);
        expect(config.processes, isEmpty);
      });

      test('deserializes full config', () {
        final json = {
          'output_history_limit': 500,
          'output_refresh_ms': 200,
          'processes': [
            {'name': 'p1', 'cmd': 'c1'},
            {'name': 'p2', 'cmd': 'c2', 'singleton': true},
          ],
        };
        final config = AppConfig.fromJson(json);
        expect(config.outputHistoryLimit, 500);
        expect(config.outputRefreshMs, 200);
        expect(config.processes.length, 2);
        expect(config.processes[0].name, 'p1');
        expect(config.processes[1].singleton, true);
      });
    });
  });
}
