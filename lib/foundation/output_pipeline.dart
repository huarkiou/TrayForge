import 'dart:async';

/// Utilities for processing process output lines.
class OutputPipeline {
  /// Regex pattern for ANSI escape sequences (CSI sequences).
  static final RegExp _ansiPattern = RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]');

  /// Strips ANSI escape codes from [line].
  static String stripAnsi(String line) {
    return line.replaceAll(_ansiPattern, '');
  }

  /// Tries to detect a Web UI URL in [line] using the given regex [pattern].
  ///
  /// Returns the first capture group as a [Uri], or `null` if the pattern
  /// doesn't match or the captured text is not a valid URL.
  static Uri? tryDetectWebUi(String line, String pattern) {
    final match = RegExp(pattern).firstMatch(line);
    if (match == null || match.groupCount < 1) return null;
    final captured = match.group(1);
    if (captured == null || captured.isEmpty) return null;
    return Uri.tryParse(captured);
  }
}

/// Stateful output pipeline that owns the full processing chain:
///
/// ```
/// raw line → strip ANSI → detect WebUI → buffer (history limit) → flush timer → clean stream
/// ```
///
/// Each pipeline belongs to a single process. [configure] sets the
/// pipeline parameters; [addLine] feeds raw output lines; [output]
/// delivers cleaned, timed-flushed lines; [onWebUiDetected] fires
/// per-pipeline WebUI detections.
class BufferedOutputPipeline {
  final StreamController<String> _outputController =
      StreamController<String>.broadcast(sync: true);
  final StreamController<Uri> _webuiController =
      StreamController<Uri>.broadcast(sync: true);

  String? _webuiPattern;
  int _historyLimit = 1000;
  int _refreshMs = 500;
  final List<String> _buffer = [];
  Timer? _flushTimer;

  /// Cleaned, timed-flushed output lines.
  Stream<String> get output => _outputController.stream;

  /// Fires when a WebUI URL is detected in a line fed to [addLine].
  Stream<Uri> get onWebUiDetected => _webuiController.stream;

  /// Update pipeline settings.
  ///
  /// Call before [addLine]. [historyLimit] caps the buffer size;
  /// [refreshMs] controls flush frequency; [webuiPattern] enables
  /// WebUI detection (disabled when `null`).
  void configure({int? historyLimit, int? refreshMs, String? webuiPattern}) {
    if (historyLimit != null) _historyLimit = historyLimit;
    if (refreshMs != null) _refreshMs = refreshMs;
    _webuiPattern = webuiPattern;
  }

  /// Feed a raw output line through the pipeline.
  ///
  /// Strips ANSI escapes, checks for WebUI URLs, and buffers the
  /// cleaned line (respecting the history limit). Lines are not
  /// emitted until [flushNow] or the periodic flush timer fires.
  void addLine(String rawLine) {
    final cleaned = OutputPipeline.stripAnsi(rawLine);

    if (_webuiPattern != null) {
      final url = OutputPipeline.tryDetectWebUi(cleaned, _webuiPattern!);
      if (url != null) {
        _webuiController.add(url);
      }
    }

    _buffer.add(cleaned);
    while (_buffer.length > _historyLimit) {
      _buffer.removeAt(0);
    }
  }

  /// Push a system message directly to [output], bypassing the buffer
  /// and flush timer.
  void push(String systemMessage) {
    _outputController.add(systemMessage);
  }

  /// Start the periodic flush timer.
  ///
  /// Every [refreshMs] milliseconds the buffer is drained to [output].
  /// Safe to call multiple times — the previous timer is cancelled first.
  void startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(Duration(milliseconds: _refreshMs), (_) {
      flushNow();
    });
  }

  /// Stop the periodic flush timer without draining the buffer.
  void stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Drain buffered lines to [output] immediately.
  void flushNow() {
    if (_buffer.isEmpty) return;
    for (final line in _buffer) {
      _outputController.add(line);
    }
    _buffer.clear();
  }

  /// Discard all buffered (un-flushed) lines.
  void clear() {
    _buffer.clear();
  }

  /// Release all resources: stops timer, closes streams.
  void dispose() {
    stopFlushTimer();
    _outputController.close();
    _webuiController.close();
  }
}
