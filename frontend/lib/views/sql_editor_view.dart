import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/sql_autocomplete_service.dart';
import '../state/app_state.dart';
import 'widgets/tactical_hud_widgets.dart';
import 'widgets/virtualized_data_table.dart';
import 'widgets/saved_queries_modal.dart';
import 'widgets/convert_code_modal.dart';
import 'widgets/sql_subquery_snippets_modal.dart';
import 'widgets/sql_autocomplete_dock.dart';
import 'widgets/api_generator_modal.dart';
import 'widgets/explain_plan_modal.dart';
import 'widgets/workspace_tab_bar.dart';
import 'widgets/row_edit_modal.dart';
import 'widgets/row_delete_modal.dart';
import 'widgets/row_insert_modal.dart';
import 'widgets/row_duplicate_modal.dart';
import 'widgets/safe_mode_confirm_dialog.dart';
import 'widgets/mutation_history_modal.dart';
import 'widgets/bulk_delete_modal.dart';
import 'widgets/cyber_switch.dart';
import '../models/table_schema.dart';
import '../models/query_result.dart';

class SqlEditorView extends StatefulWidget {
  const SqlEditorView({super.key});

  @override
  State<SqlEditorView> createState() => _SqlEditorViewState();
}

class _SqlEditorViewState extends State<SqlEditorView> {
  late final TextEditingController _queryCtrl;
  final FocusNode _editorFocusNode = FocusNode();
  final TextEditingController _tableFilterCtrl = TextEditingController();
  String _tableFilter = '';
  bool _showOptionDetail = false;
  bool _isSelectionMode = false;

  int? _sortColumnIndex;
  bool _sortAscending = true;

  // Autocomplete state
  final SqlAutocompleteService _autocompleteService = SqlAutocompleteService();
  List<SqlSuggestion> _suggestions = [];
  int _selectedSuggestionIndex = 0;
  bool _showAutocomplete = false;
  bool _isAutoSuggestEnabled = true;

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: context.read<AppState>().editorQueryText);
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _editorFocusNode.dispose();
    _tableFilterCtrl.dispose();
    super.dispose();
  }

  void _runQuery() {
    _hideAutocomplete();
    final sql = _queryCtrl.text.trim();
    if (sql.isNotEmpty) {
      context.read<AppState>().runQuery(sql);
    }
  }

  void _formatSql() {
    context.read<AppState>().formatEditorSql();
    _queryCtrl.text = context.read<AppState>().editorQueryText;
  }

  String? _inferTableName(AppState state, [List<String>? resultColumns]) {
    // 1. If active preview table is set or active tab is a table preview
    if (state.activePreviewTable != null && state.activePreviewTable!.isNotEmpty) {
      return state.activePreviewTable;
    }
    if (state.activeTab.isTablePreview &&
        state.activeTab.tableName != null &&
        state.activeTab.tableName!.isNotEmpty) {
      return state.activeTab.tableName;
    }

    // 2. Parse FROM / INTO / UPDATE clause from editor query text
    final queryText = state.editorQueryText;
    final match = RegExp(r'\b(?:FROM|INTO|UPDATE)\s+([`"a-zA-Z0-9_.]+)', caseSensitive: false).firstMatch(queryText);
    if (match != null) {
      final parsed = match.group(1)!.replaceAll('`', '').replaceAll('"', '').trim();
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    // 3. Match table by column overlap fingerprinting if result columns are known
    if (resultColumns != null && resultColumns.isNotEmpty) {
      final best = _findTableByColumns(state, resultColumns);
      if (best != null) return best.name;
    }

    // 4. Fallback only if query text has no FROM clause
    if (state.selectedTable != null) {
      return state.selectedTable!.name;
    }
    return null;
  }

  TableMetadata? _findTableByColumns(AppState state, List<String> resultColumns) {
    if (resultColumns.isEmpty) return null;
    final resColsLower = resultColumns.map((c) => c.toLowerCase()).toSet();
    TableMetadata? bestMatch;
    int maxScore = 0;

    for (final t in state.tables) {
      int score = 0;
      for (final col in t.columns) {
        if (resColsLower.contains(col.name.toLowerCase())) {
          score++;
        }
      }
      if (score > maxScore) {
        maxScore = score;
        bestMatch = t;
      }
    }
    if (bestMatch != null && (maxScore >= 2 || (resultColumns.length == 1 && maxScore == 1))) {
      return bestMatch;
    }
    return null;
  }

  TableMetadata? _findTableMetadata(AppState state, String tbl, [List<String>? resultColumns]) {
    // 1. Direct tab metadata if present
    if (state.activeTab.isTablePreview && state.activeTab.tableMetadata != null) {
      if (tbl.isEmpty || state.activeTab.tableName?.toLowerCase() == tbl.toLowerCase()) {
        return state.activeTab.tableMetadata;
      }
    }

    final cleanTbl = tbl.trim().replaceAll('"', '').replaceAll('`', '');

    // 2. Exact match by full name (e.g. "rawat_inap_rme.cara_keluar" or "cara_keluar")
    if (cleanTbl.isNotEmpty) {
      for (final t in state.tables) {
        if (t.name.toLowerCase() == cleanTbl.toLowerCase()) return t;
      }
    }

    // 3. Match by raw table name (e.g. "cara_keluar" without schema prefix)
    final rawTbl = cleanTbl.contains('.') ? cleanTbl.split('.').last : cleanTbl;
    final candidates = <TableMetadata>[];
    if (rawTbl.isNotEmpty) {
      for (final t in state.tables) {
        if (t.rawName.toLowerCase() == rawTbl.toLowerCase() ||
            t.name.toLowerCase() == rawTbl.toLowerCase() ||
            (t.name.contains('.') && t.name.split('.').last.toLowerCase() == rawTbl.toLowerCase())) {
          candidates.add(t);
        }
      }
    }

    // If multiple candidate tables exist with the same name across schemas
    // or if result columns are provided, score by matching column names
    if (resultColumns != null && resultColumns.isNotEmpty) {
      final searchPool = candidates.isNotEmpty ? candidates : state.tables;
      final resColsLower = resultColumns.map((c) => c.toLowerCase()).toSet();
      TableMetadata? bestMatch;
      int maxScore = 0;

      for (final t in searchPool) {
        int score = 0;
        for (final col in t.columns) {
          if (resColsLower.contains(col.name.toLowerCase())) {
            score++;
          }
        }
        if (score > maxScore) {
          maxScore = score;
          bestMatch = t;
        }
      }

      if (bestMatch != null && maxScore > 0) {
        return bestMatch;
      }
    }

    if (candidates.isNotEmpty) return candidates.first;

    // 4. Fallback: column fingerprinting across all tables
    if (resultColumns != null && resultColumns.isNotEmpty) {
      return _findTableByColumns(state, resultColumns);
    }

    return null;
  }

  void _openInsertRowModal(BuildContext context, AppState state, dynamic res) {
    final columnsList = List<String>.from(res.columns);
    final tbl = _inferTableName(state, columnsList);
    if (tbl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot identify target table to insert row')),
      );
      return;
    }
    final meta = _findTableMetadata(state, tbl, columnsList);
    showRowInsertModal(
      context: context,
      tableName: tbl,
      columns: columnsList,
      tableMetadata: meta,
      onInsert: ({required rowValues}) async {
        if (state.safeMode) {
          final confirmed = await showSafeModeConfirmDialog(
            context: context,
            operation: 'insert',
            tableName: tbl,
            primaryKeys: const {},
            changes: rowValues.map((k, v) => MapEntry(k, {'old': null, 'new': v})),
          );
          if (confirmed != true) return 'Operation cancelled in Safe Mode confirmation dialog.';
        }

        final ok = await state.insertTableRow(
          tableName: tbl,
          rowValues: rowValues,
        );
        if (ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Row inserted successfully'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              width: 280,
            ),
          );
          return null;
        }
        return state.errorMessage ?? 'Row insert failed. Check database constraints or logs.';
      },
    );
  }

  void _openDuplicateRowModal(
    BuildContext context,
    AppState state,
    dynamic res,
    int rowIndex,
    List<dynamic> rowValues,
  ) {
    final columnsList = List<String>.from(res.columns);
    final tbl = _inferTableName(state, columnsList);
    if (tbl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot identify target table to duplicate row')),
      );
      return;
    }
    final meta = _findTableMetadata(state, tbl, columnsList);
    showRowDuplicateModal(
      context: context,
      tableName: tbl,
      columns: columnsList,
      rowValues: rowValues,
      tableMetadata: meta,
      onDuplicate: ({required rowsToInsert, required count}) async {
        if (state.safeMode) {
          final previewChanges = rowsToInsert.isNotEmpty
              ? rowsToInsert.first.map((k, v) => MapEntry(k, {'old': null, 'new': v}))
              : <String, dynamic>{};
          final confirmed = await showSafeModeConfirmDialog(
            context: context,
            operation: 'insert',
            tableName: tbl,
            primaryKeys: const {},
            changes: previewChanges,
          );
          if (confirmed != true) return 'Operation cancelled in Safe Mode confirmation dialog.';
        }

        final ok = await state.duplicateTableRow(
          tableName: tbl,
          rowsToInsert: rowsToInsert,
          count: count,
        );
        if (ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Duplicated $count row(s) successfully'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              width: 280,
            ),
          );
          return null;
        }
        return state.errorMessage ?? 'Duplication failed. Check database constraints or logs.';
      },
    );
  }

  void _onQueryChanged(String text) {
    context.read<AppState>().editorQueryText = text;

    if (!_isAutoSuggestEnabled) {
      _hideAutocomplete();
      return;
    }

    final cursor = _queryCtrl.selection.baseOffset;
    if (cursor > 0) {
      final tables = context.read<AppState>().tables;
      final results = _autocompleteService.getSuggestions(
        text: text,
        cursorPosition: cursor,
        tables: tables,
      );

      setState(() {
        _suggestions = results;
        _selectedSuggestionIndex = 0;
        _showAutocomplete = results.isNotEmpty;
      });
    } else {
      _hideAutocomplete();
    }
  }

  void _hideAutocomplete() {
    if (_showAutocomplete) {
      setState(() {
        _showAutocomplete = false;
        _suggestions = [];
      });
    }
  }

  void _applySuggestion(SqlSuggestion suggestion) {
    final text = _queryCtrl.text;
    final cursor = _queryCtrl.selection.baseOffset;
    if (cursor < 0) return;

    final textBeforeCursor = text.substring(0, cursor);
    final wordMatch = RegExp(r'([a-zA-Z0-9_.:]+)$').firstMatch(textBeforeCursor);
    final currentWord = wordMatch?.group(1) ?? '';

    final replaceStart = cursor - currentWord.length;
    final newText = text.substring(0, replaceStart) +
        suggestion.insertText +
        text.substring(cursor);

    final newCursor = replaceStart + suggestion.insertText.length;

    _queryCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );

    context.read<AppState>().editorQueryText = newText;
    _hideAutocomplete();
    _editorFocusNode.requestFocus();
  }

  Future<void> _openSubquerySnippets() async {
    final snippet = await showSqlSubquerySnippetsModal(context);
    if (!mounted) return;
    if (snippet != null) {
      final currentSql = _queryCtrl.text.trim();
      final newSql = currentSql.isEmpty ? snippet.template : '$currentSql\n\n${snippet.template}';
      context.read<AppState>().editorQueryText = newSql;
      _queryCtrl.text = newSql;
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_showAutocomplete || _suggestions.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedSuggestionIndex = (_selectedSuggestionIndex + 1) % _suggestions.length;
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedSuggestionIndex =
              (_selectedSuggestionIndex - 1 + _suggestions.length) % _suggestions.length;
        });
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.tab ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        final isModifierActive = HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed;
        if (!isModifierActive) {
          _applySuggestion(_suggestions[_selectedSuggestionIndex]);
          return KeyEventResult.handled;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _hideAutocomplete();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final detectedParams = _autocompleteService.extractParameters(state.editorQueryText);

    // Keep text controller synchronized with AppState when preview or external action updates query
    if (_queryCtrl.text != state.editorQueryText) {
      _queryCtrl.value = TextEditingValue(
        text: state.editorQueryText,
        selection: TextSelection.collapsed(offset: state.editorQueryText.length),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final editorHeight = isMobile
            ? (constraints.maxHeight * 0.35).clamp(110.0, 320.0)
            : 180.0;

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter, control: true): _runQuery,
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _runQuery,
            const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true): _runQuery,
            const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true): _runQuery,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WorkspaceTabBar(),
              // SQL Editor Toolbar (Adaptive Mobile / Desktop)
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 10 : 16,
                  vertical: isMobile ? 6 : 8,
                ),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                child: isMobile
                    ? _buildMobileToolbar(context, state, theme, detectedParams)
                    : _buildDesktopToolbar(context, state, theme, detectedParams),
              ),

              // SQL Editor Input with Docked IntelliSense Assistant (35% on mobile)
              Focus(
                onKeyEvent: _handleKeyEvent,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DragTarget<Object>(
                      onWillAcceptWithDetails: (details) => true,
                      onAcceptWithDetails: (details) {
                        final data = details.data;
                        if (data is String) {
                          state.insertTextIntoEditor(data);
                        }
                      },
                      builder: (context, candidateData, rejectedData) {
                        final isHovered = candidateData.isNotEmpty;

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isHovered
                                ? const Color(0xFF14B8A6).withValues(alpha: 0.08)
                                : theme.colorScheme.surface,
                            border: isHovered
                                ? Border.all(color: const Color(0xFF14B8A6), width: 2)
                                : null,
                          ),
                          height: editorHeight,
                          child: Stack(
                            children: [
                              TextField(
                                controller: _queryCtrl,
                                focusNode: _editorFocusNode,
                                maxLines: null,
                                expands: true,
                                onChanged: _onQueryChanged,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: isMobile ? 12.5 : 13,
                                  height: 1.45,
                                ),
                                decoration: InputDecoration(
                                  hintText: isMobile
                                      ? 'Enter SQL query (Run Ctrl+Enter)...'
                                      : 'Enter your SQL query (type for smart autocomplete, or drag & drop tables/columns from schema sidebar)...',
                                  border: InputBorder.none,
                                ),
                              ),
                              if (isHovered)
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF14B8A6),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add, size: 14, color: Colors.white),
                                        SizedBox(width: 4),
                                        Text(
                                          'Drop to insert into query',
                                          style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (_showAutocomplete && _isAutoSuggestEnabled && _suggestions.isNotEmpty)
                      SqlAutocompleteDock(
                        suggestions: _suggestions,
                        selectedIndex: _selectedSuggestionIndex,
                        onSelect: _applySuggestion,
                        onClose: _hideAutocomplete,
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Results Section (65% on mobile)
              Expanded(
                child: _buildResultsSection(context, state),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileToolbar(
    BuildContext context,
    AppState state,
    ThemeData theme,
    List<String> detectedParams,
  ) {
    return Row(
      children: [
        TacticalPulseButton(
          onPressed: _runQuery,
          icon: const Icon(Icons.play_arrow, size: 15, color: Colors.white),
          label: 'Run',
          shortcutLabel: null,
          isExecuting: state.isExecutingQuery,
        ),
        const SizedBox(width: 8),

        IconButton(
          icon: const Icon(Icons.format_align_left_outlined, size: 16),
          tooltip: 'Format SQL',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: _formatSql,
        ),

        const SizedBox(width: 4),

        // Safe mode badge toggle
        InkWell(
          onTap: () => state.toggleSafeMode(!state.safeMode),
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: state.safeMode
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: state.safeMode
                    ? Colors.green.withValues(alpha: 0.4)
                    : Colors.amber.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state.safeMode ? Icons.shield : Icons.warning_amber,
                  size: 12,
                  color: state.safeMode ? Colors.green : Colors.amber.shade800,
                ),
                const SizedBox(width: 4),
                Text(
                  state.safeMode ? 'SAFE' : 'RAW',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: state.safeMode ? Colors.green.shade800 : Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (detectedParams.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
            decoration: BoxDecoration(
              color: Colors.pinkAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${detectedParams.length} params',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.pinkAccent),
            ),
          ),
        ],

        const Spacer(),

        // Overflow Popup Menu for Secondary Actions
        PopupMenuButton<String>(
          tooltip: 'SQL Actions & Tools',
          icon: const Icon(Icons.more_vert, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onSelected: (val) {
            switch (val) {
              case 'snippets':
                _openSubquerySnippets();
                break;
              case 'api':
                showApiGeneratorModal(context, query: _queryCtrl.text);
                break;
              case 'convert':
                showConvertCodeModal(context);
                break;
              case 'explain':
                showExplainPlanModal(context, query: _queryCtrl.text);
                break;
              case 'save':
                showSaveQueryDialog(context);
                break;
              case 'saved_list':
                showSavedQueriesModal(context);
                break;
              case 'clear':
                _queryCtrl.clear();
                state.editorQueryText = '';
                break;
              case 'suggest':
                setState(() {
                  _isAutoSuggestEnabled = !_isAutoSuggestEnabled;
                  if (!_isAutoSuggestEnabled) _hideAutocomplete();
                });
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'snippets',
              child: Row(
                children: [
                  Icon(Icons.hub_outlined, size: 15, color: Colors.purpleAccent),
                  SizedBox(width: 8),
                  Text('Subquery & CTEs', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'explain',
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined, size: 15, color: Colors.amberAccent),
                  SizedBox(width: 8),
                  Text('Explain Plan', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'api',
              child: Row(
                children: [
                  Icon(Icons.api, size: 15, color: Color(0xFF14B8A6)),
                  SizedBox(width: 8),
                  Text('Generate API', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'convert',
              child: Row(
                children: [
                  Icon(Icons.transform, size: 15, color: Colors.cyanAccent),
                  SizedBox(width: 8),
                  Text('Convert Code', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'save',
              child: Row(
                children: [
                  Icon(Icons.bookmark_add_outlined, size: 15),
                  SizedBox(width: 8),
                  Text('Save Query', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'saved_list',
              child: Row(
                children: [
                  const Icon(Icons.bookmarks_outlined, size: 15),
                  const SizedBox(width: 8),
                  Text('Saved Queries (${state.savedQueries.length})', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'suggest',
              child: Row(
                children: [
                  Icon(_isAutoSuggestEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined, size: 15, color: Colors.tealAccent),
                  const SizedBox(width: 8),
                  Text(_isAutoSuggestEnabled ? 'Auto-Helper: ON' : 'Auto-Helper: OFF', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.clear_all, size: 15, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Clear Editor', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopToolbar(
    BuildContext context,
    AppState state,
    ThemeData theme,
    List<String> detectedParams,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          TacticalPulseButton(
            onPressed: _runQuery,
            icon: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
            label: 'Run Query',
            shortcutLabel: 'Ctrl+Enter',
            isExecuting: state.isExecutingQuery,
          ),
          const SizedBox(width: 8),

          // Format SQL Button
          OutlinedButton.icon(
            onPressed: _formatSql,
            icon: const Icon(Icons.format_align_left_outlined, size: 15),
            label: const Text('Format SQL', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
          const SizedBox(width: 8),

          // Consolidated Tools & Actions BottomSheet Button
          ElevatedButton.icon(
            onPressed: () => _openToolsBottomSheet(context, state),
            icon: const Icon(Icons.auto_awesome_mosaic_outlined, size: 15, color: Color(0xFF14B8A6)),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Tools & Utilities', style: TextStyle(fontSize: 12)),
                if (state.savedQueries.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${state.savedQueries.length}',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF14B8A6)),
                    ),
                  ),
                ],
                const SizedBox(width: 3),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
            style: ElevatedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
          const SizedBox(width: 16),

          // Detected Query Parameters Indicator
          if (detectedParams.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.pinkAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.data_object, size: 12, color: Colors.pinkAccent),
                  const SizedBox(width: 4),
                  Text(
                    'Params: ${detectedParams.join(', ')}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.pinkAccent),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
          ],

          // Safe Mode Toggle
          Row(
            children: [
              Icon(
                state.safeMode ? Icons.shield : Icons.warning_amber,
                size: 16,
                color: state.safeMode ? Colors.green : Colors.amber.shade800,
              ),
              const SizedBox(width: 6),
              Text(
                'Enforce Safe Mode (AST)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: state.safeMode ? Colors.green.shade800 : Colors.amber.shade900,
                ),
              ),
              const SizedBox(width: 8),
              CyberSwitch(
                value: state.safeMode,
                onChanged: (val) => state.toggleSafeMode(val),
                activeColor: const Color(0xFF10B981),
                activeThumbIcon: const Icon(Icons.shield, size: 10, color: Colors.white),
                inactiveThumbIcon: Icon(Icons.shield_outlined, size: 10, color: Colors.amber.shade900),
                tooltip: state.safeMode ? 'Safe Mode Guardrail Active' : 'Safe Mode Disabled (RAW)',
                semanticLabel: 'Safe Mode Switch',
              ),
            ],
          ),

          const SizedBox(width: 16),

          // Limit Selector
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: state.activeLimit,
                isDense: true,
                icon: const Icon(Icons.arrow_drop_down, size: 16),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: const [
                  DropdownMenuItem(value: 25, child: Text('Limit: 25')),
                  DropdownMenuItem(value: 50, child: Text('Limit: 50')),
                  DropdownMenuItem(value: 100, child: Text('Limit: 100')),
                  DropdownMenuItem(value: 250, child: Text('Limit: 250')),
                  DropdownMenuItem(value: 500, child: Text('Limit: 500')),
                  DropdownMenuItem(value: 1000, child: Text('Limit: 1000')),
                  DropdownMenuItem(value: null, child: Text('No Limit')),
                ],
                onChanged: (val) => state.setActiveLimit(val),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openToolsBottomSheet(BuildContext context, AppState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Cyber Drag Handle
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.dividerColor.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // BottomSheet Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF14B8A6).withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.auto_awesome_mosaic_outlined, color: Color(0xFF14B8A6), size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'SQL Tools & Utilities',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // Tools List
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _buildBottomSheetTile(
                        ctx,
                        icon: Icons.hub_outlined,
                        iconColor: Colors.purpleAccent,
                        title: 'Subquery & CTEs',
                        subtitle: 'Templates for CTEs, EXISTS, correlated subqueries, and window functions',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _openSubquerySnippets();
                        },
                      ),
                      _buildBottomSheetTile(
                        ctx,
                        icon: Icons.api,
                        iconColor: const Color(0xFF14B8A6),
                        title: 'Generate Backend API',
                        subtitle: 'Scaffold FastAPI, Express, or Go code directly from this query',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          showApiGeneratorModal(context, query: _queryCtrl.text);
                        },
                      ),
                      _buildBottomSheetTile(
                        ctx,
                        icon: Icons.transform,
                        iconColor: Colors.cyanAccent,
                        title: 'Convert Function',
                        subtitle: 'Turn SQL into Python, JS/TS, or Dart repository method',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          showConvertCodeModal(context);
                        },
                      ),
                      _buildBottomSheetTile(
                        ctx,
                        icon: Icons.analytics_outlined,
                        iconColor: Colors.amberAccent,
                        title: 'Explain Plan',
                        subtitle: 'Analyze visual execution tree, cost estimates, and table scans',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          showExplainPlanModal(context, query: _queryCtrl.text);
                        },
                      ),
                      _buildBottomSheetTile(
                        ctx,
                        icon: Icons.bookmark_add_outlined,
                        iconColor: Colors.blueAccent,
                        title: 'Save Query',
                        subtitle: 'Bookmark current SQL query into your saved workspace catalog',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          showSaveQueryDialog(context);
                        },
                      ),
                      _buildBottomSheetTile(
                        ctx,
                        icon: Icons.bookmarks_outlined,
                        iconColor: Colors.lightBlueAccent,
                        title: 'Saved Queries (${state.savedQueries.length})',
                        subtitle: 'Browse, manage, and recall your saved queries catalog',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          showSavedQueriesModal(context);
                        },
                      ),
                      _buildBottomSheetTile(
                        ctx,
                        icon: Icons.history_toggle_off,
                        iconColor: Colors.orangeAccent,
                        title: 'Disaster Recovery Vault',
                        subtitle: 'Audit trail of recent mutations with one-click rollback/recovery',
                        onTap: () {
                          Navigator.of(ctx).pop();
                          showMutationHistoryModal(context);
                        },
                      ),
                      _buildBottomSheetTile(
                        ctx,
                        icon: _isAutoSuggestEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                        iconColor: _isAutoSuggestEnabled ? Colors.tealAccent : Colors.grey,
                        title: _isAutoSuggestEnabled ? 'Auto-Helper: ON' : 'Auto-Helper: OFF',
                        subtitle: 'Smart inline SQL suggestions, tables, columns, and keywords',
                        trailing: CyberSwitch(
                          value: _isAutoSuggestEnabled,
                          onChanged: (val) {
                            setState(() {
                              _isAutoSuggestEnabled = val;
                              if (!_isAutoSuggestEnabled) _hideAutocomplete();
                            });
                            Navigator.of(ctx).pop();
                          },
                          activeColor: const Color(0xFF14B8A6),
                          semanticLabel: 'Auto-Helper Switch',
                        ),
                        onTap: () {
                          setState(() {
                            _isAutoSuggestEnabled = !_isAutoSuggestEnabled;
                            if (!_isAutoSuggestEnabled) _hideAutocomplete();
                          });
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomSheetTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: iconColor),
      ),
      title: Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildResultsSection(BuildContext context, AppState state) {
    final res = state.lastQueryResult;

    if (state.isExecutingQuery) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 3),
            SizedBox(height: 12),
            Text('Executing query...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (res == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.terminal, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Run a query or preview a table from the schema explorer',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // If query was blocked by guardrail or errored
    if (res.hasError) {
      final isGuardrailBlock = res.error!.contains('GUARDRAIL BLOCKED') ||
          res.error!.contains('SECURITY GUARDRAIL REJECTION');

      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isGuardrailBlock ? const Color(0xFFFFF1F2) : Colors.red.shade50,
          border: Border.all(
            color: isGuardrailBlock ? const Color(0xFFF43F5E) : Colors.red.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isGuardrailBlock ? Icons.gpp_bad : Icons.error_outline,
                  color: isGuardrailBlock ? const Color(0xFFF43F5E) : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isGuardrailBlock ? 'Security Guardrail Blocked Execution' : 'Query Execution Error',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isGuardrailBlock ? const Color(0xFF9F1239) : Colors.red.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              res.error!,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isGuardrailBlock ? const Color(0xFF881337) : Colors.red.shade900,
              ),
            ),
          ],
        ),
      );
    }

    // Filter rows based on search term
    var rowsToDisplay = List<List<dynamic>>.from(res.rows);
    if (_tableFilter.trim().isNotEmpty) {
      final query = _tableFilter.trim().toLowerCase();
      rowsToDisplay = rowsToDisplay.where((row) {
        return row.any((cell) => cell != null && cell.toString().toLowerCase().contains(query));
      }).toList();
    }

    // Sort rows if sort column is selected
    if (_sortColumnIndex != null && _sortColumnIndex! < res.columns.length) {
      final colIdx = _sortColumnIndex!;
      rowsToDisplay.sort((a, b) {
        final dynamic aVal = colIdx < a.length ? a[colIdx] : null;
        final dynamic bVal = colIdx < b.length ? b[colIdx] : null;

        if (aVal == null && bVal == null) return 0;
        if (aVal == null) return _sortAscending ? -1 : 1;
        if (bVal == null) return _sortAscending ? 1 : -1;

        final aNum = num.tryParse(aVal.toString());
        final bNum = num.tryParse(bVal.toString());

        int cmp;
        if (aNum != null && bNum != null) {
          cmp = aNum.compareTo(bNum);
        } else {
          cmp = aVal.toString().compareTo(bVal.toString());
        }

        return _sortAscending ? cmp : -cmp;
      });
    }

    // Results Summary Bar & Stretched Data Table
    return Column(
      children: [
        // Summary Header Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (state.activePreviewTable != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.table_chart, size: 13, color: Color(0xFF14B8A6)),
                        const SizedBox(width: 4),
                        Text(
                          'Preview: ${state.activePreviewTable}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF14B8A6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                TelemetryMetricBadge(
                  label: 'ROWS',
                  value: '${res.rowCount}',
                  icon: Icons.data_array,
                ),
                const SizedBox(width: 8),
                TelemetryMetricBadge(
                  label: 'LATENCY',
                  value: '${res.executionTimeMs} ms',
                  icon: Icons.timer_outlined,
                  color: res.executionTimeMs < 50
                      ? const Color(0xFF10B981)
                      : (res.executionTimeMs < 200 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
                ),
                const SizedBox(width: 16),

                // In-Table Search / Filter Box
                SizedBox(
                  width: 200,
                  height: 32,
                  child: TextField(
                    controller: _tableFilterCtrl,
                    onChanged: (val) {
                      setState(() {
                        _tableFilter = val;
                      });
                    },
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      hintText: 'Filter results...',
                      hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, size: 14, color: Colors.grey),
                      suffixIcon: _tableFilter.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 12, color: Colors.grey),
                              onPressed: () {
                                _tableFilterCtrl.clear();
                                setState(() {
                                  _tableFilter = '';
                                });
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Option Detail Toggle (PK, FK, Data Types in Table Header)
                InkWell(
                  onTap: () => setState(() => _showOptionDetail = !_showOptionDetail),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: _showOptionDetail
                          ? const Color(0xFF14B8A6).withValues(alpha: 0.15)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _showOptionDetail
                            ? const Color(0xFF14B8A6)
                            : Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showOptionDetail ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 14,
                          color: _showOptionDetail ? const Color(0xFF14B8A6) : Colors.grey,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Option Detail',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _showOptionDetail ? FontWeight.bold : FontWeight.w500,
                            color: _showOptionDetail ? const Color(0xFF14B8A6) : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Bulk Selection Mode Toggle
                InkWell(
                  onTap: () {
                    setState(() {
                      _isSelectionMode = !_isSelectionMode;
                      if (!_isSelectionMode) {
                        state.clearRowSelection();
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: _isSelectionMode
                          ? const Color(0xFF14B8A6).withValues(alpha: 0.15)
                          : Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _isSelectionMode
                            ? const Color(0xFF14B8A6)
                            : Theme.of(context).dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isSelectionMode ? Icons.checklist : Icons.checklist_outlined,
                          size: 15,
                          color: _isSelectionMode ? const Color(0xFF14B8A6) : Colors.grey,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Bulk Select',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _isSelectionMode ? FontWeight.bold : FontWeight.w500,
                            color: _isSelectionMode ? const Color(0xFF14B8A6) : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Insert Row Action Button
                ElevatedButton.icon(
                  onPressed: () => _openInsertRowModal(context, state, res),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Insert Row', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14B8A6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    minimumSize: const Size(0, 32),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),

        // Virtualized Zero-Stutter Data Table
        Expanded(
          child: res.rows.isEmpty
              ? const Center(
                  child: Text(
                    'Query executed successfully. 0 rows returned.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              : rowsToDisplay.isEmpty
                  ? Center(
                      child: Text(
                        'No rows match filter "$_tableFilter"',
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    )
                  : VirtualizedDataTable(
                      columns: res.columns,
                      rows: rowsToDisplay,
                      sortColumnIndex: _sortColumnIndex,
                      sortAscending: _sortAscending,
                      isSafeMode: state.safeMode,
                      showColumnDetails: _showOptionDetail,
                      isSelectionMode: _isSelectionMode,
                      tableMetadata: _findTableMetadata(state, _inferTableName(state, res.columns) ?? '', res.columns),
                      allTables: state.tables,
                      onDuplicateRow: (rowIndex, rowValues) =>
                          _openDuplicateRowModal(context, state, res, rowIndex, rowValues),
                      onSort: (columnIndex, ascending) {
                        setState(() {
                          _sortColumnIndex = columnIndex;
                          _sortAscending = ascending;
                        });
                      },
                      onFilterByCellValue: (col, val) => state.filterByCellValue(col, val),
                      onInlineCellSave: (rowIndex, colName, oldValue, newValue) async {
                        final tbl = _inferTableName(state, res.columns);
                        if (tbl == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cannot identify target table for inline edit')),
                          );
                          return false;
                        }

                        final meta = _findTableMetadata(state, tbl, res.columns);

                        final rowValues = rowIndex < res.rows.length ? res.rows[rowIndex] : <dynamic>[];
                        final pkSet = <String>{};
                        if (meta != null) {
                          for (final col in meta.columns) {
                            if (col.isPrimaryKey) pkSet.add(col.name);
                          }
                        }
                        if (pkSet.isEmpty) {
                          for (final col in res.columns) {
                            if (col.toLowerCase() == 'id') {
                              pkSet.add(col);
                              break;
                            }
                          }
                        }

                        final Map<String, dynamic> pks = {};
                        if (pkSet.isNotEmpty) {
                          for (final pkCol in pkSet) {
                            final idx = res.columns.indexOf(pkCol);
                            if (idx != -1 && idx < rowValues.length) {
                              pks[pkCol] = rowValues[idx];
                            }
                          }
                        } else {
                          for (int i = 0; i < res.columns.length; i++) {
                            pks[res.columns[i]] = i < rowValues.length ? rowValues[i] : null;
                          }
                        }

                        // Safe Mode confirmation pre-check
                        if (state.safeMode) {
                          final confirmed = await showSafeModeConfirmDialog(
                            context: context,
                            operation: 'update',
                            tableName: tbl,
                            primaryKeys: pks,
                            changes: {
                              colName: {'old': oldValue, 'new': newValue},
                            },
                          );
                          if (confirmed != true) return false;
                        }

                        final ok = await state.updateTableRow(
                          tableName: tbl,
                          primaryKeys: pks,
                          updatedValues: {colName: newValue},
                        );

                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Saved: $colName = $newValue'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                              width: 280,
                            ),
                          );
                        }
                        return ok;
                      },
                      onEditRow: (rowIndex, rowValues) {
                        final tbl = _inferTableName(state, res.columns);
                        if (tbl == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cannot identify target table for this query')),
                          );
                          return;
                        }
                        final meta = _findTableMetadata(state, tbl, res.columns);
                        showRowEditModal(
                          context: context,
                          tableName: tbl,
                          columns: res.columns,
                          rowValues: rowValues,
                          tableMetadata: meta,
                          onSave: ({required primaryKeys, required updatedValues}) async {
                            if (state.safeMode) {
                              final changesMap = <String, dynamic>{};
                              for (final entry in updatedValues.entries) {
                                final colIdx = res.columns.indexOf(entry.key);
                                final oldVal = (colIdx != -1 && colIdx < rowValues.length) ? rowValues[colIdx] : null;
                                changesMap[entry.key] = {'old': oldVal, 'new': entry.value};
                              }
                              final confirmed = await showSafeModeConfirmDialog(
                                context: context,
                                operation: 'update',
                                tableName: tbl,
                                primaryKeys: primaryKeys,
                                changes: changesMap,
                              );
                              if (confirmed != true) return false;
                            }

                            final ok = await state.updateTableRow(
                              tableName: tbl,
                              primaryKeys: primaryKeys,
                              updatedValues: updatedValues,
                            );
                            if (ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Record updated successfully'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                  width: 280,
                                ),
                              );
                            }
                            return ok;
                          },
                        );
                      },
                      onDeleteRow: (rowIndex, rowValues) async {
                        final tbl = _inferTableName(state, res.columns);
                        if (tbl == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cannot identify target table for this query')),
                          );
                          return;
                        }
                        final meta = _findTableMetadata(state, tbl, res.columns);

                        // If Safe Mode is ON, prompt Safe Mode override confirmation first
                        if (state.safeMode) {
                          final pkSet = <String>{};
                          if (meta != null) {
                            for (final col in meta.columns) {
                              if (col.isPrimaryKey) pkSet.add(col.name);
                            }
                          }
                          if (pkSet.isEmpty) {
                            for (final col in res.columns) {
                              if (col.toLowerCase() == 'id') {
                                pkSet.add(col);
                                break;
                              }
                            }
                          }
                          final Map<String, dynamic> pks = {};
                          if (pkSet.isNotEmpty) {
                            for (final pkCol in pkSet) {
                              final idx = res.columns.indexOf(pkCol);
                              if (idx != -1 && idx < rowValues.length) {
                                pks[pkCol] = rowValues[idx];
                              }
                            }
                          } else {
                            for (int i = 0; i < res.columns.length; i++) {
                              pks[res.columns[i]] = i < rowValues.length ? rowValues[i] : null;
                            }
                          }

                          final confirmed = await showSafeModeConfirmDialog(
                            context: context,
                            operation: 'delete',
                            tableName: tbl,
                            primaryKeys: pks,
                          );
                          if (confirmed != true) return;
                        }

                        if (!context.mounted) return;
                        showRowDeleteModal(
                          context: context,
                          tableName: tbl,
                          columns: res.columns,
                          rowValues: rowValues,
                          tableMetadata: meta,
                          onDelete: ({required primaryKeys}) async {
                            final ok = await state.deleteTableRow(
                              tableName: tbl,
                              primaryKeys: primaryKeys,
                            );
                            if (ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Record deleted successfully'),
                                  duration: Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                  width: 280,
                                ),
                              );
                            }
                            return ok;
                          },
                        );
                      },
                      selectedRowIndices: state.selectedRowIndices,
                      onToggleRowSelection: (idx) => state.toggleRowSelection(idx),
                      onRangeSelectRow: (idx) => state.selectRowRange(idx),
                      onSelectAll: () => state.selectAllRows(rowsToDisplay.length),
                      onClearSelection: () => state.clearRowSelection(),
                      onBulkDelete: (indices) => _handleBulkDelete(context, state, res, indices),
                      onBulkExport: (indices) => _exportSelectedRows(res, indices),
                    ),
        ),

        // Pagination Bar
        if (state.activePreviewTable != null ||
            res.totalRows != null ||
            res.hasMore != null ||
            (res.page != null && res.page! > 1) ||
            (res.pageSize != null && res.rowCount > 0))
          _buildPaginationBar(context, state, res),
      ],
    );
  }

  Widget _buildPaginationBar(BuildContext context, AppState state, dynamic res) {
    final page = state.activePreviewTable != null ? state.previewPage : state.queryPage;
    final pageSize = state.activePreviewTable != null ? state.previewPageSize : state.queryPageSize;
    final totalRows = res.totalRows as int?;
    final rowCount = res.rowCount as int;

    final startRow = (page - 1) * pageSize + (rowCount > 0 ? 1 : 0);
    final endRow = (page - 1) * pageSize + rowCount;

    final int? totalPages = totalRows != null ? (totalRows / pageSize).ceil() : null;
    final bool canPrev = page > 1;
    final bool canNext = res.hasMore == true ||
        (totalPages != null ? page < totalPages : (res.hasMore == null && rowCount >= pageSize));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            totalRows != null
                ? 'Showing rows $startRow – $endRow of $totalRows (Page $page of ${totalPages ?? 1})'
                : 'Showing rows $startRow – $endRow (Page $page${res.hasMore == true ? ' • More available' : ''})',
            style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500),
          ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: canPrev ? () => state.goToPage(1) : null,
                icon: const Icon(Icons.first_page, size: 16),
                label: const Text('First', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                ),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: canPrev ? () => state.previousPage() : null,
                icon: const Icon(Icons.chevron_left, size: 16),
                label: const Text('Prev', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Page $page',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: canNext ? () => state.nextPage() : null,
                icon: const Icon(Icons.chevron_right, size: 16),
                label: const Text('Next', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleBulkDelete(
    BuildContext context,
    AppState state,
    QueryResult res,
    List<int> selectedIndices,
  ) async {
    final tbl = _inferTableName(state, res.columns);
    if (tbl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot identify target table for bulk delete')),
      );
      return;
    }

    final meta = _findTableMetadata(state, tbl, res.columns);
    final pkSet = <String>{};
    if (meta != null) {
      for (final col in meta.columns) {
        if (col.isPrimaryKey) pkSet.add(col.name);
      }
    }
    if (pkSet.isEmpty) {
      for (final col in res.columns) {
        if (col.toLowerCase() == 'id') {
          pkSet.add(col);
          break;
        }
      }
    }

    final List<Map<String, dynamic>> primaryKeysList = [];
    for (final rIdx in selectedIndices) {
      if (rIdx < res.rows.length) {
        final rowValues = res.rows[rIdx];
        final Map<String, dynamic> pks = {};
        if (pkSet.isNotEmpty) {
          for (final pkCol in pkSet) {
            final cIdx = res.columns.indexOf(pkCol);
            if (cIdx != -1 && cIdx < rowValues.length) {
              pks[pkCol] = rowValues[cIdx];
            }
          }
        } else {
          for (int i = 0; i < res.columns.length; i++) {
            pks[res.columns[i]] = i < rowValues.length ? rowValues[i] : null;
          }
        }
        primaryKeysList.add(pks);
      }
    }

    if (primaryKeysList.isEmpty) return;

    final confirmed = await showBulkDeleteModal(
      context: context,
      tableName: tbl,
      selectedCount: primaryKeysList.length,
      primaryKeysList: primaryKeysList,
      isSafeMode: state.safeMode,
      onConfirmDelete: () => state.bulkDeleteRows(
        tableName: tbl,
        primaryKeysList: primaryKeysList,
      ),
    );

    if (confirmed == true && context.mounted) {
      setState(() => _isSelectionMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bulk deleted ${primaryKeysList.length} rows successfully'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: 320,
        ),
      );
    }
  }

  void _exportSelectedRows(QueryResult res, List<int> selectedIndices) {
    final buffer = StringBuffer();
    buffer.writeln(res.columns.join(','));
    for (final idx in selectedIndices) {
      if (idx < res.rows.length) {
        final row = res.rows[idx];
        final line = row.map((v) {
          if (v == null) return '';
          final str = v.toString();
          if (str.contains(',') || str.contains('"') || str.contains('\n')) {
            return '"${str.replaceAll('"', '""')}"';
          }
          return str;
        }).join(',');
        buffer.writeln(line);
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${selectedIndices.length} rows as CSV to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 340,
      ),
    );
  }
}
