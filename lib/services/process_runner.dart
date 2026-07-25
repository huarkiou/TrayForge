import 'dart:async';
import 'dart:io';

import 'package:trayforge_flutter/foundation/process_cwd.dart';

/// Abstract handle to a running process.
///
/// Exposes the minimal surface that [ProcessManager] needs:
/// pid, stdout/stderr byte streams, exit code future, and a kill
/// method. Mock implementations use this interface in tests.
abstract class IProcessHandle {
  int get pid;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  /// Kills the process.
  ///
  /// Returns `true` if the signal was delivered.
  bool kill({ProcessSignal signal});
}

/// Abstract factory that launches processes and checks OS state.
///
/// The real implementation delegates to [Process.start].
abstract class IProcessRunner {
  Future<IProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell,
  });

  /// Returns `true` if a process with [executableName] is already
  /// running at the OS level.
  Future<bool> isProcessRunning(String executableName);

  /// Returns `true` if a process with the given [pid] is running.
  Future<bool> isPidAlive(int pid);

  /// Returns the start time of the process with [pid].
  ///
  /// Returns `null` if the process is not running or the start time
  /// cannot be determined.
  Future<DateTime?> getProcessStartTime(int pid);

  /// Kills the process tree rooted at [pid].
  ///
  /// Uses the same platform dispatch as [ProcessManager.stop]:
  /// `taskkill /t /f /pid <pid>` on Windows,
  /// `pkill -P <pid>` + `SIGKILL` on Linux.
  ///
  /// Returns `true` if the kill succeeded.
  Future<bool> killPid(int pid);

  /// Returns the set of PIDs whose current working directory matches [cwd].
  ///
  /// Used by [cleanupCwd] to kill residual processes from the same working
  /// directory before starting a new instance.
  Future<Set<int>> findPidsByCwd(String cwd);
}

// ---------------------------------------------------------------------------
// Real implementations
// ---------------------------------------------------------------------------

/// Wraps a dart:io [Process] so it satisfies [IProcessHandle].
class RealProcessHandle implements IProcessHandle {
  final Process _process;

  RealProcessHandle(this._process);

  @override
  int get pid => _process.pid;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  bool kill({ProcessSignal signal = ProcessSignal.sigkill}) {
    return _process.kill(signal);
  }
}

/// Launches real OS processes via [Process.start].
class RealProcessRunner implements IProcessRunner {
  @override
  Future<bool> isProcessRunning(String executableName) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'tasklist',
          ['/FI', 'IMAGENAME eq $executableName', '/NH'],
        );
        return result.stdout.toString().contains(executableName);
      } else {
        final result = await Process.run(
          'pgrep',
          ['-x', executableName],
        );
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isPidAlive(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $pid', '/NH'],
        );
        return result.stdout.toString().contains(pid.toString());
      } else {
        final result = await Process.run(
          'kill',
          ['-0', pid.toString()],
        );
        return result.exitCode == 0;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DateTime?> getProcessStartTime(int pid) async {
    try {
      if (Platform.isWindows) {
        // wmic returns: CreationDate=20250101083015.123456+480
        final result = await Process.run(
          'wmic',
          ['process', 'where', 'ProcessId=$pid', 'get', 'CreationDate',
           '/format:csv'],
        );
        final output = result.stdout.toString();
        final match = RegExp(r'(\d{14})\.\d+').firstMatch(output);
        if (match != null) {
          final ts = match.group(1)!;
          return DateTime(
            int.parse(ts.substring(0, 4)),
            int.parse(ts.substring(4, 6)),
            int.parse(ts.substring(6, 8)),
            int.parse(ts.substring(8, 10)),
            int.parse(ts.substring(10, 12)),
            int.parse(ts.substring(12, 14)),
          );
        }
      } else {
        // /proc/<pid>/stat: field 22 is starttime in clock ticks since boot.
        // Simpler: `ps -o lstart= -p <pid>` returns "Mon Jan  1 08:30:15 2025".
        final result = await Process.run(
          'ps',
          ['-o', 'lstart=', '-p', pid.toString()],
        );
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty) {
          return DateTime.tryParse(output);
        }
      }
    } catch (_) {
      // Fall through to null.
    }
    return null;
  }

  @override
  Future<bool> killPid(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'taskkill', ['/t', '/f', '/pid', pid.toString()],
        );
        return result.exitCode == 0;
      } else {
        await Process.run('pkill', ['-P', pid.toString()]);
        Process.killPid(pid, ProcessSignal.sigkill);
        return true;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Set<int>> findPidsByCwd(String cwd) async {
    // Import is conditional on dart:ffi availability; on platforms
    // without it the call is a no-op.
    return findPidsByCwd(cwd);
  }

  @override
  Future<IProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );
    return RealProcessHandle(process);
  }
}
