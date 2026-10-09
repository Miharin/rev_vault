class SavedQuery {
  final String id;
  final String title;
  final String? description;
  final String sql;
  final String builderMode;
  final String? createdAt;

  SavedQuery({
    required this.id,
    required this.title,
    this.description,
    required this.sql,
    this.builderMode = 'rawSql',
    this.createdAt,
  });

  factory SavedQuery.fromJson(Map<String, dynamic> json) {
    return SavedQuery(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      sql: json['sql'] as String,
      builderMode: (json['builder_mode'] ?? json['builderMode'] ?? 'rawSql') as String,
      createdAt: (json['created_at'] ?? json['createdAt']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description ?? '',
      'sql': sql,
      'builder_mode': builderMode,
      'created_at': createdAt ?? DateTime.now().toIso8601String(),
    };
  }

  SavedQuery copyWith({
    String? id,
    String? title,
    String? description,
    String? sql,
    String? builderMode,
    String? createdAt,
  }) {
    return SavedQuery(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      sql: sql ?? this.sql,
      builderMode: builderMode ?? this.builderMode,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
