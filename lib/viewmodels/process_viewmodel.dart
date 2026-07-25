// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/process_manager.dart';

/// ViewModel for a single managed process.
///
/// Mirrors [ProcState] from [ProcessManager], accumulates output lines
/// bounded by [outputHistoryLimit], tracks WebUI URL detection, and
/// exposes an optimistic toggle for immediate button feedback.
class ProcessViewModel extends ChangeNotifier {
  final String name;
  final ProcessManager _processManager;
  final int _outputHistoryLimit;

  ProcState _state = ProcState.stopped;
  final List<String> _outputLines = [];
  Uri? _webuiUrl;

  /// When non-null, the toggle button is awaiting confirmation from
  /// [ProcessManager]. The UI shows a spinner instead of the action button.
  ProcState? _optimisticState;

  StreamSubscription<ProcState>? _stateSub;
  StreamSubscription<String>? _outputSub;
  StreamSubscription<WebUiEvent>? _webuiSub;

  ProcessViewModel({
    required this.name,
    required ProcessManager processManager,
    required int outputHistoryLimit,
  }) : _processManager = processManager,
       _outputHistoryLimit = outputHistoryLimit {
    _state = processManager.getState(name);

    _stateSub = processManager.stateStream(name).listen(_onState);
    _outputSub = processManager.outputStream(name).listen(_onOutput);
    _webuiSub = processManager.onWebUiDetected.listen(_onWebUi);
  }

  /// Current process state, or the optimistic state if a toggle is in flight.
  ProcState get state => _optimisticState ?? _state;

  /// Accumulated output lines, bounded by [_outputHistoryLimit].
  List<String> get outputLines => List.unmodifiable(_outputLines);

  /// Detected WebUI URL, if any.
  Uri? get webuiUrl => _webuiUrl;

  /// Whether the toggle is awaiting confirmation (spinner state).
  bool get isTransitioning => _optimisticState != null;

  /// Toggles the process: starts if stopped/crashed/cooldown, stops if running.
  ///
  /// Immediately sets an optimistic state so the UI shows a spinner, then
  /// delegates to [ProcessManager]. The real state is restored when the
  /// manager's state stream emits the next transition.
  void toggle() {
    if (isTransitioning) return;

    if (_state == ProcState.running) {
      _optimisticState = ProcState.stopping;
      notifyListeners();
      _processManager.stop(name);
    } else if (_state.isTerminal) {
      _optimisticState = ProcState.starting;
      notifyListeners();
      _processManager.start(name);
    }
  }

  void _onState(ProcState state) {
    _state = state;
    // Only clear the optimistic state when the transition is complete —
    // i.e. on terminal states (running, stopped, crashed, cooldown), not
    // on intermediate states (starting, stopping). This ensures the spinner
    // stays visible until the ProcessManager confirms success or failure.
    if (state.isTerminal) {
      _optimisticState = null;
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

  void _onWebUi(WebUiEvent event) {
    if (event.processName == name) {
      _webuiUrl = event.url;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _outputSub?.cancel();
    _webuiSub?.cancel();
    super.dispose();
  }
}
