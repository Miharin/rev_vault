import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/table_schema.dart';
import '../../state/app_state.dart';
import 'create_table_modal.dart';

class SchemaOverviewView extends StatefulWidget {
  final String schemaName;

  const SchemaOverviewView({
    super.key,
    required this.schemaName,
  });

  @override
  State<SchemaOverviewView> createState() => _SchemaOverviewViewState();
}

class _SchemaOverviewViewState extends State<SchemaOverviewView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = '';
  bool _isCompactView = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    // Filter tables belonging exclusively to this schema
    final schemaTables = state.tables.where((t) => t.schema == widget.schemaName).toList();

    final filteredTables = _filter.isEmpty
        ? schemaTables
        : schemaTables.where((t) {
            final q = _filter.toLowerCase();
            return t.rawName.toLowerCase().contains(q) ||
                t.name.toLowerCase().contains(q) ||
                t.columns.any((c) => c.name.toLowerCase().contains(q));
          }).toList();

    final baseTableCount = schemaTables.where((t) => t.tableType != 'VIEW').length;
    final viewCount = schemaTables.where((t) => t.tableType == 'VIEW').length;

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tactical Header Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                // Schema Title & Badges
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Icon(
                        Icons.folder_copy_outlined,
                        size: 20,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.schemaName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: accent.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                state.activeConnection?.engine.toUpperCase() ?? 'DB',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${schemaTables.length} total objects • $baseTableCount tables • $viewCount views',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Controls: Search, View Mode Toggle, Create Table Action
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search bar
                    SizedBox(
                      width: 220,
                      height: 32,
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _filter = v.trim()),
                        style: const TextStyle(fontSize: 11.5),
                        decoration: InputDecoration(
                          hintText: 'Filter tables in ${widget.schemaName}...',
                          hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                          prefixIcon: const Icon(Icons.search, size: 14, color: Colors.grey),
                          suffixIcon: _filter.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 12, color: Colors.grey),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _filter = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Layout Mode Toggle (Cards vs Compact Grid)
                    Tooltip(
                      message: _isCompactView ? 'Switch to Card Grid' : 'Switch to Compact List',
                      child: IconButton(
                        icon: Icon(_isCompactView ? Icons.grid_view : Icons.view_headline, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _isCompactView = !_isCompactView),
                      ),
                    ),

                    const SizedBox(width: 4),

                    // Create Table in this schema button
                    ElevatedButton.icon(
                      onPressed: state.activeConnection == null
                          ? null
                          : () {
                              showCreateTableModal(
                                context: context,
                                engine: state.activeConnection?.engine ?? 'sqlite',
                                defaultSchema: widget.schemaName,
                                existingTables: state.tables,
                                onCreateTable: ({
                                  required tableName,
                                  schemaName,
                                  required columns,
                                  bool ifNotExists = true,
                                }) {
                                  return state.createTable(
                                    tableName: tableName,
                                    schemaName: schemaName ?? widget.schemaName,
                                    columns: columns,
                                    ifNotExists: ifNotExists,
                                  );
                                },
                              );
                            },
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text('New Table', style: TextStyle(fontSize: 11.5)),
                      style: ElevatedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Content: Tables Catalog
          Expanded(
            child: filteredTables.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.table_chart_outlined,
                            size: 48,
                            color: theme.dividerColor.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            schemaTables.isEmpty
                                ? 'No tables found in schema "${widget.schemaName}"'
                                : 'No tables match "$_filter" in schema "${widget.schemaName}"',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                : (_isCompactView
                    ? _buildCompactListView(context, state, filteredTables, accent)
                    : _buildCardGridView(context, state, filteredTables, accent)),
          ),
        ],
      ),
    );
  }

  Widget _buildCardGridView(
    BuildContext context,
    AppState state,
    List<TableMetadata> tables,
    Color accent,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 1;
        if (constraints.maxWidth > 1100) {
          crossAxisCount = 3;
        } else if (constraints.maxWidth > 650) {
          crossAxisCount = 2;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 148,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final table = tables[index];
            return _SchemaTableCard(
              table: table,
              accent: accent,
              onOpen: () => state.openTableTab(table.name),
              onQuery: () {
                final isPostgres = state.activeConnection?.engine == 'postgres';
                final qTable = isPostgres ? '"${table.schema}"."${table.rawName}"' : '`${table.rawName}`';
                state.openQueryTab(
                  initialSql: 'SELECT * FROM $qTable LIMIT 50;',
                  title: table.rawName,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCompactListView(
    BuildContext context,
    AppState state,
    List<TableMetadata> tables,
    Color accent,
  ) {
    final theme = Theme.of(context);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: tables.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final table = tables[index];
        final isView = table.tableType == 'VIEW';
        final pkCols = table.columns.where((c) => c.isPrimaryKey).map((c) => c.name).toList();

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          leading: Icon(
            isView ? Icons.visibility : Icons.table_chart_outlined,
            size: 18,
            color: isView ? Colors.cyan : accent,
          ),
          title: Row(
            children: [
              Text(
                table.rawName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: (isView ? Colors.cyan : Colors.blueGrey).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  table.tableType,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isView ? Colors.cyan : Colors.blueGrey,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Text(
            '${table.columns.length} columns${pkCols.isNotEmpty ? " • PK: ${pkCols.join(', ')}" : ""}${table.foreignKeys.isNotEmpty ? " • ${table.foreignKeys.length} FK relations" : ""}',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () => state.openTableTab(table.name),
                icon: const Icon(Icons.play_circle_outline, size: 14),
                label: const Text('View Data', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.terminal, size: 16),
                tooltip: 'Open in Query Tab',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final isPostgres = state.activeConnection?.engine == 'postgres';
                  final qTable = isPostgres ? '"${table.schema}"."${table.rawName}"' : '`${table.rawName}`';
                  state.openQueryTab(
                    initialSql: 'SELECT * FROM $qTable LIMIT 50;',
                    title: table.rawName,
                  );
                },
              ),
            ],
          ),
          onTap: () => state.openTableTab(table.name),
        );
      },
    );
  }
}

class _SchemaTableCard extends StatefulWidget {
  final TableMetadata table;
  final Color accent;
  final VoidCallback onOpen;
  final VoidCallback onQuery;

  const _SchemaTableCard({
    required this.table,
    required this.accent,
    required this.onOpen,
    required this.onQuery,
  });

  @override
  State<_SchemaTableCard> createState() => _SchemaTableCardState();
}

class _SchemaTableCardState extends State<_SchemaTableCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final table = widget.table;
    final isView = table.tableType == 'VIEW';
    final pkCols = table.columns.where((c) => c.isPrimaryKey).map((c) => c.name).toList();

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        onTap: widget.onOpen,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _isHovered ? widget.accent.withValues(alpha: 0.5) : theme.dividerColor.withValues(alpha: 0.25),
              width: _isHovered ? 1.2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Card Top: Table icon, Name, Type Badge
              Row(
                children: [
                  Icon(
                    isView ? Icons.visibility : Icons.table_chart_outlined,
                    size: 16,
                    color: isView ? Colors.cyan : widget.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      table.rawName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _isHovered ? widget.accent : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: (isView ? Colors.cyan : widget.accent).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      table.tableType,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isView ? Colors.cyan : widget.accent,
                      ),
                    ),
                  ),
                ],
              ),

              // Card Center: Columns, PK, FK Indicators
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      '${table.columns.length} cols',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (pkCols.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.key, size: 10, color: Colors.amber),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                pkCols.join(', '),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (table.foreignKeys.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link, size: 10, color: Color(0xFF14B8A6)),
                          const SizedBox(width: 3),
                          Text(
                            '${table.foreignKeys.length} FK',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF14B8A6)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              // Card Bottom: Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: table.name));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied "${table.name}" to clipboard'),
                          duration: const Duration(milliseconds: 1400),
                          behavior: SnackBarBehavior.floating,
                          width: 260,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(Icons.copy, size: 13, color: Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: widget.onQuery,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.terminal, size: 12),
                          SizedBox(width: 4),
                          Text('Query', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: widget.onOpen,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: widget.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: widget.accent.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_outline, size: 12, color: widget.accent),
                          const SizedBox(width: 4),
                          Text(
                            'View Data',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: widget.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
