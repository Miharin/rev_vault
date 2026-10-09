class ForeignKeyMetadata {
  final String columnName;
  final String targetTable;
  final String targetColumn;
  final String? constraintName;

  ForeignKeyMetadata({
    required this.columnName,
    required this.targetTable,
    required this.targetColumn,
    this.constraintName,
  });

  factory ForeignKeyMetadata.fromJson(Map<String, dynamic> json) {
    return ForeignKeyMetadata(
      columnName: json['column_name'] as String? ?? '',
      targetTable: json['target_table'] as String? ?? '',
      targetColumn: json['target_column'] as String? ?? 'id',
      constraintName: json['constraint_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'column_name': columnName,
    'target_table': targetTable,
    'target_column': targetColumn,
    'constraint_name': constraintName,
  };
}

class ColumnMetadata {
  final String name;
  final String dataType;
  final bool isNullable;
  final bool isPrimaryKey;
  final String? defaultValue;
  final ForeignKeyMetadata? foreignKey;
  final bool isUnique;

  ColumnMetadata({
    required this.name,
    required this.dataType,
    required this.isNullable,
    required this.isPrimaryKey,
    this.defaultValue,
    this.foreignKey,
    this.isUnique = false,
  });

  factory ColumnMetadata.fromJson(Map<String, dynamic> json) {
    final fkJson = json['foreign_key'] as Map<String, dynamic>?;
    return ColumnMetadata(
      name: json['name'] as String,
      dataType: json['data_type'] as String,
      isNullable: json['is_nullable'] as bool? ?? false,
      isPrimaryKey: json['is_primary_key'] as bool? ?? false,
      defaultValue: json['default_value'] as String?,
      foreignKey: fkJson != null ? ForeignKeyMetadata.fromJson(fkJson) : null,
      isUnique: json['is_unique'] as bool? ?? false,
    );
  }
}

class TableMetadata {
  final String name;
  final String schema;
  final String rawName;
  final String tableType;
  final List<ColumnMetadata> columns;
  final List<ForeignKeyMetadata> foreignKeys;

  TableMetadata({
    required this.name,
    required this.schema,
    String? rawName,
    required this.tableType,
    required this.columns,
    this.foreignKeys = const [],
  }) : rawName = rawName ?? (name.contains('.') ? name.split('.').last : name);

  String get displayName => name;

  factory TableMetadata.fromJson(Map<String, dynamic> json) {
    final rawCols = json['columns'] as List<dynamic>? ?? [];
    final rawFks = json['foreign_keys'] as List<dynamic>? ?? [];
    final name = json['name'] as String;
    return TableMetadata(
      name: name,
      schema: json['schema'] as String? ?? 'main',
      rawName: json['raw_name'] as String?,
      tableType: json['table_type'] as String? ?? 'TABLE',
      columns: rawCols.map((c) => ColumnMetadata.fromJson(c as Map<String, dynamic>)).toList(),
      foreignKeys: rawFks.map((fk) => ForeignKeyMetadata.fromJson(fk as Map<String, dynamic>)).toList(),
    );
  }
}
