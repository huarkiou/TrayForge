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
    _refreshCtrl = TextEditingController(
      text: _vm.outputRefreshMs.toString(),
    );
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

  void _saveRefreshMs(String v) {
    final val = int.tryParse(v);
    if (val != null && val >= 100 && val <= 5000) {
      _vm.setOutputRefreshMs(val);
    } else {
      _refreshCtrl.text = _vm.outputRefreshMs.toString();
    }
  }

  void _saveHistoryLimit(String v) {
    final val = int.tryParse(v);
    if (val != null && val >= 100) {
      _vm.setOutputHistoryLimit(val);
    } else {
      _historyCtrl.text = _vm.outputHistoryLimit.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _refreshCtrl,
            decoration: const InputDecoration(
              labelText: 'Output refresh (ms)',
              helperText: 'Lower = smoother, higher = less CPU',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onFieldSubmitted: _saveRefreshMs,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _historyCtrl,
            decoration: const InputDecoration(
              labelText: 'History limit',
              helperText: 'Max lines per process',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onFieldSubmitted: _saveHistoryLimit,
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
