import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'theme/cyber_theme.dart';
import 'views/sidebar_connections.dart';
import 'views/schema_tree_view.dart';
import 'views/sql_editor_view.dart';
import 'views/mcp_monitor_view.dart';
import 'views/widgets/tactical_hud_widgets.dart';
import 'views/widgets/mobile_connect_modal.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const RevVaultApp(),
    ),
  );
}

class RevVaultApp extends StatelessWidget {
  const RevVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isDark = state.isEffectiveDarkMode;
    final accent = state.accentColor;

    return MaterialApp(
      title: 'RevVault — Relva Database Companion',
      debugShowCheckedModeBanner: false,
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      theme: CyberTheme.buildTheme(isDark: false, accent: accent),
      darkTheme: CyberTheme.buildTheme(isDark: true, accent: accent),
      home: const RevVaultHomeScreen(),
    );
  }
}

class RevVaultHomeScreen extends StatefulWidget {
  const RevVaultHomeScreen({super.key});

  @override
  State<RevVaultHomeScreen> createState() => _RevVaultHomeScreenState();
}

class _RevVaultHomeScreenState extends State<RevVaultHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _cycleThemePreference(AppState state) {
    switch (state.themePreference) {
      case ThemePreference.circadian:
        state.setThemePreference(ThemePreference.dark);
        break;
      case ThemePreference.dark:
        state.setThemePreference(ThemePreference.light);
        break;
      case ThemePreference.light:
        state.setThemePreference(ThemePreference.circadian);
        break;
    }
  }

  double _getEffectiveTopInset(BuildContext context) {
    final systemTop = MediaQuery.paddingOf(context).top;
    if (systemTop > 0) return systemTop;
    final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return isMobilePlatform ? 38.0 : 0.0;
  }

  double _getEffectiveBottomInset(BuildContext context) {
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    if (systemBottom > 0) return systemBottom;
    final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return isMobilePlatform ? 16.0 : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          if (state.isSchemaExplorerHidden) {
            state.toggleSchemaExplorerHidden(false);
          } else {
            state.toggleRailCollapse();
            state.toggleSchemaRailCollapse();
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyE, control: true, shift: true): () {
          state.toggleSchemaExplorerHidden();
        },
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 700;
          final isConstrained = constraints.maxWidth < 920;
          final isBothRailsCollapsed = state.isRailCollapsed && state.isSchemaRailCollapsed;

          return Scaffold(
            drawer: isMobile ? _buildMobileDrawer(context, state, theme, accent) : null,
            body: Column(
              children: [
                // Top Tactical HUD Header Bar
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(top: _getEffectiveTopInset(context)),
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: SizedBox(
                        height: 48,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: isMobile
                              ? _buildMobileHeader(context, state, theme, accent)
                              : _buildDesktopHeader(context, state, theme, accent, isBothRailsCollapsed),
                        ),
                      ),
                    ),
                  ),
                ),

                // Mobile Navigation Sub-Bar (Explorer vs MCP Audit Tabs)
                if (isMobile)
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                      border: Border(
                        bottom: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: accent,
                      labelColor: accent,
                      unselectedLabelColor: Colors.grey,
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      unselectedLabelStyle: const TextStyle(fontSize: 12),
                      tabs: [
                        const Tab(
                          icon: Icon(Icons.terminal, size: 14),
                          text: 'SQL Studio',
                        ),
                        Tab(
                          icon: const Icon(Icons.security, size: 14),
                          text: 'Audit (${state.auditEvents.length})',
                        ),
                      ],
                    ),
                  ),

                // Main Workspace Layout
                Expanded(
                  child: isMobile
                      ? TabBarView(
                          controller: _tabController,
                          children: const [
                            SqlEditorView(),
                            McpMonitorView(),
                          ],
                        )
                      : Row(
                          children: [
                            // Leftmost: Saved Connections Sidebar
                            const SidebarConnections(),

                            // Center & Right: Tab Views
                            Expanded(
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  // Tab 1: Database Schema Tree + SQL Editor & Virtual Grid
                                  Row(
                                    children: const [
                                      SchemaTreeView(),
                                      Expanded(child: SqlEditorView()),
                                    ],
                                  ),

                                  // Tab 2: Dedicated Antigravity MCP Live Audit Monitor
                                  const McpMonitorView(),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),

                // Bottom Status & Telemetry Bar
                Container(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: _getEffectiveBottomInset(context)),
                    child: SafeArea(
                      top: false,
                      bottom: false,
                      child: SizedBox(
                        height: 24,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                Icon(Icons.bolt, size: 12, color: accent),
                                const SizedBox(width: 5),
                                const Text(
                                  'ANTIGRAVITY MCP: ACTIVE',
                                  style: TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.grey),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  'AST SAFE_MODE: ${state.safeMode ? "ARMED" : "BYPASSED"}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: state.safeMode ? const Color(0xFF10B981) : Colors.amber,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  'QUERIES: ${state.auditEvents.length} | BLOCKED: ${state.auditEvents.where((e) => e.isBlocked).length}',
                                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  isMobile ? 'MOBILE_PHONE_VIEW' : (isConstrained ? 'COMPACT_VIEW' : 'STUDIO_VIEW'),
                                  style: TextStyle(fontSize: 9.5, fontFamily: 'monospace', color: accent),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileDrawer(BuildContext context, AppState state, ThemeData theme, Color accent) {
    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      width: 310,
      child: SafeArea(
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: accent.withValues(alpha: 0.35)),
                      ),
                      child: Icon(Icons.shield, color: accent, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Database Hub',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: theme.colorScheme.onSurface),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              TabBar(
                indicatorColor: accent,
                labelColor: accent,
                unselectedLabelColor: Colors.grey,
                tabs: const [
                  Tab(icon: Icon(Icons.dns, size: 14), text: 'Connections'),
                  Tab(icon: Icon(Icons.account_tree, size: 14), text: 'Schemas'),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    SidebarConnections(forceExpanded: true),
                    SchemaTreeView(forceExpanded: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileHeader(BuildContext context, AppState state, ThemeData theme, Color accent) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
      children: [
        // Drawer toggle button (Hamburger)
        Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, size: 20),
            tooltip: 'Open Connections & Schemas',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        const SizedBox(width: 4),

        // Brand Logo & Title
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Icon(Icons.shield, color: accent, size: 14),
        ),
        const SizedBox(width: 6),
        Text(
          'RevVault',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            letterSpacing: 0.6,
            color: theme.colorScheme.onSurface,
          ),
        ),

        const SizedBox(width: 8),

        // Active Connection Chip (compact)
        if (state.activeConnection != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  state.activeConnection!.engine == 'sqlite' ? Icons.description : Icons.cloud,
                  size: 11,
                  color: accent,
                ),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Text(
                    state.activeConnection!.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],

        // Online Dot
        CyberStatusDot(
          isOnline: state.isBackendOnline,
          label: state.isBackendOnline ? 'ON' : 'OFF',
        ),

        const SizedBox(width: 4),

        // QR Mobile Connect
        IconButton(
          icon: Icon(Icons.qr_code_2, size: 16, color: accent),
          tooltip: 'Share LAN / Mobile QR',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () => showMobileConnectModal(context),
        ),

        const SizedBox(width: 4),

        // Theme Toggle
        IconButton(
          icon: Icon(state.themePreference.icon, size: 16, color: accent),
          tooltip: 'Cycle Theme Mode',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () => _cycleThemePreference(state),
        ),

        // Accent Preset
        PopupMenuButton<AccentColorPreset>(
          tooltip: 'Cyber Accent Preset',
          icon: Icon(state.accentColor.icon, size: 16, color: accent),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onSelected: (selected) => state.setAccentColor(selected),
          itemBuilder: (context) {
            return AccentColorPreset.values.map((preset) {
              return PopupMenuItem(
                value: preset,
                child: Row(
                  children: [
                    CircleAvatar(radius: 6, backgroundColor: preset.color),
                    const SizedBox(width: 10),
                    Text(preset.label, style: const TextStyle(fontSize: 12)),
                    if (preset == state.accentColor) ...[
                      const Spacer(),
                      Icon(Icons.check, size: 14, color: preset.color),
                    ],
                  ],
                ),
              );
            }).toList();
          },
        ),
      ],
    ),
  );
}

Widget _buildDesktopHeader(
    BuildContext context,
    AppState state,
    ThemeData theme,
    Color accent,
    bool isBothRailsCollapsed,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Brand Logo & Sci-Fi Badge
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Icon(Icons.shield, color: accent, size: 16),
          ),
          const SizedBox(width: 8),
          Text(
            'RevVault',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Text(
              'RELVA_v3.2',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: accent,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Toggle Rail Button (Free up window space)
          Tooltip(
            message: 'Toggle Compact Rails (Ctrl+B)',
            child: TextButton.icon(
              onPressed: () {
                final target = !isBothRailsCollapsed;
                state.toggleRailCollapse(target);
                state.toggleSchemaRailCollapse(target);
              },
              icon: Icon(
                isBothRailsCollapsed ? Icons.view_sidebar_outlined : Icons.menu_open,
                size: 16,
                color: isBothRailsCollapsed ? accent : Colors.grey,
              ),
              label: Text(
                isBothRailsCollapsed ? 'Expand Rails' : 'Compact Rails',
                style: TextStyle(
                  fontSize: 11,
                  color: isBothRailsCollapsed ? accent : Colors.grey.shade400,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Toggle Schema Explorer Minimize
          Tooltip(
            message: 'Toggle Schema Explorer Minimize (Ctrl+Shift+E)',
            child: TextButton.icon(
              onPressed: () {
                state.toggleSchemaExplorerHidden();
              },
              icon: Icon(
                state.isSchemaExplorerHidden ? Icons.view_sidebar_outlined : Icons.view_sidebar,
                size: 16,
                color: state.isSchemaExplorerHidden ? Colors.grey : accent,
              ),
              label: Text(
                state.isSchemaExplorerHidden ? 'Show Schemas' : 'Hide Schemas',
                style: TextStyle(
                  fontSize: 11,
                  color: state.isSchemaExplorerHidden ? Colors.grey.shade400 : accent,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Navigation Tabs (Explorer vs Audit)
          SizedBox(
            width: 380,
            child: TabBar(
              controller: _tabController,
              indicatorColor: accent,
              labelColor: accent,
              unselectedLabelColor: Colors.grey,
              dividerColor: Colors.transparent,
              tabs: [
                const Tab(
                  icon: Icon(Icons.terminal, size: 15),
                  text: 'Explorer & SQL',
                ),
                Tab(
                  icon: const Icon(Icons.security, size: 15),
                  text: 'MCP Audit (${state.auditEvents.length})',
                ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Active Database Connection Chip
          if (state.activeConnection != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    state.activeConnection!.engine == 'sqlite' ? Icons.description : Icons.cloud,
                    size: 13,
                    color: accent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    state.activeConnection!.name,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],

          // Backend Status Dot
          CyberStatusDot(
            isOnline: state.isBackendOnline,
            label: state.isBackendOnline ? 'Online' : 'Offline',
          ),

          const SizedBox(width: 10),

          // Connect Mobile Button
          Tooltip(
            message: 'Connect Android Phone (Scan QR)',
            child: InkWell(
              onTap: () => showMobileConnectModal(context),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.qr_code_2, size: 14, color: accent),
                    const SizedBox(width: 5),
                    Text(
                      'Mobile QR',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Accent Colorway Picker
          PopupMenuButton<AccentColorPreset>(
            tooltip: 'Cyber Accent Preset',
            icon: Icon(state.accentColor.icon, size: 16, color: accent),
            onSelected: (selected) => state.setAccentColor(selected),
            itemBuilder: (context) {
              return AccentColorPreset.values.map((preset) {
                return PopupMenuItem(
                  value: preset,
                  child: Row(
                    children: [
                      CircleAvatar(radius: 6, backgroundColor: preset.color),
                      const SizedBox(width: 10),
                      Text(preset.label, style: const TextStyle(fontSize: 12)),
                      if (preset == state.accentColor) ...[
                        const Spacer(),
                        Icon(Icons.check, size: 14, color: preset.color),
                      ],
                    ],
                  ),
                );
              }).toList();
            },
          ),

          // Circadian Theme Mode Button
          Tooltip(
            message: 'Theme: ${state.themePreference.label} (Click to switch)',
            child: InkWell(
              onTap: () => _cycleThemePreference(state),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(state.themePreference.icon, size: 14, color: accent),
                    const SizedBox(width: 5),
                    Text(
                      state.themePreference == ThemePreference.circadian
                          ? 'Circadian'
                          : (state.themePreference == ThemePreference.dark ? 'Dark' : 'Light'),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
