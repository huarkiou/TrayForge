import 'package:flutter/material.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';

/// Start/stop toggle with spinner during transitions.
class ToggleButton extends StatelessWidget {
  final ProcessViewModel viewModel;
  final VisualDensity? visualDensity;

  const ToggleButton({
    super.key,
    required this.viewModel,
    this.visualDensity,
  });

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

    final isRunning = viewModel.state.isActive;
    return IconButton(
      icon: Icon(
        isRunning ? Icons.stop_circle_outlined : Icons.play_circle_outlined,
        color: isRunning ? Colors.red : Colors.green,
      ),
      tooltip: isRunning ? 'Stop' : 'Start',
      onPressed: () => viewModel.toggle(),
      visualDensity: visualDensity,
    );
  }
}
