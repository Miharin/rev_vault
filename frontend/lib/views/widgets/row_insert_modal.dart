import 'package:flutter/material.dart';
import '../../models/table_schema.dart';

/// Cyber-styled modal dialog for inserting new rows with Supabase-style Auto Primary Key handling.
Future<bool?> showRowInsertModal({
  required BuildContext context,
  required String tableName,
  required List<String> columns,
  TableMetadata? tableMetadata,
  required Future<String?> Function({
    required Map<String, dynamic> rowValues,
  }) onInsert,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _RowInsertModalDialog(
      tableName: tableName,
      columns: columns,
      tableMetadata: tableMetadata,
      onInsert: onInsert,
    ),
  );
}

class _RowInsertModalDialog extends StatefulWidget {
  final String tableName;
  final List<String> columns;
  final TableMetadata? tableMetadata;
  final Future<String?> Function({
    required Map<String, dynamic> rowValues,
  }) onInsert;

  const _RowInsertModalDialog({
    required this.tableName,
    required this.columns,
    required this.tableMetadata,
    required this.onInsert,
  });

  @override
  State<_RowInsertModalDialog> createState() => _RowInsertModalDialogState();
}

class _RowInsertModalDialogState extends State<_RowInsertModalDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _isNullMap = {};
  final Map<String, bool> _isAutoMap = {};
  bool _isSaving = false;
  String? _errorMessage;

  Set<String> _primaryKeyCols = {};

  @override
  void initState() {
    super.initState();
    _initPrimaryKeys();

    for (int i = 0; i < widget.columns.length; i++) {
      final colName = widget.columns[i];
      final isPk = _primaryKeyCols.contains(colName);
      _controllers[colName] = TextEditingController();
      _isNullMap[colName] = false;
      // Primary keys default to Supabase-style auto-increment / database default
      _isAutoMap[colName] = isPk;
    }
  }

  void _initPrimaryKeys() {
    final pkSet = <String>{};
    if (widget.tableMetadata != null) {
      for (final col in widget.tableMetadata!.columns) {
        if (col.isPrimaryKey) {
          pkSet.add(col.name);
        }
      }
    }
    // Fallback if no explicit PK metadata: detect standard primary keys ('id', 'uuid', etc.)
    if (pkSet.isEmpty) {
      for (final col in widget.columns) {
        final lower = col.toLowerCase();
        if (lower == 'id' || lower == 'uuid') {
          pkSet.add(col);
          break;
        }
      }
    }
    if (pkSet.isEmpty) {
      for (final col in widget.columns) {
        final lower = col.toLowerCase();
        if (lower.startsWith('kd_') || lower.startsWith('id_') || lower.endsWith('_id')) {
          pkSet.add(col);
          break;
        }
      }
    }
    _primaryKeyCols = pkSet;
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  dynamic _parseValue(String raw, String colName) {
    if (_isNullMap[colName] == true) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final intVal = int.tryParse(trimmed);
    if (intVal != null && intVal.toString() == trimmed) return intVal;
    final doubleVal = double.tryParse(trimmed);
    if (doubleVal != null && trimmed.contains('.')) return doubleVal;
    if (trimmed.toLowerCase() == 'true') return true;
    if (trimmed.toLowerCase() == 'false') return false;
    return raw;
  }

  Future<void> _submit() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final Map<String, dynamic> rowValues = {};

    for (int i = 0; i < widget.columns.length; i++) {
      final col = widget.columns[i];
      // If Auto is enabled (Supabase style), exclude from INSERT statement so DB generates it
      if (_isAutoMap[col] == true) {
        continue;
      }

      final isNull = _isNullMap[col] == true;
      final rawText = _controllers[col]?.text ?? '';
      final parsed = isNull ? null : _parseValue(rawText, col);
      rowValues[col] = parsed;
    }

    try {
      final error = await widget.onInsert(rowValues: rowValues);
      if (!mounted) return;
      if (error == null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSaving = false;
          _errorMessage = error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = e.toString();
      });
    }
  }

  ColumnMetadata? _getColumnMeta(String colName) {
    if (widget.tableMetadata == null) return null;
    for (final col in widget.tableMetadata!.columns) {
      if (col.name.toLowerCase() == colName.toLowerCase()) {
        return col;
      }
    }
    return null;
  }

  String _shortenType(String raw) {
    var t = raw.toUpperCase().trim();
    t = t.replaceAll('WITHOUT TIME ZONE', '').trim();
    t = t.replaceAll('CHARACTER VARYING', 'VARCHAR').trim();
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: primary.withValues(alpha: 0.25), width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.12),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Glowing Laser Perimeter Bar
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primary.withValues(alpha: 0.1),
                        primary,
                        primary.withValues(alpha: 0.1),
                      ],
                    ),
                  ),
                ),

                // Modal Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                    ),
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.add_box_outlined, color: Color(0xFF14B8A6), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            const Text(
                              'Insert New Row',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.3),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: primary.withValues(alpha: 0.3), width: 0.8),
                              ),
                              child: Text(
                                widget.tableName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  color: primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ),

                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
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

                // Form Fields
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(14),
                    shrinkWrap: true,
                    itemCount: widget.columns.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, idx) {
                      final colName = widget.columns[idx];
                      final isNull = _isNullMap[colName] == true;
                      final isAuto = _isAutoMap[colName] == true;
                      final ctrl = _controllers[colName]!;
                      final colMeta = _getColumnMeta(colName);
                      final isPk = _primaryKeyCols.contains(colName) || (colMeta?.isPrimaryKey == true);
                      final isFk = colMeta?.foreignKey != null;
                      final fk = colMeta?.foreignKey;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isAuto
                                ? Colors.teal.withValues(alpha: 0.4)
                                : theme.dividerColor.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Column Identification
                                SizedBox(
                                  width: 175,
                                  child: Row(
                                    children: [
                                      if (isPk) ...[
                                        Tooltip(
                                          message: 'Primary Key',
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            margin: const EdgeInsets.only(right: 5),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withValues(alpha: 0.18),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.vpn_key_rounded, size: 9, color: Colors.amber),
                                                SizedBox(width: 2),
                                                Text(
                                                  'PK',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'monospace',
                                                    color: Colors.amber,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (isFk) ...[
                                        Tooltip(
                                          message: 'Foreign Key → ${fk!.targetTable}.${fk.targetColumn}',
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            margin: const EdgeInsets.only(right: 5),
                                            decoration: BoxDecoration(
                                              color: Colors.cyan.withValues(alpha: 0.18),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.cyan.withValues(alpha: 0.5), width: 0.8),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.link, size: 9, color: Colors.cyanAccent),
                                                SizedBox(width: 2),
                                                Text(
                                                  'FK',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'monospace',
                                                    color: Colors.cyanAccent,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                      Expanded(
                                        child: Text(
                                          colName,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 8),

                                // Data Type Badge
                                if (colMeta != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _shortenType(colMeta.dataType),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontFamily: 'monospace',
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],

                                const Spacer(),

                                // Supabase-style Auto Toggle for PK
                                if (isPk) ...[
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _isAutoMap[colName] = !isAuto;
                                        if (_isAutoMap[colName] == true) {
                                          _isNullMap[colName] = false;
                                        }
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isAuto
                                            ? Colors.teal.withValues(alpha: 0.2)
                                            : Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isAuto
                                              ? Colors.teal.withValues(alpha: 0.6)
                                              : Colors.grey.withValues(alpha: 0.3),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isAuto ? Icons.auto_awesome : Icons.edit,
                                            size: 10,
                                            color: isAuto ? Colors.tealAccent : Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isAuto ? 'Auto (DB Default)' : 'Manual PK',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: isAuto ? Colors.tealAccent : Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],

                                // Set NULL Toggle
                                if (!isAuto)
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _isNullMap[colName] = !isNull;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isNull
                                            ? Colors.orange.withValues(alpha: 0.2)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isNull
                                              ? Colors.orange.withValues(alpha: 0.6)
                                              : theme.dividerColor.withValues(alpha: 0.3),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        'NULL',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontFamily: 'monospace',
                                          fontWeight: isNull ? FontWeight.bold : FontWeight.normal,
                                          color: isNull ? Colors.orangeAccent : Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 5),

                            // Value Input Field
                            if (isAuto)
                              Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.bolt, size: 12, color: Colors.tealAccent),
                                    SizedBox(width: 6),
                                    Text(
                                      'Auto-generated by database (omitted from INSERT)',
                                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.tealAccent),
                                    ),
                                  ],
                                ),
                              )
                            else if (isNull)
                              Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  '<NULL>',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    fontFamily: 'monospace',
                                    color: Colors.grey.withValues(alpha: 0.6),
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                height: 32,
                                child: TextField(
                                  controller: ctrl,
                                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                                  decoration: InputDecoration(
                                    hintText: 'Enter value...',
                                    hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    filled: true,
                                    fillColor: theme.colorScheme.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(5),
                                      borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(5),
                                      borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(5),
                                      borderSide: BorderSide(color: primary, width: 1.2),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Modal Footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                    border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _submit,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.add_circle_outline, size: 15),
                        label: Text(_isSaving ? 'Inserting...' : 'Insert Record', style: const TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14B8A6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
