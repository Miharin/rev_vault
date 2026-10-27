import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/services/api_service.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/ai_assistant_view.dart';

void main() {
  group('AI Assistant Table Rendering Tests', () {
    testWidgets('Renders real DataTable when assistant returns Markdown table in response', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = AppState(api: ApiService(baseUrl: 'http://localhost:8000'));
      
      const assistantResponse = '''
Here is the active cara keluar breakdown:

| id | nama_cara_keluar | status |
| :--- | :--- | :---: |
| 1 | Pulang Sembuh | Active |
| 2 | Rujuk Ke RS Lain | Active |

And here is the SQL query you requested:

```sql
SELECT rawat_inap_rme.cara_keluar.*, public.users.nama
FROM rawat_inap_rme.cara_keluar
JOIN public.users ON rawat_inap_rme.cara_keluar.user_id = public.users.id;
```
''';

      state.addAiMessage(AiAssistantMessage(
        role: 'assistant',
        content: assistantResponse,
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(
              body: AiAssistantView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that the table was detected and parsed into a real DataTable widget
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('DATA MATRIX'), findsOneWidget);
      expect(find.text('2 rows × 3 cols'), findsOneWidget);

      // Verify table headers
      expect(find.text('id'), findsOneWidget);
      expect(find.text('nama_cara_keluar'), findsOneWidget);
      expect(find.text('status'), findsOneWidget);

      // Verify table cell values
      expect(find.text('Pulang Sembuh'), findsOneWidget);
      expect(find.text('Rujuk Ke RS Lain'), findsOneWidget);

      // Verify SQL code block is also rendered
      expect(find.text('Run in SQL Editor'), findsOneWidget);
      expect(find.textContaining('rawat_inap_rme.cara_keluar.*'), findsOneWidget);
    });

    testWidgets('Renders high-capacity structured Data Matrix directly from tool execution payload', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = AppState(api: ApiService(baseUrl: 'http://localhost:8000'));

      final generatedRows = List.generate(25, (i) => [i + 1, 'user_$i', 'user_$i@revvault.dev']);

      state.addAiMessage(AiAssistantMessage(
        role: 'assistant',
        content: 'I executed the safe query and retrieved the full dataset for you.',
        toolExecutions: [
          {
            'name': 'execute_safe_query',
            'arguments': {'sql': 'SELECT * FROM users;'},
            'output_preview': 'Retrieved 25 rows in 1.4ms',
            'success': true,
            'data': {
              'columns': ['id', 'username', 'email'],
              'rows': generatedRows,
              'row_count': 25,
              'execution_time_ms': 1.4,
              'sql': 'SELECT * FROM users;',
            },
          }
        ],
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(
              body: AiAssistantView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify structured data matrix renders
      expect(find.text('DATA MATRIX'), findsOneWidget);
      expect(find.textContaining('25 rows × 3 cols'), findsOneWidget);
      expect(find.textContaining('1.4ms'), findsOneWidget);

      // Verify column headers
      expect(find.text('username'), findsOneWidget);
      expect(find.text('email'), findsOneWidget);

      // Verify row items from page 1 (0-9)
      expect(find.text('user_0'), findsOneWidget);
      expect(find.text('user_9'), findsOneWidget);

      // Verify pagination bar
      expect(find.text('Showing 1–10 of 25 rows'), findsOneWidget);
      expect(find.text('Page 1 of 3'), findsOneWidget);

      // Verify Run in Editor button
      expect(find.text('Run in Editor'), findsOneWidget);
    });

    testWidgets('Seamlessly transitions from 10 to 25 rows with high performance and updated pagination', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = AppState(api: ApiService(baseUrl: 'http://localhost:8000'));
      final generatedRows = List.generate(50, (i) => [i + 1, 'user_$i', 'user_$i@revvault.dev']);

      state.addAiMessage(AiAssistantMessage(
        role: 'assistant',
        content: 'Query result attached.',
        toolExecutions: [
          {
            'name': 'execute_safe_query',
            'arguments': {'sql': 'SELECT * FROM users;'},
            'output_preview': 'Retrieved 50 rows in 2.1ms',
            'success': true,
            'data': {
              'columns': ['id', 'username', 'email'],
              'rows': generatedRows,
              'row_count': 50,
              'execution_time_ms': 2.1,
              'sql': 'SELECT * FROM users;',
            },
          }
        ],
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(
            home: Scaffold(
              body: AiAssistantView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initial state: 10 rows per page
      expect(find.text('Showing 1–10 of 50 rows'), findsOneWidget);
      expect(find.text('Page 1 of 5'), findsOneWidget);

      // Tap on the page size dropdown
      final pageSizeDropdown = find.text('10 rows');
      expect(pageSizeDropdown, findsOneWidget);
      await tester.tap(pageSizeDropdown);
      await tester.pumpAndSettle();

      // Select '25 rows'
      final option25 = find.text('25 rows').last;
      await tester.tap(option25);
      await tester.pumpAndSettle();

      // Verify instantaneous update to 25 rows per page
      expect(find.text('Showing 1–25 of 50 rows'), findsOneWidget);
      expect(find.text('Page 1 of 2'), findsOneWidget);
    });

    test('AppState.setAvailableAiModels filters out unsafe models by default', () {
      final state = AppState(api: ApiService(baseUrl: 'http://localhost:8000'));
      
      final rawModels = [
        'gemma4:e4b',
        'qwen2.5-coder:7b',
        'llama3-unsafe:latest',
        'rogue-model-unsafe',
        'deepseek-coder:6.7b',
      ];

      // Default: unsafe models filtered out
      state.setAvailableAiModels(rawModels);
      expect(state.availableAiModels, ['gemma4:e4b', 'qwen2.5-coder:7b', 'deepseek-coder:6.7b']);

      // Explicitly allow unsafe models
      state.setAvailableAiModels(rawModels, lunarIncludeUnsafe: true);
      expect(state.availableAiModels, rawModels);
    });
  });
}

