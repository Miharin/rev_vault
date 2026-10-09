import 'package:flutter/material.dart';
import '../../services/sql_autocomplete_service.dart';

/// Floating autocomplete suggestions popup for the Raw SQL editor.
class SqlAutocompleteOverlay extends StatelessWidget {
  final List<SqlSuggestion> suggestions;
  final int selectedIndex;
  final ValueChanged<SqlSuggestion> onSelect;
  final VoidCallback onClose;

  const SqlAutocompleteOverlay({
    super.key,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surface,
      child: Container(
        width: 380,
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
          color: theme.colorScheme.surface,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header hint bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 12, color: Colors.tealAccent),
                  const SizedBox(width: 6),
                  const Text(
                    'Suggestions',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  const Text(
                    'Tab / Enter: Insert   Esc: Close',
                    style: TextStyle(fontSize: 9.5, color: Colors.grey),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onClose,
                    child: const Icon(Icons.close, size: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Suggestions List
            Flexible(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  final isSelected = index == selectedIndex;

                  return InkWell(
                    onTap: () => onSelect(suggestion),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      color: isSelected
                          ? theme.colorScheme.primary.withValues(alpha: 0.15)
                          : Colors.transparent,
                      child: Row(
                        children: [
                          _buildTypeBadge(suggestion.type),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              suggestion.displayText,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'monospace',
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? theme.colorScheme.primary : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (suggestion.detail != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              suggestion.detail!,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
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
