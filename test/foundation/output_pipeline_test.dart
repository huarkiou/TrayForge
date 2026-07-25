import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/output_pipeline.dart';

void main() {
  group('OutputPipeline.stripAnsi', () {
    test('removes CSI color codes', () {
      const input = '\x1B[31mRed text\x1B[0m';
      expect(OutputPipeline.stripAnsi(input), 'Red text');
    });

    test('removes complex ANSI sequences', () {
      const input = '\x1B[1;32mBold green\x1B[0m normal';
      expect(OutputPipeline.stripAnsi(input), 'Bold green normal');
    });

    test('returns plain text unchanged', () {
      expect(OutputPipeline.stripAnsi('hello'), 'hello');
    });

    test('handles empty string', () {
      expect(OutputPipeline.stripAnsi(''), '');
    });

    test('removes cursor movement sequences', () {
      const input = 'text\x1B[2Kmore';
      expect(OutputPipeline.stripAnsi(input), 'textmore');
    });

    test('removes multiple ANSI sequences', () {
      const input = '\x1B[31mRed\x1B[0m \x1B[1mBold\x1B[0m';
      expect(OutputPipeline.stripAnsi(input), 'Red Bold');
    });
  });

  group('OutputPipeline.tryDetectWebUi', () {
    test('returns URL from first capture group', () {
      final result = OutputPipeline.tryDetectWebUi(
        'WebUI started at http://127.0.0.1:8080',
        r'started at (http://[\d.:]+)',
      );
      expect(result, isNotNull);
      expect(result.toString(), 'http://127.0.0.1:8080');
    });

    test('returns null when pattern does not match', () {
      final result = OutputPipeline.tryDetectWebUi(
        'WebUI started',
        r'listening on (http://[\d.:]+)',
      );
      expect(result, isNull);
    });

    test('returns null when pattern has no capture group', () {
      final result = OutputPipeline.tryDetectWebUi(
        'listening on http://localhost',
        r'http://[\d.:]+',
      );
      expect(result, isNull);
    });

    test('returns null when captured text is empty', () {
      final result = OutputPipeline.tryDetectWebUi(
        'started at ',
        r'started at ()',
      );
      expect(result, isNull);
    });

    test('returns a Uri for whatever the pattern captures', () {
      final result = OutputPipeline.tryDetectWebUi(
        'started at not-a-valid-url',
        r'started at (.+)',
      );
      // Dart's Uri.tryParse is permissive — most strings parse as valid.
      expect(result, isNotNull);
      expect(result.toString(), 'not-a-valid-url');
    });

    test('returns the first match only', () {
      final result = OutputPipeline.tryDetectWebUi(
        'started at http://a.com and also http://b.com',
        r'at (http://[\w.]+)',
      );
      expect(result.toString(), 'http://a.com');
    });
  });
}
