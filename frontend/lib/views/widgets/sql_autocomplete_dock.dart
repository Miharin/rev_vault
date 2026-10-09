import 'package:flutter/material.dart';
import '../../services/sql_autocomplete_service.dart';

/// Docked IntelliSense & Snippet Assistant that sits cleanly below the SQL editor
/// without ever covering the user's query text, and auto-scrolls to keep selected choices visible.
class SqlAutocompleteDock extends StatefulWidget {
  final List<SqlSuggestion> suggestions;
  final int selectedIndex;
  final ValueChanged<SqlSuggestion> onSelect;
  final VoidCallback onClose;

  const SqlAutocompleteDock({
    super.key,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<SqlAutocompleteDock> createState() => _SqlAutocompleteDockState();
}

class _SqlAutocompleteDockState extends State<SqlAutocompleteDock> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemExtent = 32.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(SqlAutocompleteDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.suggestions != widget.suggestions) {
      _scrollToSelected();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (!mounted || !_scrollController.hasClients || widget.suggestions.isEmpty) return;

    final activeIndex = (widget.selectedIndex >= 0 && widget.selectedIndex < widget.suggestions.length)
        ? widget.selectedIndex
        : 0;

    final targetTop = activeIndex * _itemExtent;
    final targetBottom = targetTop + _itemExtent;
    final currentOffset = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;

    if (activeIndex == 0) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    } else if (activeIndex == widget.suggestions.length - 1) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    } else if (targetTop < currentOffset) {
      _scrollController.animateTo(
        targetTop,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    } else if (targetBottom > currentOffset + viewportHeight) {
      _scrollController.animateTo(
        (targetBottom - viewportHeight) + 4.0, // extra 4px breathing room
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.suggestions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final activeIndex = (widget.selectedIndex >= 0 && widget.selectedIndex < widget.suggestions.length)
        ? widget.selectedIndex
        : 0;
    final activeSuggestion = widget.suggestions[activeIndex];

    return Container(
      height: 165,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: accent.withValues(alpha: 0.35), width: 1.5),
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        children: [
          // Header Bar
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 12, color: accent),
                const SizedBox(width: 6),
                Text(
                  'IntelliSense Assistant (${widget.suggestions.length} matches)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  '↑/↓: Navigate  •  Tab / Enter: Insert  •  Esc: Dismiss',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const Spacer(),
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text('Close', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        SizedBox(width: 2),
                        Icon(Icons.close, size: 12, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Two-Panel Body (List on left, Preview on right)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Panel: Suggestions List with Auto-Scroll
                SizedBox(
                  width: 320,
                  child: ListView.builder(
                    controller: _scrollController,
                    itemExtent: _itemExtent,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    itemCount: widget.suggestions.length,
                    itemBuilder: (context, index) {
                      final item = widget.suggestions[index];
                      final isSelected = index == activeIndex;

                      return InkWell(
                        onTap: () => widget.onSelect(item),
                        child: Container(
                          height: _itemExtent,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accent.withValues(alpha: 0.15)
                                : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: isSelected ? accent : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildTypeBadge(item.type),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.displayText,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontFamily: 'monospace',
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? theme.colorScheme.onSurface : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.keyboard_return, size: 12, color: accent),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const VerticalDivider(width: 1),

                // Right Panel: Live Template & Documentation Preview
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildTypeBadge(activeSuggestion.type),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                activeSuggestion.displayText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (activeSuggestion.detail != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                activeSuggestion.detail!,
                                style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                              ),
                            ],
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: () => widget.onSelect(activeSuggestion),
                              icon: const Icon(Icons.add, size: 12),
                              label: const Text('Insert', style: TextStyle(fontSize: 10)),
                              style: ElevatedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                minimumSize: const Size(0, 24),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: theme.dividerColor.withValues(alpha: 0.2),
                              ),
                            ),
                            child: SingleChildScrollView(
                              child: Text(
                                activeSuggestion.insertText.trim(),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  height: 1.35,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(SqlSuggestionType type) {
    IconData icon;
    Color color;
    String label;

    switch (type) {
      case SqlSuggestionType.table:
        icon = Icons.table_chart;
        color = Colors.amber;
        label = 'TBL';
        break;
      case SqlSuggestionType.column:
        icon = Icons.view_column;
        color = Colors.cyan;
        label = 'COL';
        break;
      case SqlSuggestionType.subquery:
        icon = Icons.hub;
        color = Colors.purpleAccent;
        label = 'SUB';
        break;
      case SqlSuggestionType.keyword:
        icon = Icons.code;
        color = Colors.teal;
        label = 'KEY';
        break;
      case SqlSuggestionType.function:
        icon = Icons.functions;
        color = Colors.orange;
        label = 'FN';
        break;
      case SqlSuggestionType.parameter:
        icon = Icons.data_object;
        color = Colors.pinkAccent;
        label = 'VAR';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
