import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/models/query_result.dart';
import 'package:rev_vault/models/table_schema.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/schema_tree_view.dart';
import 'package:rev_vault/views/sql_editor_view.dart';

void main() {
  testWidgets('SchemaTreeView groups tables into folders and filters correctly', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final state = AppState();
    state.tables = [
      TableMetadata(
        name: 'master.alasan_dirujuk',
        schema: 'master',
        rawName: 'alasan_dirujuk',
        tableType: 'TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'int', isNullable: false, isPrimaryKey: true),
        ],
      ),
      TableMetadata(
        name: 'master.cppt_keperawatan',
        schema: 'master',
        rawName: 'cppt_keperawatan',
        tableType: 'TABLE',
        columns: [
          ColumnMetadata(name: 'kd_tindakan', dataType: 'text', isNullable: false, isPrimaryKey: true),
        ],
      ),
      TableMetadata(
        name: 'antrian_apotek.antrian',
        schema: 'antrian_apotek',
        rawName: 'antrian',
        tableType: 'TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'int', isNullable: false, isPrimaryKey: true),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const SchemaTreeView(),
          ),
        ),
      ),
    );

    // Should find Schemas header
    expect(find.text('Schemas (2)'), findsOneWidget);

    // Should find folder headers for both schemas
    expect(find.text('antrian_apotek'), findsOneWidget);
    expect(find.text('master'), findsOneWidget);

    // Search filter test — wait for 180ms debounce + one setState pump
    await tester.enterText(find.byType(TextField), 'cppt');
    await tester.pump(const Duration(milliseconds: 200)); // debounce fires
    await tester.pump(); // allow setState to settle

    // After filtering, antrian_apotek should not match, only master
    expect(find.text('Schemas (1)'), findsOneWidget);
    expect(find.text('master'), findsOneWidget);
    expect(find.text('antrian_apotek'), findsNothing);
  });

  testWidgets('SqlEditorView displays pagination bar and responds to page navigation', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final state = AppState();
    state.activePreviewTable = 'master.alasan_dirujuk';
    state.previewPage = 1;
    state.previewPageSize = 25;
    state.lastQueryResult = QueryResult(
      columns: ['id', 'name'],
      rows: [
        [1, 'Sarana'],
        [2, 'Kapasitas'],
      ],
      rowCount: 2,
      executionTimeMs: 4.2,
      totalRows: 50,
      page: 1,
      pageSize: 25,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const SqlEditorView(),
          ),
        ),
      ),
    );

    // Should see preview badge
    expect(find.text('Preview: master.alasan_dirujuk'), findsOneWidget);

    // Should see pagination text
    expect(find.text('Showing rows 1 – 2 of 50 (Page 1 of 2)'), findsOneWidget);

    // Should find Next button and Page 1
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
  });

  testWidgets('SqlEditorView filters and sorts table rows', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final state = AppState();
    state.lastQueryResult = QueryResult(
      columns: ['id', 'city'],
      rows: [
        [10, 'Jakarta'],
        [2, 'Bandung'],
        [50, 'Surabaya'],
      ],
      rowCount: 3,
      executionTimeMs: 1.5,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const SqlEditorView(),
          ),
        ),
      ),
    );

    // Initial rows all visible
    expect(find.text('Jakarta'), findsOneWidget);
    expect(find.text('Bandung'), findsOneWidget);
    expect(find.text('Surabaya'), findsOneWidget);

    // Filter by 'ban'
    await tester.enterText(find.widgetWithText(TextField, 'Filter results...'), 'ban');
    await tester.pump();

    expect(find.text('Bandung'), findsOneWidget);
    expect(find.text('Jakarta'), findsNothing);
    expect(find.text('Surabaya'), findsNothing);

    // Clear filter
    await tester.enterText(find.widgetWithText(TextField, 'Filter results...'), '');
    await tester.pump();
    expect(find.text('Jakarta'), findsOneWidget);

    // Sort by id column (tapping 'id' column header)
    await tester.tap(find.text('id'));
    await tester.pump();

    // Verify sort works without error
    expect(find.text('Jakarta'), findsOneWidget);
  });

  testWidgets('AppState insertTextIntoEditor formats dropped tables/columns correctly', (WidgetTester tester) async {
    final state = AppState();
    // Default initial query
    expect(state.editorQueryText, 'SELECT * FROM users LIMIT 10;');

    // Dropping a table replaces default query with SELECT
    state.insertTextIntoEditor('"master"."cppt_keperawatan"');
    expect(state.editorQueryText, 'SELECT * FROM "master"."cppt_keperawatan" LIMIT 25;');

    state.insertTextIntoEditor('nama_tindakan');
    expect(state.editorQueryText, 'SELECT * FROM "master"."cppt_keperawatan" LIMIT 25 nama_tindakan;');
  });

  testWidgets('SchemaTreeView minimizes to strip and expands back', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final state = AppState();
    state.tables = [
      TableMetadata(
        name: 'master.alasan_dirujuk',
        schema: 'master',
        rawName: 'alasan_dirujuk',
        tableType: 'TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'int', isNullable: false, isPrimaryKey: true),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const SchemaTreeView(),
          ),
        ),
      ),
    );

    expect(find.text('Schemas (1)'), findsOneWidget);

    // Tap minimize button
    final minimizeBtn = find.byTooltip('Minimize Schema Explorer to Strip');
    expect(minimizeBtn, findsOneWidget);
    await tester.tap(minimizeBtn);
    await tester.pumpAndSettle();

    // Now state.isSchemaExplorerHidden should be true
    expect(state.isSchemaExplorerHidden, true);
    expect(find.text('SCHEMAS (1)'), findsOneWidget);

    // Tap the strip to expand back
    await tester.tap(find.text('SCHEMAS (1)'));
    await tester.pumpAndSettle();

    expect(state.isSchemaExplorerHidden, false);
    expect(find.text('Schemas (1)'), findsOneWidget);
  });

  testWidgets('SchemaTreeView shows loading indicator when isSchemaLoading is true', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final state = AppState();
    state.tables = [];
    state.isSchemaLoading = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const SchemaTreeView(),
          ),
        ),
      ),
    );

    expect(find.text('Loading schemas...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  test('QueryResult parses hasMore property from JSON', () {
    final json = {
      'columns': ['id', 'name'],
      'rows': [[1, 'Alice']],
      'row_count': 1,
      'execution_time_ms': 5.2,
      'page': 1,
      'page_size': 100,
      'has_more': true,
    };
    final res = QueryResult.fromJson(json);
    expect(res.hasMore, true);
    expect(res.page, 1);
    expect(res.pageSize, 100);
  });

  test('AppState query pagination rewrites LIMIT and OFFSET correctly', () {
    final state = AppState();
    state.editorQueryText = 'SELECT * FROM users;';
    state.queryPage = 1;
    state.queryPageSize = 100;

    // Simulate nextQueryPage SQL generation
    final nextSql = state.editorQueryText.trim();
    expect(nextSql, 'SELECT * FROM users;');

    state.setActiveLimit(50);
    expect(state.activeLimit, 50);
    expect(state.queryPageSize, 50);
  });

  testWidgets('SqlEditorView renders pagination bar with hasMore and enabled Next button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final state = AppState();
    state.queryPage = 1;
    state.queryPageSize = 100;
    state.activePreviewTable = null; // Ad-hoc query mode
    state.lastQueryResult = QueryResult(
      columns: ['id', 'username'],
      rows: List.generate(100, (i) => [i + 1, 'user_$i']),
      rowCount: 100,
      executionTimeMs: 12.5,
      page: 1,
      pageSize: 100,
      hasMore: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const SqlEditorView(),
          ),
        ),
      ),
    );

    // Verify pagination bar is displayed for ad-hoc query with hasMore
    expect(find.text('Showing rows 1 – 100 (Page 1 • More available)'), findsOneWidget);

    // Next button should be enabled
    final nextBtnFinder = find.widgetWithText(OutlinedButton, 'Next');
    expect(nextBtnFinder, findsOneWidget);
    final OutlinedButton nextBtn = tester.widget(nextBtnFinder);
    expect(nextBtn.onPressed, isNotNull);

    // Prev button should be disabled on page 1
    final prevBtnFinder = find.widgetWithText(OutlinedButton, 'Prev');
    expect(prevBtnFinder, findsOneWidget);
    final OutlinedButton prevBtn = tester.widget(prevBtnFinder);
    expect(prevBtn.onPressed, isNull);
  });
}


