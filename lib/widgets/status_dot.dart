import 'package:flutter/material.dart';
import 'package:trayforge/foundation/models.dart';

/// Colour used for [ProcState] in [StatusDot] and status labels.
///
/// Green = running, red = crashed, grey = stopped/starting/stopping/cooldown.
Color statusColor(ProcState state) {
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

/// A small coloured circle indicating process status.
///
/// See [statusColor] for the colour mapping.
class StatusDot extends StatelessWidget {
  final ProcState state;

  const StatusDot({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: statusColor(state),
      ),
    );
  }
}
