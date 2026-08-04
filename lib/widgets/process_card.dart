import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge/foundation/models.dart';
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

  /// Number of output lines to display in the card body.
  static const int previewLines = 15;

  const ProcessCard({
    super.key,
    required this.viewModel,
    required this.onTap,
    this.onEditTap,
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
                  ProcessCardHeader(viewModel: viewModel, onEditTap: onEditTap),
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

/// Header row for the List card: status dot, name, then the shared
/// [ProcessCardActions] (WebUI copy, toggle, edit).
class ProcessCardHeader extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback? onEditTap;

  const ProcessCardHeader({super.key, required this.viewModel, this.onEditTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StatusDot(state: viewModel.state),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            viewModel.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ProcessCardActions(viewModel: viewModel, onEditTap: onEditTap),
      ],
    );
  }
}

/// Action buttons shared by the List card header and the Grid card:
/// WebUI copy (when a URL is known), start/stop toggle, edit.
class ProcessCardActions extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback? onEditTap;

  const ProcessCardActions({
    super.key,
    required this.viewModel,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final editButton = onEditTap != null
        ? IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: 'Edit process',
            onPressed: onEditTap,
            visualDensity: VisualDensity.compact,
          )
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (viewModel.webuiUrl != null) ...[
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
        ],
        ToggleButton(
          viewModel: viewModel,
          visualDensity: VisualDensity.compact,
        ),
        if (editButton != null) ...[const SizedBox(width: 4), editButton],
      ],
    );
  }
}

/// A compact square card for the Dashboard Grid layout.
///
/// Layered to fill the square tile: status dot + label on top, process
/// name (and WebUI URL when present) and the latest two output lines in
/// the middle, action buttons along the bottom.
class ProcessGridCard extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VoidCallback onTap;
  final VoidCallback? onEditTap;

  const ProcessGridCard({
    super.key,
    required this.viewModel,
    required this.onTap,
    this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusDot(state: viewModel.state),
                      const SizedBox(width: 6),
                      Text(
                        viewModel.state.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: statusColor(viewModel.state),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    viewModel.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (viewModel.webuiUrl != null)
                    Text(
                      viewModel.webuiUrl.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  // Latest two output lines; nothing when there is no
                  // output yet (the card must stay compact).
                  _OutputPreview(
                    viewModel: viewModel,
                    maxLines: 2,
                    emptyHint: null,
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ProcessCardActions(
                        viewModel: viewModel,
                        onEditTap: onEditTap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Monospace output preview showing the last [maxLines] lines.
///
/// Shows [emptyHint] when there is no output; pass `null` to render
/// nothing instead (used by the compact grid cards).
class _OutputPreview extends StatelessWidget {
  final ProcessViewModel viewModel;
  final int maxLines;
  final String? emptyHint;

  const _OutputPreview({
    required this.viewModel,
    this.maxLines = ProcessCard.previewLines,
    this.emptyHint = 'No output yet',
  });

  @override
  Widget build(BuildContext context) {
    final lines = viewModel.outputLines;
    if (lines.isEmpty) {
      if (emptyHint == null) return const SizedBox.shrink();
      return Text(
        emptyHint!,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Colors.grey,
        ),
      );
    }

    final preview = lines.length > maxLines
        ? lines.sublist(lines.length - maxLines)
        : lines;

    return Text(
      preview.join('\n'),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        height: 1.3,
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
