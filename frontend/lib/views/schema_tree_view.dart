import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/table_schema.dart';
import '../state/app_state.dart';
import 'widgets/tactical_hud_widgets.dart';
import 'widgets/create_table_modal.dart';
import 'widgets/table_lifecycle_modal.dart';
import 'widgets/data_import_modal.dart';
import 'widgets/mock_data_generator_modal.dart';

class SchemaTreeView extends StatefulWidget {
  final bool forceExpanded;
  const SchemaTreeView({super.key, this.forceExpanded = false});

  @override
  State<SchemaTreeView> createState() => _SchemaTreeViewState();
}

class _SchemaTreeViewState extends State<SchemaTreeView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';
  Timer? _debounce;

  // Cached filter results — computed once per change, not every build()
  Map<String, List<TableMetadata>> _filteredGrouped = {};
  List<String> _sortedSchemas = [];

  // Identity tracking to detect when AppState.tables is replaced
  List<TableMetadata>? _lastTables;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initial population when tables arrive from AppState
    final state = context.read<AppState>();
    if (_lastTables != state.tables) {
      _lastTables = state.tables;
      _rebuildFilter(_filter);
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      final val = _searchCtrl.text;
      if (val == _filter) return;
      setState(() => _filter = val);
      _rebuildFilter(val);
    });
  }

  void _rebuildFilter(String raw) {
    final state = context.read<AppState>();
    final query = raw.trim().toLowerCase();
    final Map<String, List<TableMetadata>> grouped = {};
    for (final table in state.tables) {
      grouped.putIfAbsent(table.schema, () => []).add(table);
    }
    final Map<String, List<TableMetadata>> filtered = {};
    grouped.forEach((schema, tables) {
      if (query.isEmpty) {
        filtered[schema] = tables;
      } else {
        final matches = tables.where((t) {
          return schema.toLowerCase().contains(query) ||
              t.name.toLowerCase().contains(query) ||
              t.rawName.toLowerCase().contains(query);
        }).toList();
        if (matches.isNotEmpty) filtered[schema] = matches;
      }
    });
    setState(() {
      _filteredGrouped = filtered;
      _sortedSchemas = filtered.keys.toList()..sort();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Narrow rebuild: only re-render when the tables list object itself changes
    final tables = context.select<AppState, List<TableMetadata>>((s) => s.tables);
    if (tables != _lastTables) {
      _lastTables = tables;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildFilter(_filter);
      });
    }

    final state = context.read<AppState>();
    final isHidden = widget.forceExpanded ? false : context.select<AppState, bool>((s) => s.isSchemaExplorerHidden);
    final isRail = widget.forceExpanded ? false : context.select<AppState, bool>((s) => s.isSchemaRailCollapsed);
    final explorerWidth = widget.forceExpanded ? double.infinity : context.select<AppState, double>((s) => s.schemaExplorerWidth);
    final double targetWidth = widget.forceExpanded ? double.infinity : (isHidden ? 24 : (isRail ? 56 : explorerWidth));
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (widget.forceExpanded) {
      return _buildExpandedView(context, state, primary);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOutCubic,
          width: targetWidth,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
          ),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: targetWidth,
            child: isHidden
                ? SizedBox(
                    width: 24,
                    child: _buildHiddenStripView(context, state, _sortedSchemas.length, primary),
                  )
                : (isRail
                    ? SizedBox(
                        width: 56,
                        child: _buildRailView(context, state, _sortedSchemas.length, primary),
                      )
                    : SizedBox(
                        width: explorerWidth,
                        child: _buildExpandedView(context, state, primary),
                      )),
          ),
        ),
        if (!isHidden && !isRail)
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                state.setSchemaExplorerWidth(state.schemaExplorerWidth + details.delta.dx);
              },
              onDoubleTap: () => state.autoFitSchemaExplorerWidth(),
              child: Tooltip(
                message: 'Drag to resize • Double-click to auto-fit',
                waitDuration: const Duration(milliseconds: 600),
                child: Container(
                  width: 6,
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      width: 1,
                      color: theme.dividerColor.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          Container(
            width: 1,
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
      ],
    );
  }

  Widget _buildHiddenStripView(BuildContext context, AppState state, int schemaCount, Color primary) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
      child: InkWell(
        onTap: () => state.toggleSchemaExplorerHidden(false),
        child: Tooltip(
          message: 'Expand Schema Explorer ($schemaCount schemas)',
          child: SizedBox(
            width: 24,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chevron_right, size: 16, color: primary),
                const SizedBox(height: 14),
                RotatedBox(
                  quarterTurns: 3,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_copy_outlined, size: 12, color: primary),
                      const SizedBox(width: 5),
                      Text(
                        'SCHEMAS ($schemaCount)',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Icon(Icons.chevron_right, size: 16, color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRailView(BuildContext context, AppState state, int schemaCount, Color primary) {
    return Column(
      children: [
        const SizedBox(height: 8),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          tooltip: 'Expand Schemas',
          onPressed: () => state.toggleSchemaRailCollapse(false),
        ),
        IconButton(
          icon: const Icon(Icons.close_fullscreen, size: 16),
          tooltip: 'Minimize Schema Explorer to Strip',
          onPressed: () => state.toggleSchemaExplorerHidden(true),
        ),
        const Divider(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: TacticalRailItem(
            icon: Icons.folder_copy_outlined,
            label: 'Schemas ($schemaCount)',
            isSelected: false,
            badgeCount: context.read<AppState>().tables.length,
            onTap: () => state.toggleSchemaRailCollapse(false),
          ),
        ),
        IconButton(
          icon: state.isSchemaLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          tooltip: 'Refresh Schema (Bypass Cache)',
          onPressed: state.isSchemaLoading ? null : () => state.loadSchema(refresh: true),
        ),
      ],
    );
  }

  Widget _buildExpandedView(
    BuildContext context,
    AppState state,
    Color primary,
  ) {
    final theme = Theme.of(context);
    final transparentTheme = theme.copyWith(dividerColor: Colors.transparent);
    final isSearching = _filter.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            children: [
              Icon(Icons.folder_copy_outlined, size: 16, color: primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Schemas (${_sortedSchemas.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.add_box_outlined, size: 16),
                tooltip: 'Create New Table',
                onPressed: state.activeConnection == null
                    ? null
                    : () {
                        showCreateTableModal(
                          context: context,
                          engine: state.activeConnection?.engine ?? 'sqlite',
                          defaultSchema: _sortedSchemas.isNotEmpty ? _sortedSchemas.first : null,
                          existingTables: state.tables,
                          onCreateTable: ({
                            required tableName,
                            schemaName,
                            required columns,
                            bool ifNotExists = true,
                          }) {
                            return state.createTable(
                              tableName: tableName,
                              schemaName: schemaName,
                              columns: columns,
                              ifNotExists: ifNotExists,
                            );
                          },
                        );
                      },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: state.isSchemaLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 16),
                tooltip: 'Refresh Schema (Bypass Cache)',
                onPressed: state.isSchemaLoading ? null : () => state.loadSchema(refresh: true),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: Icon(
                  state.isSchemaExplorerWide ? Icons.unfold_less : Icons.unfold_more,
                  size: 16,
                  color: state.isSchemaExplorerWide ? primary : null,
                ),
                tooltip: state.isSchemaExplorerWide
                    ? 'Reset Width (Compact 280px)'
                    : 'Auto-Fit Width to Longest Table Name',
                onPressed: () {
                  if (state.isSchemaExplorerWide) {
                    state.toggleSchemaExplorerWide(false);
                  } else {
                    state.autoFitSchemaExplorerWidth();
                  }
                },
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.chevron_left, size: 18),
                tooltip: 'Collapse Schemas to Rail',
                onPressed: () => state.toggleSchemaRailCollapse(true),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.close_fullscreen, size: 15),
                tooltip: 'Minimize Schema Explorer to Strip',
                onPressed: () => state.toggleSchemaExplorerHidden(true),
              ),
            ],
          ),
        ),

        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: _searchCtrl,
              // onChanged removed — handled by controller listener + debounce
              style: const TextStyle(fontSize: 11),
              decoration: InputDecoration(
                hintText: 'Filter schemas & tables...',
                hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                prefixIcon: const Icon(Icons.search, size: 14, color: Colors.grey),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 12, color: Colors.grey),
                        onPressed: () {
                          _searchCtrl.clear();
                          // listener fires immediately for clear
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Divider(height: 1),

        // Folders Tree View — virtualized at schema level
        Expanded(
          child: state.isSchemaLoading && _sortedSchemas.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Loading schemas...',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : _sortedSchemas.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          state.tables.isEmpty
                              ? (state.activeConnection == null
                                  ? 'No active database connection'
                                  : 'No tables found in active DB')
                              : 'No schemas or tables match "$_filter"',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final availableHeight = constraints.maxHeight;

                    return ListView.builder(
                      itemCount: _sortedSchemas.length,
                      itemBuilder: (context, sIdx) {
                        final schemaName = _sortedSchemas[sIdx];
                        final tables = _filteredGrouped[schemaName] ?? [];

                        return _SchemaFolderTile(
                          key: PageStorageKey('schema_$schemaName'),
                          schemaName: schemaName,
                          tables: tables,
                          isInitiallyExpanded: isSearching,
                          transparentTheme: transparentTheme,
                          primary: primary,
                          state: state,
                          availableHeight: availableHeight,
                          isSearching: isSearching,
                          totalSchemasCount: _sortedSchemas.length,
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _SchemaFolderTile — stateful folder that owns expand state and uses
// a virtual ListView.builder for its table rows.
// ---------------------------------------------------------------------------

class _SchemaFolderTile extends StatefulWidget {
  final String schemaName;
  final List<TableMetadata> tables;
  final bool isInitiallyExpanded;
  final ThemeData transparentTheme;
  final Color primary;
  final AppState state;
  final double availableHeight;
  final bool isSearching;
  final int totalSchemasCount;

  const _SchemaFolderTile({
    super.key,
    required this.schemaName,
    required this.tables,
    required this.isInitiallyExpanded,
    required this.transparentTheme,
    required this.primary,
    required this.state,
    this.availableHeight = 600.0,
    this.isSearching = false,
    this.totalSchemasCount = 1,
  });

  @override
  State<_SchemaFolderTile> createState() => _SchemaFolderTileState();
}

class _SchemaFolderTileState extends State<_SchemaFolderTile> {
  late bool _expanded;

  // Estimated height per table row. ExpansionTile minimum header height is 48px.
  static const double _kEstimatedItemHeight = 48.0;
  // Approximate height of an ExpansionTile header.
  static const double _kFolderHeaderHeight = 48.0;
  // Fallback list height cap when unconstrained.
  static const double _kDefaultMaxListHeight = 432.0;

  // keepScrollOffset: false → bypasses PageStorage for scroll restoration.
  // Without this, the inner ListView's Scrollable reads PageStorage and finds
  // the bool that ExpansionTile wrote (its expanded state), causing:
  //   "type 'bool' is not a subtype of type 'double?' in type cast"
  final ScrollController _listScrollCtrl = ScrollController(keepScrollOffset: false);

  @override
  void initState() {
    super.initState();
    _expanded = widget.isInitiallyExpanded;
  }

  @override
  void didUpdateWidget(_SchemaFolderTile old) {
    super.didUpdateWidget(old);
    // When search changes, isInitiallyExpanded may flip — sync state
    if (old.isInitiallyExpanded != widget.isInitiallyExpanded) {
      _expanded = widget.isInitiallyExpanded;
    }
  }

  @override
  void dispose() {
    _listScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tables = widget.tables;
    final activeSchema = context.select<AppState, String?>((s) => s.activeSchemaName);
    final isSchemaTabActive = activeSchema == widget.schemaName;

    final double available = widget.availableHeight.isFinite && widget.availableHeight > 0
        ? widget.availableHeight
        : _kDefaultMaxListHeight;

    final double maxListHeight;
    if (widget.isSearching) {
      if (widget.totalSchemasCount <= 1) {
        // When searching with a single matching schema, stretch all the way to the bottom
        maxListHeight = (available - _kFolderHeaderHeight).clamp(120.0, double.infinity);
      } else {
        // When searching across multiple schemas, allocate space accounting for other schema headers
        final otherHeaders = (widget.totalSchemasCount - 1) * _kFolderHeaderHeight;
        final remaining = available - _kFolderHeaderHeight - otherHeaders;
        maxListHeight = (remaining > 200.0 ? remaining : available * 0.65).clamp(160.0, double.infinity);
      }
    } else if (widget.totalSchemasCount <= 1) {
      // In single schema databases (e.g. Postgres public or SQLite main), also stretch to bottom
      maxListHeight = (available - _kFolderHeaderHeight).clamp(120.0, double.infinity);
    } else {
      // Multiple schemas without search: allow substantial room while keeping outer scroll smooth
      maxListHeight = (available * 0.65).clamp(240.0, 700.0);
    }

    final listHeight = (tables.length * _kEstimatedItemHeight).clamp(0.0, maxListHeight);

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              if (widget.isSearching) {
                widget.state.openSchemaTab(widget.schemaName);
                return;
              }

              if (!isSchemaTabActive) {
                // First click: activate/show all tables in right section, keep folder collapsed in tree
                widget.state.openSchemaTab(widget.schemaName);
              } else {
                // Second click (already active schema tab): toggle expansion in tree
                setState(() => _expanded = !_expanded);
              }
            },
            child: Container(
              height: _kFolderHeaderHeight,
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              decoration: BoxDecoration(
                color: isSchemaTabActive
                    ? widget.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                border: isSchemaTabActive
                    ? Border(
                        left: BorderSide(color: widget.primary, width: 3),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  // Dedicated expand/collapse chevron
                  InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: AnimatedRotation(
                        turns: _expanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.folder_open : Icons.folder,
                    size: 16,
                    color: const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.schemaName,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSchemaTabActive ? FontWeight.bold : FontWeight.w600,
                        color: isSchemaTabActive ? widget.primary : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _CountBadge(count: tables.length),
                ],
              ),
            ),
          ),
          if (_expanded)
            SizedBox(
              height: listHeight,
              child: ListView.builder(
                controller: _listScrollCtrl,
                physics: const ClampingScrollPhysics(),
                itemCount: tables.length,
                itemBuilder: (ctx, i) => _TableRowTile(
                  key: ValueKey(tables[i].name),
                  table: tables[i],
                  primary: widget.primary,
                  state: widget.state,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _TableRowTile — a single table row with lazy column expansion.
// Columns are only built when the user taps to expand — never upfront.
// ---------------------------------------------------------------------------

class _TableRowTile extends StatefulWidget {
  final TableMetadata table;
  final Color primary;
  final AppState state;

  const _TableRowTile({
    super.key,
    required this.table,
    required this.primary,
    required this.state,
  });

  @override
  State<_TableRowTile> createState() => _TableRowTileState();
}

class _TableRowTileState extends State<_TableRowTile> {
  bool _columnsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final state = widget.state;
    final primary = widget.primary;
    final isSelected = state.selectedTable?.name == table.name;
    final isPostgres = state.activeConnection?.engine == 'postgres';
    final dragTableText = isPostgres
        ? '"${table.schema}"."${table.rawName}"'
        : '`${table.rawName}`';
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('table_${table.name}'),
          initiallyExpanded: false,
          onExpansionChanged: (expanded) {
            setState(() => _columnsExpanded = expanded);
            if (expanded) state.selectTable(table);
          },
          tilePadding: const EdgeInsets.only(left: 20.0, right: 6.0),
          leading: Icon(
            table.tableType == 'VIEW' ? Icons.visibility : Icons.table_chart_outlined,
            size: 15,
            color: isSelected ? primary : Colors.grey.shade600,
          ),
          title: Draggable<String>(
            data: dragTableText,
            feedback: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(6),
              color: const Color(0xFF0F172A),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.table_chart, size: 14, color: primary),
                    const SizedBox(width: 6),
                    Text(
                      dragTableText,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            childWhenDragging: Opacity(
              opacity: 0.4,
              child: Text(table.rawName, style: const TextStyle(fontSize: 12)),
            ),
            child: GestureDetector(
              onDoubleTap: () {
                state.insertTextIntoEditor(dragTableText);
              },
              child: Tooltip(
                message: '${table.rawName} (${table.columns.length} columns) • Double-click to select',
                waitDuration: const Duration(milliseconds: 250),
                child: Text(
                  table.rawName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? primary : null,
                  ),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (table.foreignKeys.isNotEmpty) ...[
                Tooltip(
                  message: '${table.foreignKeys.length} Foreign Key relations',
                  child: Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link, size: 9, color: Color(0xFF14B8A6)),
                        const SizedBox(width: 2),
                        Text(
                          '${table.foreignKeys.length}',
                          style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFF14B8A6)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Text(
                '${table.columns.length}',
                style: const TextStyle(fontSize: 9.5, color: Colors.grey),
              ),
              const SizedBox(width: 2),
              IconButton(
                icon: const Icon(Icons.play_circle_outline, size: 15),
                tooltip: 'Preview table (25 per page)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  state.selectTable(table);
                  state.openTableTab(table.name);
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 14, color: Colors.grey),
                tooltip: 'Table actions',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                onSelected: (val) {
                  if (val == 'select') {
                    state.insertTextIntoEditor('SELECT * FROM $dragTableText LIMIT 50;');
                  } else if (val == 'import') {
                    showDataImportModal(
                      context: context,
                      table: table,
                      onImportRows: ({required rows, bool truncateFirst = false}) {
                        return state.batchInsertRows(
                          tableName: table.name,
                          rowsData: rows,
                          truncateFirst: truncateFirst,
                        );
                      },
                    );
                  } else if (val == 'mock') {
                    showMockDataGeneratorModal(
                      context: context,
                      table: table,
                      onInsertMockRows: (rows) {
                        return state.batchInsertRows(
                          tableName: table.name,
                          rowsData: rows,
                        );
                      },
                    );
                  } else if (val == 'truncate') {
                    showTableLifecycleModal(
                      context: context,
                      tableName: table.name,
                      schemaName: table.schema,
                      action: TableLifecycleAction.truncate,
                      isSafeMode: state.safeMode,
                      onConfirm: ({required bool cascade}) {
                        return state.truncateTable(
                          tableName: table.name,
                          schemaName: table.schema,
                          cascade: cascade,
                        );
                      },
                    );
                  } else if (val == 'drop') {
                    showTableLifecycleModal(
                      context: context,
                      tableName: table.name,
                      schemaName: table.schema,
                      action: TableLifecycleAction.drop,
                      isSafeMode: state.safeMode,
                      onConfirm: ({required bool cascade}) {
                        return state.dropTable(
                          tableName: table.name,
                          schemaName: table.schema,
                          cascade: cascade,
                        );
                      },
                    );
                  } else if (val.startsWith('join:')) {
                    final idx = int.tryParse(val.substring(5)) ?? 0;
                    if (idx < table.foreignKeys.length) {
                      final fk = table.foreignKeys[idx];
                      state.insertTextIntoEditor('\nJOIN ${fk.targetTable} ON ${table.rawName}.${fk.columnName} = ${fk.targetTable}.${fk.targetColumn}');
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'select',
                    height: 32,
                    child: Text('Generate SELECT query', style: TextStyle(fontSize: 11)),
                  ),
                  if (table.foreignKeys.isNotEmpty) ...[
                    for (int i = 0; i < table.foreignKeys.length; i++)
                      PopupMenuItem(
                        value: 'join:$i',
                        height: 32,
                        child: Row(
                          children: [
                            const Icon(Icons.link, size: 12, color: Color(0xFF14B8A6)),
                            const SizedBox(width: 6),
                            Text('JOIN ${table.foreignKeys[i].targetTable}', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                  ],
                  const PopupMenuDivider(height: 8),
                  const PopupMenuItem(
                    value: 'import',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(Icons.file_upload_outlined, size: 13, color: Color(0xFF14B8A6)),
                        SizedBox(width: 6),
                        Text('Import Data (CSV/JSON)...', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'mock',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome_outlined, size: 13, color: Color(0xFF38BDF8)),
                        SizedBox(width: 6),
                        Text('Generate Mock Data...', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(height: 8),
                  const PopupMenuItem(
                    value: 'truncate',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(Icons.cleaning_services_outlined, size: 13, color: Color(0xFFF59E0B)),
                        SizedBox(width: 6),
                        Text('Truncate Table...', style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B))),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'drop',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever_outlined, size: 13, color: Color(0xFFF43F5E)),
                        SizedBox(width: 6),
                        Text('Drop Table...', style: TextStyle(fontSize: 11, color: Color(0xFFF43F5E))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Lazy: only build column tiles when this table row is actually expanded
          children: _columnsExpanded
              ? table.columns
                  .map((col) => _buildColumnTile(context, state, table, col, dragTableText, primary))
                  .toList()
              : [],
        ),
      ),
    );
  }

  Widget _buildColumnTile(
    BuildContext context,
    AppState state,
    TableMetadata table,
    ColumnMetadata col,
    String dragTableText,
    Color primary,
  ) {
    return Draggable<String>(
      data: col.name,
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(6),
        color: const Color(0xFF0F172A),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                col.isPrimaryKey ? Icons.key : Icons.commit,
                size: 13,
                color: col.isPrimaryKey ? Colors.amber : primary,
              ),
              const SizedBox(width: 6),
              Text(
                col.name,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  col.dataType.toUpperCase(),
                  style: const TextStyle(fontSize: 8, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.4,
        child: _buildColumnContent(context, col),
      ),
      child: GestureDetector(
        onDoubleTap: () {
          state.insertTextIntoEditor(col.name);
        },
        child: Tooltip(
          message: 'Drag column or double-click to add to query',
          child: _buildColumnContent(context, col),
        ),
      ),
    );
  }

  Widget _buildColumnContent(BuildContext context, ColumnMetadata col) {
    final hasFk = col.foreignKey != null;
    return Padding(
      padding: const EdgeInsets.only(left: 40.0, right: 12.0, top: 2.0, bottom: 2.0),
      child: Row(
        children: [
          Icon(
            col.isPrimaryKey
                ? Icons.key
                : (hasFk ? Icons.link : Icons.commit),
            size: 12,
            color: col.isPrimaryKey
                ? Colors.amber.shade700
                : (hasFk ? const Color(0xFF14B8A6) : Colors.grey.shade400),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    col.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: col.isPrimaryKey ? FontWeight.bold : FontWeight.normal,
                      color: hasFk ? const Color(0xFF2DD4BF) : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (col.isPrimaryKey) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 0.5),
                    ),
                    child: const Text('PK', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Colors.amber)),
                  ),
                ],
                if (col.isUnique && !col.isPrimaryKey) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.4), width: 0.5),
                    ),
                    child: const Text('UQ', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold, color: Colors.lightBlueAccent)),
                  ),
                ],
              ],
            ),
          ),
          if (hasFk) ...[
            Tooltip(
              message: 'Foreign Key -> ${col.foreignKey!.targetTable}.${col.foreignKey!.targetColumn}',
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.35), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link, size: 9, color: Color(0xFF14B8A6)),
                    const SizedBox(width: 2),
                    Text(
                      col.foreignKey!.targetTable,
                      style: const TextStyle(fontSize: 8, fontFamily: 'monospace', color: Color(0xFF14B8A6), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              col.dataType.toUpperCase(),
              style: const TextStyle(fontSize: 8, fontFamily: 'monospace', color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _CountBadge — small pill showing table/schema count.
// Extracted so it's not rebuilt inside itemBuilder unnecessarily.
// ---------------------------------------------------------------------------

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
