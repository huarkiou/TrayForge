/// Platform dispatch for enumerating processes by current working directory.
library;

import 'dart:io';

import 'process_cwd_linux.dart';
import 'process_cwd_win32.dart';

/// Returns the set of PIDs whose current working directory matches [cwd].
///
/// - **Windows x64**: Calls [NtQueryInformationProcess] via FFI to read the
///   PEB and extract [RTL_USER_PROCESS_PARAMETERS.CurrentDirectory].
/// - **Linux**: Reads `/proc/<pid>/cwd` symlinks and resolves to real paths.
///
/// Comparison is case-insensitive on Windows, inode-based on Linux.
/// Errors (permission denied, exited process, etc.) are silently skipped.
Set<int> findPidsByCwd(String cwd) {
  if (Platform.isWindows) {
    return findPidsByCwdWin32(cwd);
  }
  if (Platform.isLinux) {
    return findPidsByCwdLinux(cwd);
  }
  return {};
}
