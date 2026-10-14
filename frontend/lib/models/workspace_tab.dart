import 'query_result.dart';
import 'table_schema.dart';

enum WorkspaceTabType {
  sqlQuery,
  tablePreview,
  schemaOverview,
}

/// Represents an individual open tab inside the SQL Studio workspace.
/// Preserves query buffer, result sets, table preview pagination, and filters in memory.
class WorkspaceTab {
  final String id;
  String title;
  WorkspaceTabType type;
  String? schemaName;
  String? tableName;
  TableMetadata? tableMetadata;
  String queryText;
  QueryResult? result;
  bool isExecuting;
  int page;
  int pageSize;
  String filterText;
  int? sortColumnIndex;
  bool sortAscending;

  WorkspaceTab({
    required this.id,
    required this.title,
    required this.type,
    this.schemaName,
    this.tableName,
    this.tableMetadata,
    this.queryText = '',
    this.result,
    this.isExecuting = false,
    this.page = 1,
    this.pageSize = 25,
    this.filterText = '',
    this.sortColumnIndex,
    this.sortAscending = true,
  });

  bool get isTablePreview => type == WorkspaceTabType.tablePreview;
  bool get isSqlQuery => type == WorkspaceTabType.sqlQuery;
  bool get isSchemaOverview => type == WorkspaceTabType.schemaOverview;

  WorkspaceTab copyWith({
    String? id,
    String? title,
    WorkspaceTabType? type,
    String? schemaName,
    String? tableName,
    TableMetadata? tableMetadata,
    String? queryText,
    QueryResult? result,
    bool? isExecuting,
    int? page,
    int? pageSize,
    String? filterText,
    int? sortColumnIndex,
    bool? sortAscending,
  }) {
    return WorkspaceTab(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      schemaName: schemaName ?? this.schemaName,
      tableName: tableName ?? this.tableName,
      tableMetadata: tableMetadata ?? this.tableMetadata,
      queryText: queryText ?? this.queryText,
      result: result ?? this.result,
      isExecuting: isExecuting ?? this.isExecuting,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      filterText: filterText ?? this.filterText,
      sortColumnIndex: sortColumnIndex ?? this.sortColumnIndex,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}
