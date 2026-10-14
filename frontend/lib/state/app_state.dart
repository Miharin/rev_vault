import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/connection.dart';
import '../models/table_schema.dart';
import '../models/query_result.dart';
import '../models/audit_event.dart';
import '../models/saved_query.dart';
import '../models/mutation_record.dart';
import '../models/workspace_tab.dart';
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
  ThemePreference themePreference = ThemePreference.dark;
  AccentColorPreset accentColor = AccentColorPreset.emerald;

  // Responsive Rail & Window Optimization
  bool isRailCollapsed = true;
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

  // Multi-Tab Workspace State
  final List<WorkspaceTab> tabs = [
    WorkspaceTab(
      id: 'tab_init',
      title: 'Query 1',
      type: WorkspaceTabType.sqlQuery,
      queryText: 'SELECT * FROM users LIMIT 10;',
    ),
  ];
  int activeTabIndex = 0;

  WorkspaceTab get activeTab {
    if (tabs.isEmpty) {
      tabs.add(WorkspaceTab(
        id: 'tab_init',
        title: 'Query 1',
        type: WorkspaceTabType.sqlQuery,
        queryText: 'SELECT * FROM users LIMIT 10;',
      ));
      activeTabIndex = 0;
    }
    if (activeTabIndex < 0 || activeTabIndex >= tabs.length) {
      activeTabIndex = 0;
    }
    return tabs[activeTabIndex];
  }

  QueryResult? get lastQueryResult => activeTab.result;
  set lastQueryResult(QueryResult? r) {
    activeTab.result = r;
    notifyListeners();
  }

  bool get isExecutingQuery => activeTab.isExecuting;
  set isExecutingQuery(bool v) {
    activeTab.isExecuting = v;
    notifyListeners();
  }

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

  String get editorQueryText => activeTab.queryText;
  set editorQueryText(String sql) {
    activeTab.queryText = sql;
    notifyListeners();
  }

  void loadSavedQuery(SavedQuery query) {
    editorQueryText = query.sql;
    notifyListeners();
  }

  void setEditorQueryText(String sql) {
    editorQueryText = sql;
  }

  void formatEditorSql() {
    editorQueryText = SqlAutocompleteService().formatSql(editorQueryText);
  }

  String? get activePreviewTable => activeTab.tableName;
  set activePreviewTable(String? tbl) {
    activeTab.tableName = tbl;
    notifyListeners();
  }

  int get previewPage => activeTab.page;
  set previewPage(int p) {
    activeTab.page = p;
    notifyListeners();
  }

  int previewPageSize = 25;

  int get queryPage => activeTab.page;
  set queryPage(int p) {
    activeTab.page = p;
    notifyListeners();
  }

  int get queryPageSize => activeTab.pageSize;
  set queryPageSize(int size) {
    activeTab.pageSize = size;
    activeLimit = size;
    notifyListeners();
  }

  int? activeLimit = 100;

  void setActiveLimit(int? limit) {
    activeLimit = limit;
    if (limit != null && limit > 0) {
      queryPageSize = limit;
    }
    notifyListeners();
  }

  void updateEditorQuery(String sql) {
    editorQueryText = sql;
  }

  void openQueryTab({String? initialSql, String? title}) {
    final count = tabs.where((t) => t.isSqlQuery).length + 1;
    final tab = WorkspaceTab(
      id: 'tab_${DateTime.now().microsecondsSinceEpoch}',
      title: title ?? 'Query $count',
      type: WorkspaceTabType.sqlQuery,
      queryText: initialSql ?? 'SELECT * FROM users LIMIT 10;',
      pageSize: activeLimit ?? 100,
    );
    tabs.add(tab);
    activeTabIndex = tabs.length - 1;
    notifyListeners();
  }

  String? get activeSchemaName => activeTab.isSchemaOverview ? activeTab.schemaName : null;

  void openSchemaTab(String schemaName) {
    final existingIdx = tabs.indexWhere((t) => t.isSchemaOverview && t.schemaName == schemaName);
    if (existingIdx != -1) {
      activeTabIndex = existingIdx;
      notifyListeners();
      return;
    }

    final tab = WorkspaceTab(
      id: 'tab_schema_${DateTime.now().microsecondsSinceEpoch}',
      title: schemaName,
      type: WorkspaceTabType.schemaOverview,
      schemaName: schemaName,
    );
    tabs.add(tab);
    activeTabIndex = tabs.length - 1;
    notifyListeners();
  }

  Future<void> openTableTab(String tableName, {bool forceReload = false}) async {
    final existingIdx = tabs.indexWhere((t) => t.isTablePreview && t.tableName == tableName);
    if (existingIdx != -1) {
      activeTabIndex = existingIdx;
      if (forceReload || tabs[existingIdx].result == null) {
        await previewTable(tableName, page: tabs[existingIdx].page);
      } else {
        notifyListeners();
      }
      return;
    }

    final rawName = tableName.contains('.') ? tableName.split('.').last : tableName;
    final metadata = tables.cast<TableMetadata?>().firstWhere(
      (t) => t?.name == tableName,
      orElse: () => null,
    );

    final tab = WorkspaceTab(
      id: 'tab_table_${DateTime.now().microsecondsSinceEpoch}',
      title: rawName,
      type: WorkspaceTabType.tablePreview,
      tableName: tableName,
      tableMetadata: metadata,
      pageSize: previewPageSize,
      page: 1,
    );
    tabs.add(tab);
    activeTabIndex = tabs.length - 1;
    notifyListeners();
    await previewTable(tableName, page: 1);
  }

  void closeTab(int index) {
    if (index < 0 || index >= tabs.length) return;
    if (tabs.length == 1) {
      tabs[0] = WorkspaceTab(
        id: 'tab_${DateTime.now().microsecondsSinceEpoch}',
        title: 'Query 1',
        type: WorkspaceTabType.sqlQuery,
        queryText: 'SELECT * FROM users LIMIT 10;',
      );
      activeTabIndex = 0;
      notifyListeners();
      return;
    }

    tabs.removeAt(index);
    if (activeTabIndex >= tabs.length) {
      activeTabIndex = tabs.length - 1;
    }
    notifyListeners();
  }

  void closeActiveTab() {
    closeTab(activeTabIndex);
  }

  void setActiveTab(int index) {
    if (index >= 0 && index < tabs.length && index != activeTabIndex) {
      activeTabIndex = index;
      notifyListeners();
    }
  }

  void nextTab() {
    if (tabs.length > 1) {
      activeTabIndex = (activeTabIndex + 1) % tabs.length;
      notifyListeners();
    }
  }

  void previousTab() {
    if (tabs.length > 1) {
      activeTabIndex = (activeTabIndex - 1 + tabs.length) % tabs.length;
      notifyListeners();
    }
  }

  Future<bool> updateTableRow({
    required String tableName,
    required Map<String, dynamic> primaryKeys,
    required Map<String, dynamic> updatedValues,
  }) async {
    try {
      final res = await api.mutateRow(
        tableName: tableName,
        operation: 'update',
        primaryKeys: primaryKeys,
        updatedValues: updatedValues,
      );
      if (res['success'] == true) {
        if (activeTab.isTablePreview && activeTab.tableName != null) {
          await previewTable(activeTab.tableName!, page: activeTab.page);
        } else if (activeTab.queryText.isNotEmpty) {
          await runQuery(activeTab.queryText);
        }
        fetchMutationHistory();
        return true;
      } else {
        errorMessage = res['error']?.toString() ?? 'Failed to update row';
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Row update failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteTableRow({
    required String tableName,
    required Map<String, dynamic> primaryKeys,
  }) async {
    try {
      final res = await api.mutateRow(
        tableName: tableName,
        operation: 'delete',
        primaryKeys: primaryKeys,
      );
      if (res['success'] == true) {
        if (activeTab.isTablePreview && activeTab.tableName != null) {
          await previewTable(activeTab.tableName!, page: activeTab.page);
        } else if (activeTab.queryText.isNotEmpty) {
          await runQuery(activeTab.queryText);
        }
        fetchMutationHistory();
        return true;
      } else {
        errorMessage = res['error']?.toString() ?? 'Failed to delete row';
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Row deletion failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> insertTableRow({
    required String tableName,
    required Map<String, dynamic> rowValues,
  }) async {
    try {
      final res = await api.mutateRow(
        tableName: tableName,
        operation: 'insert',
        updatedValues: rowValues,
      );
      if (res['success'] == true) {
        if (activeTab.isTablePreview && activeTab.tableName != null) {
          await previewTable(activeTab.tableName!, page: activeTab.page);
        } else if (activeTab.queryText.isNotEmpty) {
          await runQuery(activeTab.queryText);
        }
        fetchMutationHistory();
        return true;
      } else {
        errorMessage = res['error']?.toString() ?? 'Failed to insert row';
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Row insert failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> duplicateTableRow({
    required String tableName,
    List<Map<String, dynamic>>? rowsToInsert,
    Map<String, dynamic>? rowValuesWithoutPks,
    int count = 1,
  }) async {
    try {
      final List<Map<String, dynamic>> targetRows = rowsToInsert ??
          List.generate(count, (_) => rowValuesWithoutPks ?? <String, dynamic>{});

      int successCount = 0;
      for (int i = 0; i < targetRows.length; i++) {
        final row = targetRows[i];
        final res = await api.mutateRow(
          tableName: tableName,
          operation: 'insert',
          updatedValues: row,
        );
        if (res['success'] == true) {
          successCount++;
        } else {
          errorMessage = res['error']?.toString() ?? 'Failed during row duplication';
          notifyListeners();
          break;
        }
      }
      if (successCount > 0) {
        if (activeTab.isTablePreview && activeTab.tableName != null) {
          await previewTable(activeTab.tableName!, page: activeTab.page);
        } else if (activeTab.queryText.isNotEmpty) {
          await runQuery(activeTab.queryText);
        }
        fetchMutationHistory();
        return successCount == targetRows.length;
      }
      return false;
    } catch (e) {
      errorMessage = 'Row duplication failed: $e';
      notifyListeners();
      return false;
    }
  }

  List<MutationRecord> mutationHistory = [];
  bool isLoadingHistory = false;

  Future<void> fetchMutationHistory() async {
    isLoadingHistory = true;
    notifyListeners();
    try {
      mutationHistory = await api.getMutationHistory();
    } catch (_) {
      mutationHistory = [];
    } finally {
      isLoadingHistory = false;
      notifyListeners();
    }
  }

  Future<bool> recoverMutation(String historyId) async {
    try {
      final res = await api.recoverMutation(historyId);
      if (res['success'] == true) {
        await fetchMutationHistory();
        if (activeTab.isTablePreview && activeTab.tableName != null) {
          await previewTable(activeTab.tableName!, page: activeTab.page);
        } else if (activeTab.queryText.isNotEmpty) {
          await runQuery(activeTab.queryText);
        }
        return true;
      } else {
        errorMessage = res['error']?.toString() ?? 'Recovery failed';
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Recovery failed: $e';
      notifyListeners();
      return false;
    }
  }

  // Multi-Row Selection State
  final Set<int> selectedRowIndices = {};
  int? _lastSelectedRowIndex;

  void toggleRowSelection(int index) {
    if (selectedRowIndices.contains(index)) {
      selectedRowIndices.remove(index);
    } else {
      selectedRowIndices.add(index);
    }
    _lastSelectedRowIndex = index;
    notifyListeners();
  }

  void selectRowRange(int targetIndex) {
    if (_lastSelectedRowIndex == null) {
      toggleRowSelection(targetIndex);
      return;
    }
    final start = math.min(_lastSelectedRowIndex!, targetIndex);
    final end = math.max(_lastSelectedRowIndex!, targetIndex);
    for (int i = start; i <= end; i++) {
      selectedRowIndices.add(i);
    }
    _lastSelectedRowIndex = targetIndex;
    notifyListeners();
  }

  void selectAllRows(int totalRows) {
    if (selectedRowIndices.length == totalRows) {
      selectedRowIndices.clear();
      _lastSelectedRowIndex = null;
    } else {
      selectedRowIndices.clear();
      for (int i = 0; i < totalRows; i++) {
        selectedRowIndices.add(i);
      }
    }
    notifyListeners();
  }

  void clearRowSelection() {
    if (selectedRowIndices.isNotEmpty) {
      selectedRowIndices.clear();
      _lastSelectedRowIndex = null;
      notifyListeners();
    }
  }

  // Table Management & Lifecycle Operations
  Future<bool> createTable({
    required String tableName,
    String? schemaName,
    required List<Map<String, dynamic>> columns,
    bool ifNotExists = true,
  }) async {
    try {
      final res = await api.createTable(
        tableName: tableName,
        schemaName: schemaName,
        columns: columns,
        ifNotExists: ifNotExists,
      );
      if (res['success'] == true) {
        await loadSchema(refresh: true);
        final fullTableName = (schemaName != null && schemaName.isNotEmpty && schemaName != 'public' && schemaName != 'main')
            ? '$schemaName.$tableName'
            : tableName;
        await openTableTab(fullTableName);
        return true;
      } else {
        errorMessage = res['error']?.toString() ?? 'Failed to create table';
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Create table failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> dropTable({
    required String tableName,
    String? schemaName,
    bool cascade = false,
  }) async {
    try {
      final res = await api.dropTable(
        tableName: tableName,
        schemaName: schemaName,
        cascade: cascade,
      );
      if (res['success'] == true) {
        // Close matching table preview tab if open
        final fullTableName = (schemaName != null && schemaName.isNotEmpty && schemaName != 'public' && schemaName != 'main')
            ? '$schemaName.$tableName'
            : tableName;
        final tabIdx = tabs.indexWhere((t) => t.isTablePreview && (t.tableName == tableName || t.tableName == fullTableName));
        if (tabIdx != -1) {
          closeTab(tabIdx);
        }
        await loadSchema(refresh: true);
        return true;
      } else {
        errorMessage = res['error']?.toString() ?? 'Failed to drop table';
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Drop table failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> truncateTable({
    required String tableName,
    String? schemaName,
    bool cascade = false,
  }) async {
    try {
      final res = await api.truncateTable(
        tableName: tableName,
        schemaName: schemaName,
        cascade: cascade,
      );
      if (res['success'] == true) {
        clearRowSelection();
        if (activeTab.isTablePreview && activeTab.tableName != null) {
          await previewTable(activeTab.tableName!, page: 1);
        } else if (activeTab.queryText.isNotEmpty) {
          await runQuery(activeTab.queryText);
        }
        fetchMutationHistory();
        return true;
      } else {
        errorMessage = res['error']?.toString() ?? 'Failed to truncate table';
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Truncate table failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> bulkDeleteRows({
    required String tableName,
    required List<Map<String, dynamic>> primaryKeysList,
  }) async {
    try {
      final res = await api.bulkMutateRows(
        tableName: tableName,
        operation: 'delete',
        rowsPks: primaryKeysList,
      );
      if (res['success'] == true) {
        clearRowSelection();
        if (activeTab.isTablePreview && activeTab.tableName != null) {
          await previewTable(activeTab.tableName!, page: activeTab.page);
        } else if (activeTab.queryText.isNotEmpty) {
          await runQuery(activeTab.queryText);
        }
        fetchMutationHistory();
        return true;
      } else {
        errorMessage = res['error']?.toString() ?? 'Bulk deletion failed';
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Bulk deletion failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> batchInsertRows({
    required String tableName,
    required List<Map<String, dynamic>> rowsData,
    bool truncateFirst = false,
  }) async {
    try {
      if (truncateFirst) {
        final okTruncate = await truncateTable(tableName: tableName);
        if (!okTruncate) return false;
      }
      final res = await api.bulkMutateRows(
        tableName: tableName,
        operation: 'insert',
        rowsData: rowsData,
      );
      if (res['success'] == true) {
        clearRowSelection();
        if (activeTab.isTablePreview && activeTab.tableName != null) {
          await previewTable(activeTab.tableName!, page: activeTab.page);
        } else if (activeTab.queryText.isNotEmpty) {
          await runQuery(activeTab.queryText);
        }
        fetchMutationHistory();
        return true;
      } else {
        errorMessage = res['error']?.toString() ?? 'Batch insertion failed';
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Batch insertion failed: $e';
      notifyListeners();
      return false;
    }
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
    activeTab.tableMetadata = tables.cast<TableMetadata?>().firstWhere(
      (t) => t?.name == tableName,
      orElse: () => null,
    );
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
