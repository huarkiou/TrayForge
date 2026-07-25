import 'package:flutter/material.dart';
import 'package:trayforge_flutter/viewmodels/dashboard_viewmodel.dart';

/// Placeholder Dashboard screen for ticket 06.
///
/// Shows the app title and a placeholder body. Process cards arrive in
/// ticket 07.
class DashboardScreen extends StatelessWidget {
  final DashboardViewModel viewModel;

  const DashboardScreen({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(DashboardViewModel.appTitle),
      ),
      body: const Center(
        child: Text(
          'Dashboard — coming soon',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ),
    );
  }
}
