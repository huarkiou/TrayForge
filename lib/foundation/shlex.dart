/// Windows command-line string splitter.
///
/// Splits a command string into an argument list, respecting
/// Windows-style quoting:
/// - Double quotes `"` delimit arguments
/// - `""` inside quotes produces a literal `"`
/// - Single quotes and backslashes are treated as literal characters
class Shlex {
  /// Splits [cmd] into an argument list using Windows quoting rules.
  ///
  /// Treats double quotes as argument delimiters and `""` as an
  /// escaped double-quote character. All other characters (including
  /// single quotes and backslashes) are literal.
  static List<String> split(String cmd) {
    final args = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    var hadQuotes = false;

    for (var i = 0; i < cmd.length; i++) {
      final ch = cmd[i];

      if (ch == '"') {
        if (inQuotes && i + 1 < cmd.length && cmd[i + 1] == '"') {
          // Escaped double quote inside quotes: "" → "
          buf.write('"');
          i++; // skip next quote
        } else {
          inQuotes = !inQuotes;
          hadQuotes = true;
          // Flush on closing quote
          if (!inQuotes) {
            args.add(buf.toString());
            buf.clear();
            hadQuotes = false;
          }
        }
      } else if (ch == ' ' || ch == '\t') {
        if (inQuotes) {
          buf.write(ch);
        } else {
          if (hadQuotes || buf.isNotEmpty) {
            args.add(buf.toString());
            buf.clear();
            hadQuotes = false;
          }
        }
      } else {
        buf.write(ch);
      }
    }

    if (hadQuotes || buf.isNotEmpty) {
      args.add(buf.toString());
    }

    return args;
  }
}
