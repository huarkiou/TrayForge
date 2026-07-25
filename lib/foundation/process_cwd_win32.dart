/// Windows 64-bit implementation: enumerate process PIDs whose current working
/// directory matches a given path.
///
/// Uses [NtQueryInformationProcess] to read the process PEB and extract the
/// CurrentDirectory from [RTL_USER_PROCESS_PARAMETERS].  All offsets assume
/// **64-bit** Windows (x64).  32-bit is not supported.
///
/// The FFI chain per process:
///   1. OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ)
///   2. NtQueryInformationProcess(ProcessBasicInformation) → PEB address
///   3. ReadProcessMemory(PEB+0x20) → ProcessParameters pointer
///   4. ReadProcessMemory(PP+0x40) → CurrentDirectory.DosPath.Buffer pointer
///   5. ReadProcessMemory(Buffer)      → Unicode string (cwd)
///   6. CloseHandle
///
/// Offsets are stable on x64 from Vista through Windows 11 but are not
/// guaranteed by a public contract.  They come from the Windows Internals
/// book and the Process Hacker (phnt) headers.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int _PROCESS_QUERY_INFORMATION = 0x0400;
const int _PROCESS_VM_READ = 0x0010;
const int _TH32CS_SNAPPROCESS = 0x00000002;
const int _ProcessBasicInformation = 0;

bool _ntSuccess(int status) => status >= 0;

// ---------------------------------------------------------------------------
// FFI type aliases
// ---------------------------------------------------------------------------

typedef _OpenProcessC =
    IntPtr Function(
      Uint32 dwDesiredAccess,
      Int32 bInheritHandle,
      Uint32 dwProcessId,
    );
typedef _OpenProcessDart =
    int Function(int dwDesiredAccess, int bInheritHandle, int dwProcessId);

typedef _ReadProcessMemoryC =
    Int32 Function(
      IntPtr hProcess,
      IntPtr lpBaseAddress,
      Pointer<Uint8> lpBuffer,
      UintPtr nSize,
      Pointer<UintPtr> lpNumberOfBytesRead,
    );
typedef _ReadProcessMemoryDart =
    int Function(
      int hProcess,
      int lpBaseAddress,
      Pointer<Uint8> lpBuffer,
      int nSize,
      Pointer<UintPtr> lpNumberOfBytesRead,
    );

typedef _CloseHandleC = Int32 Function(IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

typedef _CreateToolhelp32SnapshotC =
    IntPtr Function(Uint32 dwFlags, Uint32 th32ProcessID);
typedef _CreateToolhelp32SnapshotDart =
    int Function(int dwFlags, int th32ProcessID);

typedef _Process32FirstWC =
    Int32 Function(IntPtr hSnapshot, Pointer<ProcessEntry32W> lppe);
typedef _Process32FirstWDart =
    int Function(int hSnapshot, Pointer<ProcessEntry32W> lppe);

typedef _Process32NextWC =
    Int32 Function(IntPtr hSnapshot, Pointer<ProcessEntry32W> lppe);
typedef _Process32NextWDart =
    int Function(int hSnapshot, Pointer<ProcessEntry32W> lppe);

typedef _NtQueryInformationProcessC =
    Int32 Function(
      IntPtr ProcessHandle,
      Int32 ProcessInformationClass,
      Pointer<Uint8> ProcessInformation,
      Uint32 ProcessInformationLength,
      Pointer<Uint32> ReturnLength,
    );
typedef _NtQueryInformationProcessDart =
    int Function(
      int ProcessHandle,
      int ProcessInformationClass,
      Pointer<Uint8> ProcessInformation,
      int ProcessInformationLength,
      Pointer<Uint32> ReturnLength,
    );

// ---------------------------------------------------------------------------
// Struct: PROCESSENTRY32W
// ---------------------------------------------------------------------------

final class ProcessEntry32W extends Struct {
  @Uint32()
  external int dwSize;

  @Uint32()
  external int cntUsage;

  @Uint32()
  external int th32ProcessID;

  @UintPtr()
  external int th32DefaultHeapID;

  @Uint32()
  external int th32ModuleID;

  @Uint32()
  external int cntThreads;

  @Uint32()
  external int th32ParentProcessID;

  @Int32()
  external int pcPriClassBase;

  @Uint32()
  external int dwFlags;

  @Array(260)
  external Array<Uint16> szExeFile;
}

// ---------------------------------------------------------------------------
// Lazy-loaded function pointers
// ---------------------------------------------------------------------------

DynamicLibrary? _kernel32;
DynamicLibrary? _ntdll;

DynamicLibrary get _k32 => _kernel32 ??= DynamicLibrary.open('kernel32.dll');
DynamicLibrary get _nt => _ntdll ??= DynamicLibrary.open('ntdll.dll');

int _openProcess(int access, int inherit, int pid) {
  final f = _k32.lookupFunction<_OpenProcessC, _OpenProcessDart>('OpenProcess');
  return f(access, inherit, pid);
}

int _readProcessMemory(
  int hProcess,
  int baseAddr,
  Pointer<Uint8> buf,
  int size,
  Pointer<UintPtr> bytesRead,
) {
  final f = _k32.lookupFunction<_ReadProcessMemoryC, _ReadProcessMemoryDart>(
    'ReadProcessMemory',
  );
  return f(hProcess, baseAddr, buf, size, bytesRead);
}

int _closeHandle(int h) {
  final f = _k32.lookupFunction<_CloseHandleC, _CloseHandleDart>('CloseHandle');
  return f(h);
}

int _createToolhelp32Snapshot(int flags, int pid) {
  final f = _k32
      .lookupFunction<
        _CreateToolhelp32SnapshotC,
        _CreateToolhelp32SnapshotDart
      >('CreateToolhelp32Snapshot');
  return f(flags, pid);
}

int _process32FirstW(int snap, Pointer<ProcessEntry32W> entry) {
  final f = _k32.lookupFunction<_Process32FirstWC, _Process32FirstWDart>(
    'Process32FirstW',
  );
  return f(snap, entry);
}

int _process32NextW(int snap, Pointer<ProcessEntry32W> entry) {
  final f = _k32.lookupFunction<_Process32NextWC, _Process32NextWDart>(
    'Process32NextW',
  );
  return f(snap, entry);
}

int _ntQueryInformationProcess(
  int handle,
  int infoClass,
  Pointer<Uint8> info,
  int infoLen,
  Pointer<Uint32> retLen,
) {
  final f = _nt
      .lookupFunction<
        _NtQueryInformationProcessC,
        _NtQueryInformationProcessDart
      >('NtQueryInformationProcess');
  return f(handle, infoClass, info, infoLen, retLen);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Returns the set of PIDs whose current working directory matches [cwd].
///
/// Comparison is case-insensitive.  PIDs we cannot open or read (e.g. system
/// processes) are silently skipped.
Set<int> findPidsByCwdWin32(String cwd) {
  final result = <int>{};

  final normCwd = _normalizePath(cwd);
  if (normCwd.isEmpty) return result;

  final snapshot = _createToolhelp32Snapshot(_TH32CS_SNAPPROCESS, 0);
  if (snapshot == -1) return result; // INVALID_HANDLE_VALUE

  final entry = calloc<ProcessEntry32W>();
  try {
    entry.ref.dwSize = sizeOf<ProcessEntry32W>();

    if (_process32FirstW(snapshot, entry) == 0) return result;

    do {
      final pid = entry.ref.th32ProcessID;
      // Skip System Idle Process (0) and System (4).
      if (pid <= 4) continue;

      final processCwd = _getProcessCwd(pid);
      if (processCwd != null && _pathEq(normCwd, processCwd)) {
        result.add(pid);
      }
    } while (_process32NextW(snapshot, entry) != 0);
  } finally {
    calloc.free(entry);
    _closeHandle(snapshot);
  }

  return result;
}

// ---------------------------------------------------------------------------
// Private: per-process cwd
// ---------------------------------------------------------------------------

/// Reads the current working directory of process [pid].
///
/// Returns `null` if the PID cannot be opened, the PEB cannot be read, or
/// any step in the memory-read chain fails.
String? _getProcessCwd(int pid) {
  final hProcess = _openProcess(
    _PROCESS_QUERY_INFORMATION | _PROCESS_VM_READ,
    0, // no inherit
    pid,
  );
  if (hProcess == 0) return null;

  try {
    // Step 1: NtQueryInformationProcess → PEB address.
    final pbi = calloc<Uint8>(48); // sizeof(PROCESS_BASIC_INFORMATION) on x64
    final retLen = calloc<Uint32>();

    final status = _ntQueryInformationProcess(
      hProcess,
      _ProcessBasicInformation,
      pbi,
      48,
      retLen,
    );
    if (!_ntSuccess(status)) {
      calloc.free(pbi);
      calloc.free(retLen);
      return null;
    }

    // PebBaseAddress at offset 8 (skip ExitStatus + 4 bytes padding).
    final pebAddr = _readPtr(pbi, 8);

    calloc.free(pbi);
    calloc.free(retLen);

    // Step 2: Read PEB+0x20 → ProcessParameters pointer.
    final pp = _readRemotePtr(hProcess, pebAddr + 0x20);
    if (pp == 0) return null;

    // Step 3: Read PP+0x40 → CurrentDirectory.DosPath.Buffer pointer.
    // CURDIR.DosPath is at 0x38; UNICODE_STRING.Buffer at +0x08 → 0x40.
    final bufPtr = _readRemotePtr(hProcess, pp + 0x40);
    if (bufPtr == 0) return null;

    // Step 4: Read PP+0x38 → CurrentDirectory.DosPath.Length (USHORT).
    final cwdLen = _readRemoteUint16(hProcess, pp + 0x38);
    if (cwdLen == 0 || cwdLen > 32768) return null;

    // Step 5: Read the Unicode string.
    final cwdWide = calloc<Uint16>(cwdLen ~/ 2);
    final bytesRead = calloc<UintPtr>();
    try {
      final ok = _readProcessMemory(
        hProcess,
        bufPtr,
        cwdWide.cast<Uint8>(),
        cwdLen,
        bytesRead,
      );
      if (ok == 0 || bytesRead.value == 0) return null;

      return String.fromCharCodes(
        cwdWide.asTypedList(cwdLen ~/ 2),
      ).replaceAll('\x00', '');
    } finally {
      calloc.free(cwdWide);
      calloc.free(bytesRead);
    }
  } finally {
    _closeHandle(hProcess);
  }
}

// ---------------------------------------------------------------------------
// Private: remote memory helpers
// ---------------------------------------------------------------------------

/// Reads a pointer-sized value from local buffer [p] at [offset].
int _readPtr(Pointer<Uint8> p, int offset) {
  final bytes = p.asTypedList(48);
  int result = 0;
  for (int i = 0; i < 8; i++) {
    result |= bytes[offset + i] << (8 * i);
  }
  return result;
}

/// Reads a pointer-sized value from remote process at [addr].
int _readRemotePtr(int hProcess, int addr) {
  final buf = calloc<Uint8>(8);
  final bytesRead = calloc<UintPtr>();
  try {
    final ok = _readProcessMemory(hProcess, addr, buf, 8, bytesRead);
    if (ok == 0 || bytesRead.value != 8) return 0;
    return _readPtr(buf, 0);
  } finally {
    calloc.free(buf);
    calloc.free(bytesRead);
  }
}

/// Reads a USHORT (2 bytes) from remote process at [addr].
int _readRemoteUint16(int hProcess, int addr) {
  final buf = calloc<Uint8>(2);
  final bytesRead = calloc<UintPtr>();
  try {
    final ok = _readProcessMemory(hProcess, addr, buf, 2, bytesRead);
    if (ok == 0 || bytesRead.value != 2) return 0;
    return buf[0] | (buf[1] << 8);
  } finally {
    calloc.free(buf);
    calloc.free(bytesRead);
  }
}

// ---------------------------------------------------------------------------
// Private: path helpers
// ---------------------------------------------------------------------------

/// Case-folded, backslash-normalised path for comparison.
String _normalizePath(String path) {
  var s = path.trim().replaceAll('/', '\\').toUpperCase();
  while (s.endsWith('\\') && s.length > 3) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

bool _pathEq(String a, String b) => _normalizePath(a) == _normalizePath(b);
