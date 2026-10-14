import 'dart:convert';
import 'package:flutter/material.dart';
import '../../models/table_schema.dart';
import 'cyber_text_field.dart';

/// Cyber-styled Data Importer modal supporting CSV and JSON text/file imports with column mapping.
Future<bool?> showDataImportModal({
  required BuildContext context,
  required TableMetadata table,
  required Future<bool> Function({
    required List<Map<String, dynamic>> rows,
    bool truncateFirst,
  }) onImportRows,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _DataImportModalDialog(
      table: table,
      onImportRows: onImportRows,
    ),
  );
}

class _DataImportModalDialog extends StatefulWidget {
  final TableMetadata table;
  final Future<bool> Function({
    required List<Map<String, dynamic>> rows,
    bool truncateFirst,
  }) onImportRows;

  const _DataImportModalDialog({
    required this.table,
    required this.onImportRows,
  });

  @override
  State<_DataImportModalDialog> createState() => _DataImportModalDialogState();
}

class _DataImportModalDialogState extends State<_DataImportModalDialog> {
  final TextEditingController _rawInputCtrl = TextEditingController();
  bool _truncateFirst = false;
  bool _isImporting = false;
  String? _errorMessage;

  List<String> _sourceFields = [];
  List<Map<String, dynamic>> _parsedRecords = [];
  final Map<String, String?> _columnMappings = {}; // DB Column -> Source Field

  @override
  void initState() {
    super.initState();
    // Pre-populate 1:1 mappings if names match
    for (final col in widget.table.columns) {
      _columnMappings[col.name] = null;
    }
  }

  @override
  void dispose() {
    _rawInputCtrl.dispose();
    super.dispose();
  }

  void _parseData() {
    final text = _rawInputCtrl.text.trim();
    if (text.isEmpty) {
      setState(() {
        _sourceFields = [];
        _parsedRecords = [];
        _errorMessage = 'Input data cannot be empty.';
      });
      return;
    }

    try {
      if (text.startsWith('[') || text.startsWith('{')) {
        // Parse JSON
        final dynamic decoded = jsonDecode(text);
        final List<dynamic> list = decoded is List ? decoded : [decoded];
        if (list.isEmpty) throw const FormatException('Empty JSON array');

        final first = list.first as Map<String, dynamic>;
        final fields = first.keys.toList();
        final records = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        setState(() {
          _sourceFields = fields;
          _parsedRecords = records;
          _autoMapFields(fields);
          _errorMessage = null;
        });
      } else {
        // Parse CSV
        final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
        if (lines.length < 2) {
          throw const FormatException('CSV must contain a header row and at least one data row.');
        }

        final headers = lines[0].split(',').map((h) => h.trim().replaceAll('"', '')).toList();
        final records = <Map<String, dynamic>>[];

        for (int i = 1; i < lines.length; i++) {
          final parts = lines[i].split(',').map((p) => p.trim().replaceAll('"', '')).toList();
          final map = <String, dynamic>{};
          for (int h = 0; h < headers.length; h++) {
            map[headers[h]] = h < parts.length ? parts[h] : null;
          }
          records.add(map);
        }

        setState(() {
          _sourceFields = headers;
          _parsedRecords = records;
          _autoMapFields(headers);
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _sourceFields = [];
        _parsedRecords = [];
        _errorMessage = 'Failed to parse data: $e';
      });
    }
  }

  void _autoMapFields(List<String> fields) {
    for (final col in widget.table.columns) {
      final match = fields.firstWhere(
        (f) => f.toLowerCase() == col.name.toLowerCase(),
        orElse: () => '',
      );
      if (match.isNotEmpty) {
        _columnMappings[col.name] = match;
      }
    }
  }

  Future<void> _submit() async {
    if (_parsedRecords.isEmpty) {
      _parseData();
      if (_parsedRecords.isEmpty) return;
    }

    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final rowsToInsert = <Map<String, dynamic>>[];

      for (final rec in _parsedRecords) {
        final row = <String, dynamic>{};
        _columnMappings.forEach((dbCol, srcField) {
          if (srcField != null && srcField.isNotEmpty) {
            row[dbCol] = rec[srcField];
          }
        });
        if (row.isNotEmpty) {
          rowsToInsert.add(row);
        }
      }

      if (rowsToInsert.isEmpty) {
        setState(() {
          _isImporting = false;
          _errorMessage = 'No mapped fields selected for import.';
        });
        return;
      }

      final success = await widget.onImportRows(
        rows: rowsToInsert,
        truncateFirst: _truncateFirst,
      );

      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isImporting = false;
          _errorMessage = 'Import failed. Check server response or datatype mismatch.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: primary.withValues(alpha: 0.35)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        child: Column(
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
                    child: Icon(Icons.file_upload_outlined, color: primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Import Data (CSV / JSON)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'Destination: ${widget.table.name}',
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

            // Main Content: Input Paste + Field Mapping
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Pane: Raw Input
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'PASTE RAW CSV OR JSON DATA:',
                                style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.grey),
                              ),
                              OutlinedButton.icon(
                                onPressed: _parseData,
                                icon: const Icon(Icons.sync, size: 13),
                                label: const Text('Parse Fields', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: CyberTextField(
                              controller: _rawInputCtrl,
                              maxLines: null,
                              expands: true,
                              isMonospace: true,
                              fontSize: 11,
                              hintText: 'id,name,email\n1,Alice,alice@example.com\n2,Bob,bob@example.com\n\n-- OR JSON --\n[{"name": "Alice", "email": "alice@example.com"}]',
                              contentPadding: const EdgeInsets.all(12),
                              fillColor: const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Right Pane: Field Mapping
                    Expanded(
                      flex: 4,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'COLUMN MAPPING (${_parsedRecords.length} records detected)',
                              style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.grey),
                            ),
                            const SizedBox(height: 8),
                            if (_sourceFields.isEmpty)
                              const Expanded(
                                child: Center(
                                  child: Text(
                                    'Paste data on the left and click "Parse Fields" to map columns.',
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            else
                              Expanded(
                                child: ListView.separated(
                                  itemCount: widget.table.columns.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                                  itemBuilder: (context, idx) {
                                    final col = widget.table.columns[idx];
                                    final currentMapped = _columnMappings[col.name];

                                    return Row(
                                      children: [
                                        Expanded(
                                          flex: 4,
                                          child: Text(
                                            col.name,
                                            style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Text(' \u2190 ', style: TextStyle(color: Colors.grey)),
                                        Expanded(
                                          flex: 5,
                                          child: SizedBox(
                                            height: 32,
                                            child: DropdownButtonFormField<String?>(
                                              initialValue: currentMapped,
                                              isDense: true,
                                              decoration: const InputDecoration(
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                                border: OutlineInputBorder(),
                                              ),
                                              items: [
                                                const DropdownMenuItem<String?>(
                                                  value: null,
                                                  child: Text('(Skip)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                                ),
                                                ..._sourceFields.map((f) => DropdownMenuItem<String?>(
                                                      value: f,
                                                      child: Text(f, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                                                    )),
                                              ],
                                              onChanged: (v) => setState(() => _columnMappings[col.name] = v),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 8),
                            // Truncate first option
                            Row(
                              children: [
                                Checkbox(
                                  value: _truncateFirst,
                                  onChanged: (v) => setState(() => _truncateFirst = v ?? false),
                                  activeColor: Colors.amber,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                const Expanded(
                                  child: Text(
                                    'Truncate table before importing',
                                    style: TextStyle(fontSize: 11.5, color: Colors.amberAccent),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
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
                    onPressed: _isImporting ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isImporting ? null : _submit,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.file_upload, size: 16),
                    label: Text(
                      _isImporting ? 'Importing Data...' : 'Import ${_parsedRecords.length} Rows',
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
