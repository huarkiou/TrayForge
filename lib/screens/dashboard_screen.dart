import 'package:flutter/material.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/screens/process_detail_screen.dart';
import 'package:trayforge/screens/process_edit_page.dart';
import 'package:trayforge/screens/settings_page.dart';
import 'package:trayforge/viewmodels/dashboard_viewmodel.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';
import 'package:trayforge/widgets/process_card.dart';

/// Dashboard screen showing process cards or a welcome screen.
///
/// When no processes are configured, displays a welcome screen with an
/// "Add Process" button. When processes exist, shows the configured layout:
/// a scrollable list of [ProcessCard] widgets or an adaptive grid of
/// [ProcessGridCard] widgets, switchable via an AppBar toggle. On startup,
/// if a corrupted config was detected, shows an alert dialog before
/// rendering.
class DashboardScreen extends StatefulWidget {
  final DashboardViewModel viewModel;
  final SettingsViewModel? settingsViewModel;

  const DashboardScreen({
    super.key,
    required this.viewModel,
    this.settingsViewModel,
  });

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
    final settingsViewModel = widget.settingsViewModel;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.viewModel, ?settingsViewModel]),
      builder: (context, _) {
        final isEmpty = widget.viewModel.isEmpty;
        final isListLayout =
            settingsViewModel?.dashboardLayout == DashboardLayout.list;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Processes'),
            actions: [
              if (settingsViewModel != null && !isEmpty)
                IconButton(
                  icon: Icon(isListLayout ? Icons.grid_view : Icons.view_list),
                  tooltip: isListLayout
                      ? 'Switch to grid view'
                      : 'Switch to list view',
                  onPressed: () => settingsViewModel.setDashboardLayout(
                    isListLayout ? DashboardLayout.grid : DashboardLayout.list,
                  ),
                ),
              if (settingsViewModel != null)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add process',
                  onPressed: () => _openAddPage(context),
                ),
              if (settingsViewModel != null)
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SettingsPage(viewModel: settingsViewModel),
                      ),
                    );
                  },
                ),
            ],
          ),
          body: isEmpty
              ? _buildWelcomeBody(context)
              : _buildDashboardBody(context),
        );
      },
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
            onPressed: () => _openAddPage(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Process'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardBody(BuildContext context) {
    final layout =
        widget.settingsViewModel?.dashboardLayout ?? DashboardLayout.list;
    if (layout == DashboardLayout.grid) {
      return _buildGridBody(context);
    }
    return _buildListBody(context);
  }

  Widget _buildListBody(BuildContext context) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.viewModel.processViewModels.length,
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) {
        widget.settingsViewModel?.reorderItem(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final vm = widget.viewModel.processViewModels[index];
        // Long-press anywhere on the card to start a reorder drag;
        // quick taps pass through to the card's own handlers.
        return ReorderableDelayedDragStartListener(
          key: ValueKey(vm.name),
          index: index,
          child: ProcessCard(
            viewModel: vm,
            onEditTap: () => _openEditPage(context, vm.name),
            onTap: () => _openDetail(context, vm),
          ),
        );
      },
    );
  }

  /// Adaptive grid of compact square cards; columns adapt to window width.
  Widget _buildGridBody(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: widget.viewModel.processViewModels.length,
      itemBuilder: (context, index) {
        final vm = widget.viewModel.processViewModels[index];
        return ProcessGridCard(
          viewModel: vm,
          onEditTap: () => _openEditPage(context, vm.name),
          onTap: () => _openDetail(context, vm),
        );
      },
    );
  }

  void _openDetail(BuildContext context, ProcessViewModel vm) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessDetailPage(
          viewModel: vm,
          onEditTap: () => _openEditPage(context, vm.name),
        ),
      ),
    );
  }

  void _openAddPage(BuildContext context) {
    _navigateToEdit(context, null, null, null);
  }

  void _openEditPage(BuildContext context, String name) {
    if (widget.settingsViewModel == null) return;
    final processes = widget.settingsViewModel!.processes;
    final editIndex = processes.indexWhere((p) => p.name == name);
    if (editIndex == -1) return;
    _navigateToEdit(context, processes[editIndex], editIndex, null);
  }

  void _navigateToEdit(
    BuildContext context,
    ProcessConfig? initial,
    int? editIndex,
    String? name,
  ) {
    if (widget.settingsViewModel == null) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessEditPage(
          settingsViewModel: widget.settingsViewModel!,
          initial: initial,
          editIndex: editIndex,
        ),
      ),
      (route) => route.isFirst,
    );
  }
}
