import 'query_result.dart';

/// Represents a single conversational message in the RevVault AI Assistant.
/// Contains role, textual content, tool executions breakdown, structured query data, and timestamp.
class AiAssistantMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final List<Map<String, dynamic>> toolExecutions;
  final DateTime timestamp;

  AiAssistantMessage({
    required this.role,
    required this.content,
    this.toolExecutions = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Extracts the structured QueryResult if any tool execution returned query data directly
  QueryResult? get primaryQueryResult {
    for (final tool in toolExecutions) {
      if (tool['data'] is Map<String, dynamic>) {
        final data = tool['data'] as Map<String, dynamic>;
        if (data.containsKey('columns') && data.containsKey('rows')) {
          try {
            return QueryResult.fromJson(data);
          } catch (_) {}
        }
      }
    }
    return null;
  }

  /// Extracts the SQL string associated with the primary query execution if present
  String? get primaryQuerySql {
    for (final tool in toolExecutions) {
      if (tool['data'] is Map<String, dynamic>) {
        final data = tool['data'] as Map<String, dynamic>;
        if (data['sql'] != null && data['sql'].toString().isNotEmpty) {
          return data['sql'].toString();
        }
      }
      final args = tool['arguments'];
      if (args is Map<String, dynamic> && args['sql'] != null) {
        return args['sql'].toString();
      }
    }
    return null;
  }

  Map<String, dynamic> toHistoryMap() => {
    'role': role,
    'content': content,
  };
}
