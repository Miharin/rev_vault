import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import 'cyber_switch.dart';

Future<void> showExplainPlanModal(BuildContext context, {required String query}) async {
  await showDialog(
    context: context,
    builder: (ctx) => ExplainPlanDialog(query: query),
  );
}

class ExplainPlanDialog extends StatefulWidget {
  final String query;

  const ExplainPlanDialog({super.key, required this.query});

  @override
  State<ExplainPlanDialog> createState() => _ExplainPlanDialogState();
}

class _ExplainPlanDialogState extends State<ExplainPlanDialog> {
  bool _analyze = false;
  bool _loading = false;
  Map<String, dynamic>? _result;
  String? _error;
  bool _showRawJson = false;

  @override
  void initState() {
    super.initState();
    _runExplain();
  }

  Future<void> _runExplain() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final state = context.read<AppState>();
      final res = await state.api.explainQuery(
        sql: widget.query,
        analyze: _analyze,
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _result = res;
          _error = res['error'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to explain query: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    final engine = _result?['engine']?.toString().toUpperCase() ?? 'DB';
    final totalCost = _result?['total_cost'];
    final planTime = _result?['planning_time_ms'];
    final execTime = _result?['execution_time_ms'];
    final warnings = (_result?['warnings'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final recommendations = (_result?['recommendations'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final planTree = _result?['plan_tree'] as Map<String, dynamic>?;

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.analytics_outlined, size: 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Query Execution Plan & Cost Inspector',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Engine: $engine • AST Verified Profile',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                  // Analyze toggle
                  Row(
                    children: [
                      const Text('Analyze (Run):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      CyberSwitch(
                        value: _analyze,
                        activeColor: accent,
                        onChanged: _loading ? null : (val) {
                          setState(() => _analyze = val);
                          _runExplain();
                        },
                        tooltip: 'Analyze (Run execution)',
                        semanticLabel: 'Analyze Toggle Switch',
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),

                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Re-run Explain',
                    onPressed: _loading ? null : _runExplain,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 20),

              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else ...[
                // Metric Chips Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildMetricCard(
                        context,
                        label: 'Total Cost',
                        value: totalCost != null ? '$totalCost' : 'N/A',
                        icon: Icons.speed,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 10),
                      _buildMetricCard(
                        context,
                        label: 'Planning Time',
                        value: planTime != null ? '${planTime}ms' : 'N/A',
                        icon: Icons.timer_outlined,
                        color: Colors.cyan,
                      ),
                      const SizedBox(width: 10),
                      _buildMetricCard(
                        context,
                        label: 'Execution Time',
                        value: execTime != null ? '${execTime}ms' : (_analyze ? '0ms' : 'Dry Run'),
                        icon: Icons.bolt,
                        color: const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 10),
                      _buildMetricCard(
                        context,
                        label: 'Warnings',
                        value: '${warnings.length}',
                        icon: Icons.warning_amber_rounded,
                        color: warnings.isNotEmpty ? Colors.orangeAccent : Colors.grey,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Heuristic Advice Box
                if (warnings.isNotEmpty || recommendations.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (warnings.isNotEmpty ? Colors.amber : accent).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (warnings.isNotEmpty ? Colors.amber : accent).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              warnings.isNotEmpty ? Icons.warning_amber : Icons.lightbulb_outline,
                              size: 15,
                              color: warnings.isNotEmpty ? Colors.amber : accent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              warnings.isNotEmpty ? 'Performance Advisory' : 'Optimization Recommendations',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: warnings.isNotEmpty ? Colors.amber : accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final w in warnings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2.0),
                            child: Text('• $w', style: const TextStyle(fontSize: 11)),
                          ),
                        for (final r in recommendations)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2.0),
                            child: Text('💡 Recommendation: $r',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF14B8A6), fontWeight: FontWeight.w500)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Action Bar for View Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _showRawJson ? 'Raw Execution Plan Data' : 'Visual Execution Tree',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() => _showRawJson = !_showRawJson),
                          icon: Icon(_showRawJson ? Icons.account_tree_outlined : Icons.code, size: 14),
                          label: Text(_showRawJson ? 'Show Tree' : 'Show Raw JSON', style: const TextStyle(fontSize: 11)),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 14),
                          tooltip: 'Copy Raw Plan',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: jsonEncode(_result?['raw_plan'] ?? {})));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Copied plan to clipboard'), duration: Duration(seconds: 1)),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Main Tree or Raw JSON Container
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
                    ),
                    child: _showRawJson
                        ? SingleChildScrollView(
                            child: SelectableText(
                              const JsonEncoder.withIndent('  ').convert(_result?['raw_plan'] ?? {}),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                            ),
                          )
                        : (planTree != null
                            ? SingleChildScrollView(
                                child: _buildTreeNode(context, planTree, depth: 0),
                              )
                            : const Center(child: Text('No plan tree available', style: TextStyle(fontSize: 12)))),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTreeNode(BuildContext context, Map<String, dynamic> node, {required int depth}) {
    final nodeType = node['node_type']?.toString() ?? 'Operation';
    final relation = node['relation_name']?.toString();
    final cost = node['total_cost'];
    final timeMs = node['actual_time_ms'];
    final rows = node['rows'];
    final filter = node['filter_expr']?.toString();
    final indexName = node['index_name']?.toString();
    final detail = node['detail']?.toString();
    final children = (node['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    Color badgeColor = Colors.grey;
    IconData nodeIcon = Icons.chevron_right;

    final nUpper = nodeType.toUpperCase();
    if (nUpper.contains('SEQ') || nUpper.contains('FULL TABLE SCAN')) {
      badgeColor = Colors.redAccent;
      nodeIcon = Icons.warning_amber_rounded;
    } else if (nUpper.contains('INDEX')) {
      badgeColor = const Color(0xFF10B981);
      nodeIcon = Icons.check_circle_outline;
    } else if (nUpper.contains('JOIN') || nUpper.contains('LOOP')) {
      badgeColor = Colors.cyan;
      nodeIcon = Icons.join_inner;
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * 18.0, top: 4.0, bottom: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(nodeIcon, size: 14, color: badgeColor),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.35), width: 0.5),
                ),
                child: Text(
                  nodeType,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor, fontFamily: 'monospace'),
                ),
              ),
              if (relation != null) ...[
                const SizedBox(width: 6),
                Text('on $relation', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ],
              if (indexName != null) ...[
                const SizedBox(width: 6),
                Text('using $indexName', style: const TextStyle(fontSize: 10, color: Color(0xFF10B981))),
              ],
              const Spacer(),
              if (rows != null)
                Text('Rows: $rows  ', style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace')),
              if (cost != null)
                Text('Cost: $cost  ', style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace')),
              if (timeMs != null)
                Text('${timeMs}ms', style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontFamily: 'monospace')),
            ],
          ),
          if (detail != null && detail.isNotEmpty && detail != nodeType)
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 2.0),
              child: Text(detail, style: const TextStyle(fontSize: 10, color: Colors.grey, fontFamily: 'monospace')),
            ),
          if (filter != null && filter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 2.0),
              child: Text('Filter: $filter', style: const TextStyle(fontSize: 10, color: Colors.amber, fontFamily: 'monospace')),
            ),
          for (final child in children)
            _buildTreeNode(context, child, depth: depth + 1),
        ],
      ),
    );
  }
}
