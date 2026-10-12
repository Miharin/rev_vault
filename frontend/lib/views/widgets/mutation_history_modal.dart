import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/mutation_record.dart';
import '../../state/app_state.dart';

/// Shows the Disaster Recovery Vault containing the last 50 edits & 50 deletes.
void showMutationHistoryModal(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => const _MutationHistoryDialog(),
  );
}

class _MutationHistoryDialog extends StatefulWidget {
  const _MutationHistoryDialog();

  @override
  State<_MutationHistoryDialog> createState() => _MutationHistoryDialogState();
}

class _MutationHistoryDialogState extends State<_MutationHistoryDialog> {
  String _filter = 'all'; // 'all' | 'update' | 'delete'
  String? _recoveringId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().fetchMutationHistory();
    });
  }

  Future<void> _handleRecover(MutationRecord record) async {
    setState(() => _recoveringId = record.id);
    final state = context.read<AppState>();
    final ok = await state.recoverMutation(record.id);
    if (!mounted) return;
    setState(() => _recoveringId = null);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully recovered ${record.operation} for ${record.tableName}'),
          backgroundColor: Colors.teal,
          behavior: SnackBarBehavior.floating,
          width: 380,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(state.errorMessage ?? 'Recovery failed'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          width: 380,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<AppState>();
    final history = state.mutationHistory;

    final filtered = history.where((r) {
      if (_filter == 'update') return r.operation.toLowerCase() == 'update';
      if (_filter == 'delete') return r.operation.toLowerCase() == 'delete';
      return true;
    }).toList();

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.history_toggle_off, color: theme.colorScheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Disaster Recovery Vault & Mutation Log',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'Point-in-time rollback for the last 50 edits & 50 deletes (max 1 year retention)',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Refresh Log',
                    onPressed: () => state.fetchMutationHistory(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Filter Tabs
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1),
              child: Row(
                children: [
                  _buildFilterChip('all', 'All (${history.length})'),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'update',
                    'Edits (${history.where((r) => r.operation.toLowerCase() == "update").length})',
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'delete',
                    'Deletes (${history.where((r) => r.operation.toLowerCase() == "delete").length})',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content List
            Expanded(
              child: state.isLoadingHistory
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.assignment_turned_in_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                              const SizedBox(height: 12),
                              Text(
                                'No mutation history recorded yet',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Edits and deletes will appear here with instant undo capability',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) => _buildRecordCard(context, theme, filtered[i]),
                        ),
            ),

            // Modal Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2))),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
              ),
              child: Row(
                children: [
                  Text(
                    'Entries automatically capped at 50 updates & 50 deletes. Older than 365 days auto-pruned.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _filter == key;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => setState(() => _filter = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : theme.dividerColor.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  Widget _buildRecordCard(BuildContext context, ThemeData theme, MutationRecord record) {
    final isDelete = record.operation.toLowerCase() == 'delete';
    final accent = isDelete ? Colors.redAccent : Colors.tealAccent;
    final isRecovering = _recoveringId == record.id;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: record.isRecovered
              ? Colors.grey.withValues(alpha: 0.25)
              : accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Operation badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  record.operation.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Table name
              Text(
                record.tableName,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),

              // Timestamp
              Text(
                record.timestamp.replaceFirst('T', ' ').substring(0, record.timestamp.length > 19 ? 19 : record.timestamp.length),
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // PK and changes info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PK: ${record.primaryKeys.entries.map((e) => "${e.key}=${e.value}").join(", ")}',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (!isDelete && record.newValues != null)
                      Text(
                        'Changes: ${record.oldValues.entries.map((e) => "${e.key}: ${e.value} -> ${record.newValues![e.key]}").join(", ")}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.primary,
                        ),
                      )
                    else if (isDelete)
                      Text(
                        'Deleted snapshot captured (${record.oldValues.length} columns)',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ),

              // Recovery Button or Recovered Badge
              if (record.isRecovered)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 12, color: Colors.greenAccent),
                      SizedBox(width: 4),
                      Text(
                        'RECOVERED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: isRecovering ? null : () => _handleRecover(record),
                  icon: isRecovering
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.undo, size: 13),
                  label: Text(
                    isRecovering ? 'Restoring...' : 'Recover / Undo',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    side: BorderSide(color: accent.withValues(alpha: 0.6)),
                    foregroundColor: accent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
