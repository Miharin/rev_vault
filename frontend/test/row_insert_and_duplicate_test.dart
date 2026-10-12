import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_vault/models/table_schema.dart';
import 'package:rev_vault/views/widgets/virtualized_data_table.dart';
import 'package:rev_vault/views/widgets/row_insert_modal.dart';
import 'package:rev_vault/views/widgets/row_duplicate_modal.dart';

void main() {
  group('VirtualizedDataTable Column Details & Actions Tests', () {
    testWidgets('Header renders column types, PK, and FK badges when showColumnDetails is true', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final columns = ['id', 'user_id', 'title'];
      final rows = [
        [1, 42, 'First Post'],
      ];

      final metadata = TableMetadata(
        name: 'posts',
        schema: 'public',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(
            name: 'id',
            dataType: 'integer',
            isPrimaryKey: true,
            isNullable: false,
          ),
          ColumnMetadata(
            name: 'user_id',
            dataType: 'integer',
            isPrimaryKey: false,
            isNullable: false,
            foreignKey: ForeignKeyMetadata(
              columnName: 'user_id',
              targetTable: 'users',
              targetColumn: 'id',
            ),
          ),
          ColumnMetadata(
            name: 'title',
            dataType: 'varchar(255)',
            isPrimaryKey: false,
            isNullable: true,
          ),
        ],
      );

      // Render with showColumnDetails = true
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VirtualizedDataTable(
              columns: columns,
              rows: rows,
              tableMetadata: metadata,
              showColumnDetails: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify column name renders
      expect(find.text('id'), findsOneWidget);
      expect(find.text('user_id'), findsOneWidget);
      expect(find.text('title'), findsOneWidget);

      // Verify badges and data types
      expect(find.text('PK'), findsOneWidget);
      expect(find.text('FK \u2192 users'), findsOneWidget);
      expect(find.text('INTEGER'), findsNWidgets(2));
      expect(find.text('VARCHAR(255)'), findsOneWidget);
    });

    testWidgets('Header hides schema details badges when showColumnDetails is false', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final columns = ['id', 'user_id', 'title'];
      final rows = [
        [1, 42, 'First Post'],
      ];

      final metadata = TableMetadata(
        name: 'posts',
        schema: 'public',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(
            name: 'id',
            dataType: 'integer',
            isPrimaryKey: true,
            isNullable: false,
          ),
          ColumnMetadata(
            name: 'user_id',
            dataType: 'integer',
            isPrimaryKey: false,
            isNullable: false,
            foreignKey: ForeignKeyMetadata(
              columnName: 'user_id',
              targetTable: 'users',
              targetColumn: 'id',
            ),
          ),
          ColumnMetadata(
            name: 'title',
            dataType: 'varchar(255)',
            isPrimaryKey: false,
            isNullable: true,
          ),
        ],
      );

      // Render with showColumnDetails = false
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VirtualizedDataTable(
              columns: columns,
              rows: rows,
              tableMetadata: metadata,
              showColumnDetails: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PK'), findsNothing);
      expect(find.text('FK \u2192 users'), findsNothing);
      expect(find.text('VARCHAR(255)'), findsNothing);
    });

    testWidgets('Header renders candidate PK and inferred FK badges when table lacks formal DB constraints', (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final columns = ['counter', 'single_id', 'no_transaksi', 'no_kunjungan', 'date_created'];
      final rows = [
        [1, '202510200003', '03-071125-6', '20102025-3', '2025-12-29 01:24:37'],
      ];

      // Table like rawat_inap_rme.cara_keluar: has columns and types, but isPrimaryKey is false everywhere and foreignKeys is empty
      final metadata = TableMetadata(
        name: 'rawat_inap_rme.cara_keluar',
        schema: 'rawat_inap_rme',
        tableType: 'BASE TABLE',
        rawName: 'cara_keluar',
        columns: [
          ColumnMetadata(name: 'counter', dataType: 'integer', isPrimaryKey: false, isNullable: false),
          ColumnMetadata(name: 'single_id', dataType: 'character varying(48)', isPrimaryKey: false, isNullable: false),
          ColumnMetadata(name: 'no_transaksi', dataType: 'character varying(64)', isPrimaryKey: false, isNullable: false),
          ColumnMetadata(name: 'no_kunjungan', dataType: 'character varying(48)', isPrimaryKey: false, isNullable: false),
          ColumnMetadata(name: 'date_created', dataType: 'timestamp', isPrimaryKey: false, isNullable: true),
        ],
        foreignKeys: [],
      );

      final otherTables = [
        TableMetadata(name: 'transaksi', schema: 'public', tableType: 'BASE TABLE', rawName: 'transaksi', columns: []),
        TableMetadata(name: 'kunjungan', schema: 'public', tableType: 'BASE TABLE', rawName: 'kunjungan', columns: []),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VirtualizedDataTable(
              columns: columns,
              rows: rows,
              tableMetadata: metadata,
              allTables: otherTables,
              showColumnDetails: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify candidate PK badge on single_id
      expect(find.text('PK'), findsOneWidget);

      // Verify inferred FK badges on no_transaksi and no_kunjungan
      expect(find.text('FK \u2192 transaksi'), findsOneWidget);
      expect(find.text('FK \u2192 kunjungan'), findsOneWidget);
    });
  });

  group('RowInsertModal Widget Tests', () {
    testWidgets('RowInsertModal omits auto PK by default and sends row payload without PK', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final columns = ['id', 'name', 'status'];
      final metadata = TableMetadata(
        name: 'projects',
        schema: 'public',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'int', isPrimaryKey: true, isNullable: false),
          ColumnMetadata(name: 'name', dataType: 'text', isPrimaryKey: false, isNullable: false),
          ColumnMetadata(name: 'status', dataType: 'varchar', isPrimaryKey: false, isNullable: true),
        ],
      );

      Map<String, dynamic>? submittedValues;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showRowInsertModal(
                  context: ctx,
                  tableName: 'projects',
                  columns: columns,
                  tableMetadata: metadata,
                  onInsert: ({required Map<String, dynamic> rowValues}) async {
                    submittedValues = rowValues;
                    return null;
                  },
                ),
                child: const Text('Open Insert Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Insert Modal'));
      await tester.pumpAndSettle();

      // Check modal title and table indicator
      expect(find.text('Insert New Row'), findsOneWidget);
      expect(find.text('projects'), findsOneWidget);

      // Check Auto toggle is shown for PK column
      expect(find.text('Auto (DB Default)'), findsOneWidget);

      // Enter name value
      final textFields = find.byType(TextField);
      expect(textFields, findsWidgets);
      await tester.enterText(textFields.first, 'Cyber Alpha');
      await tester.pumpAndSettle();

      // Submit insert using Insert Record button
      expect(find.text('Insert Record'), findsOneWidget);
      await tester.tap(find.text('Insert Record'));
      await tester.pumpAndSettle();

      expect(submittedValues, isNotNull);
      // PK should be omitted because Auto (DB Default) is active
      expect(submittedValues!.containsKey('id'), isFalse);
      expect(submittedValues!['name'], 'Cyber Alpha');
    });

    testWidgets('RowInsertModal includes PK when Auto toggle is unchecked', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final columns = ['id', 'name'];
      final metadata = TableMetadata(
        name: 'projects',
        schema: 'public',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'varchar(32)', isPrimaryKey: true, isNullable: false),
          ColumnMetadata(name: 'name', dataType: 'text', isPrimaryKey: false, isNullable: false),
        ],
      );

      Map<String, dynamic>? submittedValues;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showRowInsertModal(
                  context: ctx,
                  tableName: 'projects',
                  columns: columns,
                  tableMetadata: metadata,
                  onInsert: ({required Map<String, dynamic> rowValues}) async {
                    submittedValues = rowValues;
                    return null;
                  },
                ),
                child: const Text('Open Insert Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Insert Modal'));
      await tester.pumpAndSettle();

      // Turn off Auto toggle for id
      await tester.tap(find.text('Auto (DB Default)'));
      await tester.pumpAndSettle();

      // Now enter id and name
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'custom_id_99');
      await tester.enterText(textFields.at(1), 'Beta Service');
      await tester.pumpAndSettle();

      expect(find.text('Insert Record'), findsOneWidget);
      await tester.tap(find.text('Insert Record'));
      await tester.pumpAndSettle();

      expect(submittedValues, isNotNull);
      expect(submittedValues!['id'], 'custom_id_99');
      expect(submittedValues!['name'], 'Beta Service');
    });
  });

  group('RowDuplicateModal Widget Tests', () {
    testWidgets('RowDuplicateModal excludes PK, supports checkbox exclusion toggle, and duplicates count', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final columns = ['id', 'sku', 'stock'];
      final rowValues = [101, 'NEON-A1', 50];
      final metadata = TableMetadata(
        name: 'products',
        schema: 'public',
        tableType: 'BASE TABLE',
        columns: [
          ColumnMetadata(name: 'id', dataType: 'int', isPrimaryKey: true, isNullable: false),
          ColumnMetadata(name: 'sku', dataType: 'varchar', isPrimaryKey: false, isNullable: false),
          ColumnMetadata(name: 'stock', dataType: 'int', isPrimaryKey: false, isNullable: false),
        ],
      );

      int? executedCount;
      List<Map<String, dynamic>>? executedRows;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showRowDuplicateModal(
                  context: ctx,
                  tableName: 'products',
                  columns: columns,
                  rowValues: rowValues,
                  tableMetadata: metadata,
                  onDuplicate: ({required int count, required List<Map<String, dynamic>> rowsToInsert}) async {
                    executedCount = count;
                    executedRows = rowsToInsert;
                    return null;
                  },
                ),
                child: const Text('Open Duplicate Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Duplicate Modal'));
      await tester.pumpAndSettle();

      // Check header
      expect(find.text('Duplicate Row Record'), findsOneWidget);

      // Check PK exclusion notice
      expect(find.textContaining('Collision Prevention'), findsOneWidget);
      expect(find.textContaining('[id]'), findsOneWidget);

      // Check preview
      expect(find.text('sku'), findsOneWidget);
      expect(find.text('NEON-A1'), findsOneWidget);
      expect(find.text('stock'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);

      // Toggle stock exclusion off/on
      expect(find.byType(Checkbox), findsNWidgets(3));
      // Tap 'stock' checkbox to toggle exclusion (id is 0, sku is 1, stock is 2)
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();
      expect(find.text('[EXCLUDED FROM INSERT]'), findsNWidgets(2)); // id + stock

      // Toggle stock back on
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();

      // Tap '5x' preset chip
      expect(find.text('5x'), findsOneWidget);
      await tester.tap(find.text('5x'));
      await tester.pumpAndSettle();

      // Tap confirm button
      expect(find.text('Duplicate Row (5 copies)'), findsOneWidget);
      await tester.tap(find.text('Duplicate Row (5 copies)'));
      await tester.pumpAndSettle();

      // Verify executed arguments
      expect(executedCount, 5);
      expect(executedRows, isNotNull);
      expect(executedRows!.length, 5);
      expect(executedRows!.first.containsKey('id'), isFalse);
      expect(executedRows!.first['sku'], 'NEON-A1');
      expect(executedRows!.first['stock'], 50);
    });

    testWidgets('RowDuplicateModal displays detailed database error banner when duplication fails', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final columns = ['single_id', 'title'];
      final rowValues = ['202409270157', 'Surgery'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showRowDuplicateModal(
                  context: ctx,
                  tableName: 'items',
                  columns: columns,
                  rowValues: rowValues,
                  onDuplicate: ({required int count, required List<Map<String, dynamic>> rowsToInsert}) async {
                    return 'null value in column "single_id" violates not-null constraint';
                  },
                ),
                child: const Text('Open Duplicate Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Duplicate Modal'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Duplicate Row (1 copy)'));
      await tester.pumpAndSettle();

      // Verify exact error message is rendered
      expect(find.textContaining('violates not-null constraint'), findsOneWidget);
    });
  });
}
