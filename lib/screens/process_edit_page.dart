import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge/foundation/models.dart';
import 'package:trayforge/viewmodels/settings_viewmodel.dart';

/// Full-screen form for creating or editing a [ProcessConfig].
///
/// Used by [SettingsPage] for both add (empty form) and edit (pre-filled).
/// Validation errors are shown inline; the save button is disabled until
/// the form is valid.
class ProcessEditPage extends StatefulWidget {
  final SettingsViewModel settingsViewModel;
  final ProcessConfig? initial;
  final int? editIndex;

  const ProcessEditPage({
    super.key,
    required this.settingsViewModel,
    this.initial,
    this.editIndex,
  });

  bool get isEditing => editIndex != null;

  @override
  State<ProcessEditPage> createState() => _ProcessEditPageState();
}

class _ProcessEditPageState extends State<ProcessEditPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _cwdController;
  late final TextEditingController _cmdController;
  late final TextEditingController _webuiPatternController;
  late final TextEditingController _deleteBeforeStartController;
  late final TextEditingController _maxRestartsController;

  String _encoding = 'utf-8';
  bool _singleton = false;
  bool _autostart = false;
  bool _cleanupCwd = false;
  List<_EnvRow> _envRows = [];

  String? _regexError;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _nameController = TextEditingController(text: p?.name ?? '');
    _cwdController = TextEditingController(text: p?.cwd ?? '');
    _cmdController = TextEditingController(text: p?.cmd ?? '');
    _encoding = p?.encoding ?? 'utf-8';
    _singleton = p?.singleton ?? false;
    _autostart = p?.autostart ?? false;
    _cleanupCwd = p?.cleanupCwd ?? false;
    _webuiPatternController = TextEditingController(
      text: p?.webuiPattern ?? '',
    );
    _deleteBeforeStartController = TextEditingController(
      text: (p?.deleteBeforeStart ?? []).join('\n'),
    );
    _maxRestartsController = TextEditingController(
      text: p?.maxRestarts?.toString() ?? '',
    );
    _envRows =
        (p?.env?.entries.map((e) => _EnvRow(e.key, e.value)).toList() ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cwdController.dispose();
    _cmdController.dispose();
    _webuiPatternController.dispose();
    _deleteBeforeStartController.dispose();
    _maxRestartsController.dispose();
    for (final row in _envRows) {
      row.dispose();
    }
    super.dispose();
  }

  ProcessConfig _buildConfig() {
    return ProcessConfig(
      name: _nameController.text.trim(),
      cwd: _cwdController.text.trim().isEmpty
          ? null
          : _cwdController.text.trim(),
      cmd: _cmdController.text.trim(),
      encoding: _encoding == 'utf-8' ? null : _encoding,
      singleton: _singleton,
      autostart: _autostart,
      cleanupCwd: _cleanupCwd,
      webuiPattern: _webuiPatternController.text.trim().isEmpty
          ? null
          : _webuiPatternController.text.trim(),
      deleteBeforeStart: _deleteBeforeStartController.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(),
      maxRestarts: int.tryParse(_maxRestartsController.text.trim()),
      env: _envRows.isEmpty
          ? null
          : {
              for (final r in _envRows)
                r.keyController.text: r.valueController.text,
            },
    );
  }

  void _validateRegex(String pattern) {
    if (pattern.isEmpty) {
      setState(() => _regexError = null);
      return;
    }
    try {
      RegExp(pattern);
      setState(() => _regexError = null);
    } on FormatException catch (e) {
      setState(() => _regexError = 'Invalid regex: ${e.message}');
    }
  }

  // ---- CWD browse ----

  Future<void> _browseCwd() async {
    final path = await getDirectoryPath();
    if (path != null) {
      _cwdController.text = path;
    }
  }

  // ---- Multi-line cmd editor ----

  Future<void> _editCmdMultiLine() async {
    final controller = TextEditingController(text: _cmdController.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Command'),
        content: SizedBox(
          width: 500,
          height: 240,
          child: TextField(
            controller: controller,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Enter command (Ctrl+Enter to save)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      // Collapse newlines to spaces for single-line command.
      _cmdController.text = result.replaceAll('\n', ' ').trim();
    }
    controller.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_regexError != null) return;

    final config = _buildConfig();
    final vm = widget.settingsViewModel;

    final vmError = vm.validateConfig(config);
    if (vmError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vmError), backgroundColor: Colors.red),
      );
      return;
    }

    if (widget.isEditing) {
      vm.edit(widget.editIndex!, config);
    } else {
      vm.add(config);
    }

    Navigator.of(context).pop();
  }

  void _duplicate() {
    widget.settingsViewModel.copy(widget.editIndex!);
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final name = widget.initial?.name ?? '';
    final isRunning = widget.settingsViewModel.isRunning(name);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isRunning ? 'Stop and delete?' : 'Delete process?'),
        content: Text(
          isRunning
              ? '"$name" is currently running. It will be stopped and the configuration deleted.'
              : 'Delete "$name"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(isRunning ? 'Stop and Delete' : 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (isRunning) {
      // Fire-and-forget: do not wait for process exit.
      widget.settingsViewModel.stopProcess(name);
    }
    widget.settingsViewModel.delete(widget.editIndex!);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Process' : 'Add Process'),
        actions: [
          if (widget.isEditing)
            TextButton(
              onPressed: _confirmDelete,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          if (widget.isEditing)
            TextButton(onPressed: _duplicate, child: const Text('Duplicate')),
          TextButton(
            onPressed: _regexError == null ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                helperText: 'Must not contain / or \\',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Name is required';
                }
                if (v.contains('/') || v.contains('\\')) {
                  return 'Name must not contain / or \\';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cwdController,
                    decoration: const InputDecoration(
                      labelText: 'Working Directory (cwd)',
                      hintText: 'e.g. C:\\MyApp',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: 'Browse…',
                  onPressed: _browseCwd,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cmdController,
                    decoration: const InputDecoration(
                      labelText: 'Command *',
                      hintText: 'e.g. myapp.exe --flag',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Command is required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.open_in_full),
                  tooltip: 'Multi-line editor…',
                  onPressed: _editCmdMultiLine,
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _encoding,
              decoration: const InputDecoration(
                labelText: 'Encoding',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'utf-8', child: Text('UTF-8')),
                DropdownMenuItem(value: 'gbk', child: Text('GBK')),
                DropdownMenuItem(value: 'cp936', child: Text('CP936')),
                DropdownMenuItem(value: 'latin-1', child: Text('Latin-1')),
              ],
              onChanged: (v) => setState(() => _encoding = v ?? 'utf-8'),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _singleton,
              title: const Text('Singleton'),
              subtitle: const Text(
                'Prevent starting if a process with the same name is already running',
              ),
              onChanged: (v) => setState(() => _singleton = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _autostart,
              title: const Text('Autostart'),
              subtitle: const Text(
                'Start this process automatically on launch',
              ),
              onChanged: (v) => setState(() => _autostart = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _cleanupCwd,
              title: const Text('Cleanup CWD'),
              subtitle: const Text(
                'Kill residual processes from the same working directory before start',
              ),
              onChanged: (v) => setState(() => _cleanupCwd = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _webuiPatternController,
              decoration: InputDecoration(
                labelText: 'WebUI Pattern',
                hintText: r'e.g. WebUI started at (http://[\d.:]+)',
                border: const OutlineInputBorder(),
                errorText: _regexError,
              ),
              onChanged: _validateRegex,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _maxRestartsController,
              decoration: const InputDecoration(
                labelText: 'Max Restarts',
                hintText: 'e.g. 3',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 24),
            Text(
              'Delete Before Start',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'One file path per line, relative to working directory',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _deleteBeforeStartController,
              decoration: const InputDecoration(
                hintText: 'temp.lock\ncache.dat',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Environment Variables',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _envRows.add(_EnvRow('', ''))),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            ..._envRows.asMap().entries.map((entry) {
              final idx = entry.key;
              final row = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: row.keyController,
                        decoration: const InputDecoration(
                          labelText: 'Key',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: row.valueController,
                        decoration: const InputDecoration(
                          labelText: 'Value',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      tooltip: 'Remove',
                      onPressed: () => setState(() {
                        row.dispose();
                        _envRows.removeAt(idx);
                      }),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

/// Mutable key-value pair for the env table, with its own controllers.
class _EnvRow {
  final TextEditingController keyController;
  final TextEditingController valueController;

  _EnvRow(String key, String value)
    : keyController = TextEditingController(text: key),
      valueController = TextEditingController(text: value);

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}
