import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge_flutter/viewmodels/process_viewmodel.dart';
import 'package:trayforge_flutter/widgets/copy_snackbar.dart';
import 'package:trayforge_flutter/widgets/status_dot.dart';
import 'package:trayforge_flutter/widgets/toggle_button.dart';

/// Full detail page for a single process.
///
/// Shows an [AppBar] with process name, status dot, start/stop toggle,
/// Copy WebUI button (when URL available), and a search toggle. The body
/// displays the complete output log in a scrollable, read-only, monospace
/// text area with auto-scroll and scroll-lock behaviour.
class ProcessDetailPage extends StatefulWidget {
  final ProcessViewModel viewModel;

  const ProcessDetailPage({super.key, required this.viewModel});

  @override
  State<ProcessDetailPage> createState() => _ProcessDetailPageState();
}

class _ProcessDetailPageState extends State<ProcessDetailPage> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  bool _initialScrollDone = false;
  bool _searchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  ProcessViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onViewModelChanged);
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _onViewModelChanged() {
    // Always scroll to bottom on first output load.
    if (!_initialScrollDone) {
      _initialScrollDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      return;
    }

    if (!_autoScroll) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll) _scrollToBottom();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final threshold = (position.maxScrollExtent - position.pixels).abs();
    _autoScroll = threshold < 100;
  }

  void _onSearchChanged() {
    setState(() {
      _searchText = _searchController.text.toLowerCase();
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) {
        _searchController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _toggleSearch,
      },
      child: Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: _vm,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusDot(state: _vm.state),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _vm.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          ListenableBuilder(
            listenable: _vm,
            builder: (context, _) {
              final children = <Widget>[];
              if (_vm.webuiUrl != null) {
                children.add(IconButton(
                  icon: const Icon(Icons.content_copy),
                  tooltip: 'Copy WebUI URL',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: _vm.webuiUrl.toString()),
                    );
                    showCopySnackBar(context);
                  },
                ));
              }
              children.add(IconButton(
                icon: Icon(
                  _searchVisible ? Icons.search_off : Icons.search,
                ),
                tooltip: _searchVisible ? 'Close search' : 'Search output',
                onPressed: _toggleSearch,
              ));
              children.add(ToggleButton(viewModel: _vm));
              return Row(mainAxisSize: MainAxisSize.min, children: children);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searchVisible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Filter output...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _searchController.clear(),
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          Expanded(child: _buildOutputBody()),
        ],
      ),
      ),
    );
  }

  Widget _buildOutputBody() {
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        final lines = _vm.outputLines;
        final filtered = _searchText.isEmpty
            ? lines
            : lines
                .where((line) => line.toLowerCase().contains(_searchText))
                .toList();

        if (filtered.isEmpty && _searchText.isNotEmpty) {
          return const Center(
            child: Text(
              'No matching lines',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        if (filtered.isEmpty) {
          return const Center(
            child: Text(
              'No output yet',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SelectableText(
            filtered.join('\n'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
            ),
          ),
        );
      },
    );
  }
}


