import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/workspace_tab.dart';
import '../../state/app_state.dart';
import 'table_picker_modal.dart';

/// Low-latency, cyber-themed tab bar for the SQL Studio workspace.
/// Preserves tab ordering, highlights active tab, supports quick closing,
/// adding new query tabs, and jumping to schemas.
class WorkspaceTabBar extends StatelessWidget {
  const WorkspaceTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Scrollable Tab List
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.tabs.length,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final tab = state.tabs[index];
                final isActive = state.activeTabIndex == index;

                return _WorkspaceTabItem(
                  tab: tab,
                  index: index,
                  isActive: isActive,
                  accentColor: accent,
                  onTap: () => state.setActiveTab(index),
                  onClose: () => state.closeTab(index),
                );
              },
            ),
          ),

          // Action Buttons: + New Query Tab & Quick Schema Picker
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: 'New SQL Query Tab (Ctrl+T)',
                waitDuration: const Duration(milliseconds: 350),
                child: InkWell(
                  onTap: () => state.openQueryTab(),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 28,
                    width: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.add,
                      size: 17,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Schema & Table Picker (Ctrl+P / Ctrl+Shift+S)',
                waitDuration: const Duration(milliseconds: 350),
                child: InkWell(
                  onTap: () {
                    showTablePickerModal(
                      context: context,
                      title: 'Switch Schema / Table',
                      tables: state.tables,
                      currentTable: state.selectedTable,
                      onSelected: (table) {
                        state.selectTable(table);
                        state.openTableTab(table.name);
                      },
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    margin: const EdgeInsets.only(right: 6, left: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.hub_outlined, size: 13, color: accent),
                        const SizedBox(width: 4),
                        Text(
                          'SCHEMA',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTabItem extends StatefulWidget {
  final WorkspaceTab tab;
  final int index;
  final bool isActive;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _WorkspaceTabItem({
    required this.tab,
    required this.index,
    required this.isActive,
    required this.accentColor,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_WorkspaceTabItem> createState() => _WorkspaceTabItemState();
}

class _WorkspaceTabItemState extends State<_WorkspaceTabItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTable = widget.tab.isTablePreview;
    final isSchema = widget.tab.isSchemaOverview;

    final bg = widget.isActive
        ? theme.colorScheme.surface
        : (_isHovered
            ? theme.colorScheme.surface.withValues(alpha: 0.5)
            : Colors.transparent);

    final textColor = widget.isActive
        ? widget.accentColor
        : (_isHovered
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurface.withValues(alpha: 0.65));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 100, maxWidth: 190),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              right: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.2),
                width: 1,
              ),
              bottom: BorderSide(
                color: widget.isActive ? widget.accentColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSchema
                    ? Icons.folder_copy_outlined
                    : (isTable ? Icons.table_chart_outlined : Icons.terminal),
                size: 13,
                color: isSchema
                    ? (widget.isActive ? widget.accentColor : const Color(0xFFF59E0B))
                    : (widget.isActive ? widget.accentColor : Colors.grey),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  widget.tab.title,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    fontWeight: widget.isActive ? FontWeight.bold : FontWeight.w500,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 12,
                    color: (_isHovered || widget.isActive)
                        ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
