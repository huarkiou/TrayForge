import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/process_detail_screen.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';

/// A fake ProcessManager that provides state and output streams on demand.
class _FakeProcessManager extends Fake implements ProcessManager {
  final Map<String, StreamController<ProcState>> _stateControllers = {};
  final Map<String, StreamController<String>> _outputControllers = {};
  final Map<String, StreamController<Uri>> _webuiControllers = {};
  final Map<String, ProcState> _states = {};

  @override
  Stream<ProcState> stateStream(String name) {
    return _stateControllers
        .putIfAbsent(
          name,
          () => StreamController<ProcState>.broadcast(sync: true),
        )
        .stream;
  }

  @override
  Stream<String> outputStream(String name) {
    return _outputControllers
        .putIfAbsent(name, () => StreamController<String>.broadcast(sync: true))
        .stream;
  }

  @override
  Stream<Uri> webUiStream(String name) {
    return _webuiControllers
        .putIfAbsent(name, () => StreamController<Uri>.broadcast(sync: true))
        .stream;
  }

  @override
  ProcState getState(String name) => _states[name] ?? ProcState.stopped;

  void setState(String name, ProcState state) {
    _states[name] = state;
    _stateControllers[name]?.add(state);
  }

  void emitOutput(String name, String line) {
    _outputControllers[name]?.add(line);
  }

  void emitWebUi(String name, Uri url) {
    _webuiControllers[name]?.add(url);
  }

  @override
  void clearOutput(String name) {
    // The view model clears its own buffer; nothing to reset here.
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

  @override
  Future<void> toggle(String name) async {
    final state = _states[name] ?? ProcState.stopped;
    if (state.isActive) {
      await stop(name);
    } else {
      await start(name);
    }
  }
}

/// A fake ProcessManager whose start/stop never resolve.
class _NoResolveFakeManager extends Fake implements ProcessManager {
  final Map<String, StreamController<ProcState>> _stateControllers = {};
  final Map<String, StreamController<String>> _outputControllers = {};
  final Map<String, StreamController<Uri>> _webuiControllers = {};

  @override
  Stream<ProcState> stateStream(String name) {
    return _stateControllers
        .putIfAbsent(
          name,
          () => StreamController<ProcState>.broadcast(sync: true),
        )
        .stream;
  }

  @override
  Stream<String> outputStream(String name) {
    return _outputControllers
        .putIfAbsent(name, () => StreamController<String>.broadcast(sync: true))
        .stream;
  }

  @override
  Stream<Uri> webUiStream(String name) {
    return _webuiControllers
        .putIfAbsent(name, () => StreamController<Uri>.broadcast(sync: true))
        .stream;
  }

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

  @override
  Future<void> toggle(String name) async {
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
      return MaterialApp(home: ProcessDetailPage(viewModel: vm));
    }

    // Mirrors _ProcessDetailPageState._followThreshold — the production
    // constant is private and unreachable from tests.
    const followThreshold = 100.0;
    const detachOffset = 300.0;

    // Builds a page with 120 pre-filled output lines (300-line history cap)
    // and scrolls it past the follow threshold. Returns the fake manager and
    // the page's scroll controller.
    Future<(_FakeProcessManager, ScrollController)> pumpDetached(
      WidgetTester tester,
    ) async {
      final fake = _FakeProcessManager();
      final vm = ProcessViewModel(
        name: 'test-svc',
        processManager: fake,
        outputHistoryLimit: 300,
      );
      for (var i = 0; i < 120; i++) {
        fake.emitOutput('test-svc', 'line $i');
      }
      await tester.pumpWidget(
        MaterialApp(home: ProcessDetailPage(viewModel: vm)),
      );
      await tester.pump();

      final controller = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      controller.position.jumpTo(
        controller.position.maxScrollExtent - detachOffset,
      );
      await tester.pump();
      return (fake, controller);
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
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == Colors.green,
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows red dot for crashed', (tester) async {
      fakeManager.setState('test-svc', ProcState.crashed);
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == Colors.red,
        ),
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

      await tester.pumpWidget(
        MaterialApp(home: ProcessDetailPage(viewModel: vm2)),
      );

      vm2.toggle();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // ---- WebUI button ----

    testWidgets('shows WebUI copy button when URL is detected', (tester) async {
      fakeManager.emitWebUi('test-svc', Uri.parse('http://127.0.0.1:8080'));
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
      fakeManager.emitWebUi('test-svc', Uri.parse('http://127.0.0.1:8080'));
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

    testWidgets('search filters output lines case-insensitively', (
      tester,
    ) async {
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
      selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.data, contains('beta'));
    });

    testWidgets('shows "No matching lines" when search finds nothing', (
      tester,
    ) async {
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

    testWidgets('scrolls to bottom on new output while at bottom', (
      tester,
    ) async {
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

    testWidgets('opens at the bottom even without new output', (tester) async {
      // Pre-fill the buffer before the page attaches; no notification will
      // reach the page after it opens (the process is quiet).
      for (var i = 0; i < 50; i++) {
        fakeManager.emitOutput('test-svc', 'line $i');
      }
      await tester.pumpWidget(buildPage());
      await tester.pump();

      final controller = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      expect(controller.position.pixels, controller.position.maxScrollExtent);
    });

    testWidgets('new output does not move the view while detached', (
      tester,
    ) async {
      final (fake, controller) = await pumpDetached(tester);
      final pixelsBefore = controller.position.pixels;
      expect(
        controller.position.maxScrollExtent - controller.position.pixels,
        greaterThan(followThreshold),
      );

      // New output must not change what the user sees.
      fake.emitOutput('test-svc', 'new line!');
      await tester.pump();
      await tester.pump(); // post-frame callback
      expect(controller.position.pixels, pixelsBefore);
    });

    testWidgets('re-engages follow-latest when scrolled back to the bottom', (
      tester,
    ) async {
      final (fake, controller) = await pumpDetached(tester);

      // Scroll back down to the bottom — within the threshold again.
      controller.position.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();

      fake.emitOutput('test-svc', 'new line!');
      await tester.pump();
      await tester.pump(); // post-frame callback
      expect(controller.position.pixels, controller.position.maxScrollExtent);
    });

    testWidgets('clearing output returns to follow-latest', (tester) async {
      final (fake, controller) = await pumpDetached(tester);

      // Clear while detached — the view must return to Follow-latest.
      await tester.tap(find.byIcon(Icons.delete_sweep));
      await tester.pump();
      await tester.pump();

      // Enough output to overflow the viewport: if the reset were missing,
      // the view would sit at the top while the log grows below it, and
      // pixels would stay at 0.
      for (var i = 0; i < 50; i++) {
        fake.emitOutput('test-svc', 'fresh line $i');
      }
      await tester.pump();
      await tester.pump(); // post-frame callback
      expect(controller.position.pixels, greaterThan(0));
      expect(controller.position.pixels, controller.position.maxScrollExtent);
    });

    // ---- Output preservation ----

    testWidgets('output is preserved when view model is shared', (
      tester,
    ) async {
      // Pre-populate the view model with output.
      fakeManager.emitOutput('test-svc', 'persisted line');
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(find.text('persisted line'), findsOneWidget);

      // Navigate away and back (simulated by rebuilding with same vm).
      await tester.pumpWidget(
        MaterialApp(home: const Scaffold(body: Text('other page'))),
      );
      await tester.pump();

      await tester.pumpWidget(buildPage());
      await tester.pump();

      // Output should still be there — the ViewModel holds the buffer.
      expect(find.text('persisted line'), findsOneWidget);
    });

    // ---- Edit icon ----

    testWidgets('hides edit icon when onEditTap is null', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('shows edit icon when onEditTap is provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProcessDetailPage(viewModel: vm, onEditTap: () {}),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('tapping edit icon calls onEditTap', (tester) async {
      var editTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ProcessDetailPage(
            viewModel: vm,
            onEditTap: () => editTapped = true,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit));
      expect(editTapped, true);
    });
  });
}
