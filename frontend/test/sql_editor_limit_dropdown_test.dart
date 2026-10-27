import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/services/api_service.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/sql_editor_view.dart';

void main() {
  group('SQL Editor Limit Dropdown Invariant Tests', () {
    testWidgets('DropdownButton renders stably when queryPageSize is updated from custom SQL LIMIT', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = AppState(api: ApiService(baseUrl: 'http://localhost:8000'));
      
      // Initial state has activeLimit = 100
      expect(state.activeLimit, equals(100));

      // Simulate a query updating queryPageSize to a non-standard limit (e.g. 10)
      state.queryPageSize = 10;

      // activeLimit must NOT be corrupted to 10
      expect(state.activeLimit, equals(100));

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(
              body: SqlEditorView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // DropdownButton must be rendered without assertion errors
      expect(find.byType(DropdownButton<int?>), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DropdownButton handles explicit non-standard activeLimit without assertion failure', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = AppState(api: ApiService(baseUrl: 'http://localhost:8000'));
      
      // Force activeLimit to a custom non-standard number (e.g. 10)
      state.activeLimit = 10;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(
              body: SqlEditorView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that the custom item is seamlessly recognized and rendered
      expect(find.byType(DropdownButton<int?>), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('Limit: 10 (Custom)'), findsOneWidget);
    });

    testWidgets('DropdownButton handles null activeLimit (No Limit) cleanly', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = AppState(api: ApiService(baseUrl: 'http://localhost:8000'));
      state.setActiveLimit(null);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(
              body: SqlEditorView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<int?>), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('No Limit'), findsOneWidget);
    });
  });
}
