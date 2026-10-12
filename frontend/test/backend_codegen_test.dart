import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rev_vault/services/backend_codegen_service.dart';
import 'package:rev_vault/state/app_state.dart';
import 'package:rev_vault/views/sql_editor_view.dart';
import 'package:rev_vault/views/widgets/api_generator_modal.dart';

void main() {
  group('BackendCodegenService Unit Tests', () {
    final service = BackendCodegenService();
    const testQuery = 'SELECT id, username, email FROM users WHERE id = :user_id AND status = :status;';

    test('Detects CRUD operation types correctly', () {
      expect(service.detectOperationType('SELECT * FROM users;'), equals('select'));
      expect(service.detectOperationType('INSERT INTO users (name) VALUES (:name);'), equals('insert'));
      expect(service.detectOperationType('UPDATE users SET name = :name WHERE id = :id;'), equals('update'));
      expect(service.detectOperationType('DELETE FROM users WHERE id = :id;'), equals('delete'));
    });

    test('Generates isolated function snippets for existing projects', () {
      const insertSql = 'INSERT INTO users (username, email) VALUES (:username, :email);';

      // PHP Native function snippet
      final phpSnippet = service.generateFunctionSnippet(
        framework: 'php_native',
        query: insertSql,
        endpointName: 'create_user',
        operationType: 'insert',
      );
      expect(phpSnippet, contains('function create_user(PDO \$pdo'));
      expect(phpSnippet, contains('lastInsertId'));

      // CodeIgniter 4 Model method snippet
      final ci4Snippet = service.generateFunctionSnippet(
        framework: 'ci4',
        query: insertSql,
        endpointName: 'create_user',
        operationType: 'insert',
      );
      expect(ci4Snippet, contains('public function create_user(array \$params = []): array|int'));
      expect(ci4Snippet, contains('insertID'));

      // FastAPI handler snippet
      final fastApiSnippet = service.generateFunctionSnippet(
        framework: 'fastapi',
        query: insertSql,
        endpointName: 'create_user',
        method: 'POST',
        operationType: 'insert',
      );
      expect(fastApiSnippet, contains('@app.post'));
      expect(fastApiSnippet, contains('async def create_user'));
    });

    test('Generates PHP Native with PDO bindings', () {
      final project = service.generate(
        framework: 'php_native',
        query: testQuery,
        endpointName: 'get_user_by_id',
        routePath: '/api/v1/user',
        method: 'GET',
      );

      expect(project.framework, equals('php_native'));
      expect(project.files.containsKey('index.php'), isTrue);
      expect(project.files.containsKey('db.php'), isTrue);
      expect(project.files.containsKey('README.md'), isTrue);
      expect(project.files['index.php'], contains('PDO::FETCH_ASSOC'));
      expect(project.files['index.php'], contains(':user_id'));
    });

    test('Generates CodeIgniter 4 Controller and Model', () {
      final project = service.generate(
        framework: 'ci4',
        query: testQuery,
        endpointName: 'get_users',
        routePath: '/api/v1/users',
        method: 'GET',
      );

      expect(project.framework, equals('ci4'));
      expect(project.files.containsKey('app/Controllers/ApiController.php'), isTrue);
      expect(project.files.containsKey('app/Models/QueryModel.php'), isTrue);
      expect(project.files['app/Controllers/ApiController.php'], contains('ResourceController'));
      expect(project.files['app/Models/QueryModel.php'], contains('executeCustomQuery'));
    });

    test('Generates CodeIgniter 3 Controller and Model', () {
      final project = service.generate(
        framework: 'ci3',
        query: testQuery,
        endpointName: 'get_users',
        routePath: '/api/v1/users',
        method: 'GET',
      );

      expect(project.framework, equals('ci3'));
      expect(project.files.containsKey('application/controllers/Api.php'), isTrue);
      expect(project.files.containsKey('application/models/Query_model.php'), isTrue);
    });

    test('Generates FastAPI with asyncpg and Pydantic', () {
      final project = service.generate(
        framework: 'fastapi',
        query: testQuery,
        endpointName: 'fetch_users',
        routePath: '/api/v1/users',
        method: 'GET',
      );

      expect(project.framework, equals('fastapi'));
      expect(project.files.containsKey('main.py'), isTrue);
      expect(project.files.containsKey('requirements.txt'), isTrue);
      expect(project.files['main.py'], contains('app.get("/api/v1/users"'));
      expect(project.files['main.py'], contains('async def fetch_users'));
    });

    test('Generates Express.js with pg pool and package.json', () {
      final project = service.generate(
        framework: 'express',
        query: testQuery,
        endpointName: 'fetch_users',
        routePath: '/api/v1/users',
        method: 'GET',
      );

      expect(project.framework, equals('express'));
      expect(project.files.containsKey('server.js'), isTrue);
      expect(project.files.containsKey('package.json'), isTrue);
      expect(project.files['server.js'], contains("app.get('/api/v1/users'"));
    });

    test('Generates Bun ElysiaJS with type-safe routing', () {
      final project = service.generate(
        framework: 'elysia',
        query: testQuery,
        endpointName: 'fetch_users',
        routePath: '/api/v1/users',
        method: 'GET',
      );

      expect(project.framework, equals('elysia'));
      expect(project.files.containsKey('src/index.ts'), isTrue);
      expect(project.files.containsKey('package.json'), isTrue);
    });

    test('Generates multi-operation function snippets and projects', () {
      final multiSnippet = service.generateFunctionSnippet(
        framework: 'fastapi',
        query: testQuery,
        endpointName: 'manage_users',
        operationTypes: ['select', 'insert'],
      );

      expect(multiSnippet, contains('1. SELECT Operation'));
      expect(multiSnippet, contains('2. INSERT Operation'));
      expect(multiSnippet, contains('@app.get'));
      expect(multiSnippet, contains('@app.post'));

      final multiProj = service.generate(
        framework: 'fastapi',
        query: testQuery,
        endpointName: 'manage_users',
        operationTypes: ['select', 'insert', 'update', 'delete'],
      );

      expect(multiProj.operationTypes.length, equals(4));
      expect(multiProj.functionSnippet, contains('4. DELETE Operation'));
    });

    test('Generates snippets and projects using tailored per-operation SQL queries', () {
      final customQueries = {
        'select': 'SELECT id, username FROM app_users WHERE active = true;',
        'insert': 'INSERT INTO app_users (username, email) VALUES (:username, :email);',
        'update': 'UPDATE app_users SET email = :email WHERE id = :id;',
        'delete': 'DELETE FROM app_users WHERE id = :id AND is_system = false;',
      };

      final snippet = service.generateFunctionSnippet(
        framework: 'fastapi',
        query: 'SELECT * FROM fallback;',
        endpointName: 'user_management',
        operationTypes: ['select', 'insert', 'update', 'delete'],
        operationQueries: customQueries,
      );

      expect(snippet, contains('SELECT id, username FROM app_users WHERE active = true;'));
      expect(snippet, contains('INSERT INTO app_users (username, email) VALUES (:username, :email);'));
      expect(snippet, contains('UPDATE app_users SET email = :email WHERE id = :id;'));
      expect(snippet, contains('DELETE FROM app_users WHERE id = :id AND is_system = false;'));

      final proj = service.generate(
        framework: 'fastapi',
        query: 'SELECT * FROM fallback;',
        endpointName: 'user_management',
        operationTypes: ['select', 'insert'],
        operationQueries: customQueries,
      );
      expect(proj.primaryCode, contains('SELECT id, username FROM app_users WHERE active = true;'));
    });
  });

  group('ApiGeneratorModal Widget Tests', () {
    testWidgets('Opens modal dialog, toggles multi-choice CRUD operations, and switches to Function Only mode', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = AppState();
      state.editorQueryText = 'SELECT * FROM users WHERE id = :user_id;';

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

      // Open Tools & Utilities bottom sheet
      expect(find.text('Tools & Utilities'), findsOneWidget);
      await tester.tap(find.text('Tools & Utilities'));
      await tester.pumpAndSettle();

      // Tap Generate Backend API
      expect(find.text('Generate Backend API'), findsOneWidget);
      await tester.tap(find.text('Generate Backend API'));
      await tester.pumpAndSettle();

      // Verify Modal Dialog is shown with CRUD operation selector
      expect(find.text('Auto Backend API & Function Generator'), findsOneWidget);
      expect(find.text('Operation Type:'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('SELECT'), findsOneWidget);
      expect(find.text('INSERT'), findsOneWidget);
      expect(find.text('UPDATE'), findsOneWidget);
      expect(find.text('DELETE'), findsOneWidget);

      // Verify Operation SQL Queries panel is rendered with per-operation controls
      expect(find.text('Operation SQL Queries'), findsOneWidget);
      expect(find.text('Use Editor SQL'), findsOneWidget);
      expect(find.text('Auto Template'), findsOneWidget);
      expect(find.text('Saved (0)'), findsOneWidget);
      expect(find.text('Put in...'), findsOneWidget);

      // Tap INSERT to toggle multi-choice (now both SELECT and INSERT are selected!)
      await tester.tap(find.text('INSERT'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('HTTP: GET | POST'), findsOneWidget);

      // Tap All CRUD quick action to select all 4
      await tester.tap(find.text('All CRUD'));
      await tester.pumpAndSettle();
      expect(find.text('4 selected'), findsOneWidget);

      // Switch to Function Only mode
      await tester.tap(find.text('Function Only'));
      await tester.pumpAndSettle();

      expect(find.text('Copy Function Snippet'), findsOneWidget);
      expect(find.text('Ready to paste into existing project'), findsOneWidget);

      // Switch back to Full Project mode
      await tester.tap(find.text('Full Project'));
      await tester.pumpAndSettle();

      expect(find.text('Download Project ZIP'), findsOneWidget);

      // Switch framework to Node.js Express
      await tester.ensureVisible(find.text('Node.js Express'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Node.js Express'));
      await tester.pumpAndSettle();

      // Verify Express server.js file tab is visible
      expect(find.text('server.js'), findsOneWidget);
      // Verify OpenAPI 3.1 Spec and Postman Collection exporter buttons
      expect(find.text('OpenAPI 3.1 Spec'), findsOneWidget);
      expect(find.text('Postman Collection'), findsOneWidget);

      // Close modal
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Auto Backend API & Function Generator'), findsNothing);
    });

    testWidgets('ApiGeneratorModal renders operation tabs with black text in Light Theme', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = AppState();
      state.editorQueryText = 'SELECT * FROM users;';

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: ChangeNotifierProvider<AppState>.value(
            value: state,
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showApiGeneratorModal(context, query: 'SELECT * FROM users'),
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      final selectTabText = tester.widget<Text>(find.text('SELECT (GET)'));
      expect(selectTabText.style?.color, equals(Colors.black));

      final insertTabText = tester.widget<Text>(find.text('INSERT (POST)'));
      expect(insertTabText.style?.color, equals(Colors.black87));
    });
  });
}
