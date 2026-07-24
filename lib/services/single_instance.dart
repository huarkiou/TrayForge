// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'package:trayforge_flutter/foundation/logger.dart';

/// Platform-level single-instance guard.
///
/// On Windows, uses a session-local named mutex (`CreateMutexW` with
/// `Local\` prefix — no elevation needed).
/// On Linux, uses a file-based lock on `{data_dir}/instance.lock`:
/// writes the current PID and checks whether a process with that PID
/// is still alive via `kill -0`. (Dart's `lockSync()` is blocking, so
/// we use PID-checking instead — `tryAcquire` must return immediately.)
///
/// **Fail-closed:** if lock acquisition encounters an unexpected error,
/// [tryAcquire] returns `false` — the app must not launch. The only
/// exception is an unrecognised platform, where `true` is returned.
///
/// When [tryAcquire] returns `false`, the second instance should call
/// [signalFirstInstance] to ask the first instance to show its window,
/// then exit. The first instance polls with [checkForWakeSignal].
///
/// Call [tryAcquire] at startup; call [release] on clean shutdown.
class SingleInstance {
  final String dataDir;
  final Logger? logger;
  final String _mutexName;

  // Windows: kernel32 handle
  int? _mutexHandle;
  // Linux: path to the PID lock file for cleanup
  String? _lockPath;

  SingleInstance({String? dataDir, this.logger, String? mutexName})
      : dataDir = dataDir ?? Logger.getDataDir(),
        _mutexName = mutexName ?? 'Local\\TrayForge_SingleInstance';

  // ---- public API ----

  /// Attempts to acquire the single-instance lock.
  ///
  /// Returns `true` if this process is the first instance.
  /// Returns `false` if another instance is already running **or** if
  /// an unexpected error prevents acquisition (fail-closed).
  bool tryAcquire() {
    if (Platform.isWindows) return _tryAcquireWindows();
    if (Platform.isLinux) return _tryAcquireLinux();
    // Unknown platform: allow (no single-instance mechanism available).
    return true;
  }

  /// Releases the single-instance lock.
  ///
  /// Safe to call multiple times. If the lock was never acquired, this
  /// is a no-op.
  void release() {
    if (Platform.isWindows) {
      _releaseWindows();
    } else if (Platform.isLinux) {
      _releaseLinux();
    }
  }

  /// Writes a wake signal for the first instance.
  ///
  /// Call this from a second instance when [tryAcquire] returned `false`.
  /// The first instance should poll with [checkForWakeSignal] and show
  /// its window when the signal is received.
  void signalFirstInstance() {
    _ensureDataDir();
    try {
      final signalFile = File(p.join(dataDir, 'wake_signal'));
      signalFile.writeAsStringSync(
        '${DateTime.now().millisecondsSinceEpoch}\n',
        flush: true,
      );
      logger?.log('SingleInstance: wake signal sent');
    } catch (e) {
      logger?.log('SingleInstance: failed to write wake signal: $e');
    }
  }

  /// Checks whether a second instance has requested a wake-up.
  ///
  /// Returns `true` if a wake signal was found (and deletes it).
  /// Returns `false` if no signal is present.
  ///
  /// The first instance should call this periodically (e.g. on a timer)
  /// and show its window when `true` is returned.
  bool checkForWakeSignal() {
    try {
      final signalFile = File(p.join(dataDir, 'wake_signal'));
      if (signalFile.existsSync()) {
        signalFile.deleteSync();
        logger?.log('SingleInstance: wake signal received');
        return true;
      }
    } catch (e) {
      logger?.log('SingleInstance: error checking wake signal: $e');
    }
    return false;
  }

  // ---- Windows (named mutex via kernel32) ----

  static const int _ERROR_ALREADY_EXISTS = 183;

  static final DynamicLibrary _kernel32 =
      DynamicLibrary.open('kernel32.dll');

  static final _CreateMutexW = _kernel32.lookupFunction<
      IntPtr Function(Pointer<Void> lpMutexAttributes, Int32 bInitialOwner,
          Pointer<Utf16> lpName),
      int Function(Pointer<Void> lpMutexAttributes, int bInitialOwner,
          Pointer<Utf16> lpName)>('CreateMutexW');

  static final _GetLastError =
      _kernel32.lookupFunction<Int32 Function(), int Function()>(
          'GetLastError');

  static final _CloseHandle = _kernel32.lookupFunction<
      Int32 Function(IntPtr hObject), int Function(int hObject)>(
          'CloseHandle');

  bool _tryAcquireWindows() {
    try {
      final name = _mutexName.toNativeUtf16();
      try {
        final handle = _CreateMutexW(
            Pointer.fromAddress(0), 0, name);
        final lastError = _GetLastError();
        if (handle == 0) {
          logger?.log(
              'SingleInstance: CreateMutexW failed (error $lastError)');
          return false; // fail closed
        }
        _mutexHandle = handle;
        if (lastError == _ERROR_ALREADY_EXISTS) {
          logger?.log('SingleInstance: another instance detected (mutex)');
          // Release the handle we just opened — we didn't create it.
          _CloseHandle(handle);
          _mutexHandle = null;
          return false;
        }
        logger?.log('SingleInstance: mutex acquired');
        return true;
      } finally {
        malloc.free(name);
      }
    } catch (e) {
      logger?.log('SingleInstance: error acquiring mutex: $e');
      return false; // fail closed
    }
  }

  void _releaseWindows() {
    final h = _mutexHandle;
    if (h == null || h == 0) return;
    try {
      _CloseHandle(h);
      logger?.log('SingleInstance: mutex released');
    } catch (e) {
      logger?.log('SingleInstance: error releasing mutex: $e');
    }
    _mutexHandle = null;
  }

  // ---- Linux (PID file) ----

  bool _tryAcquireLinux() {
    try {
      _ensureDataDir();
    } catch (e) {
      logger?.log('SingleInstance: cannot create data dir: $e');
      return false; // fail closed
    }

    final lockFile = File(p.join(dataDir, 'instance.lock'));
    final myPid = pid;

    if (lockFile.existsSync()) {
      try {
        final content = lockFile.readAsStringSync().trim();
        final existingPid = int.parse(content);
        if (_processExists(existingPid)) {
          logger
              ?.log('SingleInstance: another instance running (pid $existingPid)');
          return false;
        }
        // Stale lock — process is gone.
        logger?.log('SingleInstance: removing stale lock (pid $existingPid)');
      } catch (e) {
        // Corrupted lock file — overwrite.
        logger?.log('SingleInstance: corrupted lock file, overwriting: $e');
      }
    }

    try {
      lockFile.writeAsStringSync('$myPid', flush: true);
    } catch (e) {
      logger?.log('SingleInstance: cannot write lock file: $e');
      return false; // fail closed
    }

    _lockPath = lockFile.path;
    logger?.log('SingleInstance: lock acquired (pid $myPid)');
    return true;
  }

  void _releaseLinux() {
    final path = _lockPath;
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) {
        f.deleteSync();
      }
      logger?.log('SingleInstance: lock released');
    } catch (e) {
      logger?.log('SingleInstance: error releasing lock: $e');
    }
    _lockPath = null;
  }

  // ---- helpers ----

  void _ensureDataDir() {
    final dir = Directory(dataDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  /// Checks whether a process with [pid] exists.
  ///
  /// Uses `kill -0 <pid>` which sends no signal but checks
  /// the process existence.
  static bool _processExists(int pid) {
    try {
      final result = Process.runSync('kill', ['-0', '$pid']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
