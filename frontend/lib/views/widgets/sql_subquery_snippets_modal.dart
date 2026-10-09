import 'package:flutter/material.dart';
import '../../services/sql_autocomplete_service.dart';

/// Opens an interactive modal allowing developers to browse, search, and insert
/// advanced Subquery and CTE templates into their Raw SQL query.
Future<SqlSubquerySnippet?> showSqlSubquerySnippetsModal(BuildContext context) async {
  return showDialog<SqlSubquerySnippet>(
    context: context,
    builder: (ctx) => const _SqlSubquerySnippetsDialog(),
  );
}

class _SqlSubquerySnippetsDialog extends StatefulWidget {
  const _SqlSubquerySnippetsDialog();

  @override
  State<_SqlSubquerySnippetsDialog> createState() => _SqlSubquerySnippetsDialogState();
}

class _SqlSubquerySnippetsDialogState extends State<_SqlSubquerySnippetsDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchFilter = '';
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    final categories = ['All', 'Filtering', 'CTE / Modular', 'Joins', 'Projection', 'Analytics', 'Expressions'];

    final snippets = SqlAutocompleteService.subquerySnippets.where((snippet) {
      final matchesCategory = _selectedCategory == 'All' || snippet.category == _selectedCategory;
      final matchesSearch = _searchFilter.isEmpty ||
          snippet.title.toLowerCase().contains(_searchFilter) ||
          snippet.description.toLowerCase().contains(_searchFilter) ||
          snippet.template.toLowerCase().contains(_searchFilter);
      return matchesCategory && matchesSearch;
    }).toList();

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      title: Row(
        children: [
          Icon(Icons.hub_outlined, color: accent, size: 22),
          const SizedBox(width: 8),
          const Text('Subquery & CTE Snippets Library', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          children: [
            // Search Bar & Categories
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (val) => setState(() => _searchFilter = val.trim().toLowerCase()),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search subqueries, CTEs, window functions...',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: _searchFilter.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchFilter = '');
                              },
                            )
                          : null,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Category Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(cat, style: const TextStyle(fontSize: 11)),
                      onSelected: (val) {
                        setState(() => _selectedCategory = cat);
                      },
                      visualDensity: VisualDensity.compact,
                      selectedColor: accent.withValues(alpha: 0.2),
                      checkmarkColor: accent,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),

            // Snippet Cards List
            Expanded(
              child: snippets.isEmpty
                  ? const Center(
                      child: Text('No matching subquery snippets found.', style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: snippets.length,
                      separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = snippets[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.category,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accent),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () => Navigator.of(context).pop(item),
                                    icon: const Icon(Icons.add, size: 14),
                                    label: const Text('Insert', style: TextStyle(fontSize: 11)),
                                    style: ElevatedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.description,
                                style: TextStyle(fontSize: 11.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                                ),
                                child: SelectableText(
                                  item.template,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.35),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
