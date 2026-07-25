import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/viewmodels/process_viewmodel.dart';

/// A Material [Card] widget that displays a single process.
///
/// Shows the process name, a coloured status dot, last ~15 lines of output,
/// a start/stop toggle button, and an optional WebUI copy-to-clipboard button.
class ProcessCard extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback onTap;

  /// Number of output lines to display in the card body.
  static const int previewLines = 15;

  const ProcessCard({
    super.key,
    required this.viewModel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    viewModel: viewModel,
                    scaffoldMessenger: ScaffoldMessenger.of(context),
                  ),
                  const SizedBox(height: 8),
                  _OutputPreview(viewModel: viewModel),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Header row: status dot, name, WebUI button, toggle button.
class _Header extends StatelessWidget {
  final ProcessViewModel viewModel;
  final ScaffoldMessengerState scaffoldMessenger;

  const _Header({
    required this.viewModel,
    required this.scaffoldMessenger,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatusDot(state: viewModel.state),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            viewModel.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (viewModel.webuiUrl != null)
          IconButton(
            icon: const Icon(Icons.open_in_browser, size: 20),
            tooltip: 'Copy URL to clipboard',
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: viewModel.webuiUrl.toString()),
              );
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text('URL copied'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            visualDensity: VisualDensity.compact,
          ),
        const SizedBox(width: 4),
        _ToggleButton(viewModel: viewModel),
      ],
    );
  }
}

/// Start/stop toggle with spinner during transitions.
class _ToggleButton extends StatelessWidget {
  final ProcessViewModel viewModel;

  const _ToggleButton({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.isTransitioning) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final isRunning = viewModel.state == ProcState.running;
    return IconButton(
      icon: Icon(
        isRunning ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
        color: isRunning ? Colors.red : Colors.green,
      ),
      tooltip: isRunning ? 'Stop' : 'Start',
      onPressed: () => viewModel.toggle(),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Monospace output preview showing the last [ProcessCard.previewLines] lines.
class _OutputPreview extends StatelessWidget {
  final ProcessViewModel viewModel;

  const _OutputPreview({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final lines = viewModel.outputLines;
    if (lines.isEmpty) {
      return const Text(
        'No output yet',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Colors.grey,
        ),
      );
    }

    final preview = lines.length > ProcessCard.previewLines
        ? lines.sublist(lines.length - ProcessCard.previewLines)
        : lines;

    return Text(
      preview.join('\n'),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        height: 1.3,
      ),
      maxLines: ProcessCard.previewLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A small coloured circle indicating process status.
///
/// Green = running, red = crashed, grey = stopped/starting/stopping/cooldown.
class _StatusDot extends StatelessWidget {
  final ProcState state;

  const _StatusDot({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color,
      ),
    );
  }

  Color get _color {
    switch (state) {
      case ProcState.running:
        return Colors.green;
      case ProcState.crashed:
        return Colors.red;
      case ProcState.stopped:
      case ProcState.starting:
      case ProcState.stopping:
      case ProcState.cooldown:
        return Colors.grey;
    }
  }
}
