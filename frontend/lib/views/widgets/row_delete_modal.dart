import 'package:flutter/material.dart';
import '../../models/table_schema.dart';

/// Cyber-styled confirmation modal dialog for deleting a database row.
Future<bool?> showRowDeleteModal({
  required BuildContext context,
  required String tableName,
  required List<String> columns,
  required List<dynamic> rowValues,
  TableMetadata? tableMetadata,
  required Future<bool> Function({
    required Map<String, dynamic> primaryKeys,
  }) onDelete,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _RowDeleteModalDialog(
      tableName: tableName,
      columns: columns,
      rowValues: rowValues,
      tableMetadata: tableMetadata,
      onDelete: onDelete,
    ),
  );
}

class _RowDeleteModalDialog extends StatefulWidget {
  final String tableName;
  final List<String> columns;
  final List<dynamic> rowValues;
  final TableMetadata? tableMetadata;
  final Future<bool> Function({
    required Map<String, dynamic> primaryKeys,
  }) onDelete;

  const _RowDeleteModalDialog({
    required this.tableName,
    required this.columns,
    required this.rowValues,
    required this.tableMetadata,
    required this.onDelete,
  });

  @override
  State<_RowDeleteModalDialog> createState() => _RowDeleteModalDialogState();
}

class _RowDeleteModalDialogState extends State<_RowDeleteModalDialog> {
  bool _isDeleting = false;
  String? _errorMessage;

  late final Map<String, dynamic> _primaryKeys;

  @override
  void initState() {
    super.initState();
    final pkSet = <String>{};
    if (widget.tableMetadata != null) {
      for (final col in widget.tableMetadata!.columns) {
        if (col.isPrimaryKey) {
          pkSet.add(col.name);
        }
      }
    }
    if (pkSet.isEmpty) {
      for (final col in widget.columns) {
        if (col.toLowerCase() == 'id') {
          pkSet.add(col);
          break;
        }
      }
    }

    final Map<String, dynamic> pks = {};
    if (pkSet.isNotEmpty) {
      for (final pkCol in pkSet) {
        final idx = widget.columns.indexOf(pkCol);
        if (idx != -1 && idx < widget.rowValues.length) {
          pks[pkCol] = widget.rowValues[idx];
        }
      }
    } else {
      for (int i = 0; i < widget.columns.length; i++) {
        final col = widget.columns[i];
        pks[col] = i < widget.rowValues.length ? widget.rowValues[i] : null;
      }
    }
    _primaryKeys = pks;
  }

  Future<void> _submit() async {
    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onDelete(primaryKeys: _primaryKeys);
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isDeleting = false;
          _errorMessage = 'Failed to delete row. Check server response or foreign key constraints.';
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
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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
                    child: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Confirm Delete Row',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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

            // Warning Notice & Row Details
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Are you sure you want to permanently delete this row? This action cannot be undone.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'IDENTIFYING KEY(S):',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ..._primaryKeys.entries.map((entry) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Text(
                                    '${entry.key}: ',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    entry.value?.toString() ?? 'NULL',
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: entry.value == null ? Colors.grey : Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            )),
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
                        : const Icon(Icons.delete, size: 16),
                    label: Text(_isDeleting ? 'Deleting...' : 'Delete Row', style: const TextStyle(fontSize: 12)),
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
