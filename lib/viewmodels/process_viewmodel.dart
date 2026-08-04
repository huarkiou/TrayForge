// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/process_manager.dart';

/// ViewModel for a single managed process.
///
/// Mirrors [ProcState] from [ProcessManager], accumulates output lines
/// bounded by [outputHistoryLimit], tracks WebUI URL detection via a
/// per-process pipeline stream, and exposes a toggle that shows a spinner
/// while the manager works. The start/stop decision itself lives in
/// `ProcessController.toggle` — not here.
class ProcessViewModel extends ChangeNotifier {
  final String name;
  final ProcessManager _processManager;
  final int _outputHistoryLimit;

  bool _disposed = false;
  ProcState _state = ProcState.stopped;
  final List<String> _outputLines = [];
  Uri? _webuiUrl;

  /// True while a toggle is awaiting confirmation from [ProcessManager].
  /// The UI shows a spinner instead of the action button.
  bool _transitioning = false;

  StreamSubscription<ProcState>? _stateSub;
  StreamSubscription<String>? _outputSub;
  StreamSubscription<Uri>? _webuiSub;

  ProcessViewModel({
    required this.name,
    required ProcessManager processManager,
    required int outputHistoryLimit,
  }) : _processManager = processManager,
       _outputHistoryLimit = outputHistoryLimit {
    _state = processManager.getState(name);

    _stateSub = processManager.stateStream(name).listen(_onState);
    _outputSub = processManager.outputStream(name).listen(_onOutput);
    _webuiSub = processManager.webUiStream(name).listen(_onWebUi);
  }

  /// Current process state, mirrored from [ProcessManager].
  ProcState get state => _state;

  /// Accumulated output lines, bounded by [_outputHistoryLimit].
  List<String> get outputLines => List.unmodifiable(_outputLines);

  /// Detected WebUI URL, if any.
  Uri? get webuiUrl => _webuiUrl;

  /// Whether the toggle is awaiting confirmation (spinner state).
  bool get isTransitioning => _transitioning;

  /// Toggles the process via [ProcessManager].
  ///
  /// The start/stop decision lives in `ProcessController.toggle` — this
  /// viewmodel only shows a spinner while the manager works and ignores
  /// re-entry. The real state is restored when the manager's state stream
  /// emits the next transition.
  void toggle() {
    if (isTransitioning) return;
    _transitioning = true;
    notifyListeners();
    _processManager.toggle(name);
  }

  void _onState(ProcState state) {
    _state = state;
    // Only clear the transitioning flag when the transition is complete —
    // i.e. on terminal states (running, stopped, crashed, cooldown), not
    // on intermediate states (starting, stopping). This ensures the spinner
    // stays visible until the ProcessManager confirms success or failure.
    if (state.isTerminal) {
      _transitioning = false;
    }
    // Clear WebUI URL when process is no longer running.
    if (state != ProcState.running) {
      _webuiUrl = null;
    }
    notifyListeners();
  }

  /// Clears all accumulated output lines and the underlying
  /// [ProcessManager] output buffer.
  void clearOutput() {
    _outputLines.clear();
    _processManager.clearOutput(name);
    notifyListeners();
  }

  void _onOutput(String line) {
    _outputLines.add(line);
    while (_outputLines.length > _outputHistoryLimit) {
      _outputLines.removeAt(0);
    }
    notifyListeners();
  }

  void _onWebUi(Uri url) {
    _webuiUrl = url;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) return;
    super.removeListener(listener);
  }

  @override
  void dispose() {
    _disposed = true;
    _stateSub?.cancel();
    _outputSub?.cancel();
    _webuiSub?.cancel();
    super.dispose();
  }
}
