import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge_flutter/foundation/models.dart';
import 'package:trayforge_flutter/screens/process_edit_page.dart';
import 'package:trayforge_flutter/viewmodels/settings_viewmodel.dart';

/// Settings page with a reorderable list of process configurations.
///
/// Supports add (FAB), edit (tap name), copy, delete (with running-process
/// awareness), and drag-to-reorder. Changes are persisted through
/// [SettingsViewModel] and trigger a [ProcessManager] reload.
class SettingsPage extends StatefulWidget {
  final SettingsViewModel viewModel;

  const SettingsPage({super.key, required this.viewModel});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onChanged);
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  // ---- Global settings ----

  Widget _buildGlobalSettings(BuildContext context) {
    final refreshCtrl = TextEditingController(
      text: _vm.outputRefreshMs.toString(),
    );
    final historyCtrl = TextEditingController(
      text: _vm.outputHistoryLimit.toString(),
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: refreshCtrl,
              decoration: const InputDecoration(
                labelText: 'Output refresh (ms)',
                helperText: 'Lower = smoother, higher = less CPU',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (v) {
                final val = int.tryParse(v);
                if (val != null && val >= 100 && val <= 5000) {
                  _vm.setOutputRefreshMs(val);
                } else {
                  refreshCtrl.text = _vm.outputRefreshMs.toString();
                }
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              controller: historyCtrl,
              decoration: const InputDecoration(
                labelText: 'History limit',
                helperText: 'Max lines per process',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (v) {
                final val = int.tryParse(v);
                if (val != null && val >= 100) {
                  _vm.setOutputHistoryLimit(val);
                } else {
                  historyCtrl.text = _vm.outputHistoryLimit.toString();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- Navigation ----

  Future<void> _openAddPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessEditPage(settingsViewModel: _vm),
      ),
    );
  }

  Future<void> _openEditPage(int index) async {
    final config = _vm.processes[index];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProcessEditPage(
          settingsViewModel: _vm,
          initial: config,
          editIndex: index,
        ),
      ),
    );
  }

  // ---- Delete ----

  Future<void> _confirmDelete(int index) async {
    final config = _vm.processes[index];

    if (_vm.isRunning(config.name)) {
      final ok = await _showDeleteDialog(
        title: 'Stop and delete?',
        content:
            '"${config.name}" is currently running. '
            'Do you want to stop it and delete the configuration?',
        confirmLabel: 'Stop and Delete',
      );
      if (ok) {
        await _vm.stopProcess(config.name);
        _vm.delete(index);
      }
    } else {
      final ok = await _showDeleteDialog(
        title: 'Delete process?',
        content: 'Delete "${config.name}"? This cannot be undone.',
        confirmLabel: 'Delete',
      );
      if (ok) {
        _vm.delete(index);
      }
    }
  }

  /// Shows a confirmation dialog with a destructive action.
  Future<bool> _showDeleteDialog({
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final processes = _vm.processes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Column(
        children: [
          _buildGlobalSettings(context),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Launch at startup'),
            value: _vm.autostartEnabled,
            onChanged: (_) => _vm.toggleAutostart(),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('Processes',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
          Expanded(
            child: processes.isEmpty
                ? const Center(
                    child: Text(
                      'No processes configured',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: processes.length,
                    onReorderItem: _vm.reorderItem,
                    proxyDecorator: _proxyDecorator,
                    itemBuilder: (context, index) {
                      return _ProcessRow(
                        key: ValueKey(processes[index].name),
                        index: index,
                        config: processes[index],
                        isRunning: _vm.isRunning(processes[index].name),
                        onTap: () => _openEditPage(index),
                        onCopy: () => _vm.copy(index),
                        onDelete: () => _confirmDelete(index),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddPage,
        tooltip: 'Add Process',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> anim) {
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final t = anim.value;
        final elevation = (1 - t) * 0 + t * 6;
        return Material(
          elevation: elevation,
          color: Colors.transparent,
          shadowColor: Colors.black26,
          child: child,
        );
      },
      child: child,
    );
  }
}

/// A single row in the process list.
class _ProcessRow extends StatelessWidget {
  final int index;
  final ProcessConfig config;
  final bool isRunning;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _ProcessRow({
    super.key,
    required this.index,
    required this.config,
    required this.isRunning,
    required this.onTap,
    required this.onCopy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle, color: Colors.grey),
                ),
              ),
              if (isRunning)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.play_arrow, color: Colors.green, size: 18),
                ),
              Expanded(
                child: Text(
                  config.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.content_copy, size: 20),
                tooltip: 'Copy',
                onPressed: onCopy,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete',
                onPressed: onDelete,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
