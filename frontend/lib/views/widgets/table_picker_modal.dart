import 'package:flutter/material.dart';
import '../../models/table_schema.dart';

/// Shows a rich, searchable modal (dialog on desktop/tablet, bottom sheet on mobile)
/// for browsing and selecting database tables grouped by schema namespace.
Future<TableMetadata?> showTablePickerModal({
  required BuildContext context,
  required String title,
  required List<TableMetadata> tables,
  TableMetadata? currentTable,
  required ValueChanged<TableMetadata> onSelected,
}) async {
  final isWide = MediaQuery.of(context).size.width >= 600;

  if (isWide) {
    return showDialog<TableMetadata>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 640,
            maxHeight: 700,
          ),
          child: _TablePickerModalContent(
            title: title,
            tables: tables,
            currentTable: currentTable,
            onSelected: onSelected,
            isDialog: true,
          ),
        ),
      ),
    );
  } else {
    return showModalBottomSheet<TableMetadata>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _TablePickerModalContent(
        title: title,
        tables: tables,
        currentTable: currentTable,
        onSelected: onSelected,
        isDialog: false,
      ),
    );
  }
}

class _TablePickerModalContent extends StatefulWidget {
  final String title;
  final List<TableMetadata> tables;
  final TableMetadata? currentTable;
  final ValueChanged<TableMetadata> onSelected;
  final bool isDialog;

  const _TablePickerModalContent({
    required this.title,
    required this.tables,
    required this.currentTable,
    required this.onSelected,
    required this.isDialog,
  });

  @override
  State<_TablePickerModalContent> createState() => _TablePickerModalContentState();
}

class _TablePickerModalContentState extends State<_TablePickerModalContent> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Cached filter results — computed once per change, not every build()
  Map<String, List<TableMetadata>> _filteredGrouped = {};
  List<String> _sortedSchemas = [];

  @override
  void initState() {
    super.initState();
    _rebuildFilter('');
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _rebuildFilter(_searchCtrl.text.trim().toLowerCase());
  }

  void _rebuildFilter(String query) {
    final Map<String, List<TableMetadata>> grouped = {};
    for (final t in widget.tables) {
      final s = t.schema.isNotEmpty ? t.schema : 'default';
      grouped.putIfAbsent(s, () => []).add(t);
    }
    final Map<String, List<TableMetadata>> filtered = {};
    grouped.forEach((schema, tables) {
      if (query.isEmpty) {
        filtered[schema] = tables;
      } else {
        final m = tables.where((t) =>
          schema.toLowerCase().contains(query) ||
          t.rawName.toLowerCase().contains(query) ||
          t.name.toLowerCase().contains(query)
        ).toList();
        if (m.isNotEmpty) filtered[schema] = m;
      }
    });
    setState(() {
      _filteredGrouped = filtered;
      _sortedSchemas = filtered.keys.toList()..sort();
      _searchQuery = query;
    });
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalFilteredTables =
        _filteredGrouped.values.fold<int>(0, (sum, list) => sum + list.length);
    final isSearching = _searchQuery.isNotEmpty;

    return SafeArea(
      child: Container(
        constraints: widget.isDialog
            ? null
            : BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          mainAxisSize: widget.isDialog ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.isDialog)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.folder_copy_outlined,
                      size: 19, color: Color(0xFFF59E0B)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '$totalFilteredTables tables in ${_sortedSchemas.length} schema folder${_sortedSchemas.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search Bar
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search tables or schema folder...',
                hintStyle:
                    const TextStyle(fontSize: 12, color: Colors.grey),
                prefixIcon:
                    const Icon(Icons.search, size: 18, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: theme.dividerColor.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                      color: Color(0xFF14B8A6), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Folders List — virtualized within large schema folders
            Expanded(
              child: _sortedSchemas.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.folder_off_outlined,
                                size: 36, color: Colors.grey),
                            const SizedBox(height: 8),
                            Text(
                              'No tables or schema folders match "$_searchQuery"',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _sortedSchemas.length,
                      itemBuilder: (context, sIdx) {
                        final schemaName = _sortedSchemas[sIdx];
                        final tables = _filteredGrouped[schemaName] ?? [];
                        final hasSelectedInSchema =
                            widget.currentTable != null &&
                                (widget.currentTable!.schema == schemaName ||
                                    (widget.currentTable!.schema.isEmpty &&
                                        schemaName == 'default'));

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LazySchemaPickerFolder(
                            key: PageStorageKey('picker_schema_$schemaName'),
                            schemaName: schemaName,
                            tables: tables,
                            currentTable: widget.currentTable,
                            isInitiallyExpanded: isSearching ||
                                _sortedSchemas.length <= 3 ||
                                hasSelectedInSchema,
                            onSelected: (t) {
                              Navigator.of(context).pop(t);
                              widget.onSelected(t);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _LazySchemaPickerFolder — schema folder with lazy-load spinner for large
// schemas (>50 tables) and virtual ListView.builder for table rows.
// ---------------------------------------------------------------------------

class _LazySchemaPickerFolder extends StatefulWidget {
  final String schemaName;
  final List<TableMetadata> tables;
  final TableMetadata? currentTable;
  final bool isInitiallyExpanded;
  final ValueChanged<TableMetadata> onSelected;

  const _LazySchemaPickerFolder({
    super.key,
    required this.schemaName,
    required this.tables,
    required this.currentTable,
    required this.isInitiallyExpanded,
    required this.onSelected,
  });

  @override
  State<_LazySchemaPickerFolder> createState() => _LazySchemaPickerFolderState();
}

class _LazySchemaPickerFolderState extends State<_LazySchemaPickerFolder> {
  bool _expanded = false;
  bool _isLoading = false;

  // Schemas with more than this many tables show a brief loading spinner
  static const int _kLargeThreshold = 50;
  // Height per table row item in the modal (matches the Row padding; fixed height = OK)
  static const double _kItemExtent = 52.0;
  // Cap visible list so the modal stays scrollable
  static const double _kMaxListHeight = 400.0;

  // keepScrollOffset: false → bypasses PageStorage for scroll restoration.
  // Without this, the inner ListView's Scrollable reads PageStorage and finds
  // the bool that ExpansionTile wrote (its expanded state), causing:
  //   "type 'bool' is not a subtype of type 'double?' in type cast"
  final ScrollController _listScrollCtrl = ScrollController(keepScrollOffset: false);

  @override
  void initState() {
    super.initState();
    if (widget.isInitiallyExpanded) {
      _triggerExpand();
    }
  }

  @override
  void didUpdateWidget(_LazySchemaPickerFolder old) {
    super.didUpdateWidget(old);
    if (!old.isInitiallyExpanded && widget.isInitiallyExpanded && !_expanded) {
      _triggerExpand();
    }
  }

  @override
  void dispose() {
    _listScrollCtrl.dispose();
    super.dispose();
  }

  void _triggerExpand() {
    if (widget.tables.length > _kLargeThreshold) {
      // Show spinner for 1 frame so Flutter can render before building the list
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() { _isLoading = true; _expanded = false; });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() { _isLoading = false; _expanded = true; });
        });
      });
    } else {
      _expanded = true;
    }
  }

  void _onExpansionChanged(bool expanded) {
    if (expanded && widget.tables.length > _kLargeThreshold) {
      setState(() { _expanded = false; _isLoading = true; });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() { _isLoading = false; _expanded = true; });
      });
    } else {
      setState(() { _expanded = expanded; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tables = widget.tables;
    final listHeight = (tables.length * _kItemExtent).clamp(0.0, _kMaxListHeight);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.2),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: widget.key,
          initiallyExpanded: _expanded,
          onExpansionChanged: _onExpansionChanged,
          leading: const Icon(
            Icons.folder,
            size: 18,
            color: Color(0xFFF59E0B),
          ),
          title: Text(
            widget.schemaName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          trailing: _PickerCountBadge(count: tables.length),
          children: [
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_expanded)
              SizedBox(
                height: listHeight,
                child: ListView.builder(
                  controller: _listScrollCtrl,
                  physics: const ClampingScrollPhysics(),
                  itemCount: tables.length,
                  itemExtent: _kItemExtent,
                  itemBuilder: (_, i) => _buildTableItem(context, tables[i], theme),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableItem(BuildContext context, TableMetadata t, ThemeData theme) {
    final isSelected = widget.currentTable != null &&
        widget.currentTable!.rawName == t.rawName &&
        widget.currentTable!.schema == t.schema;

    return Material(
      color: isSelected
          ? const Color(0xFF14B8A6).withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelected(t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Icon(
                Icons.table_chart_outlined,
                size: 16,
                color: isSelected ? const Color(0xFF14B8A6) : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      t.rawName,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        fontSize: 12.5,
                        color: isSelected ? const Color(0xFF14B8A6) : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${t.columns.length} columns • ${t.tableType}',
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle,
                    size: 16, color: Color(0xFF14B8A6))
              else
                const Icon(Icons.chevron_right,
                    size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PickerCountBadge — count badge for schema folder in the modal.
// ---------------------------------------------------------------------------

class _PickerCountBadge extends StatelessWidget {
  final int count;

  const _PickerCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
