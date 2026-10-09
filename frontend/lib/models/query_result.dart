class QueryResult {
  final List<String> columns;
  final List<List<dynamic>> rows;
  final int rowCount;
  final double executionTimeMs;
  final String? error;
  final int? totalRows;
  final int? page;
  final int? pageSize;
  final bool? hasMore;

  QueryResult({
    required this.columns,
    required this.rows,
    required this.rowCount,
    required this.executionTimeMs,
    this.error,
    this.totalRows,
    this.page,
    this.pageSize,
    this.hasMore,
  });

  bool get hasError => error != null && error!.isNotEmpty;
  bool get isSuccess => !hasError;

  factory QueryResult.fromJson(Map<String, dynamic> json) {
    final rawCols = json['columns'] as List<dynamic>? ?? [];
    final rawRows = json['rows'] as List<dynamic>? ?? [];

    return QueryResult(
      columns: rawCols.map((c) => c.toString()).toList(),
      rows: rawRows.map((r) => (r as List<dynamic>)).toList(),
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      executionTimeMs: (json['execution_time_ms'] as num?)?.toDouble() ?? 0.0,
      error: json['error'] as String?,
      totalRows: (json['total_rows'] as num?)?.toInt(),
      page: (json['page'] as num?)?.toInt(),
      pageSize: (json['page_size'] as num?)?.toInt(),
      hasMore: json['has_more'] as bool?,
    );
  }
}
