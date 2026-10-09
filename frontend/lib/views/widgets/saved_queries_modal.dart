import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/saved_query.dart';
import '../../state/app_state.dart';

/// Opens a sci-fi styled BottomSheet modal to browse, search, preview, load, and delete saved queries.
Future<SavedQuery?> showSavedQueriesModal(BuildContext context) async {
  return showModalBottomSheet<SavedQuery>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const _SavedQueriesModalContent(),
  );
}

/// Opens a prompt dialog to save the current query with title & optional description.
Future<bool> showSaveQueryDialog(BuildContext context) async {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final state = context.read<AppState>();
  final formKey = GlobalKey<FormState>();

  final bool? result = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      final theme = Theme.of(dialogCtx);
      final accent = theme.colorScheme.primary;

      return AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Row(
          children: [
            Icon(Icons.bookmark_add, color: accent, size: 20),
            const SizedBox(width: 8),
            const Text('Save Query Preset', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: titleCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Query Name / Title',
                  hintText: 'e.g. Active Customer Orders',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Title is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: descCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Description / Notes (Optional)',
                  hintText: 'e.g. Joins users with orders where status is active',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'SQL Preview:\n${state.editorQueryText}',
                  style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Colors.grey),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Save'),
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final success = await state.saveCurrentQuery(titleCtrl.text, description: descCtrl.text);
                if (dialogCtx.mounted) {
                  Navigator.of(dialogCtx).pop(success);
                }
              }
            },
          ),
        ],
      );
    },
  );

  return result ?? false;
}

class _SavedQueriesModalContent extends StatefulWidget {
  const _SavedQueriesModalContent();

  @override
  State<_SavedQueriesModalContent> createState() => _SavedQueriesModalContentState();
}

class _SavedQueriesModalContentState extends State<_SavedQueriesModalContent> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    final queries = state.savedQueries.where((q) {
      if (_searchQuery.isEmpty) return true;
      final qLower = _searchQuery.toLowerCase();
      return q.title.toLowerCase().contains(qLower) ||
          q.sql.toLowerCase().contains(qLower) ||
          (q.description?.toLowerCase().contains(qLower) ?? false);
    }).toList();

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.bookmarks_outlined, size: 19, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Saved Queries & Presets',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '${queries.length} saved statement${queries.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search Filter Bar
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search saved queries by name or SQL...',
                hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // List of Saved Queries
            Expanded(
              child: queries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bookmark_outline, size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No saved queries match "$_searchQuery"'
                                : 'No saved queries yet. Click "Save Query" in the editor to bookmark one!',
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: queries.length,
                      itemBuilder: (context, idx) {
                        final q = queries[idx];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.terminal, size: 16, color: accent),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        q.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        q.builderMode,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: accent,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                      tooltip: 'Delete Saved Query',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        await state.deleteSavedQuery(q.id);
                                      },
                                    ),
                                  ],
                                ),
                                if (q.description != null && q.description!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    q.description!,
                                    style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                                  ),
                                ],
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
                                    q.sql,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      color: Colors.blueGrey,
                                    ),
                                    maxLines: 3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.play_arrow, size: 14),
                                      label: const Text('Load into Editor', style: TextStyle(fontSize: 11)),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        minimumSize: const Size(0, 30),
                                      ),
                                      onPressed: () {
                                        state.loadSavedQuery(q);
                                        Navigator.of(context).pop(q);
                                      },
                                    ),
                                  ],
                                ),
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
}
