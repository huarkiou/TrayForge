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

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          _buildGlobalSettings(context),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Launch at startup'),
            value: _vm.autostartEnabled,
            onChanged: (_) => _vm.toggleAutostart(),
          ),
        ],
      ),
    );
  }
}
