import 'package:flutter/material.dart';

/// Stub detail page for a single process.
///
/// Shows the process name in the AppBar and a "Coming soon" body.
/// Navigation target for tapping a [ProcessCard].
class ProcessDetailPage extends StatelessWidget {
  final String processName;

  const ProcessDetailPage({super.key, required this.processName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(processName),
      ),
      body: const Center(
        child: Text(
          'Coming soon',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ),
    );
  }
}
