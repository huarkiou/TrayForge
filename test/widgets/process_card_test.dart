import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/services/process_manager.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';
import 'package:trayforge/widgets/process_card.dart';

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
    // Simulate real async: first microtask emits starting, then later running.
    await Future<void>.delayed(Duration.zero);
    setState(name, ProcState.starting);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    setState(name, ProcState.running);
  }

  @override
  Future<void> stop(String name) async {
    await Future<void>.delayed(Duration.zero);
    setState(name, ProcState.stopping);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    setState(name, ProcState.stopped);
  }
}

/// A fake ProcessManager whose start/stop never resolve, so the
/// optimistic state is preserved for spinner testing.
class _NoResolveFakeManager extends Fake implements ProcessManager {
  final Map<String, StreamController<ProcState>> _stateControllers = {};
  final Map<String, StreamController<String>> _outputControllers = {};
  final StreamController<WebUiEvent> _webuiController =
      StreamController<WebUiEvent>.broadcast(sync: true);

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
  Stream<WebUiEvent> get onWebUiDetected => _webuiController.stream;

  @override
  ProcState getState(String name) => ProcState.stopped;

  @override
  Future<void> start(String name) async {
    // Never resolves — keeps the optimistic state alive.
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
  group('ProcessCard', () {
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

    Widget buildCard({VoidCallback? onTap}) {
      return MaterialApp(
        home: Scaffold(
          body: ProcessCard(viewModel: vm, onTap: onTap ?? () {}),
        ),
      );
    }

    // ---- Rendering ----

    testWidgets('renders process name', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('test-svc'), findsOneWidget);
    });

    testWidgets('renders "No output yet" when no output', (tester) async {
      await tester.pumpWidget(buildCard());
      expect(find.text('No output yet'), findsOneWidget);
    });

    testWidgets('renders output lines in monospace', (tester) async {
      fakeManager.emitOutput('test-svc', 'hello world');
      await tester.pumpWidget(buildCard());
      // Wait for the ListenableBuilder to rebuild.
      await tester.pump();

      final text = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && w.data != null && w.data!.contains('hello world'),
        ),
      );
      expect(text.style?.fontFamily, 'monospace');
    });

    testWidgets('renders last N lines of output', (tester) async {
      for (var i = 0; i < 20; i++) {
        fakeManager.emitOutput('test-svc', 'line $i');
      }
      await tester.pumpWidget(buildCard());
      await tester.pump();

      // Should show last 15 lines.
      final text = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && w.data != null && w.data!.startsWith('line '),
        ),
      );
      expect(text.data, contains('line 5'));
      expect(text.data, contains('line 19'));
    });

    // ---- Status dot ----

    testWidgets('shows green dot for running', (tester) async {
      fakeManager.setState('test-svc', ProcState.running);
      await tester.pumpWidget(buildCard());
      await tester.pump();

      final dot = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == Colors.green,
        ),
      );
      expect(dot, isNotNull);
    });

    testWidgets('shows red dot for crashed', (tester) async {
      fakeManager.setState('test-svc', ProcState.crashed);
      await tester.pumpWidget(buildCard());
      await tester.pump();

      final dot = tester.widget<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == Colors.red,
        ),
      );
      expect(dot, isNotNull);
    });

    testWidgets('shows grey dot for stopped/starting/stopping/cooldown', (
      tester,
    ) async {
      for (final state in [
        ProcState.stopped,
        ProcState.starting,
        ProcState.stopping,
        ProcState.cooldown,
      ]) {
        fakeManager.setState('test-svc', state);
        await tester.pumpWidget(buildCard());
        await tester.pump();

        final dot = tester.widget<Container>(
          find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color == Colors.grey,
          ),
        );
        expect(dot, isNotNull, reason: 'Expected grey dot for $state');
      }
    });

    // ---- Toggle button ----

    testWidgets('shows play button when stopped', (tester) async {
      fakeManager.setState('test-svc', ProcState.stopped);
      await tester.pumpWidget(buildCard());
      await tester.pump();

      expect(find.byIcon(Icons.play_circle_outlined), findsOneWidget);
    });

    testWidgets('shows stop button when running', (tester) async {
      fakeManager.setState('test-svc', ProcState.running);
      await tester.pumpWidget(buildCard());
      await tester.pump();

      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    });

    testWidgets('shows spinner when transitioning', (tester) async {
      // Create a fake manager whose start() never resolves so the
      // optimistic state stays indefinitely.
      final noResolveFake = _NoResolveFakeManager();
      final vm2 = ProcessViewModel(
        name: 'test-svc',
        processManager: noResolveFake,
        outputHistoryLimit: 100,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessCard(viewModel: vm2, onTap: () {}),
          ),
        ),
      );

      // Tap toggle to enter optimistic state. Since the fake never
      // emits a state change, the spinner should appear.
      vm2.toggle();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    // ---- WebUI button ----

    testWidgets('shows WebUI button when URL is detected', (tester) async {
      fakeManager.emitWebUi(
        WebUiEvent('test-svc', Uri.parse('http://127.0.0.1:8080')),
      );
      await tester.pumpWidget(buildCard());
      await tester.pump();

      expect(find.byIcon(Icons.content_copy), findsOneWidget);
    });

    testWidgets('hides WebUI button when no URL', (tester) async {
      await tester.pumpWidget(buildCard());
      await tester.pump();

      expect(find.byIcon(Icons.content_copy), findsNothing);
    });

    // ---- Tap navigation ----

    testWidgets('calls onTap when card is tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(buildCard(onTap: () => tapped = true));

      await tester.tap(find.byType(InkWell).first);
      expect(tapped, true);
    });

    // ---- Edit icon ----

    testWidgets('hides edit icon when onEditTap is null', (tester) async {
      await tester.pumpWidget(buildCard());
      await tester.pump();

      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('shows edit icon when onEditTap is non-null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessCard(viewModel: vm, onTap: () {}, onEditTap: () {}),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('tapping edit icon calls onEditTap', (tester) async {
      var editTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessCard(
              viewModel: vm,
              onTap: () {},
              onEditTap: () => editTapped = true,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit));
      expect(editTapped, true);
    });

    // ---- Drag handle ----

    testWidgets('hides drag handle when dragHandleIndex is null', (
      tester,
    ) async {
      await tester.pumpWidget(buildCard());
      await tester.pump();

      expect(find.byIcon(Icons.drag_handle), findsNothing);
    });

    testWidgets('shows drag handle when dragHandleIndex is non-null', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProcessCard(
              viewModel: vm,
              onTap: () {},
              dragHandleIndex: 0,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.drag_handle), findsOneWidget);
    });
  });
}
