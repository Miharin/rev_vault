import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/connection.dart';
import '../models/table_schema.dart';
import '../models/query_result.dart';
import '../models/audit_event.dart';
import '../models/saved_query.dart';
import '../services/api_service.dart';
import '../services/audit_stream_service.dart';
import '../services/sql_autocomplete_service.dart';
import '../services/backend_sidecar_service.dart';
import '../services/backend_config_service.dart';

import '../theme/cyber_theme.dart';

class AppState extends ChangeNotifier {
  final ApiService api;
  final AuditStreamService auditStream;

  AppState({
    ApiService? api,
    AuditStreamService? auditStream,
  })  : api = api ?? ApiService(),
        auditStream = auditStream ?? AuditStreamService();

  // Cyber Theme & Circadian Engine
  ThemePreference themePreference = ThemePreference.circadian;
  AccentColorPreset accentColor = AccentColorPreset.emerald;

  // Responsive Rail & Window Optimization
  bool isRailCollapsed = false;
  bool isSchemaRailCollapsed = false;

  bool get isEffectiveDarkMode {
    switch (themePreference) {
      case ThemePreference.dark:
        return true;
      case ThemePreference.light:
        return false;
      case ThemePreference.circadian:
        final hour = DateTime.now().hour;
        // 07:00 to 18:00 is Tech Daylight; 18:00 to 07:00 is Obsidian Dark
        return hour < 7 || hour >= 18;
    }
  }

  void setThemePreference(ThemePreference pref) {
    themePreference = pref;
    notifyListeners();
  }

  void setAccentColor(AccentColorPreset accent) {
    accentColor = accent;
    notifyListeners();
  }

  void toggleRailCollapse([bool? forceValue]) {
    isRailCollapsed = forceValue ?? !isRailCollapsed;
    notifyListeners();
  }

  void toggleSchemaRailCollapse([bool? forceValue]) {
    isSchemaRailCollapsed = forceValue ?? !isSchemaRailCollapsed;
    notifyListeners();
  }

  bool isSchemaExplorerHidden = false;
  double schemaExplorerWidth = 280.0;
  bool isSchemaExplorerWide = false;

  void toggleSchemaExplorerHidden([bool? forceValue]) {
    isSchemaExplorerHidden = forceValue ?? !isSchemaExplorerHidden;
    notifyListeners();
  }

  void setSchemaExplorerWidth(double width) {
    schemaExplorerWidth = width.clamp(200.0, 700.0);
    isSchemaExplorerWide = schemaExplorerWidth > 320.0;
    notifyListeners();
  }

  void toggleSchemaExplorerWide([bool? forceValue]) {
    isSchemaExplorerWide = forceValue ?? !isSchemaExplorerWide;
    if (isSchemaExplorerWide) {
      if (schemaExplorerWidth < 400.0) {
        schemaExplorerWidth = 420.0;
      }
    } else {
      schemaExplorerWidth = 280.0;
    }
    notifyListeners();
  }

  void autoFitSchemaExplorerWidth() {
    if (tables.isEmpty) {
      schemaExplorerWidth = 280.0;
      isSchemaExplorerWide = false;
    } else {
      int maxLen = 0;
      for (final t in tables) {
        if (t.rawName.length > maxLen) maxLen = t.rawName.length;
      }
      // Calculate width to fit table name comfortably + leading icon + trailing controls
      final needed = (maxLen * 7.8 + 140.0).clamp(280.0, 650.0);
      schemaExplorerWidth = needed;
      isSchemaExplorerWide = needed > 310.0;
    }
    notifyListeners();
  }

  bool isBackendOnline = false;
  bool isLoading = false;
  String? errorMessage;
  String get backendBaseUrl => api.baseUrl;

  List<ConnectionConfig> connections = [];
  ConnectionConfig? activeConnection;

  List<TableMetadata> tables = [];
  TableMetadata? selectedTable;
  List<Map<String, dynamic>> relationships = [];

  List<SavedQuery> savedQueries = [];

  QueryResult? lastQueryResult;
  bool isExecutingQuery = false;
  bool safeMode = true;
  bool isSchemaLoading = false;

  final List<AuditEvent> auditEvents = [];
  StreamSubscription<AuditEvent>? _auditSubscription;
  String? customBackendUrl;

  Future<void> init() async {
    isLoading = true;
    notifyListeners();

    // 1. Check if a custom backend endpoint was saved previously (e.g., mobile Wi-Fi)
    final savedUrl = await BackendConfigService.loadSavedUrl();
    if (savedUrl != null && savedUrl.isNotEmpty) {
      customBackendUrl = savedUrl;
      api.setBaseUrl(savedUrl);
      auditStream.setWsUrl(BackendConfigService.toWebSocketUrl(savedUrl));
      isBackendOnline = await api.checkHealth(retries: 3, delay: const Duration(milliseconds: 400));
      if (isBackendOnline) {
        await loadConnections();
        await Future.wait([
          loadSchema(),
          loadSavedQueries(),
        ]);
        _initAuditStream();
        isLoading = false;
        notifyListeners();
        return;
      }
    }

    // 2. Ensure backend sidecar is running on desktop
    final port = await BackendSidecarService.instance.ensureBackendRunning();
    final defaultUrl = savedUrl ?? 'http://127.0.0.1:$port';
    api.setBaseUrl(defaultUrl);
    auditStream.setWsUrl(BackendConfigService.toWebSocketUrl(defaultUrl));

    isBackendOnline = await api.checkHealth(retries: 5, delay: const Duration(milliseconds: 500));
    if (isBackendOnline) {
      await loadConnections();
      await Future.wait([
        loadSchema(),
        loadSavedQueries(),
      ]);
      _initAuditStream();
    } else {
      errorMessage = 'RevVault backend service is not reachable at $defaultUrl.';
    }

    isLoading = false;
    notifyListeners();
  }

  void _initAuditStream() {
    _auditSubscription?.cancel();
    auditStream.disconnect();
    auditStream.connect();
    _auditSubscription = auditStream.stream.listen((event) {
      // Add to front of audit list
      auditEvents.insert(0, event);
      if (auditEvents.length > 200) {
        auditEvents.removeLast();
      }
      notifyListeners();
    });
  }

  /// Dynamically updates the backend URL, saves to preferences, and reinitializes connections.
  Future<bool> updateBackendUrl(String newUrl, {bool persist = true}) async {
    final normalized = BackendConfigService.normalizeUrl(newUrl);
    final wsUrl = BackendConfigService.toWebSocketUrl(normalized);

    isLoading = true;
    notifyListeners();

    api.setBaseUrl(normalized);
    auditStream.setWsUrl(wsUrl);

    final online = await api.checkHealth(retries: 3, delay: const Duration(milliseconds: 400));
    isBackendOnline = online;

    if (online) {
      customBackendUrl = normalized;
      if (persist) {
        await BackendConfigService.saveUrl(normalized);
      }
      errorMessage = null;
      await loadConnections();
      await Future.wait([
        loadSchema(refresh: true),
        loadSavedQueries(),
      ]);
      _initAuditStream();
    } else {
      errorMessage = 'Cannot reach RevVault backend at $normalized';
    }

    isLoading = false;
    notifyListeners();
    return online;
  }

  /// Resets to default backend URL (localhost sidecar) and clears stored preference.
  Future<void> resetBackendUrl() async {
    await BackendConfigService.resetToDefault();
    customBackendUrl = null;
    await init();
  }

  Future<void> loadConnections() async {
    try {
      connections = await api.getConnections();
      activeConnection = connections.cast<ConnectionConfig?>().firstWhere(
        (c) => c?.isActive == true,
        orElse: () => connections.isNotEmpty ? connections.first : null,
      );
    } catch (e) {
      errorMessage = 'Error loading connections: $e';
    }
    notifyListeners();
  }

  Future<void> setActiveConnection(ConnectionConfig conn) async {
    try {
      isLoading = true;
      notifyListeners();

      final updated = await api.setActiveConnection(conn.id);
      activeConnection = updated;
      await loadConnections();
      await loadSchema();
    } catch (e) {
      errorMessage = 'Failed to activate connection: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> saveConnection(ConnectionConfig conn) async {
    try {
      await api.saveConnection(conn);
      await loadConnections();
      return true;
    } catch (e) {
      errorMessage = 'Failed to save connection: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteConnection(String id) async {
    try {
      await api.deleteConnection(id);
      await loadConnections();
      if (activeConnection?.id == id) {
        activeConnection = connections.isNotEmpty ? connections.first : null;
        if (activeConnection != null) {
          await loadSchema();
        }
      }
    } catch (e) {
      errorMessage = 'Failed to delete connection: $e';
    }
    notifyListeners();
  }

  Future<void> loadSchema({bool refresh = false}) async {
    if (activeConnection == null) return;
    try {
      isSchemaLoading = true;
      notifyListeners();

      final results = await Future.wait([
        api.getSchema(refresh: refresh),
        api.getRelationships(refresh: refresh),
      ]);

      tables = results[0] as List<TableMetadata>;
      relationships = results[1] as List<Map<String, dynamic>>;

      if (tables.isNotEmpty) {
        if (selectedTable != null) {
          selectedTable = tables.firstWhere(
            (t) => t.name == selectedTable!.name,
            orElse: () => tables.first,
          );
        } else {
          selectedTable = tables.first;
        }
      } else {
        selectedTable = null;
      }
    } catch (e) {
      errorMessage = 'Failed to load schema: $e';
    } finally {
      isSchemaLoading = false;
      notifyListeners();
    }
  }

  void selectTable(TableMetadata table) {
    selectedTable = table;
    notifyListeners();
  }

  // Saved Queries Operations
  Future<void> loadSavedQueries() async {
    try {
      savedQueries = await api.getSavedQueries();
    } catch (e) {
      errorMessage = 'Failed to load saved queries: $e';
    }
    notifyListeners();
  }

  Future<bool> saveCurrentQuery(String title, {String? description}) async {
    if (title.trim().isEmpty || editorQueryText.trim().isEmpty) return false;
    final query = SavedQuery(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.trim(),
      description: description?.trim(),
      sql: editorQueryText.trim(),
      builderMode: 'rawSql',
      createdAt: DateTime.now().toIso8601String(),
    );

    final saved = await api.saveQuery(query);
    if (saved != null) {
      final idx = savedQueries.indexWhere((q) => q.id == saved.id);
      if (idx != -1) {
        savedQueries[idx] = saved;
      } else {
        savedQueries.insert(0, saved);
      }
      notifyListeners();
      return true;
    } else {
      // Fallback local save if backend is offline / unavailable
      savedQueries.insert(0, query);
      notifyListeners();
      return true;
    }
  }

  Future<void> deleteSavedQuery(String id) async {
    await api.deleteSavedQuery(id);
    savedQueries.removeWhere((q) => q.id == id);
    notifyListeners();
  }


  // Focus & Minimize Preview Table State
  bool isResultsMinimized = false;

  void toggleResultsMinimized([bool? minimized]) {
    isResultsMinimized = minimized ?? !isResultsMinimized;
    notifyListeners();
  }

  String editorQueryText = 'SELECT * FROM users LIMIT 10;';

  void loadSavedQuery(SavedQuery query) {
    editorQueryText = query.sql;
    notifyListeners();
  }

  void setEditorQueryText(String sql) {
    editorQueryText = sql;
    notifyListeners();
  }

  void formatEditorSql() {
    editorQueryText = SqlAutocompleteService().formatSql(editorQueryText);
    notifyListeners();
  }

  String? activePreviewTable;
  int previewPage = 1;
  int previewPageSize = 25;

  int queryPage = 1;
  int queryPageSize = 100;
  int? activeLimit = 100;

  void setActiveLimit(int? limit) {
    activeLimit = limit;
    if (limit != null && limit > 0) {
      queryPageSize = limit;
    }
    notifyListeners();
  }

  void setQueryPageSize(int size) {
    queryPageSize = size;
    activeLimit = size;
    notifyListeners();
  }

  void updateEditorQuery(String sql) {
    editorQueryText = sql;
    notifyListeners();
  }

  void insertTextIntoEditor(String text) {
    final trimmed = editorQueryText.trim();
    if (trimmed.isEmpty || trimmed == 'SELECT * FROM users LIMIT 10;') {
      if (text.startsWith('"') || text.contains('.')) {
        editorQueryText = 'SELECT * FROM $text LIMIT 25;';
      } else {
        editorQueryText = 'SELECT $text FROM ';
      }
    } else {
      // Insert with proper spacing
      if (trimmed.endsWith(';') || trimmed.endsWith(',')) {
        editorQueryText = '${trimmed.substring(0, trimmed.length - 1)} $text;';
      } else {
        editorQueryText = '$trimmed $text';
      }
    }
    notifyListeners();
  }

  void filterByCellValue(String column, dynamic value) {
    final valStr = value == null ? ' IS NULL' : " = '$value'";
    final clause = '"$column"$valStr';
    var sql = editorQueryText.trim().replaceAll(RegExp(r';$'), '');

    if (sql.toUpperCase().contains('WHERE')) {
      sql = sql.replaceFirstMapped(
        RegExp(r'(WHERE\s+)(.+?)(\s+LIMIT|\s+ORDER|\s*$)', caseSensitive: false),
        (match) => 'WHERE ${match.group(2)} AND $clause${match.group(3)}',
      );
    } else if (sql.toUpperCase().contains('ORDER BY')) {
      sql = sql.replaceFirstMapped(
        RegExp(r'(\s+ORDER\s+BY)', caseSensitive: false),
        (match) => ' WHERE $clause${match.group(1)}',
      );
    } else if (sql.toUpperCase().contains('LIMIT')) {
      sql = sql.replaceFirstMapped(
        RegExp(r'(\s+LIMIT)', caseSensitive: false),
        (match) => ' WHERE $clause${match.group(1)}',
      );
    } else {
      sql = '$sql WHERE $clause;';
    }
    if (!sql.endsWith(';')) sql = '$sql;';
    runQuery(sql);
  }

  String _rewriteQueryPagination(String sql, int pageSize, int offset) {
    var trimmed = sql.trim().replaceAll(RegExp(r';\s*$'), '');
    final hasLimit = RegExp(r'\bLIMIT\s+\d+', caseSensitive: false).hasMatch(trimmed);
    final hasOffset = RegExp(r'\bOFFSET\s+\d+', caseSensitive: false).hasMatch(trimmed);

    if (hasLimit && hasOffset) {
      trimmed = trimmed.replaceFirstMapped(
        RegExp(r'(\bLIMIT\s+)\d+', caseSensitive: false),
        (m) => '${m.group(1)}$pageSize',
      );
      trimmed = trimmed.replaceFirstMapped(
        RegExp(r'(\bOFFSET\s+)\d+', caseSensitive: false),
        (m) => '${m.group(1)}$offset',
      );
    } else if (hasLimit) {
      trimmed = trimmed.replaceFirstMapped(
        RegExp(r'(\bLIMIT\s+)\d+', caseSensitive: false),
        (m) => '${m.group(1)}$pageSize OFFSET $offset',
      );
    } else {
      trimmed = '$trimmed LIMIT $pageSize OFFSET $offset';
    }
    return '$trimmed;';
  }

  Future<void> runQuery(String sql) async {
    editorQueryText = sql;
    activePreviewTable = null;
    isExecutingQuery = true;
    notifyListeners();

    final limitMatch = RegExp(r'\bLIMIT\s+(\d+)', caseSensitive: false).firstMatch(sql);
    final offsetMatch = RegExp(r'\bOFFSET\s+(\d+)', caseSensitive: false).firstMatch(sql);
    final parsedLimit = limitMatch != null ? int.tryParse(limitMatch.group(1)!) : null;
    final parsedOffset = offsetMatch != null ? int.tryParse(offsetMatch.group(1)!) : null;

    final effectiveLimit = parsedLimit ?? activeLimit;
    if (parsedLimit != null) {
      queryPageSize = parsedLimit;
    } else if (activeLimit != null) {
      queryPageSize = activeLimit!;
    }

    if (parsedOffset != null && queryPageSize > 0) {
      queryPage = (parsedOffset ~/ queryPageSize) + 1;
    } else {
      queryPage = 1;
    }

    try {
      lastQueryResult = await api.executeQuery(sql, safeMode: safeMode, limit: effectiveLimit);
      if (lastQueryResult?.page != null) {
        queryPage = lastQueryResult!.page!;
      }
      if (lastQueryResult?.pageSize != null) {
        queryPageSize = lastQueryResult!.pageSize!;
      }
    } catch (e) {
      lastQueryResult = QueryResult(
        columns: [],
        rows: [],
        rowCount: 0,
        executionTimeMs: 0.0,
        error: e.toString(),
      );
    } finally {
      isExecutingQuery = false;
      notifyListeners();
    }
  }

  Future<void> nextQueryPage() async {
    final nextPage = queryPage + 1;
    final offset = (nextPage - 1) * queryPageSize;
    final newSql = _rewriteQueryPagination(editorQueryText, queryPageSize, offset);
    await runQuery(newSql);
  }

  Future<void> previousQueryPage() async {
    if (queryPage <= 1) return;
    final prevPage = queryPage - 1;
    final offset = (prevPage - 1) * queryPageSize;
    final newSql = _rewriteQueryPagination(editorQueryText, queryPageSize, offset);
    await runQuery(newSql);
  }

  Future<void> goToQueryPage(int page) async {
    if (page < 1) return;
    final offset = (page - 1) * queryPageSize;
    final newSql = _rewriteQueryPagination(editorQueryText, queryPageSize, offset);
    await runQuery(newSql);
  }

  Future<void> previewTable(String tableName, {int page = 1}) async {
    activePreviewTable = tableName;
    previewPage = page < 1 ? 1 : page;
    queryPage = previewPage;
    queryPageSize = previewPageSize;
    isExecutingQuery = true;

    final parts = tableName.split('.');
    final quoted = activeConnection?.engine == 'postgres'
        ? parts.map((p) => '"$p"').join('.')
        : parts.map((p) => '`$p`').join('.');
    final offset = (previewPage - 1) * previewPageSize;
    editorQueryText = 'SELECT * FROM $quoted LIMIT $previewPageSize OFFSET $offset;';

    notifyListeners();

    try {
      lastQueryResult = await api.previewTable(tableName, page: previewPage, pageSize: previewPageSize);
    } catch (e) {
      lastQueryResult = QueryResult(
        columns: [],
        rows: [],
        rowCount: 0,
        executionTimeMs: 0.0,
        error: e.toString(),
      );
    } finally {
      isExecutingQuery = false;
      notifyListeners();
    }
  }

  void nextPreviewPage() {
    if (activePreviewTable != null) {
      previewTable(activePreviewTable!, page: previewPage + 1);
    }
  }

  void previousPreviewPage() {
    if (activePreviewTable != null && previewPage > 1) {
      previewTable(activePreviewTable!, page: previewPage - 1);
    }
  }

  void goToPreviewPage(int page) {
    if (activePreviewTable != null && page >= 1) {
      previewTable(activePreviewTable!, page: page);
    }
  }

  void nextPage() {
    if (activePreviewTable != null) {
      nextPreviewPage();
    } else {
      nextQueryPage();
    }
  }

  void previousPage() {
    if (activePreviewTable != null) {
      previousPreviewPage();
    } else {
      previousQueryPage();
    }
  }

  void goToPage(int page) {
    if (activePreviewTable != null) {
      goToPreviewPage(page);
    } else {
      goToQueryPage(page);
    }
  }

  void toggleSafeMode(bool value) {
    safeMode = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _auditSubscription?.cancel();
    BackendSidecarService.instance.terminate();
    auditStream.dispose();
    super.dispose();
  }
}
