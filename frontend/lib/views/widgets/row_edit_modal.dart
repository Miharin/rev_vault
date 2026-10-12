import 'package:flutter/material.dart';
import '../../models/table_schema.dart';

/// Cyber-styled modal dialog for editing row cells with primary key detection.
Future<bool?> showRowEditModal({
  required BuildContext context,
  required String tableName,
  required List<String> columns,
  required List<dynamic> rowValues,
  TableMetadata? tableMetadata,
  required Future<bool> Function({
    required Map<String, dynamic> primaryKeys,
    required Map<String, dynamic> updatedValues,
  }) onSave,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _RowEditModalDialog(
      tableName: tableName,
      columns: columns,
      rowValues: rowValues,
      tableMetadata: tableMetadata,
      onSave: onSave,
    ),
  );
}

class _RowEditModalDialog extends StatefulWidget {
  final String tableName;
  final List<String> columns;
  final List<dynamic> rowValues;
  final TableMetadata? tableMetadata;
  final Future<bool> Function({
    required Map<String, dynamic> primaryKeys,
    required Map<String, dynamic> updatedValues,
  }) onSave;

  const _RowEditModalDialog({
    required this.tableName,
    required this.columns,
    required this.rowValues,
    required this.tableMetadata,
    required this.onSave,
  });

  @override
  State<_RowEditModalDialog> createState() => _RowEditModalDialogState();
}

class _RowEditModalDialogState extends State<_RowEditModalDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _isNullMap = {};
  bool _isSaving = false;
  String? _errorMessage;

  Set<String> _primaryKeyCols = {};

  @override
  void initState() {
    super.initState();
    _initPrimaryKeys();

    for (int i = 0; i < widget.columns.length; i++) {
      final colName = widget.columns[i];
      final val = i < widget.rowValues.length ? widget.rowValues[i] : null;
      _isNullMap[colName] = val == null;
      final ctrl = TextEditingController(text: val == null ? '' : val.toString());
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });
      _controllers[colName] = ctrl;
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
    // Fallback if no explicit PK: detect primary identity columns ('id', 'kd_*', '*_id', 'uuid')
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
  void didUpdateWidget(covariant _RowEditModalDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableMetadata != widget.tableMetadata || oldWidget.columns != widget.columns) {
      _initPrimaryKeys();
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _extractPrimaryKeys() {
    final Map<String, dynamic> pks = {};
    if (_primaryKeyCols.isNotEmpty) {
      for (final pkCol in _primaryKeyCols) {
        final idx = widget.columns.indexOf(pkCol);
        if (idx != -1 && idx < widget.rowValues.length) {
          pks[pkCol] = widget.rowValues[idx];
        }
      }
    } else {
      // Compound key fallback: all column values
      for (int i = 0; i < widget.columns.length; i++) {
        final col = widget.columns[i];
        pks[col] = i < widget.rowValues.length ? widget.rowValues[i] : null;
      }
    }
    return pks;
  }

  dynamic _parseValue(String raw, String colName) {
    if (_isNullMap[colName] == true) return null;
    final trimmed = raw.trim();
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

    final primaryKeys = _extractPrimaryKeys();
    final Map<String, dynamic> updatedValues = {};

    for (int i = 0; i < widget.columns.length; i++) {
      final col = widget.columns[i];
      final isNull = _isNullMap[col] == true;
      final rawText = _controllers[col]?.text ?? '';
      final parsed = isNull ? null : _parseValue(rawText, col);
      final original = i < widget.rowValues.length ? widget.rowValues[i] : null;

      if (parsed != original) {
        updatedValues[col] = parsed;
      }
    }

    if (updatedValues.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }

    try {
      final success = await widget.onSave(
        primaryKeys: primaryKeys,
        updatedValues: updatedValues,
      );
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to update record. Check logs or constraints.';
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
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 580),
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
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: primary.withValues(alpha: 0.3)),
                        ),
                        child: Icon(Icons.edit_note_rounded, color: primary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            const Text(
                              'Edit Row Record',
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

                // Form Fields (Compact & Simple Layout with Informational Badges)
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(14),
                    shrinkWrap: true,
                    itemCount: widget.columns.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, idx) {
                      final colName = widget.columns[idx];
                      final isNull = _isNullMap[colName] == true;
                      final ctrl = _controllers[colName]!;
                      final originalVal = idx < widget.rowValues.length ? widget.rowValues[idx] : null;
                      final origStr = originalVal == null ? null : originalVal.toString();
                      final currentStr = isNull ? null : ctrl.text;
                      final isModified = isNull ? (originalVal != null) : (currentStr != origStr);
                      final colMeta = _getColumnMeta(colName);
                      final isPk = _primaryKeyCols.contains(colName) || (colMeta?.isPrimaryKey == true);
                      final isFk = colMeta?.foreignKey != null;
                      final fk = colMeta?.foreignKey;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isModified
                              ? primary.withValues(alpha: 0.05)
                              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isModified
                                ? primary.withValues(alpha: 0.6)
                                : theme.dividerColor.withValues(alpha: 0.2),
                            width: isModified ? 1.2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Column Identification Section (PK/FK badges, Name, Type)
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
                                              color: primary.withValues(alpha: 0.18),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: primary.withValues(alpha: 0.5), width: 0.8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.vpn_key_rounded, size: 9, color: primary),
                                                const SizedBox(width: 2),
                                                Text(
                                                  'PK',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'monospace',
                                                    color: primary,
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
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              colName,
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                                fontWeight: (isModified || isPk) ? FontWeight.bold : FontWeight.w600,
                                                color: isModified ? primary : null,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (colMeta != null && colMeta.dataType.isNotEmpty)
                                              Text(
                                                _shortenType(colMeta.dataType),
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontFamily: 'monospace',
                                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),

                                // Text Field
                                Expanded(
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      controller: ctrl,
                                      enabled: !isNull && !_isSaving,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: isNull ? theme.colorScheme.onSurface.withValues(alpha: 0.3) : null,
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: isNull ? 'NULL' : '',
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                        filled: true,
                                        fillColor: isNull
                                            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.1)
                                            : theme.colorScheme.surface,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(4),
                                          borderSide: BorderSide(
                                            color: isModified ? primary.withValues(alpha: 0.5) : theme.dividerColor.withValues(alpha: 0.25),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(4),
                                          borderSide: BorderSide(
                                            color: isModified ? primary.withValues(alpha: 0.7) : theme.dividerColor.withValues(alpha: 0.25),
                                            width: isModified ? 1.2 : 1,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(4),
                                          borderSide: BorderSide(color: primary, width: 1.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // Revert Button (if modified)
                                if (isModified) ...[
                                  Tooltip(
                                    message: 'Revert field',
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _isNullMap[colName] = originalVal == null;
                                          ctrl.text = origStr ?? '';
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(Icons.undo, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],

                                // NULL Toggle
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _isNullMap[colName] = !isNull;
                                      if (!isNull) {
                                        ctrl.clear();
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isNull
                                          ? Colors.amber.withValues(alpha: 0.2)
                                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isNull
                                            ? Colors.amber.withValues(alpha: 0.6)
                                            : theme.dividerColor.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Text(
                                      'NULL',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: isNull ? Colors.amber : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Subtle inline diff beneath field
                            if (isModified) ...[
                              const SizedBox(height: 3),
                              Padding(
                                padding: const EdgeInsets.only(left: 185),
                                child: Row(
                                  children: [
                                    Text(
                                      'Was: ',
                                      style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                                    ),
                                    Text(
                                      origStr ?? 'NULL',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontFamily: 'monospace',
                                        color: Colors.redAccent,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_rounded, size: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Now: ',
                                      style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                                    ),
                                    Text(
                                      currentStr ?? 'NULL',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        color: primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Modal Actions
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                    ),
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                  ),
                  child: Builder(
                    builder: (context) {
                      int modifiedCount = 0;
                      for (int i = 0; i < widget.columns.length; i++) {
                        final c = widget.columns[i];
                        final isNull = _isNullMap[c] == true;
                        final orig = i < widget.rowValues.length ? widget.rowValues[i] : null;
                        final origStr = orig == null ? null : orig.toString();
                        final curStr = isNull ? null : _controllers[c]?.text;
                        if (isNull ? (orig != null) : (curStr != origStr)) {
                          modifiedCount++;
                        }
                      }

                      return Row(
                        children: [
                          if (modifiedCount > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: primary.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                '$modifiedCount modified',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Reset all modified fields',
                              child: InkWell(
                                onTap: _isSaving
                                    ? null
                                    : () {
                                        setState(() {
                                          for (int i = 0; i < widget.columns.length; i++) {
                                            final c = widget.columns[i];
                                            final orig = i < widget.rowValues.length ? widget.rowValues[i] : null;
                                            _isNullMap[c] = orig == null;
                                            _controllers[c]?.text = orig == null ? '' : orig.toString();
                                          }
                                        });
                                      },
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.undo, size: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                                      const SizedBox(width: 2),
                                      Text(
                                        'Reset',
                                        style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ] else
                            Text(
                              'No changes',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: (_isSaving || modifiedCount == 0) ? null : _submit,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Save Changes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      );
                    },
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
