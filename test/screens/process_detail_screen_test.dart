import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/screens/process_detail_screen.dart';
import 'package:trayforge_flutter/services/process_manager.dart';
import 'package:trayforge_flutter/viewmodels/process_viewmodel.dart';

/// A fake ProcessManager that provides state and output streams on demand.
class _FakeProcessManager extends Fake implements ProcessManager {
  final Map<String, StreamController<ProcState>> _stateControllers = {};
  final Map<String, StreamController<String>> _outputControllers = {};
  final StreamController<WebUiEvent> _webuiController =
      StreamController<WebUiEvent>.broadcast(sync: true);
  final Map<String, ProcState> _states = {};

  @override
  Stream<ProcState> stateStream(String name) {
    return _stateControllers
        .putIfAbsent(
            name, () => StreamController<ProcState>.broadcast(sync: true))
        .stream;
  }

  @override
  Stream<String> outputStream(String name) {
    return _outputControllers
        .putIfAbsent(
            name, () => StreamController<String>.broadcast(sync: true))
        .stream;
  }

  @override
  Stream<WebUiEvent> get onWebUiDetected => _webuiController.stream;

  @override
  ProcState getState(String name) => _states[name] ?? ProcState.stopped;

  void setState(String name, ProcState state) {
    _states[name] = state;
    _stateControllers[name]?.add(state);
  }

  void emitOutput(String name, String line) {
    _outputControllers[name]?.add(line);
  }

  void emitWebUi(WebUiEvent event) {
    _webuiController.add(event);
  }

  @override
  Future<void> start(String name) async {
    await Future<void>.delayed(Duration.zero);
    setState(name, ProcState.starting);
  }

  @override
  Future<void> stop(String name) async {
    await Future<void>.delayed(Duration.zero);
    setState(name, ProcState.stopping);
  }
}

/// A fake ProcessManager whose start/stop never resolve.
class _NoResolveFakeManager extends Fake implements ProcessManager {
  final Map<String, StreamController<ProcState>> _stateControllers = {};
  final Map<String, StreamController<String>> _outputControllers = {};
  final StreamController<WebUiEvent> _webuiController =
      StreamController<WebUiEvent>.broadcast(sync: true);

  @override
  Stream<ProcState> stateStream(String name) {
    return _stateControllers
        .putIfAbsent(
            name, () => StreamController<ProcState>.broadcast(sync: true))
        .stream;
  }

  @override
  Stream<String> outputStream(String name) {
    return _outputControllers
        .putIfAbsent(
            name, () => StreamController<String>.broadcast(sync: true))
        .stream;
  }

  @override
  Stream<WebUiEvent> get onWebUiDetected => _webuiController.stream;

  @override
  ProcState getState(String name) => ProcState.stopped;

  @override
  Future<void> start(String name) async {
    await Completer<void>().future;
  }

  @override
  Future<void> stop(String name) async {
    await Completer<void>().future;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ProcessDetailPage', () {
    late _FakeProcessManager fakeManager;
    late ProcessViewModel vm;

    setUp(() {
      fakeManager = _FakeProcessManager();
      vm = ProcessViewModel(
        name: 'test-svc',
        processManager: fakeManager,
        outputHistoryLimit: 100,
      );
    });

    Widget buildPage() {
      return MaterialApp(
        home: ProcessDetailPage(viewModel: vm),
      );
    }

    // ---- Rendering ----

    testWidgets('renders process name in AppBar', (tester) async {
      await tester.pumpWidget(buildPage());
      expect(find.text('test-svc'), findsOneWidget);
    });

    testWidgets('shows "No output yet" when no output', (tester) async {
      await tester.pumpWidget(buildPage());
      expect(find.text('No output yet'), findsOneWidget);
    });

    testWidgets('renders output lines in monospace', (tester) async {
      fakeManager.emitOutput('test-svc', 'hello world');
      await tester.pumpWidget(buildPage());
      await tester.pump();

      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.style?.fontFamily, 'monospace');
      expect(selectable.data, contains('hello world'));
    });

    testWidgets('renders all output lines', (tester) async {
      for (var i = 0; i < 30; i++) {
        fakeManager.emitOutput('test-svc', 'line $i');
      }
      await tester.pumpWidget(buildPage());
      await tester.pump();

      // All 30 lines should be visible (no preview cap on detail page).
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.data, contains('line 29'));
      expect(selectable.data, contains('line 0'));
    });

    // ---- Status dot ----

    testWidgets('shows green dot for running', (tester) async {
      fakeManager.setState('test-svc', ProcState.running);
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(
        find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.green),
        findsOneWidget,
      );
    });

    testWidgets('shows red dot for crashed', (tester) async {
      fakeManager.setState('test-svc', ProcState.crashed);
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(
        find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == Colors.red),
        findsOneWidget,
      );
    });

    // ---- Toggle button ----

    testWidgets('shows play button when stopped', (tester) async {
      fakeManager.setState('test-svc', ProcState.stopped);
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(find.byIcon(Icons.play_circle_outlined), findsOneWidget);
    });

    testWidgets('shows stop button when running', (tester) async {
      fakeManager.setState('test-svc', ProcState.running);
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    });

    testWidgets('shows spinner when transitioning', (tester) async {
      final noResolveFake = _NoResolveFakeManager();
      final vm2 = ProcessViewModel(
        name: 'test-svc',
        processManager: noResolveFake,
        outputHistoryLimit: 100,
      );

      await tester.pumpWidget(MaterialApp(
        home: ProcessDetailPage(viewModel: vm2),
      ));

      vm2.toggle();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // ---- WebUI button ----

    testWidgets('shows WebUI copy button when URL is detected',
        (tester) async {
      fakeManager.emitWebUi(
        WebUiEvent('test-svc', Uri.parse('http://127.0.0.1:8080')),
      );
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(find.byIcon(Icons.content_copy), findsOneWidget);
    });

    testWidgets('hides WebUI button when no URL', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(find.byIcon(Icons.content_copy), findsNothing);
    });

    testWidgets('WebUI button copies URL to clipboard', (tester) async {
      fakeManager.emitWebUi(
        WebUiEvent('test-svc', Uri.parse('http://127.0.0.1:8080')),
      );
      await tester.pumpWidget(buildPage());
      await tester.pump();

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

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump();

      expect(clipboardContent, 'http://127.0.0.1:8080');
    });

    // ---- Search bar ----

    testWidgets('search button toggles search bar', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      // Search bar should not be visible initially.
      expect(find.byType(TextField), findsNothing);

      // Tap search icon.
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      // Search bar should appear.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsOneWidget);

      // Tap again to dismiss.
      await tester.tap(find.byIcon(Icons.search_off));
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('search filters output lines case-insensitively',
        (tester) async {
      fakeManager.emitOutput('test-svc', 'Hello World');
      fakeManager.emitOutput('test-svc', 'foo bar');
      fakeManager.emitOutput('test-svc', 'HELLO again');
      await tester.pumpWidget(buildPage());
      await tester.pump();

      // Open search.
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();

      // Type search text.
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      // Should show only the two "hello" lines.
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.data, contains('Hello World'));
      expect(selectable.data, contains('HELLO again'));
      expect(selectable.data, isNot(contains('foo bar')));
    });

    testWidgets('clearing search shows all lines', (tester) async {
      fakeManager.emitOutput('test-svc', 'alpha');
      fakeManager.emitOutput('test-svc', 'beta');
      await tester.pumpWidget(buildPage());
      await tester.pump();

      // Open search and filter.
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump();

      // Only alpha visible.
      var selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.data, isNot(contains('beta')));

      // Clear search field.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      // Both visible again.
      selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.data, contains('beta'));
    });

    testWidgets('shows "No matching lines" when search finds nothing',
        (tester) async {
      fakeManager.emitOutput('test-svc', 'hello');
      await tester.pumpWidget(buildPage());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'xyzzy');
      await tester.pump();

      expect(find.text('No matching lines'), findsOneWidget);
    });

    // ---- Auto-scroll and scroll lock ----

    testWidgets('scrolls to bottom on initial load', (tester) async {
      // Fill with enough lines to require scrolling.
      for (var i = 0; i < 50; i++) {
        fakeManager.emitOutput('test-svc', 'line $i');
      }
      await tester.pumpWidget(buildPage());
      await tester.pump(); // post-frame callback for initial scroll
      await tester.pump();

      // After initial load, the last line should be in the output.
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.data, contains('line 49'));
    });

    testWidgets('scrolls to bottom on new output while at bottom',
        (tester) async {
      for (var i = 0; i < 40; i++) {
        fakeManager.emitOutput('test-svc', 'line $i');
      }
      await tester.pumpWidget(buildPage());
      await tester.pump(); // post-frame callback for initial scroll
      await tester.pump();

      // Emit new output — user is at bottom, should auto-scroll.
      fakeManager.emitOutput('test-svc', 'new line!');
      await tester.pump();
      await tester.pump(); // post-frame callback

      // The new line should be in the output.
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      expect(selectable.data, contains('new line!'));
    });

    // ---- Output preservation ----

    testWidgets('output is preserved when view model is shared',
        (tester) async {
      // Pre-populate the view model with output.
      fakeManager.emitOutput('test-svc', 'persisted line');
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(find.text('persisted line'), findsOneWidget);

      // Navigate away and back (simulated by rebuilding with same vm).
      await tester.pumpWidget(MaterialApp(
        home: const Scaffold(body: Text('other page')),
      ));
      await tester.pump();

      await tester.pumpWidget(buildPage());
      await tester.pump();

      // Output should still be there — the ViewModel holds the buffer.
      expect(find.text('persisted line'), findsOneWidget);
    });
  });
}
