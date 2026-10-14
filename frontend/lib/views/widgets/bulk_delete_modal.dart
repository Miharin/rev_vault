import 'package:flutter/material.dart';

/// Cyber-styled confirmation modal dialog for deleting multiple database rows in bulk.
Future<bool?> showBulkDeleteModal({
  required BuildContext context,
  required String tableName,
  required int selectedCount,
  required List<Map<String, dynamic>> primaryKeysList,
  required bool isSafeMode,
  required Future<bool> Function() onConfirmDelete,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _BulkDeleteModalDialog(
      tableName: tableName,
      selectedCount: selectedCount,
      primaryKeysList: primaryKeysList,
      isSafeMode: isSafeMode,
      onConfirmDelete: onConfirmDelete,
    ),
  );
}

class _BulkDeleteModalDialog extends StatefulWidget {
  final String tableName;
  final int selectedCount;
  final List<Map<String, dynamic>> primaryKeysList;
  final bool isSafeMode;
  final Future<bool> Function() onConfirmDelete;

  const _BulkDeleteModalDialog({
    required this.tableName,
    required this.selectedCount,
    required this.primaryKeysList,
    required this.isSafeMode,
    required this.onConfirmDelete,
  });

  @override
  State<_BulkDeleteModalDialog> createState() => _BulkDeleteModalDialogState();
}

class _BulkDeleteModalDialogState extends State<_BulkDeleteModalDialog> {
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _submit() async {
    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onConfirmDelete();
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isDeleting = false;
          _errorMessage = 'Failed to bulk delete rows. Check server error or foreign key constraints.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Danger Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.redAccent.withValues(alpha: 0.2)),
                ),
                color: Colors.red.withValues(alpha: 0.08),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Confirm Bulk Delete (${widget.selectedCount} Rows)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          widget.tableName,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (widget.isSafeMode)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock, size: 10, color: Colors.amberAccent),
                          SizedBox(width: 3),
                          Text(
                            'SAFE MODE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ),

            // Warning Notice & Selected Keys Preview
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Are you sure you want to permanently delete these ${widget.selectedCount} selected rows from ${widget.tableName}? '
                    'This action is executed in a single atomic transaction.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.cyan.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.history, size: 14, color: Colors.cyanAccent),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Disaster Recovery Active: A snapshot of deleted rows will be saved to Mutation History for undo restoration.',
                            style: TextStyle(fontSize: 11, color: Colors.cyanAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 140),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IDENTIFYING KEYS (${widget.primaryKeysList.length}):',
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: widget.primaryKeysList.length,
                            itemBuilder: (context, idx) {
                              final item = widget.primaryKeysList[idx];
                              final desc = item.entries.map((e) => '${e.key}=${e.value}').join(', ');
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '• $desc',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Colors.redAccent,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Modal Actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isDeleting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isDeleting ? null : _submit,
                    icon: _isDeleting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.delete_sweep, size: 16),
                    label: Text(
                      _isDeleting ? 'Deleting...' : 'Delete ${widget.selectedCount} Rows',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
