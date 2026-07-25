/// Linux implementation: reads `/proc/<pid>/cwd` symlinks to find processes
/// whose current working directory matches a given path.
library;

import 'dart:io';

/// Returns the set of PIDs whose current working directory matches [cwd].
///
/// Comparison uses [FileSystemEntity.identicalSync] which delegates to
/// `realpath`-based inode comparison after resolving symlinks.  This
/// handles bind mounts, symlinks in the path, and trailing slashes.
///
/// PIDs we cannot read (e.g. kernel threads, `/proc` permissions) are
/// silently skipped.
Set<int> findPidsByCwdLinux(String cwd) {
  final result = <int>{};

  final dir = Directory('/proc');
  if (!dir.existsSync()) return result;

  final target = Directory(cwd);
  String? targetResolved;
  try {
    targetResolved = target.resolveSymbolicLinksSync();
  } catch (_) {
    return result;
  }

  for (final entry in dir.listSync()) {
    final name = entry.path.split('/').last;
    final pid = int.tryParse(name);
    if (pid == null) continue;

    try {
      final cwdLink = File('${entry.path}/cwd');
      if (!cwdLink.existsSync()) continue;

      final linkTarget = cwdLink.resolveSymbolicLinksSync();
      if (linkTarget == targetResolved) {
        result.add(pid);
      }
    } catch (_) {
      // Permission denied, process already exited, etc.
      continue;
    }
  }

  return result;
}
