import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/table_schema.dart';
import 'cyber_checkbox.dart';

/// Ultra-high performance virtualized data table for large datasets.
/// Uses ListView.builder with fixed itemExtent for O(1) row recycling,
/// synchronized dual horizontal scrolling, sticky headers, and AAA cyber HUD aesthetics.
class VirtualizedDataTable extends StatefulWidget {
  final List<String> columns;
  final List<List<dynamic>> rows;
  final int? sortColumnIndex;
  final bool sortAscending;
  final void Function(int columnIndex, bool ascending)? onSort;
  final void Function(String column, dynamic value)? onFilterByCellValue;
  final void Function(int rowIndex, List<dynamic> rowValues)? onEditRow;
  final void Function(int rowIndex, List<dynamic> rowValues)? onDeleteRow;
  final void Function(int rowIndex, List<dynamic> rowValues)? onDuplicateRow;
  final Future<bool> Function(int rowIndex, String column, dynamic oldValue, dynamic newValue)? onInlineCellSave;
  final bool isSafeMode;
  final bool showColumnDetails;
  final bool isSelectionMode;
  final TableMetadata? tableMetadata;
  final List<TableMetadata>? allTables;
  final Set<int>? selectedRowIndices;
  final void Function(int rowIndex)? onToggleRowSelection;
  final void Function(int targetIndex)? onRangeSelectRow;
  final void Function()? onSelectAll;
  final void Function()? onClearSelection;
  final void Function(List<int> selectedIndices)? onBulkDelete;
  final void Function(List<int> selectedIndices)? onBulkDuplicate;
  final void Function(List<int> selectedIndices)? onBulkExport;

  const VirtualizedDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSort,
    this.onFilterByCellValue,
    this.onEditRow,
    this.onDeleteRow,
    this.onDuplicateRow,
    this.onInlineCellSave,
    this.isSafeMode = true,
    this.showColumnDetails = false,
    this.isSelectionMode = false,
    this.tableMetadata,
    this.allTables,
    this.selectedRowIndices,
    this.onToggleRowSelection,
    this.onRangeSelectRow,
    this.onSelectAll,
    this.onClearSelection,
    this.onBulkDelete,
    this.onBulkDuplicate,
    this.onBulkExport,
  });

  @override
  State<VirtualizedDataTable> createState() => _VirtualizedDataTableState();
}

class _VirtualizedDataTableState extends State<VirtualizedDataTable> {
  final ScrollController _horizontalHeaderCtrl = ScrollController();
  final ScrollController _horizontalBodyCtrl = ScrollController();
  final ScrollController _verticalRowsCtrl = ScrollController();

  bool _isSyncingHeader = false;
  bool _isSyncingBody = false;

  int? _hoveredRowIndex;
  int? _editingRowIndex;
  int? _editingColIndex;
  TextEditingController? _inlineEditCtrl;
  FocusNode? _inlineFocusNode;

  static const double _rowHeight = 32.0;
  static const double _selectionColWidth = 38.0;
  static const double _indexColWidth = 52.0;
  static const double _actionsColWidth = 64.0;
  static const double _defaultColWidth = 140.0;

  @override
  void initState() {
    super.initState();

    _horizontalHeaderCtrl.addListener(() {
      if (_isSyncingHeader) return;
      _isSyncingBody = true;
      if (_horizontalBodyCtrl.hasClients &&
          _horizontalBodyCtrl.offset != _horizontalHeaderCtrl.offset) {
        _horizontalBodyCtrl.jumpTo(_horizontalHeaderCtrl.offset);
      }
      _isSyncingBody = false;
    });

    _horizontalBodyCtrl.addListener(() {
      if (_isSyncingBody) return;
      _isSyncingHeader = true;
      if (_horizontalHeaderCtrl.hasClients &&
          _horizontalHeaderCtrl.offset != _horizontalBodyCtrl.offset) {
        _horizontalHeaderCtrl.jumpTo(_horizontalBodyCtrl.offset);
      }
      _isSyncingHeader = false;
    });
  }

  @override
  void dispose() {
    _inlineEditCtrl?.dispose();
    _inlineFocusNode?.dispose();
    _horizontalHeaderCtrl.dispose();
    _horizontalBodyCtrl.dispose();
    _verticalRowsCtrl.dispose();
    super.dispose();
  }

  void _startInlineEdit(int rowIndex, int colIndex, dynamic initialValue) {
    if (widget.onInlineCellSave == null) return;
    _inlineEditCtrl?.dispose();
    _inlineFocusNode?.dispose();

    final text = initialValue == null ? '' : initialValue.toString();
    final ctrl = TextEditingController(text: text);
    final focus = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelInlineEdit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    setState(() {
      _editingRowIndex = rowIndex;
      _editingColIndex = colIndex;
      _inlineEditCtrl = ctrl;
      _inlineFocusNode = focus;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _inlineFocusNode != null) {
        _inlineFocusNode!.requestFocus();
        ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
      }
    });
  }

  void _cancelInlineEdit() {
    if (_editingRowIndex != null || _editingColIndex != null) {
      _inlineEditCtrl?.dispose();
      _inlineFocusNode?.dispose();
      setState(() {
        _editingRowIndex = null;
        _editingColIndex = null;
        _inlineEditCtrl = null;
        _inlineFocusNode = null;
      });
    }
  }

  Future<void> _commitInlineEdit() async {
    if (_editingRowIndex == null || _editingColIndex == null) return;
    final rIdx = _editingRowIndex!;
    final cIdx = _editingColIndex!;
    if (cIdx >= widget.columns.length || rIdx >= widget.rows.length) {
      _cancelInlineEdit();
      return;
    }

    final colName = widget.columns[cIdx];
    final row = widget.rows[rIdx];
    final dynamic oldVal = cIdx < row.length ? row[cIdx] : null;
    final newText = _inlineEditCtrl?.text.trim() ?? '';

    final oldStr = oldVal == null ? '' : oldVal.toString().trim();
    if (newText == oldStr) {
      _cancelInlineEdit();
      return;
    }

    dynamic parsedNewVal;
    if (newText.isEmpty) {
      parsedNewVal = null;
    } else if (oldVal is int || (int.tryParse(newText) != null && (oldVal == null || oldVal is int))) {
      parsedNewVal = int.tryParse(newText) ?? newText;
    } else if (oldVal is double || (double.tryParse(newText) != null && oldVal is double)) {
      parsedNewVal = double.tryParse(newText) ?? newText;
    } else if (oldVal is bool) {
      parsedNewVal = newText.toLowerCase() == 'true';
    } else {
      parsedNewVal = newText;
    }

    _cancelInlineEdit();
    if (widget.onInlineCellSave != null) {
      await widget.onInlineCellSave!(rIdx, colName, oldVal, parsedNewVal);
    }
  }

  ColumnMetadata? _getColumnMeta(String colName) {
    if (widget.tableMetadata == null) return null;
    final cleanCol = colName.trim().replaceAll('"', '').replaceAll('`', '');
    final rawCol = cleanCol.contains('.') ? cleanCol.split('.').last : cleanCol;

    for (final col in widget.tableMetadata!.columns) {
      if (col.name.toLowerCase() == cleanCol.toLowerCase() ||
          col.name.toLowerCase() == rawCol.toLowerCase()) {
        return col;
      }
    }
    return null;
  }

  String _inferColumnTypeFromRows(String colName) {
    final idx = widget.columns.indexOf(colName);
    if (idx == -1 || widget.rows.isEmpty) return 'TEXT';
    for (int i = 0; i < math.min(15, widget.rows.length); i++) {
      if (idx < widget.rows[i].length) {
        final val = widget.rows[i][idx];
        if (val != null) {
          if (val is int) return 'INT';
          if (val is double) return 'FLOAT';
          if (val is bool) return 'BOOL';
          final s = val.toString().trim();
          if (s.isEmpty) continue;
          if (int.tryParse(s) != null) return 'INT';
          if (double.tryParse(s) != null) return 'FLOAT';
          if (s.toLowerCase() == 'true' || s.toLowerCase() == 'false') return 'BOOL';
          if (s.length >= 10 && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return 'TIMESTAMP';
          return 'TEXT';
        }
      }
    }
    return 'TEXT';
  }

  double get _effectiveActionsColWidth =>
      (widget.onDuplicateRow != null) ? 88.0 : _actionsColWidth;

  String? _determineCandidatePrimaryKey(List<String> cols, TableMetadata? tableMeta) {
    final lowerCols = cols.map((c) => c.trim().replaceAll('"', '').replaceAll('`', '').split('.').last.toLowerCase()).toList();
    // 1. Direct identifier columns: single_id, id, uuid
    for (final target in ['single_id', 'id', 'uuid']) {
      final idx = lowerCols.indexOf(target);
      if (idx != -1) return cols[idx];
    }
    // 2. Table-specific id (e.g. cara_keluar_id, id_cara_keluar)
    if (tableMeta != null) {
      final rawName = tableMeta.rawName.toLowerCase();
      final idx1 = lowerCols.indexOf('${rawName}_id');
      if (idx1 != -1) return cols[idx1];
      final idx2 = lowerCols.indexOf('id_$rawName');
      if (idx2 != -1) return cols[idx2];
    }
    // 3. First column ending with _id or starting with id_ that isn't a foreign key pattern
    for (int i = 0; i < cols.length; i++) {
      final lower = lowerCols[i];
      if ((lower.endsWith('_id') || lower.startsWith('id_')) &&
          !lower.startsWith('kd_') &&
          !lower.contains('transaksi') &&
          !lower.contains('kunjungan') &&
          !lower.contains('user') &&
          !lower.contains('pasien') &&
          !lower.contains('parent')) {
        return cols[i];
      }
    }
    return null;
  }

  String? _findMatchingTable(String entity, List<TableMetadata>? allTables) {
    if (allTables == null || allTables.isEmpty) {
      if (entity == 'transaksi') return 'transaksi';
      if (entity == 'kunjungan') return 'kunjungan';
      if (entity == 'user') return 'users';
      return null;
    }

    final entityLower = entity.toLowerCase();
    // Direct rawName match
    for (final t in allTables) {
      if (t.rawName.toLowerCase() == entityLower) return t.rawName;
    }
    // Plural match (e.g. user -> users)
    for (final t in allTables) {
      if (t.rawName.toLowerCase() == '${entityLower}s') return t.rawName;
    }
    // Prefix match (e.g. transaksi -> transaksi)
    for (final t in allTables) {
      if (t.rawName.toLowerCase().startsWith(entityLower)) return t.rawName;
    }
    return null;
  }

  ForeignKeyMetadata? _inferForeignKey(String colName, List<TableMetadata>? allTables) {
    final clean = colName.trim().replaceAll('"', '').replaceAll('`', '');
    final lower = clean.contains('.') ? clean.split('.').last.toLowerCase() : clean.toLowerCase();

    // Primary keys are not foreign keys
    if (lower == 'id' || lower == 'uuid' || lower == 'single_id') return null;

    // 1. Cross-check against other tables where this column is their primary key
    if (allTables != null && allTables.isNotEmpty) {
      for (final t in allTables) {
        if (widget.tableMetadata != null &&
            (t.name.toLowerCase() == widget.tableMetadata!.name.toLowerCase() ||
             t.rawName.toLowerCase() == widget.tableMetadata!.rawName.toLowerCase())) {
          continue;
        }
        for (final col in t.columns) {
          if (col.isPrimaryKey && col.name.toLowerCase() == lower) {
            return ForeignKeyMetadata(
              columnName: colName,
              targetTable: t.rawName,
              targetColumn: col.name,
              constraintName: 'inferred_pk_match',
            );
          }
        }
      }
    }

    // 2. Pattern: no_<entity> -> references table <entity> (e.g. no_transaksi, no_kunjungan)
    if (lower.startsWith('no_') && lower.length > 3) {
      final entity = lower.substring(3);
      final matchedTable = _findMatchingTable(entity, allTables);
      if (matchedTable != null) {
        return ForeignKeyMetadata(
          columnName: colName,
          targetTable: matchedTable,
          targetColumn: lower,
          constraintName: 'inferred_no_prefix',
        );
      }
    }

    // 3. Pattern: kd_<entity> -> references table <entity> (e.g. kd_user, kd_instalasi)
    if (lower.startsWith('kd_') && lower.length > 3) {
      final entity = lower.substring(3);
      final matchedTable = _findMatchingTable(entity, allTables);
      if (matchedTable != null) {
        return ForeignKeyMetadata(
          columnName: colName,
          targetTable: matchedTable,
          targetColumn: lower,
          constraintName: 'inferred_kd_prefix',
        );
      }
    }

    // 4. Pattern: <entity>_id or id_<entity> -> references table <entity>
    String? entity;
    if (lower.endsWith('_id') && lower.length > 3) {
      entity = lower.substring(0, lower.length - 3);
    } else if (lower.startsWith('id_') && lower.length > 3) {
      entity = lower.substring(3);
    }

    if (entity != null && entity.isNotEmpty) {
      final matchedTable = _findMatchingTable(entity, allTables);
      if (matchedTable != null) {
        return ForeignKeyMetadata(
          columnName: colName,
          targetTable: matchedTable,
          targetColumn: 'id',
          constraintName: 'inferred_id_pattern',
        );
      }
    }

    return null;
  }

  double _calculateColWidth(int index) {
    if (index >= widget.columns.length) return _defaultColWidth;
    final name = widget.columns[index];
    if (widget.showColumnDetails) {
      final meta = _getColumnMeta(name);
      final typeStr = (meta != null && meta.dataType.trim().isNotEmpty)
          ? meta.dataType
          : _inferColumnTypeFromRows(name);
      final cleanCol = name.trim().replaceAll('"', '').replaceAll('`', '');
      final rawCol = cleanCol.contains('.') ? cleanCol.split('.').last.toLowerCase() : cleanCol.toLowerCase();

      final hasExplicitPks = widget.tableMetadata?.columns.any((c) => c.isPrimaryKey) == true;
      final candidatePk = hasExplicitPks ? null : _determineCandidatePrimaryKey(widget.columns, widget.tableMetadata);
      final isPk = meta?.isPrimaryKey == true || (candidatePk != null && candidatePk.toLowerCase() == rawCol);

      ForeignKeyMetadata? fkMeta = meta?.foreignKey;
      if (fkMeta == null && widget.tableMetadata != null) {
        for (final fk in widget.tableMetadata!.foreignKeys) {
          final fkCol = fk.columnName.toLowerCase();
          if (fkCol == rawCol || fkCol == cleanCol.toLowerCase()) {
            fkMeta = fk;
            break;
          }
        }
      }
      if (fkMeta == null && !isPk) {
        fkMeta = _inferForeignKey(rawCol, widget.allTables);
      }

      double extraWidth = 0;
      if (isPk) extraWidth += 36.0;
      if (fkMeta != null) extraWidth += (fkMeta.targetTable.length * 7.0) + 42.0;

      final estimated = math.max((name.length * 9.0) + 54.0 + extraWidth, (typeStr.length * 7.5) + 60.0 + extraWidth);
      return estimated.clamp(140.0, 380.0);
    }
    final estimated = (name.length * 9.0) + 48.0;
    return estimated.clamp(120.0, 260.0);
  }

  double _totalColumnsWidth() {
    double total = _indexColWidth;
    if (widget.isSelectionMode && widget.onToggleRowSelection != null) {
      total += _selectionColWidth;
    }
    if (widget.onEditRow != null || widget.onDeleteRow != null || widget.onDuplicateRow != null) {
      total += _effectiveActionsColWidth;
    }
    for (int i = 0; i < widget.columns.length; i++) {
      total += _calculateColWidth(i);
    }
    return total;
  }

  Widget _buildHeaderDetailBadges(ThemeData theme, String colName) {
    final meta = _getColumnMeta(colName);
    final cleanCol = colName.trim().replaceAll('"', '').replaceAll('`', '');
    final rawCol = cleanCol.contains('.') ? cleanCol.split('.').last.toLowerCase() : cleanCol.toLowerCase();

    // 1. Primary key check: explicit metadata flag, or heuristic candidate PK if table lacks formal PK constraint
    final hasExplicitPks = widget.tableMetadata?.columns.any((c) => c.isPrimaryKey) == true;
    final candidatePk = hasExplicitPks ? null : _determineCandidatePrimaryKey(widget.columns, widget.tableMetadata);
    final isPk = meta?.isPrimaryKey == true || (candidatePk != null && candidatePk.toLowerCase() == rawCol);
    final isCandidatePkOnly = isPk && meta?.isPrimaryKey != true;

    // 2. Foreign key check: column-level FK, table-level foreignKeys, or heuristic inferred FK
    ForeignKeyMetadata? fkMeta = meta?.foreignKey;
    if (fkMeta == null && widget.tableMetadata != null) {
      for (final fk in widget.tableMetadata!.foreignKeys) {
        final fkCol = fk.columnName.toLowerCase();
        if (fkCol == rawCol || fkCol == cleanCol.toLowerCase()) {
          fkMeta = fk;
          break;
        }
      }
    }
    bool isInferredFk = false;
    if (fkMeta == null && !isPk) {
      fkMeta = _inferForeignKey(rawCol, widget.allTables);
      if (fkMeta != null) isInferredFk = true;
    }
    final isFk = fkMeta != null;

    final dataType = (meta != null && meta.dataType.trim().isNotEmpty)
        ? meta.dataType.toUpperCase()
        : _inferColumnTypeFromRows(colName);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPk) ...[
            Tooltip(
              message: isCandidatePkOnly
                  ? 'Candidate Primary Key (Inferred identifier)'
                  : 'Primary Key',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.key, size: 9, color: Colors.amber),
                    SizedBox(width: 2),
                    Text('PK', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.amber)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (isFk) ...[
            Tooltip(
              message: isInferredFk
                  ? 'FK \u2192 ${fkMeta.targetTable}.${fkMeta.targetColumn} (Inferred from schema relations)'
                  : 'FK \u2192 ${fkMeta.targetTable}.${fkMeta.targetColumn}',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: Colors.cyan.withValues(alpha: isInferredFk ? 0.35 : 0.5),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link, size: 9, color: Colors.cyanAccent),
                    SizedBox(width: 2),
                    Text(
                      'FK \u2192 ${fkMeta.targetTable}',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.cyanAccent,
                        fontStyle: isInferredFk ? FontStyle.normal : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              dataType,
              style: TextStyle(
                fontSize: 8.5,
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    String column,
    dynamic value, {
    int? rowIndex,
    List<dynamic>? row,
  }) {
    final theme = Theme.of(context);
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: theme.colorScheme.surface,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.dividerColor),
      ),
      items: [
        if (rowIndex != null && row != null && widget.onEditRow != null)
          PopupMenuItem(
            height: 36,
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 15, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text('Edit row', style: TextStyle(fontSize: 12)),
              ],
            ),
            onTap: () => widget.onEditRow!(rowIndex, row),
          ),
        if (rowIndex != null && row != null && widget.onDuplicateRow != null)
          PopupMenuItem(
            height: 36,
            child: const Row(
              children: [
                Icon(Icons.copy_all_outlined, size: 15, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Text('Duplicate row', style: TextStyle(fontSize: 12)),
              ],
            ),
            onTap: () => widget.onDuplicateRow!(rowIndex, row),
          ),
        if (rowIndex != null && row != null && widget.onDeleteRow != null)
          PopupMenuItem(
            height: 36,
            child: const Row(
              children: [
                Icon(Icons.delete_outline, size: 15, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Delete row', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
              ],
            ),
            onTap: () => widget.onDeleteRow!(rowIndex, row),
          ),
        PopupMenuItem(
          height: 36,
          child: Row(
            children: [
              Icon(Icons.filter_alt, size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Filter by "$column = $value"',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          onTap: () => widget.onFilterByCellValue?.call(column, value),
        ),
        PopupMenuItem(
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.copy, size: 15, color: Colors.grey),
              SizedBox(width: 8),
              Text('Copy cell value', style: TextStyle(fontSize: 12)),
            ],
          ),
          onTap: () {
            if (value != null) {
              Clipboard.setData(ClipboardData(text: value.toString()));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied "$value" to clipboard'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                  width: 280,
                ),
              );
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalWidth = _totalColumnsWidth();
    final selectedCount = widget.selectedRowIndices?.length ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(totalWidth + 32.0, constraints.maxWidth);

        return Stack(
          children: [
            Column(
              children: [
                // Sticky Header Row
            Container(
              height: widget.showColumnDetails ? 50.0 : 34.0,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor,
                    width: 1.5,
                  ),
                ),
              ),
              child: SingleChildScrollView(
                controller: _horizontalHeaderCtrl,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: contentWidth,
                  child: Row(
                    children: [
                      // Multi-Select Checkbox Header
                      if (widget.isSelectionMode && widget.onToggleRowSelection != null) ...[
                        Container(
                          width: _selectionColWidth,
                          height: widget.showColumnDetails ? 50.0 : 34.0,
                          alignment: Alignment.center,
                          child: CyberCheckbox(
                            value: (widget.selectedRowIndices != null &&
                                    widget.rows.isNotEmpty &&
                                    widget.selectedRowIndices!.length == widget.rows.length)
                                ? true
                                : (widget.selectedRowIndices != null && widget.selectedRowIndices!.isNotEmpty
                                    ? null
                                    : false),
                            tristate: true,
                            size: 16.0,
                            onChanged: (_) => widget.onSelectAll?.call(),
                            tooltip: 'Select All / Clear Selection',
                            semanticLabel: 'Select all rows',
                          ),
                        ),
                        Container(width: 1, height: widget.showColumnDetails ? 32 : 20, color: theme.dividerColor.withValues(alpha: 0.3)),
                      ],

                      // Sticky Row Number Header
                      Container(
                        width: _indexColWidth,
                        height: widget.showColumnDetails ? 50.0 : 34.0,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        child: Text(
                          '#',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      Container(width: 1, height: widget.showColumnDetails ? 32 : 20, color: theme.dividerColor.withValues(alpha: 0.3)),

                      // Actions Column Header
                      if (widget.onEditRow != null || widget.onDeleteRow != null || widget.onDuplicateRow != null) ...[
                        Container(
                          width: _effectiveActionsColWidth,
                          height: widget.showColumnDetails ? 50.0 : 34.0,
                          alignment: Alignment.center,
                          child: Text(
                            'ACTIONS',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        Container(width: 1, height: widget.showColumnDetails ? 32 : 20, color: theme.dividerColor.withValues(alpha: 0.3)),
                      ],

                      // Column Headers
                      ...List.generate(widget.columns.length, (colIdx) {
                        final col = widget.columns[colIdx];
                        final width = _calculateColWidth(colIdx);
                        final isSorted = widget.sortColumnIndex == colIdx;

                        return Container(
                          width: width,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          child: InkWell(
                            onTap: widget.onSort != null
                                ? () {
                                    final newAsc = isSorted ? !widget.sortAscending : true;
                                    widget.onSort!(colIdx, newAsc);
                                  }
                                : null,
                            child: widget.showColumnDetails
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              col,
                                              style: TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                                color: isSorted
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme.onSurface.withValues(alpha: 0.9),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isSorted)
                                            Icon(
                                              widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                              size: 12,
                                              color: theme.colorScheme.primary,
                                            )
                                          else
                                            Icon(
                                              Icons.unfold_more,
                                              size: 12,
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      _buildHeaderDetailBadges(theme, col),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          col,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.bold,
                                            color: isSorted
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurface.withValues(alpha: 0.85),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isSorted)
                                        Icon(
                                          widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                                          size: 13,
                                          color: theme.colorScheme.primary,
                                        )
                                      else
                                        Icon(
                                          Icons.unfold_more,
                                          size: 13,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                                        ),
                                    ],
                                  ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),

            // Virtualized Row List (Recycled on scroll, zero lag)
            Expanded(
              child: SingleChildScrollView(
                controller: _horizontalBodyCtrl,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: contentWidth,
                  child: ListView.builder(
                    controller: _verticalRowsCtrl,
                    itemCount: widget.rows.length,
                    itemExtent: _rowHeight, // Enables O(1) virtualization
                    itemBuilder: (context, rowIndex) {
                      final row = widget.rows[rowIndex];
                      final isEven = rowIndex % 2 == 0;
                      final isHovered = _hoveredRowIndex == rowIndex;

                      final isSelected = widget.isSelectionMode && widget.selectedRowIndices?.contains(rowIndex) == true;
                      final rowBg = isSelected
                          ? theme.colorScheme.primary.withValues(alpha: 0.2)
                          : (isHovered
                              ? theme.colorScheme.primary.withValues(alpha: 0.12)
                              : (isEven
                                  ? Colors.transparent
                                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15)));

                      return MouseRegion(
                        onEnter: (_) => setState(() => _hoveredRowIndex = rowIndex),
                        onExit: (_) {
                          if (_hoveredRowIndex == rowIndex) {
                            setState(() => _hoveredRowIndex = null);
                          }
                        },
                        child: Container(
                          height: _rowHeight,
                          decoration: BoxDecoration(
                            color: rowBg,
                            border: Border(
                              left: isSelected
                                  ? BorderSide(color: theme.colorScheme.primary, width: 3)
                                  : BorderSide.none,
                              bottom: BorderSide(
                                color: theme.dividerColor.withValues(alpha: 0.2),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Multi-Select Checkbox
                              if (widget.isSelectionMode && widget.onToggleRowSelection != null) ...[
                                Container(
                                  width: _selectionColWidth,
                                  alignment: Alignment.center,
                                  child: CyberCheckbox(
                                    value: isSelected,
                                    size: 16.0,
                                    onChanged: (_) {
                                      final isShift = HardwareKeyboard.instance.isShiftPressed;
                                      if (isShift && widget.onRangeSelectRow != null) {
                                        widget.onRangeSelectRow!(rowIndex);
                                      } else {
                                        widget.onToggleRowSelection?.call(rowIndex);
                                      }
                                    },
                                    semanticLabel: 'Select row $rowIndex',
                                  ),
                                ),
                                Container(width: 1, height: 16, color: theme.dividerColor.withValues(alpha: 0.15)),
                              ],

                              // Row Index Number
                              Container(
                                width: _indexColWidth,
                                alignment: Alignment.center,
                                child: Text(
                                  '${rowIndex + 1}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                              Container(width: 1, height: 16, color: theme.dividerColor.withValues(alpha: 0.15)),

                              // In-Row Actions
                              if (widget.onEditRow != null || widget.onDeleteRow != null || widget.onDuplicateRow != null) ...[
                                Container(
                                  width: _effectiveActionsColWidth,
                                  alignment: Alignment.center,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.onEditRow != null)
                                        Tooltip(
                                          message: 'Edit row',
                                          waitDuration: const Duration(milliseconds: 350),
                                          child: InkWell(
                                            onTap: () => widget.onEditRow!(rowIndex, row),
                                            borderRadius: BorderRadius.circular(4),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                                              child: Icon(
                                                Icons.edit_outlined,
                                                size: 14,
                                                color: isHovered
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (widget.onDuplicateRow != null)
                                        Tooltip(
                                          message: 'Duplicate row (exclude PK)',
                                          waitDuration: const Duration(milliseconds: 350),
                                          child: InkWell(
                                            onTap: () => widget.onDuplicateRow!(rowIndex, row),
                                            borderRadius: BorderRadius.circular(4),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                                              child: Icon(
                                                Icons.copy_all_outlined,
                                                size: 14,
                                                color: isHovered
                                                    ? Colors.cyanAccent
                                                    : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (widget.onDeleteRow != null)
                                        Tooltip(
                                          message: widget.isSafeMode ? 'Delete row (Safe Mode ON)' : 'Delete row',
                                          waitDuration: const Duration(milliseconds: 350),
                                          child: InkWell(
                                            onTap: () => widget.onDeleteRow!(rowIndex, row),
                                            borderRadius: BorderRadius.circular(4),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  Icon(
                                                    Icons.delete_outline,
                                                    size: 14,
                                                    color: isHovered
                                                        ? (widget.isSafeMode ? Colors.amberAccent : Colors.redAccent)
                                                        : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                                                  ),
                                                  if (widget.isSafeMode)
                                                    Positioned(
                                                      right: -2,
                                                      bottom: -2,
                                                      child: Icon(
                                                        Icons.lock,
                                                        size: 7,
                                                        color: Colors.amberAccent.withValues(alpha: 0.9),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, height: 16, color: theme.dividerColor.withValues(alpha: 0.15)),
                              ],

                              // Cell Values
                              ...List.generate(widget.columns.length, (colIdx) {
                                final colName = widget.columns[colIdx];
                                final width = _calculateColWidth(colIdx);
                                final cellValue = colIdx < row.length ? row[colIdx] : null;
                                final isNull = cellValue == null;
                                final isEditing = _editingRowIndex == rowIndex && _editingColIndex == colIdx;

                                if (isEditing) {
                                  return Container(
                                    width: width,
                                    height: _rowHeight,
                                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                    alignment: Alignment.centerLeft,
                                    child: TapRegion(
                                      groupId: 'inline_cell_editor',
                                      onTapOutside: (_) => _commitInlineEdit(),
                                      child: Container(
                                        height: _rowHeight - 4,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surface,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: theme.colorScheme.primary, width: 1.5),
                                          boxShadow: [
                                            BoxShadow(
                                              color: theme.colorScheme.primary.withValues(alpha: 0.35),
                                              blurRadius: 6,
                                              spreadRadius: 0.5,
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextField(
                                                controller: _inlineEditCtrl,
                                                focusNode: _inlineFocusNode,
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: theme.colorScheme.onSurface,
                                                ),
                                                decoration: const InputDecoration(
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                                  isDense: true,
                                                  filled: false,
                                                  border: InputBorder.none,
                                                  enabledBorder: InputBorder.none,
                                                  focusedBorder: InputBorder.none,
                                                ),
                                                onSubmitted: (_) => _commitInlineEdit(),
                                              ),
                                            ),
                                            // Micro Actions: Commit and Cancel
                                            MouseRegion(
                                              cursor: SystemMouseCursors.click,
                                              child: GestureDetector(
                                                onTap: _commitInlineEdit,
                                                child: Tooltip(
                                                  message: 'Save (Enter)',
                                                  child: Container(
                                                    padding: const EdgeInsets.all(3),
                                                    margin: const EdgeInsets.only(right: 2),
                                                    decoration: BoxDecoration(
                                                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Icon(Icons.check, size: 13, color: theme.colorScheme.primary),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            MouseRegion(
                                              cursor: SystemMouseCursors.click,
                                              child: GestureDetector(
                                                onTap: _cancelInlineEdit,
                                                child: Tooltip(
                                                  message: 'Cancel (Esc)',
                                                  child: Container(
                                                    padding: const EdgeInsets.all(3),
                                                    margin: const EdgeInsets.only(right: 3),
                                                    decoration: BoxDecoration(
                                                      color: Colors.redAccent.withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: const Icon(Icons.close, size: 13, color: Colors.redAccent),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                return MouseRegion(
                                  cursor: widget.onInlineCellSave != null ? SystemMouseCursors.click : MouseCursor.defer,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onDoubleTap: () {
                                      if (widget.onInlineCellSave != null) {
                                        _startInlineEdit(rowIndex, colIdx, cellValue);
                                      } else {
                                        widget.onFilterByCellValue?.call(colName, cellValue);
                                      }
                                    },
                                    onSecondaryTapDown: (details) {
                                      _showContextMenu(
                                        context,
                                        details.globalPosition,
                                        colName,
                                        cellValue,
                                        rowIndex: rowIndex,
                                        row: row,
                                      );
                                    },
                                    onLongPressStart: (details) {
                                      _showContextMenu(
                                        context,
                                        details.globalPosition,
                                        colName,
                                        cellValue,
                                        rowIndex: rowIndex,
                                        row: row,
                                      );
                                    },
                                    child: Container(
                                      width: width,
                                      height: _rowHeight,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      alignment: Alignment.centerLeft,
                                      child: Tooltip(
                                        message: isNull ? 'NULL (Double-click to edit)' : '$cellValue (Double-click to edit)',
                                        waitDuration: const Duration(milliseconds: 600),
                                        child: Text(
                                          isNull ? 'NULL' : cellValue.toString(),
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11.5,
                                            fontStyle: isNull ? FontStyle.italic : FontStyle.normal,
                                            color: isNull
                                                ? Colors.grey.withValues(alpha: 0.6)
                                                : (isHovered ? theme.colorScheme.onSurface : null),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),

        // Floating Tactical HUD Bulk Actions Dock
        if (widget.isSelectionMode && selectedCount > 0)
          Positioned(
            left: 20,
            right: 20,
            bottom: 12,
            child: _buildFloatingBulkActionDock(context, theme, selectedCount),
          ),
      ],
    );
  },
);
  }

  Widget _buildFloatingBulkActionDock(BuildContext context, ThemeData theme, int selectedCount) {
    final primary = theme.colorScheme.primary;
    final selectedIndices = widget.selectedRowIndices!.toList()..sort();

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(10),
      color: const Color(0xFF0F172A),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: primary.withValues(alpha: 0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.25),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: primary.withValues(alpha: 0.5)),
              ),
              child: Text(
                '$selectedCount selected',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: widget.onClearSelection,
              icon: const Icon(Icons.close, size: 14, color: Colors.grey),
              label: const Text('Deselect', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            ),
            const SizedBox(width: 8),
            if (widget.onBulkDuplicate != null) ...[
              OutlinedButton.icon(
                onPressed: () => widget.onBulkDuplicate!(selectedIndices),
                icon: const Icon(Icons.copy_all, size: 14, color: Colors.cyanAccent),
                label: const Text('Duplicate', style: TextStyle(fontSize: 11.5, color: Colors.cyanAccent)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.cyan.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (widget.onBulkExport != null) ...[
              OutlinedButton.icon(
                onPressed: () => widget.onBulkExport!(selectedIndices),
                icon: const Icon(Icons.file_download_outlined, size: 14),
                label: const Text('Export', style: TextStyle(fontSize: 11.5)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Spacer(),
            if (widget.onBulkDelete != null)
              FilledButton.icon(
                onPressed: () => widget.onBulkDelete!(selectedIndices),
                icon: const Icon(Icons.delete_sweep, size: 15),
                label: Text('Delete ($selectedCount)', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
