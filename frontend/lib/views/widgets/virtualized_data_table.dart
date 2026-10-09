import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  const VirtualizedDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSort,
    this.onFilterByCellValue,
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

  static const double _rowHeight = 32.0;
  static const double _indexColWidth = 52.0;
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
    _horizontalHeaderCtrl.dispose();
    _horizontalBodyCtrl.dispose();
    _verticalRowsCtrl.dispose();
    super.dispose();
  }

  double _calculateColWidth(int index) {
    if (index >= widget.columns.length) return _defaultColWidth;
    final name = widget.columns[index];
    // Dynamic column width based on header length with bounds
    final estimated = (name.length * 9.0) + 48.0;
    return estimated.clamp(120.0, 260.0);
  }

  double _totalColumnsWidth() {
    double total = _indexColWidth;
    for (int i = 0; i < widget.columns.length; i++) {
      total += _calculateColWidth(i);
    }
    return total;
  }

  void _showContextMenu(BuildContext context, Offset position, String column, dynamic value) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(totalWidth + 32.0, constraints.maxWidth);

        return Column(
          children: [
            // Sticky Header Row
            Container(
              height: 34,
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
                      // Sticky Row Number Header
                      Container(
                        width: _indexColWidth,
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
                      Container(width: 1, height: 20, color: theme.dividerColor.withValues(alpha: 0.3)),

                      // Column Headers
                      ...List.generate(widget.columns.length, (colIdx) {
                        final col = widget.columns[colIdx];
                        final width = _calculateColWidth(colIdx);
                        final isSorted = widget.sortColumnIndex == colIdx;

                        return Container(
                          width: width,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: InkWell(
                            onTap: widget.onSort != null
                                ? () {
                                    final newAsc = isSorted ? !widget.sortAscending : true;
                                    widget.onSort!(colIdx, newAsc);
                                  }
                                : null,
                            child: Row(
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

                      final rowBg = isHovered
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : (isEven
                              ? Colors.transparent
                              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15));

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
                              bottom: BorderSide(
                                color: theme.dividerColor.withValues(alpha: 0.2),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
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

                              // Cell Values
                              ...List.generate(widget.columns.length, (colIdx) {
                                final colName = widget.columns[colIdx];
                                final width = _calculateColWidth(colIdx);
                                final cellValue = colIdx < row.length ? row[colIdx] : null;
                                final isNull = cellValue == null;

                                return Container(
                                  width: width,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  alignment: Alignment.centerLeft,
                                  child: GestureDetector(
                                    onDoubleTap: () {
                                      widget.onFilterByCellValue?.call(colName, cellValue);
                                    },
                                    onSecondaryTapDown: (details) {
                                      _showContextMenu(context, details.globalPosition, colName, cellValue);
                                    },
                                    onLongPressStart: (details) {
                                      _showContextMenu(context, details.globalPosition, colName, cellValue);
                                    },
                                    child: Tooltip(
                                      message: isNull ? 'NULL' : cellValue.toString(),
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
        );
      },
    );
  }
}
