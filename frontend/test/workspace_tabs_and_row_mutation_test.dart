import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/models/query_result.dart';
import 'package:rev_vault/models/table_schema.dart';
import 'package:rev_vault/models/workspace_tab.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/widgets/virtualized_data_table.dart';
import 'package:rev_vault/views/widgets/workspace_tab_bar.dart';
import 'package:rev_vault/views/widgets/row_edit_modal.dart';
import 'package:rev_vault/views/widgets/row_delete_modal.dart';

void main() {
  group('Multi-Tab Workspace State & Tab Reservation Tests', () {
    test('Initializes with default Query 1 tab', () {
      final state = AppState();
      expect(state.tabs.length, 1);
      expect(state.activeTabIndex, 0);
      expect(state.activeTab.title, 'Query 1');
      expect(state.activeTab.isSqlQuery, true);
    });

    test('openQueryTab adds a new SQL tab and sets it active', () {
      final state = AppState();
      state.openQueryTab(initialSql: 'SELECT * FROM orders;', title: 'Custom Query');

      expect(state.tabs.length, 2);
      expect(state.activeTabIndex, 1);
      expect(state.activeTab.title, 'Custom Query');
      expect(state.activeTab.queryText, 'SELECT * FROM orders;');
    });

    test('openTableTab reserves existing tab instead of recreating it', () async {
      final state = AppState();
      state.tables = [
        TableMetadata(
          name: 'public.users',
          schema: 'public',
          rawName: 'users',
          tableType: 'BASE TABLE',
          columns: [
            ColumnMetadata(name: 'id', dataType: 'int', isNullable: false, isPrimaryKey: true),
            ColumnMetadata(name: 'name', dataType: 'text', isNullable: true, isPrimaryKey: false),
          ],
        ),
      ];

      // Seed first tab
      state.tabs[0].result = QueryResult(
        columns: ['id'],
        rows: [[1]],
        rowCount: 1,
        executionTimeMs: 1.0,
      );

      // Open new table tab
      final tab2 = WorkspaceTab(
        id: 'tab_users',
        title: 'users',
        type: WorkspaceTabType.tablePreview,
        tableName: 'public.users',
        result: QueryResult(
          columns: ['id', 'name'],
          rows: [[1, 'Alice'], [2, 'Bob']],
          rowCount: 2,
          executionTimeMs: 1.2,
        ),
      );
      state.tabs.add(tab2);
      state.activeTabIndex = 1;

      // When opening public.users again without forceReload, it reserves existing tab and its cached result
      await state.openTableTab('public.users', forceReload: false);

      expect(state.activeTabIndex, 1);
      expect(state.tabs.length, 2);
      expect(state.activeTab.result?.rowCount, 2);
    });

    test('openSchemaTab opens new tab or focuses existing schema tab without duplicates', () {
      final state = AppState();
      expect(state.tabs.length, 1);

      state.openSchemaTab('public');
      expect(state.tabs.length, 2);
      expect(state.activeTabIndex, 1);
      expect(state.activeTab.isSchemaOverview, true);
      expect(state.activeTab.schemaName, 'public');
      expect(state.activeSchemaName, 'public');

      // Opening again switches to existing tab
      state.setActiveTab(0);
      expect(state.activeTabIndex, 0);

      state.openSchemaTab('public');
      expect(state.tabs.length, 2);
      expect(state.activeTabIndex, 1);
    });

    test('closeTab handles multiple tabs and prevents empty tab list', () {
      final state = AppState();
      state.openQueryTab(title: 'Query 2');
      expect(state.tabs.length, 2);

      // Close second tab
      state.closeTab(1);
      expect(state.tabs.length, 1);
      expect(state.activeTabIndex, 0);

      // Closing the only remaining tab resets it cleanly rather than leaving an empty list
      state.closeTab(0);
      expect(state.tabs.length, 1);
      expect(state.activeTab.title, 'Query 1');
    });

    test('nextTab and previousTab cycle cleanly', () {
      final state = AppState();
      state.openQueryTab(title: 'Query 2');
      state.openQueryTab(title: 'Query 3');
      expect(state.activeTabIndex, 2);

      state.nextTab();
      expect(state.activeTabIndex, 0);

      state.previousTab();
      expect(state.activeTabIndex, 2);
    });
  });

  group('WorkspaceTabBar Widget Tests', () {
    testWidgets('Renders open tabs, highlights active tab, and responds to tab click', (tester) async {
      final state = AppState();
      state.openQueryTab(title: 'Orders Query');

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const Scaffold(
              body: WorkspaceTabBar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Query 1'), findsOneWidget);
      expect(find.text('Orders Query'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('SCHEMA'), findsOneWidget);

      // Tap first tab
      await tester.tap(find.text('Query 1'));
      await tester.pumpAndSettle();

      expect(state.activeTabIndex, 0);

      // Tap + button to add new tab
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(state.tabs.length, 3);
    });
  });

  group('VirtualizedDataTable In-Row Actions Tests', () {
    testWidgets('Renders Actions column and invokes onEditRow and onDeleteRow callbacks', (tester) async {
      int? editedRow;
      int? deletedRow;

      final columns = ['id', 'username', 'email'];
      final rows = [
        [1, 'john_doe', 'john@example.com'],
        [2, 'jane_doe', 'jane@example.com'],
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VirtualizedDataTable(
              columns: columns,
              rows: rows,
              onEditRow: (rowIndex, rowValues) {
                editedRow = rowIndex;
              },
              onDeleteRow: (rowIndex, rowValues) {
                deletedRow = rowIndex;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ACTIONS'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

      // Tap edit on first row
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pump();
      expect(editedRow, 0);

      // Tap delete on second row
      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pump();
      expect(deletedRow, 1);
    });
  });

  group('RowEditModal & RowDeleteModal Widget Tests', () {
    testWidgets('RowEditModal displays PK badge and submits modified values', (tester) async {
      Map<String, dynamic>? capturedPks;
      Map<String, dynamic>? capturedUpdates;

      final meta = TableMetadata(
        name: 'users',
        schema: 'public',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'int', isNullable: false, isPrimaryKey: true),
          ColumnMetadata(name: 'name', dataType: 'text', isNullable: true, isPrimaryKey: false),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showRowEditModal(
                    context: ctx,
                    tableName: 'users',
                    columns: ['id', 'name'],
                    rowValues: [42, 'Alice'],
                    tableMetadata: meta,
                    onSave: ({required primaryKeys, required updatedValues}) async {
                      capturedPks = primaryKeys;
                      capturedUpdates = updatedValues;
                      return true;
                    },
                  );
                },
                child: const Text('Open Edit'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Row Record'), findsOneWidget);
      expect(find.text('PK'), findsOneWidget); // Primary key badge

      // Modify the name field
      final nameFieldFinder = find.widgetWithText(TextField, 'Alice');
      expect(nameFieldFinder, findsOneWidget);

      await tester.enterText(nameFieldFinder, 'Alice Cooper');
      await tester.pump();

      // Tap Save Changes
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(capturedPks?['id'], 42);
      expect(capturedUpdates?['name'], 'Alice Cooper');
    });

    testWidgets('RowEditModal displays PK and FK informational badges and saves edits', (tester) async {
      Map<String, dynamic>? capturedPks;
      Map<String, dynamic>? capturedUpdates;

      // Table with PK and FK
      final meta = TableMetadata(
        name: 'order_items',
        schema: 'public',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'integer', isNullable: false, isPrimaryKey: true),
          ColumnMetadata(
            name: 'order_id',
            dataType: 'integer',
            isNullable: false,
            isPrimaryKey: false,
            foreignKey: ForeignKeyMetadata(
              columnName: 'order_id',
              constraintName: 'fk_order',
              targetTable: 'orders',
              targetColumn: 'id',
            ),
          ),
          ColumnMetadata(name: 'quantity', dataType: 'numeric', isNullable: true, isPrimaryKey: false),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showRowEditModal(
                    context: ctx,
                    tableName: 'order_items',
                    columns: ['id', 'order_id', 'quantity'],
                    rowValues: [1, 100, 2.5],
                    tableMetadata: meta,
                    onSave: ({required primaryKeys, required updatedValues}) async {
                      capturedPks = primaryKeys;
                      capturedUpdates = updatedValues;
                      return true;
                    },
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Row Record'), findsOneWidget);
      expect(find.text('order_items'), findsOneWidget);

      // Verify informational badges
      expect(find.text('PK'), findsOneWidget);
      expect(find.text('FK'), findsOneWidget);

      // Modify quantity
      final qtyField = find.widgetWithText(TextField, '2.5');
      expect(qtyField, findsOneWidget);
      await tester.enterText(qtyField, '5.0');
      await tester.pump();

      // Tap Save Changes
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(capturedPks, isNotNull);
      expect(capturedPks!['id'], 1);
      expect(capturedUpdates?['quantity'], 5.0);
    });

    testWidgets('RowDeleteModal displays key details and confirms deletion', (tester) async {
      Map<String, dynamic>? capturedPks;

      final meta = TableMetadata(
        name: 'orders',
        schema: 'public',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(name: 'order_id', dataType: 'int', isNullable: false, isPrimaryKey: true),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showRowDeleteModal(
                    context: ctx,
                    tableName: 'orders',
                    columns: ['order_id'],
                    rowValues: [1001],
                    tableMetadata: meta,
                    onDelete: ({required primaryKeys}) async {
                      capturedPks = primaryKeys;
                      return true;
                    },
                  );
                },
                child: const Text('Open Delete'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Delete Row'), findsOneWidget);
      expect(find.text('1001'), findsOneWidget);

      // Tap Delete Row confirm button
      await tester.tap(find.text('Delete Row'));
      await tester.pumpAndSettle();

      expect(capturedPks?['order_id'], 1001);
    });
  });
}
