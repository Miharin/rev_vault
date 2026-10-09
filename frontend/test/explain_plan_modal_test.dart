import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/services/api_service.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/widgets/explain_plan_modal.dart';

class MockExplainApiService extends ApiService {
  final Map<String, dynamic> mockResponse;

  MockExplainApiService(this.mockResponse);

  @override
  Future<Map<String, dynamic>> explainQuery({required String sql, bool analyze = false}) async {
    return mockResponse;
  }
}

void main() {
  group('ExplainPlanDialog Widget Tests', () {
    final mockExplainData = {
      'engine': 'postgresql',
      'total_cost': 142.50,
      'planning_time_ms': 0.85,
      'execution_time_ms': 12.30,
      'warnings': [
        'Sequential scan detected on large table "users". Consider adding an index.',
      ],
      'recommendations': [
        'CREATE INDEX idx_users_email ON users(email);',
      ],
      'plan_tree': {
        'node_type': 'Seq Scan',
        'relation_name': 'users',
        'total_cost': 142.50,
        'actual_rows': 2500,
        'actual_total_time': 12.30,
        'plans': [],
      },
      'raw_plan': {
        'node_type': 'Seq Scan',
        'relation_name': 'users',
      },
    };

    testWidgets('Renders metric cards, plan tree, and performance warnings', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockApi = MockExplainApiService(mockExplainData);
      final state = AppState(api: mockApi);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const Scaffold(
              body: ExplainPlanDialog(query: 'SELECT * FROM users WHERE email LIKE "%test%"'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header and engine badge
      expect(find.text('Query Execution Plan & Cost Inspector'), findsOneWidget);
      expect(find.textContaining('Engine: POSTGRESQL'), findsOneWidget);

      // Check metric cards
      expect(find.text('Total Cost'), findsOneWidget);
      expect(find.text('142.5'), findsOneWidget);
      expect(find.text('Planning Time'), findsOneWidget);
      expect(find.text('0.85ms'), findsOneWidget);
      expect(find.text('Execution Time'), findsOneWidget);
      expect(find.text('12.3ms'), findsOneWidget);

      // Check Performance Advisory and recommendations
      expect(find.text('Performance Advisory'), findsOneWidget);
      expect(find.textContaining('Sequential scan detected on large table "users"'), findsOneWidget);
      expect(find.textContaining('CREATE INDEX idx_users_email'), findsOneWidget);

      // Check Visual Plan Tree
      expect(find.text('Visual Execution Tree'), findsOneWidget);
      expect(find.text('Seq Scan'), findsOneWidget);
      expect(find.text('on users'), findsOneWidget);

      // Toggle Raw JSON
      await tester.tap(find.text('Show Raw JSON'));
      await tester.pumpAndSettle();

      expect(find.text('Raw Execution Plan Data'), findsOneWidget);
      expect(find.textContaining('"node_type": "Seq Scan"'), findsOneWidget);
    });

    testWidgets('Displays graceful error banner if explain query fails', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockApi = MockExplainApiService({
        'error': 'Syntax error in SQL near "FOOBAR"',
      });
      final state = AppState(api: mockApi);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: const Scaffold(
              body: ExplainPlanDialog(query: 'SELECT FOOBAR FROM users'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.textContaining('Syntax error in SQL near "FOOBAR"'), findsOneWidget);
    });
  });
}
