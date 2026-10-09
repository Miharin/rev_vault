import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/main.dart';
import 'package:rev_vault/state/app_state.dart';

void main() {
  testWidgets('RevVault smoke test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const RevVaultApp(),
      ),
    );
    expect(find.text('RevVault'), findsOneWidget);
    expect(find.text('Explorer & SQL'), findsOneWidget);
    expect(find.textContaining('MCP Audit'), findsOneWidget);
    expect(find.text('UI Studio'), findsNothing);
  });

  testWidgets('RevVault header and telemetry bar span full viewport width without horizontal gaps', (WidgetTester tester) async {
    const double testWidth = 1024.0;
    tester.view.physicalSize = const Size(testWidth, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const RevVaultApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify telemetry bar spans full viewport width
    final telemetryTextFinder = find.text('ANTIGRAVITY MCP: ACTIVE');
    expect(telemetryTextFinder, findsOneWidget);

    final bottomContainerFinder = find.ancestor(
      of: telemetryTextFinder,
      matching: find.byType(Container),
    );
    expect(bottomContainerFinder, findsWidgets);
    final bottomBarSize = tester.getSize(bottomContainerFinder.last);
    expect(bottomBarSize.width, equals(testWidth));

    // Verify header bar spans full viewport width
    final brandTextFinder = find.text('RevVault');
    final headerContainerFinder = find.ancestor(
      of: brandTextFinder,
      matching: find.byType(Container),
    );
    final headerBarSize = tester.getSize(headerContainerFinder.last);
    expect(headerBarSize.width, equals(testWidth));
  });
}
