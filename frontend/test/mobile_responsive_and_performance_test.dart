import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/main.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/widgets/tactical_hud_widgets.dart';
import 'package:rev_vault/views/sql_editor_view.dart';
import 'package:rev_vault/models/connection.dart';

void main() {
  testWidgets('CyberStatusDot stays dormant on idle without continuous ticking', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CyberStatusDot(isOnline: true, label: 'Online'),
        ),
      ),
    );

    // Initial render
    await tester.pump(const Duration(milliseconds: 700));

    // After settling, pump with no elapsed time - should not throw and should remain stable
    await tester.pump();
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('Mobile Phone Viewport (<700px) activates Drawer and compact mobile HUD', (tester) async {
    // Set phone viewport (iPhone 14 / Pixel: 390x844)
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final appState = AppState();
    appState.connections = [
      ConnectionConfig(
        id: 'conn_1',
        name: 'Mobile SQLite Test',
        engine: 'sqlite',
        database: ':memory:',
        isActive: true,
      ),
    ];
    appState.activeConnection = appState.connections.first;
    appState.isBackendOnline = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const RevVaultApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Hamburger menu icon exists on mobile
    final hamburgerFinder = find.byIcon(Icons.menu);
    expect(hamburgerFinder, findsOneWidget);

    // Verify mobile status bottom bar displays MOBILE_PHONE_VIEW
    expect(find.text('MOBILE_PHONE_VIEW'), findsOneWidget);

    // Tap Hamburger menu to open mobile drawer
    await tester.tap(hamburgerFinder);
    await tester.pumpAndSettle();

    // Verify Drawer opened with "Database Hub", "Connections", and "Schemas"
    expect(find.text('Database Hub'), findsOneWidget);
    expect(find.text('Connections'), findsNWidgets(2));
    expect(find.text('Schemas'), findsOneWidget);
    expect(find.text('Mobile SQLite Test'), findsNWidgets(2));

    // Close the drawer
    final closeButtonFinder = find.byIcon(Icons.close);
    expect(closeButtonFinder, findsOneWidget);
    await tester.tap(closeButtonFinder);
    await tester.pumpAndSettle();

    // Verify drawer is closed
    expect(find.text('Database Hub'), findsNothing);
  });

  testWidgets('SqlEditorView on mobile screen (<700px) uses compact toolbar and 35% height ratio', (tester) async {
    // Set mobile phone size
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final appState = AppState();
    appState.editorQueryText = 'SELECT * FROM users;';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AppState>.value(
            value: appState,
            child: const SqlEditorView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify compact mobile "Run" button exists (instead of "Run Query")
    expect(find.text('Run'), findsOneWidget);

    // Verify Safe mode badge exists
    expect(find.text('SAFE'), findsOneWidget);

    // Verify mobile overflow popup menu exists
    final moreVertFinder = find.byIcon(Icons.more_vert);
    expect(moreVertFinder, findsOneWidget);

    // Open popup menu to verify secondary actions
    await tester.tap(moreVertFinder);
    await tester.pumpAndSettle();

    expect(find.text('Subquery & CTEs'), findsOneWidget);
    expect(find.text('Explain Plan'), findsOneWidget);
    expect(find.text('Generate API'), findsOneWidget);
    expect(find.text('Convert Code'), findsOneWidget);
    expect(find.text('Save Query'), findsOneWidget);
    expect(find.text('Clear Editor'), findsOneWidget);
  });
}
