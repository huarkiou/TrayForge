import 'dart:async';
import 'dart:io';

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

/// Abstract factory that launches processes.
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
