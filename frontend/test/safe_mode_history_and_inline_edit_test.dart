import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_vault/views/widgets/virtualized_data_table.dart';
import 'package:rev_vault/views/widgets/safe_mode_confirm_dialog.dart';

void main() {
  group('VirtualizedDataTable Inline Editing & Safe Mode Tests', () {
    testWidgets('Double-clicking cell enters inline edit mode and saves on outside tap', (tester) async {
      String? savedCol;
      dynamic savedOld;
      dynamic savedNew;

      final columns = ['id', 'username', 'email'];
      final rows = [
        [1, 'john_doe', 'john@example.com'],
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: VirtualizedDataTable(
                columns: columns,
                rows: rows,
                isSafeMode: true,
                onInlineCellSave: (rowIndex, col, oldVal, newVal) async {
                  savedCol = col;
                  savedOld = oldVal;
                  savedNew = newVal;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify john_doe is visible as Text
      expect(find.text('john_doe'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      // Double-click the cell
      await tester.tap(find.text('john_doe'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('john_doe'));
      await tester.pumpAndSettle();

      // TextField is now active
      expect(find.byType(TextField), findsOneWidget);

      // Enter new text
      await tester.enterText(find.byType(TextField), 'jane_doe');
      await tester.pumpAndSettle();

      // Tap outside the cell to commit
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Verify callback was invoked with updated value
      expect(savedCol, equals('username'));
      expect(savedOld, equals('john_doe'));
      expect(savedNew, equals('jane_doe'));
    });

    testWidgets('Double-clicking on empty area of cell (not directly on text) enters inline edit mode', (tester) async {
      final columns = ['id', 'username'];
      final rows = [
        [1, 'a'], // short 1-char text in a 140px wide cell
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: VirtualizedDataTable(
                columns: columns,
                rows: rows,
                onInlineCellSave: (rowIndex, col, oldVal, newVal) async => true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the text 'a'
      final textFinder = find.text('a');
      expect(textFinder, findsOneWidget);
      final textPos = tester.getCenter(textFinder);

      // Tap far to the right of the text (in the empty cell padding area)
      final emptyCellOffset = Offset(textPos.dx + 50, textPos.dy);

      // Double tap the empty cell area
      await tester.tapAt(emptyCellOffset);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(emptyCellOffset);
      await tester.pumpAndSettle();

      // Verify TextField activated!
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Safe mode lock icon is present on delete button when isSafeMode is true', (tester) async {
      final columns = ['id', 'username'];
      final rows = [
        [1, 'john_doe'],
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: VirtualizedDataTable(
                columns: columns,
                rows: rows,
                isSafeMode: true,
                onDeleteRow: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify delete icon and lock icon are rendered
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
    });
  });

  group('SafeModeConfirmDialog Tests', () {
    testWidgets('Renders Safe Mode warning and confirms on click', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showSafeModeConfirmDialog(
                    context: context,
                    operation: 'update',
                    tableName: 'users',
                    primaryKeys: {'id': 1},
                    changes: {
                      'status': {'old': 'active', 'new': 'suspended'},
                    },
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('SAFE MODE GUARDRAIL ACTIVE'), findsOneWidget);
      expect(find.text('users'), findsOneWidget);
      expect(find.text('status: '), findsOneWidget);
      expect(find.text('active'), findsOneWidget);
      expect(find.text('suspended'), findsOneWidget);

      // Tap Confirm
      await tester.tap(find.text('Confirm & Save'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });
  });
}
