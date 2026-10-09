class AuditEvent {
  final String id;
  final String timestamp;
  final String source; // 'ANTIGRAVITY_MCP' | 'FLUTTER_UI'
  final String action;
  final String? sql;
  final String status; // 'ALLOWED' | 'BLOCKED' | 'ERROR'
  final double executionTimeMs;
  final int rowCount;
  final String? message;

  AuditEvent({
    required this.id,
    required this.timestamp,
    required this.source,
    required this.action,
    this.sql,
    required this.status,
    required this.executionTimeMs,
    required this.rowCount,
    this.message,
  });

  bool get isBlocked => status == 'BLOCKED';
  bool get isAllowed => status == 'ALLOWED';

  factory AuditEvent.fromJson(Map<String, dynamic> json) {
    return AuditEvent(
      id: json['id'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      source: json['source'] as String? ?? 'UNKNOWN',
      action: json['action'] as String? ?? '',
      sql: json['sql'] as String?,
      status: json['status'] as String? ?? 'ALLOWED',
      executionTimeMs: (json['execution_time_ms'] as num?)?.toDouble() ?? 0.0,
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      message: json['message'] as String?,
    );
  }
}
