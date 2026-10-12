class MutationRecord {
  final String id;
  final String timestamp;
  final String tableName;
  final String operation; // "update" | "delete"
  final Map<String, dynamic> primaryKeys;
  final Map<String, dynamic> oldValues;
  final Map<String, dynamic>? newValues;
  final String inverseSql;
  final bool isRecovered;

  const MutationRecord({
    required this.id,
    required this.timestamp,
    required this.tableName,
    required this.operation,
    required this.primaryKeys,
    required this.oldValues,
    this.newValues,
    required this.inverseSql,
    this.isRecovered = false,
  });

  factory MutationRecord.fromJson(Map<String, dynamic> json) {
    return MutationRecord(
      id: json['id'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      tableName: json['table_name'] as String? ?? '',
      operation: json['operation'] as String? ?? 'update',
      primaryKeys: json['primary_keys'] != null
          ? Map<String, dynamic>.from(json['primary_keys'] as Map)
          : {},
      oldValues: json['old_values'] != null
          ? Map<String, dynamic>.from(json['old_values'] as Map)
          : {},
      newValues: json['new_values'] != null
          ? Map<String, dynamic>.from(json['new_values'] as Map)
          : null,
      inverseSql: json['inverse_sql'] as String? ?? '',
      isRecovered: json['is_recovered'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp,
      'table_name': tableName,
      'operation': operation,
      'primary_keys': primaryKeys,
      'old_values': oldValues,
      'new_values': newValues,
      'inverse_sql': inverseSql,
      'is_recovered': isRecovered,
    };
  }
}
