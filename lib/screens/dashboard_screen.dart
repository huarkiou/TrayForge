import 'package:flutter/material.dart';
import 'package:trayforge_flutter/screens/process_detail_screen.dart';
import 'package:trayforge_flutter/screens/settings_page.dart';
import 'package:trayforge_flutter/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge_flutter/viewmodels/settings_viewmodel.dart';
import 'package:trayforge_flutter/widgets/process_card.dart';

/// Dashboard screen showing process cards or a welcome screen.
///
/// When no processes are configured, displays a welcome screen with an
/// "Add Process" button. When processes exist, shows a scrollable list
/// of [ProcessCard] widgets. On startup, if a corrupted config was detected,
/// shows an alert dialog before rendering.
class DashboardScreen extends StatefulWidget {
  final DashboardViewModel viewModel;
  final SettingsViewModel? settingsViewModel;

  const DashboardScreen({super.key, required this.viewModel, this.settingsViewModel});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.viewModel.configCorrupted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showCorruptedDialog();
      });
    }
  }

  void _showCorruptedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configuration Error'),
        content: const Text(
          'The configuration file is corrupted and has been backed up. '
          'Please check your config file.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.viewModel.clearCorruptedFlag();
              Navigator.of(ctx).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(DashboardViewModel.appTitle),
        actions: [
          if (widget.settingsViewModel != null)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(
                      viewModel: widget.settingsViewModel!,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          if (widget.viewModel.isEmpty) {
            return _buildWelcomeBody(context);
          }
          return _buildDashboardBody(context);
        },
      ),
    );
  }

  Widget _buildWelcomeBody(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No processes configured',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              if (widget.settingsViewModel != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsPage(
                      viewModel: widget.settingsViewModel!,
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Process'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardBody(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.viewModel.processViewModels.length,
      itemBuilder: (context, index) {
        final vm = widget.viewModel.processViewModels[index];
        return ProcessCard(
          viewModel: vm,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ProcessDetailPage(viewModel: vm),
              ),
            );
          },
        );
      },
    );
  }
}
