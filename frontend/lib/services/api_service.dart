import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/connection.dart';
import '../models/table_schema.dart';
import '../models/query_result.dart';
import '../models/audit_event.dart';
import '../models/saved_query.dart';
import '../models/mutation_record.dart';

String getDefaultBaseUrl() {
  if (kIsWeb) {
    final host = Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
    final scheme = Uri.base.scheme.startsWith('https') ? 'https' : 'http';
    return '$scheme://$host:8000';
  }
  return 'http://127.0.0.1:8000';
}

class ApiService {
  String _baseUrl;
  String get baseUrl => _baseUrl;

  ApiService({String? baseUrl}) : _baseUrl = baseUrl ?? getDefaultBaseUrl();

  void setBaseUrl(String url) {
    _baseUrl = url;
  }

  Future<bool> checkHealth({
    int retries = 5,
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    for (int i = 0; i < retries; i++) {
      try {
        final res = await http
            .get(Uri.parse('$baseUrl/health'))
            .timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) return true;
      } catch (_) {
        // Retry if attempts remain
      }
      if (i < retries - 1) {
        await Future.delayed(delay);
      }
    }
    return false;
  }

  Future<List<ConnectionConfig>> getConnections() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/connections'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((e) => ConnectionConfig.fromJson(e as Map<String, dynamic>)).toList();
      }
      throw Exception('Failed to fetch connections: ${res.body}');
    } catch (e) {
      if (e is http.ClientException) {
        throw Exception('Cannot connect to RevVault backend at $baseUrl: ${e.message}. Is run_server.py running?');
      }
      rethrow;
    }
  }

  Future<ConnectionConfig> saveConnection(ConnectionConfig conn) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/connections'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(conn.toJson()),
      );
      if (res.statusCode == 200) {
        return ConnectionConfig.fromJson(jsonDecode(res.body));
      }
      throw Exception('Failed to save connection: ${res.body}');
    } catch (e) {
      if (e is http.ClientException) {
        throw Exception('Cannot connect to RevVault backend at $baseUrl: ${e.message}. Is run_server.py running?');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> testConnection(ConnectionConfig conn) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/connections/test'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'config': conn.toJson()}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {'success': false, 'message': 'Backend error (${res.statusCode}): ${res.body}'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Cannot reach RevVault backend at $baseUrl ($e). Please start the backend: python run_server.py'
      };
    }
  }

  Future<void> deleteConnection(String id) async {
    try {
      final res = await http.delete(Uri.parse('$baseUrl/api/connections/$id'));
      if (res.statusCode != 200) {
        throw Exception('Failed to delete connection');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<ConnectionConfig> setActiveConnection(String id) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/api/connections/active/$id'));
      if (res.statusCode == 200) {
        return ConnectionConfig.fromJson(jsonDecode(res.body));
      }
      throw Exception('Failed to activate connection: ${res.body}');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<TableMetadata>> getSchema({bool includeViews = true, bool refresh = false}) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/schema?include_views=$includeViews&refresh=$refresh'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((e) => TableMetadata.fromJson(e as Map<String, dynamic>)).toList();
      }
      throw Exception('Failed to fetch schema: ${res.body}');
    } catch (e) {
      rethrow;
    }
  }

  Future<QueryResult> executeQuery(String sql, {bool safeMode = true, int? limit, int? offset}) async {
    try {
      final Map<String, dynamic> body = {
        'sql': sql,
        'safe_mode': safeMode,
      };
      if (limit != null) {
        body['requested_limit'] = limit;
      }
      if (offset != null) {
        body['offset'] = offset;
      }

      final res = await http.post(
        Uri.parse('$baseUrl/api/query'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      if (res.statusCode == 200) {
        return QueryResult.fromJson(jsonDecode(res.body));
      }
      return QueryResult(
        columns: [],
        rows: [],
        rowCount: 0,
        executionTimeMs: 0.0,
        error: 'HTTP error ${res.statusCode}: ${res.body}',
      );
    } catch (e) {
      return QueryResult(
        columns: [],
        rows: [],
        rowCount: 0,
        executionTimeMs: 0.0,
        error: 'Backend communication error: $e',
      );
    }
  }

  Future<Map<String, dynamic>> mutateRow({
    required String tableName,
    required String operation,
    Map<String, dynamic>? primaryKeys,
    Map<String, dynamic>? updatedValues,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/query/row/mutate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'table_name': tableName,
          'operation': operation,
          'primary_keys': primaryKeys ?? {},
          'updated_values': updatedValues,
        }),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {
        'success': false,
        'error': 'HTTP error ${res.statusCode}: ${res.body}',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Backend communication error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> bulkMutateRows({
    required String tableName,
    required String operation,
    List<Map<String, dynamic>>? rowsPks,
    List<Map<String, dynamic>>? rowsData,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/query/row/bulk-mutate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'table_name': tableName,
          'operation': operation,
          'rows_pks': rowsPks,
          'rows_data': rowsData,
        }),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {
        'success': false,
        'error': 'HTTP error ${res.statusCode}: ${res.body}',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Backend communication error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> createTable({
    required String tableName,
    String? schemaName,
    required List<Map<String, dynamic>> columns,
    bool ifNotExists = true,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/schema/table/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'table_name': tableName,
          'schema_name': schemaName,
          'columns': columns,
          'if_not_exists': ifNotExists,
        }),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {
        'success': false,
        'error': 'Failed to create table (${res.statusCode}): ${res.body}',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Backend communication error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> dropTable({
    required String tableName,
    String? schemaName,
    bool cascade = false,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/schema/table/drop'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'table_name': tableName,
          'schema_name': schemaName,
          'cascade': cascade,
        }),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {
        'success': false,
        'error': 'Failed to drop table (${res.statusCode}): ${res.body}',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Backend communication error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> truncateTable({
    required String tableName,
    String? schemaName,
    bool cascade = false,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/schema/table/truncate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'table_name': tableName,
          'schema_name': schemaName,
          'cascade': cascade,
        }),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {
        'success': false,
        'error': 'Failed to truncate table (${res.statusCode}): ${res.body}',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Backend communication error: $e',
      };
    }
  }

  Future<QueryResult> previewTable(String tableName, {int page = 1, int pageSize = 25}) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/query/preview/$tableName?page=$page&page_size=$pageSize'));
      if (res.statusCode == 200) {
        return QueryResult.fromJson(jsonDecode(res.body));
      }
      return QueryResult(
        columns: [],
        rows: [],
        rowCount: 0,
        executionTimeMs: 0.0,
        error: 'Failed to preview table: ${res.body}',
      );
    } catch (e) {
      return QueryResult(
        columns: [],
        rows: [],
        rowCount: 0,
        executionTimeMs: 0.0,
        error: 'Backend communication error: $e',
      );
    }
  }

  Future<List<AuditEvent>> getAuditHistory() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/audit'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((e) => AuditEvent.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<SavedQuery>> getSavedQueries() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/query/saved'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((e) => SavedQuery.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<SavedQuery?> saveQuery(SavedQuery query) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/query/saved'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(query.toJson()),
      );
      if (res.statusCode == 200) {
        return SavedQuery.fromJson(jsonDecode(res.body));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> deleteSavedQuery(String id) async {
    try {
      final res = await http.delete(Uri.parse('$baseUrl/api/query/saved/$id'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getRelationships({bool refresh = false}) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/schema/relationships?refresh=$refresh'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> explainQuery({required String sql, bool analyze = false}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/query/explain'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sql': sql, 'analyze': analyze}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {
        'error': 'Explain failed (${res.statusCode}): ${res.body}',
        'engine': 'unknown',
        'warnings': <dynamic>[],
        'recommendations': <dynamic>[],
      };
    } catch (e) {
      return {
        'error': 'Network error contacting backend: $e',
        'engine': 'unknown',
        'warnings': <dynamic>[],
        'recommendations': <dynamic>[],
      };
    }
  }

  Future<List<MutationRecord>> getMutationHistory() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/query/history'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.map((e) => MutationRecord.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> recoverMutation(String historyId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/query/history/recover/$historyId'),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return {
        'success': false,
        'error': 'Recovery failed (${res.statusCode}): ${res.body}',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error contacting backend: $e',
      };
    }
  }
}

