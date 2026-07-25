import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';
import 'package:trayforge/widgets/copy_snackbar.dart';
import 'package:trayforge/widgets/status_dot.dart';
import 'package:trayforge/widgets/toggle_button.dart';

/// A Material [Card] widget that displays a single process.
///
/// Shows the process name, a coloured status dot, last ~15 lines of output,
/// a start/stop toggle button, and an optional WebUI copy-to-clipboard button.
class ProcessCard extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback onTap;
  final VoidCallback? onEditTap;
  final int? dragHandleIndex;

  /// Number of output lines to display in the card body.
  static const int previewLines = 15;

  const ProcessCard({
    super.key,
    required this.viewModel,
    required this.onTap,
    this.onEditTap,
    this.dragHandleIndex,
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
                    onEditTap: onEditTap,
                    dragHandleIndex: dragHandleIndex,
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

/// Header row: status dot, name, WebUI button, toggle button, edit button.
class _Header extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback? onEditTap;
  final int? dragHandleIndex;

  const _Header({
    required this.viewModel,
    this.onEditTap,
    this.dragHandleIndex,
  });

  @override
  Widget build(BuildContext context) {
    final dragHandle = dragHandleIndex != null
        ? ReorderableDragStartListener(
            index: dragHandleIndex!,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle, color: Colors.grey),
            ),
          )
        : null;

    final editButton = onEditTap != null
        ? IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: 'Edit process',
            onPressed: onEditTap,
            visualDensity: VisualDensity.compact,
          )
        : null;

    return Row(
      children: [
        if (dragHandle != null) dragHandle,
        StatusDot(state: viewModel.state),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            viewModel.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (viewModel.webuiUrl != null)
          IconButton(
            icon: const Icon(Icons.content_copy, size: 20),
            tooltip: 'Copy URL to clipboard',
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: viewModel.webuiUrl.toString()),
              );
              showCopySnackBar(context);
            },
            visualDensity: VisualDensity.compact,
          ),
        const SizedBox(width: 4),
        ToggleButton(
          viewModel: viewModel,
          visualDensity: VisualDensity.compact,
        ),
        if (editButton != null) editButton,
      ],
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
