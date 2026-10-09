class ConnectionConfig {
  final String id;
  final String name;
  final String engine; // 'sqlite' | 'postgres'
  final String? filepath;
  final String? host;
  final int port;
  final String? database;
  final String? username;
  final String? password;
  final String ssl;
  final bool isActive;

  ConnectionConfig({
    required this.id,
    required this.name,
    required this.engine,
    this.filepath,
    this.host,
    this.port = 5432,
    this.database,
    this.username,
    this.password,
    this.ssl = 'prefer',
    this.isActive = false,
  });

  factory ConnectionConfig.fromJson(Map<String, dynamic> json) {
    return ConnectionConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      engine: json['engine'] as String,
      filepath: json['filepath'] as String?,
      host: json['host'] as String?,
      port: (json['port'] as num?)?.toInt() ?? 5432,
      database: json['database'] as String?,
      username: json['username'] as String?,
      password: json['password'] as String?,
      ssl: json['ssl'] as String? ?? 'prefer',
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'engine': engine,
      'filepath': filepath,
      'host': host,
      'port': port,
      'database': database,
      'username': username,
      'password': password,
      'ssl': ssl,
      'is_active': isActive,
    };
  }
}
