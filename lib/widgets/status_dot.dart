import 'package:flutter/material.dart';
import 'package:trayforge_flutter/foundation/models.dart';

/// A small coloured circle indicating process status.
///
/// Green = running, red = crashed, grey = stopped/starting/stopping/cooldown.
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
        color: _color,
      ),
    );
  }

  Color get _color => state.statusColor;
}
