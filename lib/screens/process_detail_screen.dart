import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trayforge/viewmodels/process_viewmodel.dart';
import 'package:trayforge/widgets/copy_snackbar.dart';
import 'package:trayforge/widgets/status_dot.dart';
import 'package:trayforge/widgets/toggle_button.dart';

/// Full detail page for a single process.
///
/// Shows an [AppBar] with process name, status dot, start/stop toggle,
/// Copy WebUI button (when URL available), and a search toggle. The body
/// displays the complete output log in a scrollable, read-only, monospace
/// text area with auto-scroll and scroll-lock behaviour.
class ProcessDetailPage extends StatefulWidget {
  final ProcessViewModel viewModel;
  final VoidCallback? onEditTap;

  const ProcessDetailPage({super.key, required this.viewModel, this.onEditTap});

  @override
  State<ProcessDetailPage> createState() => _ProcessDetailPageState();
}

class _ProcessDetailPageState extends State<ProcessDetailPage> {
  /// Distance from the bottom of the log that separates Follow-latest
  /// from Detached.
  static const double _followThreshold = 100.0;

  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  bool _searchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchText = '';

  ProcessViewModel get _vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onViewModelChanged);
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    // Opening the page always starts in Follow-latest, pinned to the newest
    // output — independent of any view-model notification.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _onViewModelChanged() {
    if (!_autoScroll) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll) _scrollToBottom();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final threshold = (position.maxScrollExtent - position.pixels).abs();
    _autoScroll = threshold < _followThreshold;
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
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
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
                  child: Text(_vm.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          actions: [
            if (widget.onEditTap != null)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit process',
                onPressed: widget.onEditTap,
              ),
            ListenableBuilder(
              listenable: _vm,
              builder: (context, _) {
                final children = <Widget>[];
                if (_vm.webuiUrl != null) {
                  children.add(
                    IconButton(
                      icon: const Icon(Icons.content_copy),
                      tooltip: 'Copy WebUI URL',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: _vm.webuiUrl.toString()),
                        );
                        showCopySnackBar(context);
                      },
                    ),
                  );
                }
                children.add(
                  IconButton(
                    icon: const Icon(Icons.delete_sweep),
                    tooltip: 'Clear output',
                    onPressed: () {
                      // Clearing starts a new log session: return to
                      // Follow-latest, since the previous scroll position
                      // referred to deleted content.
                      _autoScroll = true;
                      _vm.clearOutput();
                    },
                  ),
                );
                children.add(
                  IconButton(
                    icon: Icon(
                      _searchVisible ? Icons.search_off : Icons.search,
                    ),
                    tooltip: _searchVisible ? 'Close search' : 'Search output',
                    onPressed: _toggleSearch,
                  ),
                );
                children.add(ToggleButton(viewModel: _vm));
                return Row(mainAxisSize: MainAxisSize.min, children: children);
              },
            ),
          ],
        ),
        body: Column(
          // Stretch: with loose constraints (Scaffold body) the Column would
          // otherwise collapse to the log's content width, dragging the
          // scrollbar away from the window's right edge.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_searchVisible)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
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
            child: Text('No output yet', style: TextStyle(color: Colors.grey)),
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
