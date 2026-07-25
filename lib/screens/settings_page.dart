import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

/// Settings page showing only global configuration options.
///
/// Process CRUD has moved to the Dashboard and process edit form.
class SettingsPage extends StatefulWidget {
  final SettingsViewModel viewModel;

  const SettingsPage({super.key, required this.viewModel});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsViewModel get _vm => widget.viewModel;

  late final TextEditingController _refreshCtrl;
  late final TextEditingController _historyCtrl;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onChanged);
    _refreshCtrl = TextEditingController(text: _vm.outputRefreshMs.toString());
    _historyCtrl = TextEditingController(
      text: _vm.outputHistoryLimit.toString(),
    );
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _refreshCtrl.dispose();
    _historyCtrl.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _applyRefreshMs(int val) {
    _vm.setOutputRefreshMs(val);
    _refreshCtrl.text = val.toString();
  }

  void _applyHistoryLimit(int val) {
    _vm.setOutputHistoryLimit(val);
    _historyCtrl.text = val.toString();
  }

  Widget _buildStepperField({
    required String label,
    required String tooltip,
    required TextEditingController controller,
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 4),
        Tooltip(
          message: tooltip,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onFieldSubmitted: (v) {
                    final val = int.tryParse(v);
                    if (val != null && val >= min && val <= max) {
                      onChanged(val);
                    } else {
                      controller.text = value.toString();
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 32,
                    height: 24,
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      onPressed: value < max
                          ? () => onChanged(value + step)
                          : null,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 24,
                    child: IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      onPressed: value > min
                          ? () => onChanged(value - step)
                          : null,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Takes effect on next process start',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStepperField(
            label: 'Output refresh (ms)',
            tooltip: 'Lower = smoother, higher = less CPU',
            controller: _refreshCtrl,
            value: _vm.outputRefreshMs,
            min: 100,
            max: 5000,
            step: 100,
            onChanged: _applyRefreshMs,
          ),
          const SizedBox(height: 16),
          _buildStepperField(
            label: 'History limit',
            tooltip: 'Max lines per process',
            controller: _historyCtrl,
            value: _vm.outputHistoryLimit,
            min: 100,
            max: 100000,
            step: 500,
            onChanged: _applyHistoryLimit,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Launch at startup'),
            value: _vm.autostartEnabled,
            onChanged: (_) => _vm.toggleAutostart(),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
