import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/connection.dart';
import '../state/app_state.dart';
import 'widgets/tactical_hud_widgets.dart';

class SidebarConnections extends StatelessWidget {
  final bool forceExpanded;
  const SidebarConnections({super.key, this.forceExpanded = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isRail = forceExpanded ? false : state.isRailCollapsed;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      width: forceExpanded ? null : (isRail ? 56 : 260),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: isRail ? _buildRailView(context, state, primary) : _buildExpandedView(context, state, primary),
    );
  }

  Widget _buildRailView(BuildContext context, AppState state, Color primary) {
    return Column(
      children: [
        const SizedBox(height: 8),
        // Toggle expand button
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          tooltip: 'Expand Connections (Ctrl+B)',
          onPressed: () => state.toggleRailCollapse(false),
        ),
        const Divider(height: 12),
        // Add connection button
        IconButton(
          icon: Icon(Icons.add_circle_outline, size: 20, color: primary),
          tooltip: 'Add Connection',
          onPressed: () => _showAddConnectionDialog(context),
        ),
        const SizedBox(height: 8),
        // Connection icons
        Expanded(
          child: ListView.builder(
            itemCount: state.connections.length,
            itemBuilder: (context, index) {
              final conn = state.connections[index];
              final isActive = state.activeConnection?.id == conn.id;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 7),
                child: TacticalRailItem(
                  icon: conn.engine == 'sqlite' ? Icons.description_outlined : Icons.cloud_outlined,
                  label: '${conn.name} (${conn.engine})',
                  isSelected: isActive,
                  onTap: () => state.setActiveConnection(conn),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedView(BuildContext context, AppState state, Color primary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Row(
            children: [
              Icon(Icons.storage, size: 17, color: primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Connections',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Add Connection',
                onPressed: () => _showAddConnectionDialog(context),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.chevron_left, size: 20),
                tooltip: 'Collapse to Rail',
                onPressed: () => state.toggleRailCollapse(true),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Connection List
        Expanded(
          child: state.connections.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.link_off, size: 36, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        const Text(
                          'No databases connected',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: () => _showAddConnectionDialog(context),
                          icon: const Icon(Icons.add, size: 15),
                          label: const Text('Add DB', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  itemCount: state.connections.length,
                  itemBuilder: (context, index) {
                    final conn = state.connections[index];
                    final isActive = state.activeConnection?.id == conn.id;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => state.setActiveConnection(conn),
                          onLongPress: () => _confirmDelete(context, conn),
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? primary.withValues(alpha: 0.12)
                                  : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isActive
                                    ? primary.withValues(alpha: 0.6)
                                    : Theme.of(context).dividerColor.withValues(alpha: 0.2),
                                width: isActive ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: conn.engine == 'sqlite'
                                      ? Colors.amber.shade700.withValues(alpha: 0.2)
                                      : Colors.blue.shade700.withValues(alpha: 0.2),
                                  child: Icon(
                                    conn.engine == 'sqlite' ? Icons.description : Icons.cloud,
                                    size: 14,
                                    color: conn.engine == 'sqlite'
                                        ? Colors.amber.shade800
                                        : Colors.blue.shade700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        conn.name,
                                        style: TextStyle(
                                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                                          fontSize: 12.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        conn.engine == 'sqlite'
                                            ? (conn.filepath ?? '')
                                            : '${conn.username ?? "user"}@${conn.host ?? "localhost"}:${conn.port}',
                                        style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (isActive)
                                  Icon(Icons.check_circle, size: 15, color: primary),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, ConnectionConfig conn) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Connection'),
        content: Text('Are you sure you want to remove "${conn.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AppState>().deleteConnection(conn.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddConnectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const AddConnectionDialog(),
    );
  }
}

class AddConnectionDialog extends StatefulWidget {
  const AddConnectionDialog({super.key});

  @override
  State<AddConnectionDialog> createState() => _AddConnectionDialogState();
}

class _AddConnectionDialogState extends State<AddConnectionDialog> {
  String engine = 'sqlite';
  final nameCtrl = TextEditingController(text: 'My Database');
  final pathCtrl = TextEditingController(text: '/tmp/test.db');
  final hostCtrl = TextEditingController(text: 'localhost');
  final portCtrl = TextEditingController(text: '5432');
  final dbCtrl = TextEditingController(text: 'postgres');
  final userCtrl = TextEditingController(text: 'postgres');
  final passCtrl = TextEditingController();

  bool isTesting = false;
  String? testFeedback;
  bool? testSuccess;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Database Connection'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'sqlite',
                    label: Text('SQLite (Local File)'),
                    icon: Icon(Icons.description, size: 16),
                  ),
                  ButtonSegment(
                    value: 'postgres',
                    label: Text('PostgreSQL'),
                    icon: Icon(Icons.cloud, size: 16),
                  ),
                ],
                selected: {engine},
                onSelectionChanged: (set) {
                  setState(() {
                    engine = set.first;
                    testFeedback = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Connection Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              if (engine == 'sqlite') ...[
                TextField(
                  controller: pathCtrl,
                  decoration: const InputDecoration(
                    labelText: 'SQLite Database File Path',
                    hintText: '/home/user/data/mydb.sqlite',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: hostCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Host',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: portCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dbCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Database Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: userCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: passCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (testFeedback != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (testSuccess ?? false)
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        (testSuccess ?? false) ? Icons.check_circle : Icons.error,
                        size: 16,
                        color: (testSuccess ?? false) ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          testFeedback!,
                          style: TextStyle(
                            fontSize: 12,
                            color: (testSuccess ?? false) ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isTesting ? null : _testConnection,
          child: isTesting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Test Connection'),
        ),
        FilledButton(
          onPressed: _saveConnection,
          child: const Text('Save & Connect'),
        ),
      ],
    );
  }

  ConnectionConfig _buildConfig() {
    final id = 'conn_${DateTime.now().millisecondsSinceEpoch}';
    return ConnectionConfig(
      id: id,
      name: nameCtrl.text.trim(),
      engine: engine,
      filepath: engine == 'sqlite' ? pathCtrl.text.trim() : null,
      host: engine == 'postgres' ? hostCtrl.text.trim() : null,
      port: int.tryParse(portCtrl.text.trim()) ?? 5432,
      database: engine == 'postgres' ? dbCtrl.text.trim() : null,
      username: engine == 'postgres' ? userCtrl.text.trim() : null,
      password: engine == 'postgres' ? passCtrl.text : null,
      isActive: true,
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      isTesting = true;
      testFeedback = null;
    });

    final cfg = _buildConfig();
    final res = await context.read<AppState>().api.testConnection(cfg);

    setState(() {
      isTesting = false;
      testSuccess = res['success'] as bool? ?? false;
      testFeedback = res['message'] as String? ?? 'No response';
    });
  }

  Future<void> _saveConnection() async {
    final cfg = _buildConfig();
    final ok = await context.read<AppState>().saveConnection(cfg);
    if (ok && mounted) {
      context.read<AppState>().setActiveConnection(cfg);
      Navigator.pop(context);
    }
  }
}
