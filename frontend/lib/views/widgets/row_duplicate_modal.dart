import 'package:flutter/material.dart';
import '../../models/table_schema.dart';

/// Sandboxed expression and formula evaluator for multi-row duplication.
class RowFormulaEvaluator {
  /// Evaluates an expression or template for a specific copy index (0-indexed [copyIndex]).
  /// Supported:
  /// - Arithmetic with 'i' (0-based) or 'step' / 'index' (1-based), 'val' (base numeric value).
  ///   e.g. "i + 1", "val + i", "val + 1", "i", "step", "100 + i"
  /// - Relative offsets like "+1", "+ 1", "+ i", "+ (i + 1)"
  /// - Template strings with ${...}: e.g. "INV-${i + 1}", "${val}_copy_${i+1}"
  static dynamic evaluate({
    required String formula,
    required dynamic baseVal,
    required int copyIndex,
  }) {
    final trimmed = formula.trim();
    if (trimmed.isEmpty) {
      return baseVal;
    }

    // Template interpolation with ${...}
    if (trimmed.contains(r'${')) {
      return trimmed.replaceAllMapped(RegExp(r'\$\{([^}]+)\}'), (m) {
        final inner = m.group(1) ?? '';
        final res = _evalArithmetic(inner, baseVal, copyIndex);
        return res != null ? res.toString() : '';
      });
    }

    // Pure arithmetic evaluation
    final numRes = _evalArithmetic(trimmed, baseVal, copyIndex);
    if (numRes != null) {
      return numRes;
    }

    // Fallback: if it's not arithmetic, return trimmed string
    return trimmed;
  }

  static dynamic _evalArithmetic(String expr, dynamic baseVal, int copyIndex) {
    String clean = expr.trim();
    if (clean.isEmpty) return baseVal;

    num baseNum = 0;
    if (baseVal is num) {
      baseNum = baseVal;
    } else if (baseVal != null) {
      baseNum = num.tryParse(baseVal.toString()) ?? 0;
    }

    final int iVal = copyIndex;
    final int stepVal = copyIndex + 1;

    // Handle relative shorthand like "+ 1" or "+1" or "+ i" -> "val + 1" / "val + i"
    if (clean.startsWith('+') || clean.startsWith('-') || clean.startsWith('*') || clean.startsWith('/')) {
      clean = 'val $clean';
    }

    // Tokenize / Replace identifiers:
    // 'val' or 'base' -> baseNum
    // 'step' or 'index' -> stepVal
    // 'i' -> iVal
    final replaced = clean.replaceAllMapped(RegExp(r'\b(val|base|step|index|i)\b', caseSensitive: false), (m) {
      final token = m.group(1)!.toLowerCase();
      switch (token) {
        case 'val':
        case 'base':
          return baseNum.toString();
        case 'step':
        case 'index':
          return stepVal.toString();
        case 'i':
          return iVal.toString();
        default:
          return m.group(0)!;
      }
    });

    try {
      final val = _calculateExpression(replaced);
      if (val != null) {
        if (val % 1 == 0) {
          return val.toInt();
        }
        return val;
      }
    } catch (_) {
      // Ignored: fallback to null
    }
    return null;
  }

  // Recursive descent parser for basic math expressions (+, -, *, /, %, numbers, parentheses)
  static double? _calculateExpression(String text) {
    final tokens = _tokenize(text);
    if (tokens.isEmpty) return null;
    return _MathParser(tokens).parse();
  }

  static List<String> _tokenize(String text) {
    final List<String> tokens = [];
    int i = 0;
    while (i < text.length) {
      final ch = text[i];
      if (ch == ' ' || ch == '\t') {
        i++;
        continue;
      }
      if ('+-*/%()'.contains(ch)) {
        tokens.add(ch);
        i++;
        continue;
      }
      if ((ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) || ch == '.') {
        int start = i;
        while (i < text.length &&
            ((text.codeUnitAt(i) >= 48 && text.codeUnitAt(i) <= 57) || text[i] == '.')) {
          i++;
        }
        tokens.add(text.substring(start, i));
        continue;
      }
      i++;
    }
    return tokens;
  }
}

class _MathParser {
  final List<String> tokens;
  int pos = 0;

  _MathParser(this.tokens);

  double? parse() {
    try {
      return parseExpression();
    } catch (_) {
      return null;
    }
  }

  double parseExpression() {
    double value = parseTerm();
    while (pos < tokens.length) {
      final op = tokens[pos];
      if (op == '+' || op == '-') {
        pos++;
        final nextTerm = parseTerm();
        if (op == '+') value += nextTerm;
        if (op == '-') value -= nextTerm;
      } else {
        break;
      }
    }
    return value;
  }

  double parseTerm() {
    double value = parseFactor();
    while (pos < tokens.length) {
      final op = tokens[pos];
      if (op == '*' || op == '/' || op == '%') {
        pos++;
        final nextFactor = parseFactor();
        if (op == '*') value *= nextFactor;
        if (op == '/') value = nextFactor == 0 ? 0 : value / nextFactor;
        if (op == '%') value = nextFactor == 0 ? 0 : value % nextFactor;
      } else {
        break;
      }
    }
    return value;
  }

  double parseFactor() {
    if (pos >= tokens.length) return 0;
    final t = tokens[pos];

    if (t == '+') {
      pos++;
      return parseFactor();
    }
    if (t == '-') {
      pos++;
      return -parseFactor();
    }
    if (t == '(') {
      pos++;
      final val = parseExpression();
      if (pos < tokens.length && tokens[pos] == ')') pos++;
      return val;
    }

    pos++;
    return double.tryParse(t) ?? 0.0;
  }
}

/// Modal dialog for confirming row duplication with primary key collision prevention,
/// inline value editing, formula generator support (e.g. i + 1), and quantity selection.
Future<bool?> showRowDuplicateModal({
  required BuildContext context,
  required String tableName,
  required List<String> columns,
  required List<dynamic> rowValues,
  TableMetadata? tableMetadata,
  required Future<String?> Function({
    required List<Map<String, dynamic>> rowsToInsert,
    required int count,
  }) onDuplicate,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _RowDuplicateModalDialog(
      tableName: tableName,
      columns: columns,
      rowValues: rowValues,
      tableMetadata: tableMetadata,
      onDuplicate: onDuplicate,
    ),
  );
}

class _RowDuplicateModalDialog extends StatefulWidget {
  final String tableName;
  final List<String> columns;
  final List<dynamic> rowValues;
  final TableMetadata? tableMetadata;
  final Future<String?> Function({
    required List<Map<String, dynamic>> rowsToInsert,
    required int count,
  }) onDuplicate;

  const _RowDuplicateModalDialog({
    required this.tableName,
    required this.columns,
    required this.rowValues,
    required this.tableMetadata,
    required this.onDuplicate,
  });

  @override
  State<_RowDuplicateModalDialog> createState() => _RowDuplicateModalDialogState();
}

class _RowDuplicateModalDialogState extends State<_RowDuplicateModalDialog> {
  int _count = 1;
  bool _isDuplicating = false;
  String? _errorMessage;
  Set<String> _excludedCols = {};

  final Map<String, TextEditingController> _valControllers = {};
  final Map<String, TextEditingController> _formulaControllers = {};
  final Set<String> _activeFormulaCols = {};

  @override
  void initState() {
    super.initState();
    _initExclusions();
    _initControllers();
  }

  void _initControllers() {
    for (int i = 0; i < widget.columns.length; i++) {
      final col = widget.columns[i];
      final val = i < widget.rowValues.length ? widget.rowValues[i] : null;
      _valControllers[col] = TextEditingController(text: val?.toString() ?? '');
      _formulaControllers[col] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _valControllers.values) {
      c.dispose();
    }
    for (final c in _formulaControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _initExclusions() {
    final excluded = <String>{};
    if (widget.tableMetadata != null) {
      for (final col in widget.tableMetadata!.columns) {
        if (col.isPrimaryKey) {
          excluded.add(col.name);
        } else if (col.defaultValue != null) {
          final defLower = col.defaultValue!.toLowerCase();
          if (defLower.contains('nextval') ||
              defLower.contains('gen_random_uuid') ||
              defLower.contains('uuid_generate') ||
              defLower.contains('auto_increment')) {
            excluded.add(col.name);
          }
        }
      }
    }

    // Conservative fallback heuristic ONLY when no explicit PK was detected
    if (excluded.isEmpty) {
      for (final colName in widget.columns) {
        final lower = colName.toLowerCase();
        if (lower == 'id' || lower == 'uuid') {
          final meta = _findColMeta(colName);
          if (meta == null || meta.defaultValue != null || meta.isNullable) {
            excluded.add(colName);
            break;
          }
        }
      }
    }

    _excludedCols = excluded;
  }

  ColumnMetadata? _findColMeta(String name) {
    if (widget.tableMetadata == null) return null;
    for (final c in widget.tableMetadata!.columns) {
      if (c.name.toLowerCase() == name.toLowerCase()) return c;
    }
    return null;
  }

  dynamic _parseValue(String raw, ColumnMetadata? meta) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toUpperCase() == '<NULL>' || trimmed.toLowerCase() == 'null') {
      return null;
    }
    if (meta != null) {
      final dt = meta.dataType.toLowerCase();
      if (dt.contains('int') || dt.contains('serial')) {
        final i = int.tryParse(trimmed);
        if (i != null) return i;
      }
      if (dt.contains('float') ||
          dt.contains('double') ||
          dt.contains('numeric') ||
          dt.contains('decimal') ||
          dt.contains('real')) {
        final d = double.tryParse(trimmed);
        if (d != null) return d;
      }
      if (dt.contains('bool')) {
        if (trimmed.toLowerCase() == 'true') return true;
        if (trimmed.toLowerCase() == 'false') return false;
      }
    }
    final intVal = int.tryParse(trimmed);
    if (intVal != null && intVal.toString() == trimmed) return intVal;
    final doubleVal = double.tryParse(trimmed);
    if (doubleVal != null) return doubleVal;
    return trimmed;
  }

  List<Map<String, dynamic>> _generateRowsToInsert() {
    final List<Map<String, dynamic>> rows = [];
    for (int c = 0; c < _count; c++) {
      final Map<String, dynamic> row = {};
      for (int i = 0; i < widget.columns.length; i++) {
        final col = widget.columns[i];
        if (_excludedCols.contains(col)) continue;

        final meta = _findColMeta(col);
        final rawText = _valControllers[col]?.text ?? '';
        final baseVal = _parseValue(rawText, meta);

        if (_activeFormulaCols.contains(col) &&
            _formulaControllers[col]?.text.trim().isNotEmpty == true) {
          final formula = _formulaControllers[col]!.text.trim();
          final evalResult = RowFormulaEvaluator.evaluate(
            formula: formula,
            baseVal: baseVal,
            copyIndex: c,
          );
          row[col] = evalResult;
        } else {
          row[col] = baseVal;
        }
      }
      rows.add(row);
    }
    return rows;
  }

  String _generatePreviewText(String col) {
    final formula = _formulaControllers[col]?.text.trim() ?? '';
    if (formula.isEmpty) return '';
    final rawText = _valControllers[col]?.text ?? '';
    final meta = _findColMeta(col);
    final baseVal = _parseValue(rawText, meta);

    final List<String> previews = [];
    final previewLimit = _count > 4 ? 3 : _count;
    for (int c = 0; c < previewLimit; c++) {
      final val = RowFormulaEvaluator.evaluate(
        formula: formula,
        baseVal: baseVal,
        copyIndex: c,
      );
      previews.add('#${c + 1}: $val');
    }
    if (_count > 4) {
      final lastVal = RowFormulaEvaluator.evaluate(
        formula: formula,
        baseVal: baseVal,
        copyIndex: _count - 1,
      );
      previews.add('... #$_count: $lastVal');
    }
    return previews.join('  |  ');
  }

  Future<void> _submit() async {
    setState(() {
      _isDuplicating = true;
      _errorMessage = null;
    });

    final rows = _generateRowsToInsert();
    try {
      final error = await widget.onDuplicate(
        rowsToInsert: rows,
        count: _count,
      );
      if (!mounted) return;
      if (error == null) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isDuplicating = false;
          _errorMessage = error;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDuplicating = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final excludedList = _excludedCols.toList();
    final includedCols = widget.columns.where((c) => !_excludedCols.contains(c)).toList();

    final cyanColor = isDark ? Colors.cyanAccent : const Color(0xFF0369A1);
    final cyanBgColor = isDark ? Colors.cyan.withValues(alpha: 0.15) : const Color(0xFFE0F2FE);
    final cyanBorderColor = isDark ? Colors.cyanAccent.withValues(alpha: 0.3) : const Color(0xFF7DD3FC);

    final bannerColor = isDark ? Colors.tealAccent : const Color(0xFF0F766E);
    final bannerBgColor = isDark ? Colors.teal.withValues(alpha: 0.1) : const Color(0xFFF0FDFA);
    final bannerBorderColor = isDark ? Colors.teal.withValues(alpha: 0.35) : const Color(0xFF5EEAD4);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: (isDark ? Colors.cyanAccent : primary).withValues(alpha: 0.3), width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.cyanAccent : primary).withValues(alpha: 0.1),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cyber Top Neon Bar
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyan.withValues(alpha: 0.1),
                        isDark ? Colors.cyanAccent : primary,
                        Colors.cyan.withValues(alpha: 0.1),
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
                          color: cyanBgColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cyanBorderColor),
                        ),
                        child: Icon(Icons.copy_all_outlined, color: cyanColor, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            const Text(
                              'Duplicate Row Record',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.3),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: cyanBgColor,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: cyanBorderColor, width: 0.8),
                                ),
                                child: Text(
                                  widget.tableName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                    color: cyanColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 11.5, color: Colors.redAccent, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ),

                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Collision-Prevention Callout Banner
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: bannerBgColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: bannerBorderColor),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.shield_outlined, size: 18, color: bannerColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Collision Prevention & Expression Generator',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: bannerColor),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      excludedList.isNotEmpty
                                          ? 'Columns [${excludedList.join(', ')}] are excluded from INSERT to prevent primary key collision. You can edit values and attach formulas (e.g. i + 1, val + i) per column below.'
                                          : 'All columns are included by default. Edit column values or toggle formulas (fx) to customize values across copies.',
                                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.8), height: 1.35),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Quantity Selector: How many rows
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Number of copies to insert',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Formulas will evaluate across copies (i = 0..${_count - 1})',
                                      style: TextStyle(fontSize: 10.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: _count > 1 ? () => setState(() => _count--) : null,
                                icon: const Icon(Icons.remove, size: 16),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: cyanBorderColor),
                                ),
                                child: Text(
                                  '$_count',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: cyanColor,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: _count < 50 ? () => setState(() => _count++) : null,
                                icon: const Icon(Icons.add, size: 16),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                              const SizedBox(width: 6),
                              // Quick Presets
                              Wrap(
                                spacing: 4,
                                children: [1, 2, 5, 10].map((preset) {
                                  final isSel = _count == preset;
                                  return InkWell(
                                    onTap: () => setState(() => _count = preset),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? cyanBgColor
                                            : theme.colorScheme.surface,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isSel ? cyanBorderColor : theme.dividerColor.withValues(alpha: 0.3),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        '${preset}x',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isSel ? cyanColor : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Columns & Values Table
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Columns, Editable Values & Formulas:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${includedCols.length} included / ${excludedList.length} excluded',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 330),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: widget.columns.length,
                            separatorBuilder: (ctx, i) => const Divider(height: 1, thickness: 0.5),
                            itemBuilder: (ctx, i) {
                              final col = widget.columns[i];
                              final isExcluded = _excludedCols.contains(col);
                              final meta = _findColMeta(col);
                              final isPk = meta?.isPrimaryKey == true;
                              final isFormulaActive = _activeFormulaCols.contains(col);
                              final formulaCtrl = _formulaControllers[col]!;
                              final valCtrl = _valControllers[col]!;

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: Checkbox(
                                            value: !isExcluded,
                                            onChanged: (val) {
                                              setState(() {
                                                if (val == true) {
                                                  _excludedCols.remove(col);
                                                } else {
                                                  _excludedCols.add(col);
                                                }
                                              });
                                            },
                                            activeColor: const Color(0xFF14B8A6),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 140,
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  col,
                                                  style: TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 11,
                                                    fontWeight: isPk ? FontWeight.bold : FontWeight.w600,
                                                    color: isExcluded
                                                        ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                                                        : (isPk ? Colors.amberAccent : theme.colorScheme.onSurface.withValues(alpha: 0.85)),
                                                    decoration: isExcluded ? TextDecoration.lineThrough : null,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isPk) ...[
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.amber.withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                  child: const Text('PK', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.amber)),
                                                ),
                                              ],
                                              if (meta?.dataType != null) ...[
                                                const SizedBox(width: 3),
                                                Text(
                                                  meta!.dataType,
                                                  style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // Editable Value Field or Excluded Indicator
                                        if (isExcluded)
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                '[EXCLUDED FROM INSERT]',
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 11,
                                                  fontStyle: FontStyle.italic,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          )
                                        else ...[
                                          Expanded(
                                            child: SizedBox(
                                              height: 32,
                                              child: TextField(
                                                controller: valCtrl,
                                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                                decoration: InputDecoration(
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                                  hintText: 'Value (or NULL)',
                                                  hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                                                  filled: true,
                                                  fillColor: theme.colorScheme.surface,
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(5),
                                                    borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                                                  ),
                                                  focusedBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(5),
                                                    borderSide: const BorderSide(color: Color(0xFF14B8A6)),
                                                  ),
                                                ),
                                                onChanged: (_) {
                                                  if (isFormulaActive) setState(() {});
                                                },
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),

                                          // Formula Toggle Button
                                          InkWell(
                                            onTap: () {
                                              setState(() {
                                                if (isFormulaActive) {
                                                  _activeFormulaCols.remove(col);
                                                } else {
                                                  _activeFormulaCols.add(col);
                                                  if (formulaCtrl.text.isEmpty) {
                                                    // Default suggestion based on column name or value
                                                    final lower = col.toLowerCase();
                                                    if (lower.contains('count') || lower.contains('urutan') || lower.contains('no')) {
                                                      formulaCtrl.text = 'val + i';
                                                    } else {
                                                      formulaCtrl.text = 'i + 1';
                                                    }
                                                  }
                                                }
                                              });
                                            },
                                            borderRadius: BorderRadius.circular(4),
                                            child: Container(
                                              height: 30,
                                              padding: const EdgeInsets.symmetric(horizontal: 7),
                                              decoration: BoxDecoration(
                                                color: isFormulaActive
                                                    ? const Color(0xFF14B8A6).withValues(alpha: 0.2)
                                                    : theme.colorScheme.surface,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: isFormulaActive
                                                      ? const Color(0xFF14B8A6)
                                                      : theme.dividerColor.withValues(alpha: 0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'fx',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontStyle: FontStyle.italic,
                                                      fontWeight: FontWeight.bold,
                                                      fontFamily: 'monospace',
                                                      color: isFormulaActive ? const Color(0xFF14B8A6) : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                                    ),
                                                  ),
                                                  if (isFormulaActive) ...[
                                                    const SizedBox(width: 3),
                                                    const Icon(Icons.check, size: 11, color: Color(0xFF14B8A6)),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),

                                    // Expandable Formula Drawer when fx is Active
                                    if (!isExcluded && isFormulaActive) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        margin: const EdgeInsets.only(left: 30),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF14B8A6).withValues(alpha: 0.06),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.25)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                const Icon(Icons.functions, size: 13, color: Color(0xFF14B8A6)),
                                                const SizedBox(width: 5),
                                                const Text(
                                                  'Formula Generator:',
                                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF14B8A6)),
                                                ),
                                                const Spacer(),
                                                // Formula Presets
                                                Wrap(
                                                  spacing: 4,
                                                  children: ['i + 1', 'val + i', 'val + (i + 1)'].map((preset) {
                                                    return InkWell(
                                                      onTap: () {
                                                        setState(() {
                                                          formulaCtrl.text = preset;
                                                        });
                                                      },
                                                      borderRadius: BorderRadius.circular(3),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                        decoration: BoxDecoration(
                                                          color: theme.colorScheme.surface,
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.4), width: 0.8),
                                                        ),
                                                        child: Text(
                                                          preset,
                                                          style: const TextStyle(fontSize: 9.5, fontFamily: 'monospace', color: Color(0xFF14B8A6)),
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            SizedBox(
                                              height: 30,
                                              child: TextField(
                                                controller: formulaCtrl,
                                                style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF14B8A6)),
                                                decoration: InputDecoration(
                                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                                  hintText: 'e.g. i + 1, val + i, prefix_\${i + 1}',
                                                  hintStyle: const TextStyle(fontSize: 10, color: Colors.grey),
                                                  filled: true,
                                                  fillColor: theme.colorScheme.surface,
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(4),
                                                    borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                                                  ),
                                                ),
                                                onChanged: (_) => setState(() {}),
                                              ),
                                            ),
                                            if (formulaCtrl.text.trim().isNotEmpty) ...[
                                              const SizedBox(height: 5),
                                              Row(
                                                children: [
                                                  const Icon(Icons.remove_red_eye_outlined, size: 11, color: Colors.grey),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      'Live Preview: ${_generatePreviewText(col)}',
                                                      style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: cyanColor),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
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
                      ],
                    ),
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
                        onPressed: _isDuplicating ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: _isDuplicating ? null : _submit,
                        icon: _isDuplicating
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: isDark ? Colors.black87 : Colors.white,
                                ),
                              )
                            : const Icon(Icons.copy, size: 15),
                        label: Text(
                          _isDuplicating
                              ? 'Duplicating...'
                              : 'Duplicate Row ($_count ${_count == 1 ? 'copy' : 'copies'})',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.cyanAccent : const Color(0xFF0284C7),
                          foregroundColor: isDark ? Colors.black87 : Colors.white,
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
