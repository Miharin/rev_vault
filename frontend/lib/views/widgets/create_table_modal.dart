import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/table_schema.dart';
import 'cyber_dropdown_bottom_sheet.dart';
import 'cyber_text_field.dart';
import 'cyber_checkbox.dart';

class ColumnEditorModel {
  String name;
  String dataType;
  String lengthPrecision;
  bool isNullable;
  bool isPrimaryKey;
  bool isAutoIncrement;
  bool isUnique;
  String defaultValue;
  String? foreignKeyTable;
  String? foreignKeyColumn;
  String onForeignKeyDelete;

  ColumnEditorModel({
    this.name = '',
    this.dataType = 'TEXT',
    this.lengthPrecision = '',
    this.isNullable = true,
    this.isPrimaryKey = false,
    this.isAutoIncrement = false,
    this.isUnique = false,
    this.defaultValue = '',
    this.foreignKeyTable,
    this.foreignKeyColumn,
    this.onForeignKeyDelete = 'CASCADE',
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name.trim(),
      'data_type': dataType,
      'length_precision': lengthPrecision.trim().isEmpty
          ? null
          : lengthPrecision.trim(),
      'is_nullable': isNullable,
      'is_primary_key': isPrimaryKey,
      'is_auto_increment': isAutoIncrement,
      'is_unique': isUnique,
      'default_value': defaultValue.trim().isEmpty ? null : defaultValue.trim(),
      'foreign_key_table': foreignKeyTable,
      'foreign_key_column': foreignKeyColumn,
      'on_delete': onForeignKeyDelete,
    };
  }
}

/// Cyber-styled interactive dialog for designing and creating a new database table.
Future<bool?> showCreateTableModal({
  required BuildContext context,
  required String engine, // "sqlite" | "postgres"
  String? defaultSchema,
  required List<TableMetadata> existingTables,
  required Future<bool> Function({
    required String tableName,
    String? schemaName,
    required List<Map<String, dynamic>> columns,
    bool ifNotExists,
  })
  onCreateTable,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _CreateTableModalDialog(
      engine: engine,
      defaultSchema: defaultSchema,
      existingTables: existingTables,
      onCreateTable: onCreateTable,
    ),
  );
}

class _CreateTableModalDialog extends StatefulWidget {
  final String engine;
  final String? defaultSchema;
  final List<TableMetadata> existingTables;
  final Future<bool> Function({
    required String tableName,
    String? schemaName,
    required List<Map<String, dynamic>> columns,
    bool ifNotExists,
  })
  onCreateTable;

  const _CreateTableModalDialog({
    required this.engine,
    required this.defaultSchema,
    required this.existingTables,
    required this.onCreateTable,
  });

  @override
  State<_CreateTableModalDialog> createState() =>
      _CreateTableModalDialogState();
}

class _CreateTableModalDialogState extends State<_CreateTableModalDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _tableNameCtrl;
  late final TextEditingController _schemaCtrl;
  bool _ifNotExists = true;
  bool _isCreating = false;
  String? _errorMessage;

  late final TabController _tabCtrl;
  final List<ColumnEditorModel> _columns = [];

  List<String> get _availableDataTypes {
    if (widget.engine == 'sqlite') {
      return [
        'INTEGER',
        'TEXT',
        'REAL',
        'BLOB',
        'NUMERIC',
        'BOOLEAN',
        'DATETIME',
      ];
    }
    return [
      'BIGINT',
      'INTEGER',
      'VARCHAR',
      'TEXT',
      'BOOLEAN',
      'TIMESTAMPTZ',
      'NUMERIC',
      'DOUBLE PRECISION',
      'JSONB',
      'UUID',
      'DATE',
    ];
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tableNameCtrl = TextEditingController();
    _schemaCtrl = TextEditingController(
      text:
          widget.defaultSchema ??
          (widget.engine == 'postgres' ? 'public' : 'main'),
    );

    // Initial default columns
    _columns.add(
      ColumnEditorModel(
        name: 'id',
        dataType: widget.engine == 'sqlite' ? 'INTEGER' : 'BIGINT',
        isNullable: false,
        isPrimaryKey: true,
        isAutoIncrement: true,
      ),
    );
    _columns.add(
      ColumnEditorModel(
        name: 'name',
        dataType: widget.engine == 'sqlite' ? 'TEXT' : 'VARCHAR',
        lengthPrecision: widget.engine == 'postgres' ? '255' : '',
        isNullable: false,
      ),
    );
    _columns.add(
      ColumnEditorModel(
        name: 'created_at',
        dataType: widget.engine == 'sqlite' ? 'DATETIME' : 'TIMESTAMPTZ',
        isNullable: false,
        defaultValue: 'CURRENT_TIMESTAMP',
      ),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _tableNameCtrl.dispose();
    _schemaCtrl.dispose();
    super.dispose();
  }

  void _addColumn() {
    setState(() {
      _columns.add(
        ColumnEditorModel(
          name: 'col_${_columns.length + 1}',
          dataType: widget.engine == 'sqlite' ? 'TEXT' : 'VARCHAR',
          lengthPrecision: widget.engine == 'postgres' ? '255' : '',
          isNullable: true,
        ),
      );
    });
  }

  void _removeColumn(int index) {
    if (_columns.length <= 1) return;
    setState(() {
      _columns.removeAt(index);
    });
  }

  String _generateDdlPreview() {
    final rawTable = _tableNameCtrl.text.trim().isEmpty
        ? 'new_table'
        : _tableNameCtrl.text.trim();
    final rawSchema = _schemaCtrl.text.trim().isEmpty
        ? 'public'
        : _schemaCtrl.text.trim();

    final targetName = widget.engine == 'postgres'
        ? '"$rawSchema"."$rawTable"'
        : '`$rawTable`';

    final lines = <String>[];
    for (final col in _columns) {
      final colName = col.name.trim().isEmpty ? 'unnamed' : col.name.trim();
      final qCol = widget.engine == 'postgres' ? '"$colName"' : '`$colName`';
      var typeStr = col.dataType.toUpperCase();
      if (col.lengthPrecision.trim().isNotEmpty) {
        typeStr = '$typeStr(${col.lengthPrecision.trim()})';
      }

      final parts = <String>[qCol];
      if (col.isAutoIncrement) {
        if (widget.engine == 'sqlite') {
          parts.add('INTEGER PRIMARY KEY AUTOINCREMENT');
        } else {
          if (typeStr.contains('BIG')) {
            parts.add('BIGSERIAL PRIMARY KEY');
          } else {
            parts.add('SERIAL PRIMARY KEY');
          }
        }
      } else {
        parts.add(typeStr);
        if (col.isPrimaryKey) parts.add('PRIMARY KEY');
        if (!col.isNullable) parts.add('NOT NULL');
        if (col.isUnique && !col.isPrimaryKey) parts.add('UNIQUE');
        if (col.defaultValue.trim().isNotEmpty) {
          parts.add('DEFAULT ${col.defaultValue.trim()}');
        }
      }

      if (col.foreignKeyTable != null && col.foreignKeyColumn != null) {
        final fkTable = col.foreignKeyTable!;
        final fkCol = col.foreignKeyColumn!;
        final onDel = col.onForeignKeyDelete.isNotEmpty
            ? ' ON DELETE ${col.onForeignKeyDelete}'
            : '';
        if (widget.engine == 'postgres') {
          parts.add('REFERENCES "$fkTable" ("$fkCol")$onDel');
        } else {
          parts.add('REFERENCES `$fkTable` (`$fkCol`)$onDel');
        }
      }

      lines.add('  ${parts.join(' ')}');
    }

    final ine = _ifNotExists ? 'IF NOT EXISTS ' : '';
    return 'CREATE TABLE $ine$targetName (\n${lines.join(',\n')}\n);';
  }

  Future<void> _submit() async {
    final tableName = _tableNameCtrl.text.trim();
    if (tableName.isEmpty) {
      setState(() => _errorMessage = 'Table name cannot be empty');
      return;
    }
    if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(tableName)) {
      setState(
        () => _errorMessage = 'Table name must start with a letter/underscore and contain only alphanumeric characters.',
      );
      return;
    }

    for (final c in _columns) {
      if (c.name.trim().isEmpty) {
        setState(() => _errorMessage = 'Column names cannot be empty');
        return;
      }
      if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(c.name.trim())) {
        setState(
          () =>
              _errorMessage = 'Column "${c.name}" contains invalid characters.',
        );
        return;
      }
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onCreateTable(
        tableName: tableName,
        schemaName: _schemaCtrl.text.trim().isEmpty
            ? null
            : _schemaCtrl.text.trim(),
        columns: _columns.map((c) => c.toJson()).toList(),
        ifNotExists: _ifNotExists,
      );

      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isCreating = false;
          _errorMessage =
              'Failed to create table. Check server response or constraints.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _errorMessage = e.toString();
      });
    }
  }

  List<String> get _detectedSchemas {
    final set = <String>{};
    for (final t in widget.existingTables) {
      if (t.schema.trim().isNotEmpty) {
        set.add(t.schema.trim());
      }
    }
    if (widget.engine == 'postgres') {
      set.add('public');
    } else {
      set.add('main');
    }
    final list = set.toList()..sort();
    return list;
  }

  void _openSchemaSelectionBottomSheet(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final schemas = _detectedSchemas;
    final customCtrl = TextEditingController();
    final searchCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final query = searchCtrl.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? schemas
                : schemas
                      .where((s) => s.toLowerCase().contains(query))
                      .toList();

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 580,
                  maxHeight: MediaQuery.of(ctx).size.height * 0.70,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    border: Border.all(
                      color: primary.withValues(alpha: 0.35),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 20,
                        offset: const Offset(0, -6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(15),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Drag pill handle
                          Center(
                            child: Container(
                              margin: const EdgeInsets.only(top: 10, bottom: 6),
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          // Header
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.folder_copy_outlined,
                                    color: Color(0xFFF59E0B),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Select Database Schema',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Choose an existing schema or specify a custom schema',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () => Navigator.of(bCtx).pop(),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Filter search input
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: CyberTextField(
                              controller: searchCtrl,
                              hintText: 'Filter schemas...',
                              prefixIcon: const Icon(Icons.search, size: 16),
                              showClearButton: true,
                              height: 38,
                              onChanged: (_) => setModalState(() {}),
                            ),
                          ),

                          // Schemas List
                          Flexible(
                            child: filtered.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 24,
                                    ),
                                    child: Center(
                                      child: Text(
                                        'No existing schema matches "${searchCtrl.text}"',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: filtered.length,
                                    itemBuilder: (lCtx, i) {
                                      final s = filtered[i];
                                      final isSelected =
                                          _schemaCtrl.text.trim() == s;
                                      final tableCount = widget.existingTables
                                          .where((t) => t.schema == s)
                                          .length;

                                      return InkWell(
                                        onTap: () {
                                          setState(() {
                                            _schemaCtrl.text = s;
                                          });
                                          Navigator.of(bCtx).pop();
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? primary.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : Colors.transparent,
                                            border: Border(
                                              bottom: BorderSide(
                                                color: theme.dividerColor
                                                    .withValues(alpha: 0.1),
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.folder,
                                                size: 16,
                                                color: isSelected
                                                    ? primary
                                                    : const Color(0xFFF59E0B),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  s,
                                                  style: TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 12.5,
                                                    fontWeight: isSelected
                                                        ? FontWeight.bold
                                                        : FontWeight.w500,
                                                    color: isSelected
                                                        ? primary
                                                        : null,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: theme
                                                      .colorScheme
                                                      .surfaceContainerHighest
                                                      .withValues(alpha: 0.5),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '$tableCount tables',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ),
                                              if (isSelected) ...[
                                                const SizedBox(width: 8),
                                                Icon(
                                                  Icons.check,
                                                  size: 16,
                                                  color: primary,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),

                          const Divider(height: 1),

                          // Custom Schema Entry
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.15),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: CyberTextField(
                                    controller: customCtrl,
                                    hintText: 'Or enter custom schema (e.g. analytics)',
                                    isMonospace: true,
                                    height: 42,
                                    prefixIcon: const Icon(
                                      Icons.create_new_folder_outlined,
                                      size: 18,
                                    ),
                                    showClearButton: true,
                                    textInputAction: TextInputAction.done,
                                    onChanged: (_) => setModalState(() {}),
                                    onSubmitted: (text) {
                                      final trimmed = text.trim();
                                      if (trimmed.isNotEmpty &&
                                          RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$')
                                              .hasMatch(trimmed)) {
                                        setState(() {
                                          _schemaCtrl.text = trimmed;
                                        });
                                        Navigator.of(bCtx).pop();
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  onPressed: () {
                                    final text = customCtrl.text.trim();
                                    if (text.isNotEmpty &&
                                        RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$')
                                            .hasMatch(text)) {
                                      setState(() {
                                        _schemaCtrl.text = text;
                                      });
                                      Navigator.of(bCtx).pop();
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Use',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 0,
                                    ),
                                    minimumSize: const Size(0, 42),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
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
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: primary.withValues(alpha: 0.35)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(1080, screenWidth - 40),
          maxHeight: math.max(680, screenHeight * 0.92),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.2),
                  ),
                ),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.add_box_outlined,
                      color: primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Create New Table',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Engine: ${widget.engine.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 270,
                    child: TabBar(
                      controller: _tabCtrl,
                      indicatorColor: primary,
                      labelColor: primary,
                      unselectedLabelColor: Colors.grey,
                      labelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                      tabs: const [
                        Tab(text: 'Columns Builder'),
                        Tab(text: 'SQL DDL Preview'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 18,
                      color: Colors.redAccent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Top Configuration Bar (Table Name, Schema, IF NOT EXISTS)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: CyberTextField(
                      controller: _tableNameCtrl,
                      labelText: 'Table Name',
                      hintText: 'e.g. inventory_items',
                      isMonospace: true,
                      fontSize: 13,
                      height: 46,
                      prefixIcon: const Icon(
                        Icons.table_chart_outlined,
                        size: 18,
                      ),
                      showClearButton: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 14),
                  if (widget.engine == 'postgres') ...[
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: () => _openSchemaSelectionBottomSheet(context),
                        borderRadius: BorderRadius.circular(8),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Schema',
                            labelStyle: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.25),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: theme.dividerColor.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            suffixIcon: const Icon(
                              Icons.keyboard_arrow_down,
                              size: 20,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.folder_outlined,
                                size: 16,
                                color: Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _schemaCtrl.text.isEmpty
                                      ? 'public'
                                      : _schemaCtrl.text,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.2),
                      ),
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.15),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _ifNotExists,
                          onChanged: (v) =>
                              setState(() => _ifNotExists = v ?? true),
                          activeColor: primary,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'IF NOT EXISTS',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Tab Views: Columns Builder vs SQL DDL Preview
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Tab 1: Columns Builder
                  Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'COLUMNS DEFINITION (${_columns.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                                letterSpacing: 0.5,
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: _addColumn,
                              icon: const Icon(Icons.add, size: 15),
                              label: const Text(
                                'Add Column',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Remastered Spreadsheet DataGrid
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              const colWidthIndex = 36.0;
                              const colWidthName = 220.0;
                              const colWidthType = 170.0;
                              const colWidthLen = 88.0;
                              const colWidthCheck = 46.0;
                              const colWidthDefault = 190.0;
                              const colWidthActions = 44.0;

                              const totalMinWidth = colWidthIndex +
                                  colWidthName +
                                  colWidthType +
                                  colWidthLen +
                                  (colWidthCheck * 4) +
                                  colWidthDefault +
                                  colWidthActions;

                              final tableWidth = math.max(totalMinWidth, constraints.maxWidth);

                              return Container(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: theme.dividerColor.withValues(alpha: 0.20),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: tableWidth,
                                    height: constraints.maxHeight,
                                    child: Column(
                                      children: [
                                        // Header Row
                                        Container(
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
                                            border: Border(
                                              bottom: BorderSide(
                                                color: theme.dividerColor.withValues(alpha: 0.25),
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              _buildHeaderCell('#', width: colWidthIndex, theme: theme, center: true),
                                              _buildHeaderCell('COLUMN NAME', width: colWidthName, theme: theme),
                                              _buildHeaderCell('DATA TYPE', width: colWidthType, theme: theme),
                                              _buildHeaderCell('LEN / PREC', width: colWidthLen, theme: theme),
                                              _buildHeaderCell('PK', width: colWidthCheck, theme: theme, center: true, tooltip: 'Primary Key'),
                                              _buildHeaderCell('AI', width: colWidthCheck, theme: theme, center: true, tooltip: 'Auto Increment / Serial'),
                                              _buildHeaderCell('NULL', width: colWidthCheck, theme: theme, center: true, tooltip: 'Nullable'),
                                              _buildHeaderCell('UQ', width: colWidthCheck, theme: theme, center: true, tooltip: 'Unique Constraint'),
                                              Expanded(
                                                child: _buildHeaderCell('DEFAULT VALUE', width: null, theme: theme),
                                              ),
                                              _buildHeaderCell('', width: colWidthActions, theme: theme, center: true, isLast: true),
                                            ],
                                          ),
                                        ),

                                        // Rows Body
                                        Expanded(
                                          child: ListView.builder(
                                            itemCount: _columns.length,
                                            itemBuilder: (context, idx) {
                                              final col = _columns[idx];
                                              final isAlternate = idx.isOdd;
                                              final cellBorderColor = theme.dividerColor.withValues(alpha: 0.16);

                                              return Container(
                                                height: 38,
                                                decoration: BoxDecoration(
                                                  color: isAlternate
                                                      ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.08)
                                                      : Colors.transparent,
                                                  border: Border(
                                                    bottom: BorderSide(color: cellBorderColor, width: 1),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    // Index Cell
                                                    Container(
                                                      width: colWidthIndex,
                                                      height: 38,
                                                      alignment: Alignment.center,
                                                      decoration: BoxDecoration(
                                                        border: Border(right: BorderSide(color: cellBorderColor, width: 1)),
                                                      ),
                                                      child: Text(
                                                        '${idx + 1}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontFamily: 'monospace',
                                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.40),
                                                        ),
                                                      ),
                                                    ),

                                                    // Column Name Cell
                                                    Container(
                                                      width: colWidthName,
                                                      height: 38,
                                                      decoration: BoxDecoration(
                                                        border: Border(right: BorderSide(color: cellBorderColor, width: 1)),
                                                      ),
                                                      child: _GridTextCell(
                                                        initialValue: col.name,
                                                        hintText: 'column_name',
                                                        isMonospace: true,
                                                        fontSize: 12.5,
                                                        fontWeight: FontWeight.w600,
                                                        onChanged: (v) => col.name = v,
                                                      ),
                                                    ),

                                                    // Data Type Cell
                                                    Container(
                                                      width: colWidthType,
                                                      height: 38,
                                                      decoration: BoxDecoration(
                                                        border: Border(right: BorderSide(color: cellBorderColor, width: 1)),
                                                      ),
                                                      child: _GridDataTypeCell(
                                                        selectedType: col.dataType,
                                                        availableTypes: _availableDataTypes,
                                                        onChanged: (newType) {
                                                          setState(() => col.dataType = newType);
                                                        },
                                                      ),
                                                    ),

                                                    // Length / Precision Cell
                                                    Container(
                                                      width: colWidthLen,
                                                      height: 38,
                                                      decoration: BoxDecoration(
                                                        border: Border(right: BorderSide(color: cellBorderColor, width: 1)),
                                                      ),
                                                      child: _GridTextCell(
                                                        initialValue: col.lengthPrecision,
                                                        hintText: '255',
                                                        isMonospace: true,
                                                        fontSize: 12,
                                                        alignment: Alignment.centerLeft,
                                                        onChanged: (v) => col.lengthPrecision = v,
                                                      ),
                                                    ),

                                                    // PK Cell
                                                    Container(
                                                      width: colWidthCheck,
                                                      height: 38,
                                                      alignment: Alignment.center,
                                                      decoration: BoxDecoration(
                                                        border: Border(right: BorderSide(color: cellBorderColor, width: 1)),
                                                      ),
                                                      child: _CyberCellCheckbox(
                                                        value: col.isPrimaryKey,
                                                        activeColor: const Color(0xFFF59E0B),
                                                        tooltip: 'Primary Key',
                                                        onChanged: (v) => setState(() {
                                                          col.isPrimaryKey = v;
                                                          if (col.isPrimaryKey) col.isNullable = false;
                                                        }),
                                                      ),
                                                    ),

                                                    // AI Cell
                                                    Container(
                                                      width: colWidthCheck,
                                                      height: 38,
                                                      alignment: Alignment.center,
                                                      decoration: BoxDecoration(
                                                        border: Border(right: BorderSide(color: cellBorderColor, width: 1)),
                                                      ),
                                                      child: _CyberCellCheckbox(
                                                        value: col.isAutoIncrement,
                                                        activeColor: const Color(0xFF06B6D4),
                                                        tooltip: 'Auto Increment',
                                                        onChanged: (v) => setState(() {
                                                          col.isAutoIncrement = v;
                                                          if (col.isAutoIncrement) {
                                                            col.isPrimaryKey = true;
                                                            col.isNullable = false;
                                                          }
                                                        }),
                                                      ),
                                                    ),

                                                    // NULL Cell
                                                    Container(
                                                      width: colWidthCheck,
                                                      height: 38,
                                                      alignment: Alignment.center,
                                                      decoration: BoxDecoration(
                                                        border: Border(right: BorderSide(color: cellBorderColor, width: 1)),
                                                      ),
                                                      child: _CyberCellCheckbox(
                                                        value: col.isNullable,
                                                        activeColor: theme.colorScheme.primary,
                                                        enabled: !col.isPrimaryKey,
                                                        tooltip: 'Nullable',
                                                        onChanged: (v) => setState(() => col.isNullable = v),
                                                      ),
                                                    ),

                                                    // UQ Cell
                                                    Container(
                                                      width: colWidthCheck,
                                                      height: 38,
                                                      alignment: Alignment.center,
                                                      decoration: BoxDecoration(
                                                        border: Border(right: BorderSide(color: cellBorderColor, width: 1)),
                                                      ),
                                                      child: _CyberCellCheckbox(
                                                        value: col.isUnique,
                                                        activeColor: const Color(0xFF10B981),
                                                        tooltip: 'Unique Constraint',
                                                        onChanged: (v) => setState(() => col.isUnique = v),
                                                      ),
                                                    ),

                                                    // Default Value Cell
                                                    Expanded(
                                                      child: Container(
                                                        height: 38,
                                                        decoration: BoxDecoration(
                                                          border: Border(right: BorderSide(color: cellBorderColor, width: 1)),
                                                        ),
                                                        child: _GridTextCell(
                                                          initialValue: col.defaultValue,
                                                          hintText: 'NULL / 0 / CURRENT_TIMESTAMP',
                                                          isMonospace: true,
                                                          fontSize: 12,
                                                          onChanged: (v) => col.defaultValue = v,
                                                        ),
                                                      ),
                                                    ),

                                                    // Actions Cell
                                                    Container(
                                                      width: colWidthActions,
                                                      height: 38,
                                                      alignment: Alignment.center,
                                                      child: IconButton(
                                                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                                        onPressed: _columns.length > 1 ? () => _removeColumn(idx) : null,
                                                        tooltip: 'Delete column',
                                                        padding: EdgeInsets.zero,
                                                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                        visualDensity: VisualDensity.compact,
                                                      ),
                                                    ),
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
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab 2: SQL DDL Preview
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'GENERATED DDL STATEMENT',
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                final ddl = _generateDdlPreview();
                                Clipboard.setData(ClipboardData(text: ddl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('DDL copied to clipboard'),
                                    duration: Duration(seconds: 1),
                                    behavior: SnackBarBehavior.floating,
                                    width: 220,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text(
                                'Copy SQL',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                _generateDdlPreview(),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                  color: Color(0xFF38BDF8),
                                  height: 1.5,
                                ),
                              ),
                            ),
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
                  top: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.2),
                  ),
                ),
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.15,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isCreating
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isCreating ? null : _submit,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 16),
                    label: Text(
                      _isCreating ? 'Creating Table...' : 'Create Table',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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

  Widget _buildHeaderCell(
    String label, {
    required double? width,
    required ThemeData theme,
    bool center = false,
    bool isLast = false,
    String? tooltip,
  }) {
    final cellBorder = BorderSide(color: theme.dividerColor.withValues(alpha: 0.20), width: 1);

    Widget textWidget = Text(
      label,
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.4,
        color: Colors.grey,
      ),
      overflow: TextOverflow.ellipsis,
    );

    if (tooltip != null) {
      textWidget = Tooltip(message: tooltip, child: textWidget);
    }

    final containerChild = Container(
      height: 36,
      alignment: center ? Alignment.center : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: center ? 2 : 10),
      decoration: BoxDecoration(
        border: isLast ? null : Border(right: cellBorder),
      ),
      child: textWidget,
    );

    if (width != null) {
      return SizedBox(width: width, child: containerChild);
    }
    return containerChild;
  }
}

/// Custom 18x18px micro-checkbox designed specifically for data-grid rows.
class _CyberCellCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color activeColor;
  final bool enabled;
  final String? tooltip;

  const _CyberCellCheckbox({
    required this.value,
    required this.onChanged,
    required this.activeColor,
    this.enabled = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CyberCheckbox(
        value: value,
        onChanged: enabled && onChanged != null ? (v) => onChanged!(v ?? false) : null,
        activeColor: activeColor,
        tooltip: tooltip,
        size: 18.0,
      ),
    );
  }
}

/// Seamless in-cell editable text field designed to blend directly into spreadsheet rows.
class _GridTextCell extends StatefulWidget {
  final String initialValue;
  final String hintText;
  final bool isMonospace;
  final double fontSize;
  final FontWeight fontWeight;
  final Alignment alignment;
  final ValueChanged<String> onChanged;

  const _GridTextCell({
    required this.initialValue,
    required this.hintText,
    this.isMonospace = false,
    this.fontSize = 12.5,
    this.fontWeight = FontWeight.normal,
    this.alignment = Alignment.centerLeft,
    required this.onChanged,
  });

  @override
  State<_GridTextCell> createState() => _GridTextCellState();
}

class _GridTextCellState extends State<_GridTextCell> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode.addListener(() {
      if (mounted) {
        setState(() => _isFocused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _GridTextCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue && _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      alignment: widget.alignment,
      decoration: BoxDecoration(
        color: _isFocused
            ? primary.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontFamily: widget.isMonospace ? 'monospace' : null,
          fontWeight: widget.fontWeight,
          color: theme.colorScheme.onSurface,
        ),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: widget.fontSize,
            fontFamily: widget.isMonospace ? 'monospace' : null,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// Seamless in-cell data type bottom-sheet selector with badge aesthetics.
class _GridDataTypeCell extends StatelessWidget {
  final String selectedType;
  final List<String> availableTypes;
  final ValueChanged<String> onChanged;

  const _GridDataTypeCell({
    required this.selectedType,
    required this.availableTypes,
    required this.onChanged,
  });

  String _getTypeCategory(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('INT') ||
        upper.contains('SERIAL') ||
        upper.contains('FLOAT') ||
        upper.contains('DOUBLE') ||
        upper.contains('DECIMAL') ||
        upper.contains('NUMERIC') ||
        upper.contains('REAL')) {
      return 'Numeric';
    }
    if (upper.contains('CHAR') ||
        upper.contains('TEXT') ||
        upper.contains('CLOB') ||
        upper.contains('STRING')) {
      return 'Text / String';
    }
    if (upper.contains('DATE') ||
        upper.contains('TIME') ||
        upper.contains('YEAR') ||
        upper.contains('TIMESTAMP')) {
      return 'Date / Time';
    }
    if (upper.contains('BOOL')) {
      return 'Boolean';
    }
    if (upper.contains('JSON') ||
        upper.contains('XML') ||
        upper.contains('BLOB') ||
        upper.contains('BYTE') ||
        upper.contains('UUID')) {
      return 'Complex / Binary';
    }
    return 'Data Type';
  }

  IconData _getTypeIcon(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('INT') ||
        upper.contains('SERIAL') ||
        upper.contains('NUMERIC') ||
        upper.contains('DECIMAL')) {
      return Icons.tag;
    }
    if (upper.contains('CHAR') || upper.contains('TEXT')) {
      return Icons.text_fields;
    }
    if (upper.contains('DATE') ||
        upper.contains('TIME') ||
        upper.contains('TIMESTAMP')) {
      return Icons.calendar_today_outlined;
    }
    if (upper.contains('BOOL')) {
      return Icons.toggle_on_outlined;
    }
    if (upper.contains('JSON')) {
      return Icons.data_object;
    }
    if (upper.contains('BLOB') || upper.contains('BYTE')) {
      return Icons.memory;
    }
    return Icons.code;
  }

  Future<void> _openSelector(BuildContext context) async {
    final items = availableTypes.map((type) {
      return CyberDropdownItem<String>(
        value: type,
        label: type,
        subtitle: _getTypeCategory(type),
        icon: _getTypeIcon(type),
      );
    }).toList();

    final selected = await showCyberDropdownBottomSheet<String>(
      context: context,
      title: 'Select Data Type',
      items: items,
      selectedValue: selectedType,
      searchHint: 'Filter data types (e.g. VARCHAR, INT, JSON)...',
      headerIcon: Icons.data_object,
    );

    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSelector(context),
        hoverColor: primary.withValues(alpha: 0.05),
        splashColor: primary.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selectedType.isNotEmpty ? selectedType : 'TEXT',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.unfold_more,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

