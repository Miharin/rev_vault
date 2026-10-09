import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/audit_event.dart';
import '../state/app_state.dart';

class McpMonitorView extends StatefulWidget {
  const McpMonitorView({super.key});

  @override
  State<McpMonitorView> createState() => _McpMonitorViewState();
}

class _McpMonitorViewState extends State<McpMonitorView> {
  String _filter = 'ALL'; // 'ALL', 'BLOCKED', 'ALLOWED'

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final filtered = state.auditEvents.where((e) {
      if (_filter == 'BLOCKED') return e.isBlocked;
      if (_filter == 'ALLOWED') return e.isAllowed;
      return true;
    }).toList();

    return Column(
      children: [
        // Top Toolbar & Stats
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Row(
            children: [
              const Icon(Icons.security, size: 20, color: Color(0xFF14B8A6)),
              const SizedBox(width: 8),
              const Text(
                'Antigravity MCP Live Audit Stream',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'ALL',
                    label: Text('All (${state.auditEvents.length})'),
                  ),
                  ButtonSegment(
                    value: 'ALLOWED',
                    label: Text(
                      'Safe (${state.auditEvents.where((e) => e.isAllowed).length})',
                    ),
                    icon: const Icon(Icons.check_circle, size: 14, color: Colors.green),
                  ),
                  ButtonSegment(
                    value: 'BLOCKED',
                    label: Text(
                      'Blocked (${state.auditEvents.where((e) => e.isBlocked).length})',
                    ),
                    icon: const Icon(Icons.block, size: 14, color: Color(0xFFF43F5E)),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (set) => setState(() => _filter = set.first),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Event Stream List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shield_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'No queries recorded yet from Antigravity MCP',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Incoming queries from Antigravity will stream here in real time.',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final event = filtered[index];
                    return _buildEventCard(context, event);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEventCard(BuildContext context, AuditEvent event) {
    Color cardBorder;
    Color badgeBg;
    Color badgeFg;
    IconData badgeIcon;

    if (event.isBlocked) {
      cardBorder = const Color(0xFFF43F5E);
      badgeBg = const Color(0xFFFFF1F2);
      badgeFg = const Color(0xFFE11D48);
      badgeIcon = Icons.gpp_bad;
    } else if (event.isAllowed) {
      cardBorder = const Color(0xFF10B981);
      badgeBg = const Color(0xFFECFDF5);
      badgeFg = const Color(0xFF047857);
      badgeIcon = Icons.check_circle;
    } else {
      cardBorder = Colors.orange;
      badgeBg = Colors.orange.shade50;
      badgeFg = Colors.orange.shade800;
      badgeIcon = Icons.warning;
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: cardBorder.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 14, color: badgeFg),
                    const SizedBox(width: 4),
                    Text(
                      event.status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeFg,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  event.source,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                event.timestamp,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          if (event.sql != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                event.sql!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (event.message != null) ...[
            const SizedBox(height: 8),
            Text(
              event.message!,
              style: TextStyle(
                fontSize: 11,
                color: event.isBlocked ? const Color(0xFFE11D48) : Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
