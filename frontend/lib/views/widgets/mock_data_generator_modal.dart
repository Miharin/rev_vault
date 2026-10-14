import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/table_schema.dart';

/// Cyber-styled dialog to generate and insert synthetic mock records into a database table.
Future<bool?> showMockDataGeneratorModal({
  required BuildContext context,
  required TableMetadata table,
  required Future<bool> Function(List<Map<String, dynamic>> rows) onInsertMockRows,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _MockDataGeneratorModalDialog(
      table: table,
      onInsertMockRows: onInsertMockRows,
    ),
  );
}

class _MockDataGeneratorModalDialog extends StatefulWidget {
  final TableMetadata table;
  final Future<bool> Function(List<Map<String, dynamic>> rows) onInsertMockRows;

  const _MockDataGeneratorModalDialog({
    required this.table,
    required this.onInsertMockRows,
  });

  @override
  State<_MockDataGeneratorModalDialog> createState() => _MockDataGeneratorModalDialogState();
}

class _MockDataGeneratorModalDialogState extends State<_MockDataGeneratorModalDialog> {
  int _rowCount = 25;
  bool _isGenerating = false;
  String? _errorMessage;

  final math.Random _rng = math.Random();

  static const List<String> _firstNames = ['Alex', 'Jordan', 'Taylor', 'Morgan', 'Casey', 'Riley', 'Avery', 'Sam', 'Logan', 'Dakota'];
  static const List<String> _lastNames = ['Vance', 'Sterling', 'Mercer', 'Reeves', 'Bishop', 'Sinclair', 'Winter', 'Frost', 'Cross', 'Hale'];
  static const List<String> _domains = ['relva.io', 'cybervault.dev', 'synthetix.org', 'cloudops.net'];
  static const List<String> _statuses = ['active', 'pending', 'verified', 'archived', 'processing'];
  static const List<String> _titles = ['Project Alpha', 'Telemetry Core', 'Quantum Sensor', 'Orbital Module', 'Relay Hub', 'Matrix Gate'];

  Map<String, dynamic> _generateSingleRow(int index) {
    final row = <String, dynamic>{};

    for (final col in widget.table.columns) {
      final colName = col.name.toLowerCase();

      // Skip auto-increment primary keys
      if (col.isPrimaryKey && (col.dataType.toUpperCase().contains('INT') || col.dataType.toUpperCase().contains('SERIAL'))) {
        continue;
      }

      final type = col.dataType.toUpperCase();

      if (colName.contains('email')) {
        final f = _firstNames[_rng.nextInt(_firstNames.length)].toLowerCase();
        final l = _lastNames[_rng.nextInt(_lastNames.length)].toLowerCase();
        final d = _domains[_rng.nextInt(_domains.length)];
        row[col.name] = '$f.$l${index + 1}@$d';
      } else if (colName.contains('name') || colName.contains('author') || colName.contains('user')) {
        final f = _firstNames[_rng.nextInt(_firstNames.length)];
        final l = _lastNames[_rng.nextInt(_lastNames.length)];
        row[col.name] = '$f $l';
      } else if (colName.contains('status')) {
        row[col.name] = _statuses[_rng.nextInt(_statuses.length)];
      } else if (colName.contains('title') || colName.contains('item') || colName.contains('product')) {
        final t = _titles[_rng.nextInt(_titles.length)];
        row[col.name] = '$t #${100 + index}';
      } else if (colName.contains('sku') || colName.contains('code')) {
        row[col.name] = 'SKU-${_rng.nextInt(9000) + 1000}';
      } else if (colName.contains('uuid') || colName.contains('guid')) {
        row[col.name] = '00000000-0000-4000-8000-${(100000000000 + index).toString()}';
      } else if (type.contains('INT')) {
        row[col.name] = _rng.nextInt(1000) + 1;
      } else if (type.contains('NUM') || type.contains('REAL') || type.contains('DOUBLE') || type.contains('FLOAT') || type.contains('DECIMAL')) {
        row[col.name] = double.parse((_rng.nextDouble() * 500 + 10).toStringAsFixed(2));
      } else if (type.contains('BOOL')) {
        row[col.name] = _rng.nextBool();
      } else if (type.contains('TIME') || type.contains('DATE')) {
        final now = DateTime.now().subtract(Duration(days: _rng.nextInt(60), hours: _rng.nextInt(24)));
        row[col.name] = now.toIso8601String();
      } else {
        row[col.name] = 'Sample ${col.name} ${index + 1}';
      }
    }

    return row;
  }

  Future<void> _submit() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final rows = List.generate(_rowCount, (i) => _generateSingleRow(i));
      final success = await widget.onInsertMockRows(rows);

      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isGenerating = false;
          _errorMessage = 'Failed to insert mock data into table. Check constraint errors.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final samplePreview = _generateSingleRow(0);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: primary.withValues(alpha: 0.35)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                ),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.auto_awesome, color: primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Generate Synthetic Mock Data',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'Target: ${widget.table.name} (${widget.table.columns.length} columns)',
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

            // Content
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select how many synthetic records to generate and populate into this table:',
                    style: TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),

                  // Preset Row Count Chips
                  Row(
                    children: [10, 25, 50, 100, 250].map((count) {
                      final isSelected = _rowCount == count;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('$count Rows', style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : null)),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) setState(() => _rowCount = count);
                          },
                          selectedColor: primary,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Sample Generated Preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SYNTHETIC RECORD PREVIEW (Sample 1 of N):',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: Colors.cyanAccent,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...samplePreview.entries.take(6).map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Text(
                                    '${e.key}: ',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${e.value}',
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11.5,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        if (samplePreview.length > 6)
                          Text(
                            '+ ${samplePreview.length - 6} more columns...',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Actions
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
                    onPressed: _isGenerating ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isGenerating ? null : _submit,
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(
                      _isGenerating ? 'Inserting $_rowCount Rows...' : 'Generate & Insert $_rowCount Rows',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
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
