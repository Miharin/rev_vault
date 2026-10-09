import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/models/saved_query.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/widgets/cyber_dropdown_bottom_sheet.dart';
import 'package:rev_vault/views/widgets/saved_queries_modal.dart';

void main() {
  group('SavedQuery Model & AppState Tests', () {
    test('SavedQuery json serialization roundtrip', () {
      final query = SavedQuery(
        id: 'q123',
        title: 'High Value Orders',
        description: 'Orders with total > 500',
        sql: 'SELECT * FROM orders WHERE total > 500;',
        builderMode: 'rawSql',
        createdAt: '2026-10-01T12:00:00Z',
      );

      final json = query.toJson();
      expect(json['id'], equals('q123'));
      expect(json['title'], equals('High Value Orders'));
      expect(json['sql'], equals('SELECT * FROM orders WHERE total > 500;'));

      final parsed = SavedQuery.fromJson(json);
      expect(parsed.id, equals(query.id));
      expect(parsed.title, equals(query.title));
      expect(parsed.sql, equals(query.sql));
      expect(parsed.builderMode, equals('rawSql'));
    });

    test('AppState saves, loads, and deletes queries', () async {
      final state = AppState();
      state.editorQueryText = 'SELECT * FROM users LIMIT 10;';

      // Save query
      final savedSuccess = await state.saveCurrentQuery('Default Users', description: 'Test query');
      expect(savedSuccess, isTrue);
      expect(state.savedQueries.length, equals(1));
      expect(state.savedQueries.first.title, equals('Default Users'));

      // Load query into editor
      final newQuery = SavedQuery(
        id: 'q2',
        title: 'Active Accounts',
        sql: 'SELECT * FROM accounts WHERE status = "active";',
        builderMode: 'rawSql',
      );
      state.loadSavedQuery(newQuery);
      expect(state.editorQueryText, equals('SELECT * FROM accounts WHERE status = "active";'));

      // Test formatEditorSql
      state.editorQueryText = 'select id, name from users where id > 10;';
      state.formatEditorSql();
      expect(state.editorQueryText, contains('SELECT'));
      expect(state.editorQueryText, contains('FROM'));
      expect(state.editorQueryText, contains('WHERE'));

      // Delete saved query
      await state.deleteSavedQuery(state.savedQueries.first.id);
      expect(state.savedQueries.isEmpty, isTrue);
    });
  });

  group('CyberDropdownBottomSheet Widget Tests', () {
    testWidgets('Renders items and returns selected item on tap', (WidgetTester tester) async {
      String? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedResult = await showCyberDropdownBottomSheet<String>(
                    context: context,
                    title: 'Test Picker',
                    items: const [
                      CyberDropdownItem(value: 'opt1', label: 'Option 1', subtitle: 'First'),
                      CyberDropdownItem(value: 'opt2', label: 'Option 2', subtitle: 'Second'),
                    ],
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      expect(find.text('Test Picker'), findsOneWidget);
      expect(find.text('Option 1'), findsOneWidget);
      expect(find.text('Option 2'), findsOneWidget);

      await tester.tap(find.text('Option 2'));
      await tester.pumpAndSettle();

      expect(selectedResult, equals('opt2'));
    });
  });

  group('SavedQueriesModal Widget Tests', () {
    testWidgets('Renders saved queries and loads selected query', (WidgetTester tester) async {
      final appState = AppState();
      await appState.saveCurrentQuery('Test Saved Preset', description: 'Preset notes');

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSavedQueriesModal(context),
                  child: const Text('Open Saved Queries'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Saved Queries'));
      await tester.pumpAndSettle();

      expect(find.text('Saved Queries & Presets'), findsOneWidget);
      expect(find.text('Test Saved Preset'), findsOneWidget);
      expect(find.text('Preset notes'), findsOneWidget);

      await tester.tap(find.text('Load into Editor'));
      await tester.pumpAndSettle();

      expect(find.text('Saved Queries & Presets'), findsNothing);
    });
  });
}
