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
}
