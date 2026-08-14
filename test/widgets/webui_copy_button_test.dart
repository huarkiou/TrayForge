import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/widgets/webui_copy_button.dart';

void main() {
  Widget buildButton({bool compact = false}) {
    return MaterialApp(
      home: Scaffold(
        body: WebUiCopyButton(
          url: Uri.parse('http://127.0.0.1:8080'),
          compact: compact,
        ),
      ),
    );
  }

  group('WebUiCopyButton', () {
    testWidgets('left-click copies URL to clipboard', (tester) async {
      await tester.pumpWidget(buildButton());

      // Intercept clipboard writes.
      String? clipboardContent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardContent =
                (call.arguments as Map<String, dynamic>)['text'] as String;
          }
          return null;
        },
      );

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(clipboardContent, 'http://127.0.0.1:8080');
    });

    testWidgets('right-click opens URL in browser instead of copying', (
      tester,
    ) async {
      await tester.pumpWidget(buildButton());

      // Intercept url_launcher calls (plugins are not registered in tests,
      // so launchUrl goes through the default method channel).
      String? launchedUrl;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        (call) async {
          if (call.method == 'launch') {
            launchedUrl = (call.arguments as Map)['url'] as String?;
            return true;
          }
          return null;
        },
      );

      await tester.tap(find.byType(IconButton), buttons: kSecondaryMouseButton);
      await tester.pump();

      expect(launchedUrl, 'http://127.0.0.1:8080');
    });

    testWidgets('compact uses smaller icon and dense hit target', (
      tester,
    ) async {
      await tester.pumpWidget(buildButton(compact: true));

      final icon = tester.widget<Icon>(find.byIcon(Icons.content_copy));
      expect(icon.size, 20);

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.visualDensity, VisualDensity.compact);
    });
  });
}
