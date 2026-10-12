import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/models/table_schema.dart';
import 'package:rev_vault/services/sql_autocomplete_service.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/sql_editor_view.dart';

void main() {
  group('SqlAutocompleteService Unit Tests', () {
    final service = SqlAutocompleteService();

    final testTables = <TableMetadata>[
      TableMetadata(
        schema: 'public',
        name: 'public.users',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'integer', isPrimaryKey: true, isNullable: false),
          ColumnMetadata(name: 'username', dataType: 'varchar', isPrimaryKey: false, isNullable: false),
          ColumnMetadata(name: 'email', dataType: 'varchar', isPrimaryKey: false, isNullable: true),
          ColumnMetadata(name: 'created_at', dataType: 'timestamp', isPrimaryKey: false, isNullable: true),
        ],
      ),
      TableMetadata(
        schema: 'public',
        name: 'public.orders',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'integer', isPrimaryKey: true, isNullable: false),
          ColumnMetadata(name: 'user_id', dataType: 'integer', isPrimaryKey: false, isNullable: false),
          ColumnMetadata(name: 'total_amount', dataType: 'numeric', isPrimaryKey: false, isNullable: false),
          ColumnMetadata(name: 'status', dataType: 'varchar', isPrimaryKey: false, isNullable: true),
        ],
      ),
    ];

    test('Suggests starting keywords on empty query', () {
      final suggestions = service.getSuggestions(
        text: '',
        cursorPosition: 0,
        tables: testTables,
      );

      expect(suggestions, isNotEmpty);
      expect(suggestions.any((s) => s.displayText == 'SELECT'), isTrue);
      expect(suggestions.any((s) => s.displayText.contains('WITH')), isTrue);
    });

    test('Suggests tables after FROM keyword', () {
      const text = 'SELECT * FROM ';
      final suggestions = service.getSuggestions(
        text: text,
        cursorPosition: text.length,
        tables: testTables,
      );

      expect(suggestions.any((s) => s.insertText == 'users'), isTrue);
      expect(suggestions.any((s) => s.insertText == 'orders'), isTrue);
    });

    test('Suggests columns when typing table accessor u.', () {
      const text = 'SELECT u. FROM users u';
      final suggestions = service.getSuggestions(
        text: text,
        cursorPosition: 9, // right after "u."
        tables: testTables,
      );

      expect(suggestions.any((s) => s.insertText == 'id'), isTrue);
      expect(suggestions.any((s) => s.insertText == 'username'), isTrue);
      expect(suggestions.any((s) => s.insertText == 'email'), isTrue);
    });

    test('Suggests subquery snippets when typing subquery keyword or partial phrase', () {
      const text = 'SELECT * FROM users WHERE exist';
      final suggestions = service.getSuggestions(
        text: text,
        cursorPosition: text.length,
        tables: testTables,
      );

      expect(suggestions.any((s) => s.type == SqlSuggestionType.subquery), isTrue);
      expect(suggestions.any((s) => s.displayText.contains('EXISTS')), isTrue);
    });

    test('Extracts parameters from SQL query', () {
      const sql = 'SELECT * FROM users WHERE id = :user_id AND status = :status AND org_id = \$1 AND active = ?;';
      final params = service.extractParameters(sql);

      expect(params, containsAll(['user_id', 'status', '\$1', '?']));
    });

    test('formatSql capitalizes keywords and adds structured newlines', () {
      const raw = 'select id, username from users where id > 5 and status = 1 order by id desc limit 10;';
      final formatted = service.formatSql(raw);

      expect(formatted, contains('SELECT'));
      expect(formatted, contains('FROM users'));
      expect(formatted, contains('\nWHERE id > 5 AND status = 1'));
      expect(formatted, contains('\nORDER BY id DESC'));
      expect(formatted, contains('\nLIMIT 10;'));
    });

    test('Suggests relational JOIN based on foreign keys', () {
      final ordersWithFk = TableMetadata(
        schema: 'public',
        name: 'public.orders',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'integer', isPrimaryKey: true, isNullable: false),
          ColumnMetadata(
            name: 'user_id',
            dataType: 'integer',
            isPrimaryKey: false,
            isNullable: false,
            foreignKey: ForeignKeyMetadata(columnName: 'user_id', targetTable: 'users', targetColumn: 'id'),
          ),
        ],
        foreignKeys: [
          ForeignKeyMetadata(columnName: 'user_id', targetTable: 'users', targetColumn: 'id'),
        ],
      );

      const text = 'SELECT * FROM orders JOIN ';
      final suggestions = service.getSuggestions(
        text: text,
        cursorPosition: text.length,
        tables: [testTables[0], ordersWithFk],
      );

      expect(suggestions.any((s) => s.insertText.contains('users ON orders.user_id = users.id')), isTrue);
    });
  });

  group('SqlEditorView & Subquery Modal Widget Tests', () {
    testWidgets('Renders SqlEditorView and opens Subquery Snippets Modal', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = AppState();
      state.editorQueryText = 'SELECT * FROM users;';

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const Scaffold(
              body: SqlEditorView(),
            ),
          ),
        ),
      );

      // Verify buttons in toolbar
      expect(find.text('Run Query'), findsOneWidget);
      expect(find.text('Tools & Utilities'), findsOneWidget);
      expect(find.text('Format SQL'), findsOneWidget);

      // Open Tools & Utilities bottom sheet
      await tester.tap(find.text('Tools & Utilities'));
      await tester.pumpAndSettle();

      // Tap on Subquery & CTEs tile
      expect(find.text('Subquery & CTEs'), findsOneWidget);
      await tester.tap(find.text('Subquery & CTEs'));
      await tester.pumpAndSettle();

      // Verify modal is open and first items are visible
      expect(find.text('Subquery & CTE Snippets Library'), findsOneWidget);
      expect(find.text('WHERE IN (Subquery)'), findsOneWidget);

      // Tap on 'CTE / Modular' category chip to filter
      await tester.tap(find.text('CTE / Modular'));
      await tester.pumpAndSettle();
      expect(find.text('WITH CTE (Common Table Expression)'), findsOneWidget);

      // Tap on Insert button of the CTE snippet
      final insertButtons = find.widgetWithText(ElevatedButton, 'Insert');
      expect(insertButtons, findsWidgets);
      await tester.tap(insertButtons.first);
      await tester.pumpAndSettle();

      // Verify modal closed and template inserted into query text
      expect(find.text('Subquery & CTE Snippets Library'), findsNothing);
      expect(state.editorQueryText, contains('WITH cte_summary AS'));
    });

    testWidgets('Displays docked IntelliSense assistant and responds to Auto-Helper toggle', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = AppState();
      state.editorQueryText = 'SELECT ';

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const Scaffold(
              body: SqlEditorView(),
            ),
          ),
        ),
      );

      // Verify toolbar has Tools & Utilities button
      expect(find.text('Tools & Utilities'), findsOneWidget);

      // Open Tools & Utilities bottom sheet to verify Auto-Helper: ON
      await tester.tap(find.text('Tools & Utilities'));
      await tester.pumpAndSettle();
      expect(find.text('Auto-Helper: ON'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Type in TextField to trigger autocomplete
      await tester.enterText(find.byType(TextField).first, 'SELECT * FROM wh');
      await tester.pumpAndSettle();

      // Check if docked assistant is shown with navigation hint
      expect(find.textContaining('IntelliSense Assistant'), findsOneWidget);
      expect(find.textContaining('↑/↓: Navigate'), findsOneWidget);

      // Open Tools & Utilities & Toggle Auto-Helper to OFF
      await tester.tap(find.text('Tools & Utilities'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto-Helper: ON'));
      await tester.pumpAndSettle();

      // Verify assistant dismissed and state toggled
      expect(find.textContaining('IntelliSense Assistant'), findsNothing);

      // Re-open Tools & Utilities to confirm toggle text changed to OFF
      await tester.tap(find.text('Tools & Utilities'));
      await tester.pumpAndSettle();
      expect(find.text('Auto-Helper: OFF'), findsOneWidget);
    });

    testWidgets('Auto-scrolls choices list when navigating with arrow keys in SqlAutocompleteDock', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = AppState();
      state.editorQueryText = 'SELECT * FROM ';

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const Scaffold(
              body: SqlEditorView(),
            ),
          ),
        ),
      );

      // Type 'SELECT * FROM whe' to trigger multiple subquery / keyword suggestions
      await tester.enterText(find.byType(TextField).first, 'SELECT * FROM whe');
      await tester.pumpAndSettle();

      expect(find.textContaining('IntelliSense Assistant'), findsOneWidget);

      // Navigate down 5 times to scroll through the list
      for (int i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }

      // The dock remains visible and healthy with active selection updated
      expect(find.textContaining('IntelliSense Assistant'), findsOneWidget);
    });

    testWidgets('Plain Enter chooses the highlighted autocomplete suggestion', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = AppState();
      state.editorQueryText = 'SELECT ';

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const Scaffold(
              body: SqlEditorView(),
            ),
          ),
        ),
      );

      // Type to open autocomplete suggestions
      await tester.enterText(find.byType(TextField).first, 'SELECT * FROM whe');
      await tester.pumpAndSettle();

      expect(find.textContaining('IntelliSense Assistant'), findsOneWidget);

      // Plain Enter should apply the suggestion
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Autocomplete dock should close and text should be updated
      expect(find.textContaining('IntelliSense Assistant'), findsNothing);
      expect(state.editorQueryText, isNot('SELECT * FROM whe'));
    });

    testWidgets('Ctrl + Enter runs query and dismisses helper without choosing suggestion', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = AppState();
      state.editorQueryText = 'SELECT ';

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const Scaffold(
              body: SqlEditorView(),
            ),
          ),
        ),
      );

      // Type query prefix that opens autocomplete
      const queryText = 'SELECT * FROM whe';
      await tester.enterText(find.byType(TextField).first, queryText);
      await tester.pumpAndSettle();

      expect(find.textContaining('IntelliSense Assistant'), findsOneWidget);

      // Press Ctrl + Enter
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      // The helper must be dismissed
      expect(find.textContaining('IntelliSense Assistant'), findsNothing);
      // Query text must remain the user's typed query, NOT replaced by helper
      expect(state.editorQueryText, equals(queryText));
    });

    testWidgets('Meta + Enter runs query and dismisses helper without choosing suggestion', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = AppState();
      state.editorQueryText = 'SELECT ';

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const Scaffold(
              body: SqlEditorView(),
            ),
          ),
        ),
      );

      // Type query prefix that opens autocomplete
      const queryText = 'SELECT * FROM whe';
      await tester.enterText(find.byType(TextField).first, queryText);
      await tester.pumpAndSettle();

      expect(find.textContaining('IntelliSense Assistant'), findsOneWidget);

      // Press Meta + Enter
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();

      // The helper must be dismissed
      expect(find.textContaining('IntelliSense Assistant'), findsNothing);
      // Query text must remain the user's typed query
      expect(state.editorQueryText, equals(queryText));
    });
  });
}
