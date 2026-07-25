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
