import 'dart:convert';

/// Represents a query parameter extracted from SQL (e.g. :id, :status)
class ApiQueryParam {
  final String name;
  final String type; // 'string', 'int', 'boolean', 'date'
  final bool required;
  final String defaultValue;

  const ApiQueryParam({
    required this.name,
    this.type = 'string',
    this.required = true,
    this.defaultValue = '',
  });

  ApiQueryParam copyWith({
    String? name,
    String? type,
    bool? required,
    String? defaultValue,
  }) {
    return ApiQueryParam(
      name: name ?? this.name,
      type: type ?? this.type,
      required: required ?? this.required,
      defaultValue: defaultValue ?? this.defaultValue,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'required': required,
    'default': defaultValue,
  };
}

/// Holds the generated file map and function snippet for a project
class GeneratedApiProject {
  final String framework;
  final String endpointName;
  final String routePath;
  final String method;
  final String primaryFile;
  final String operationType;
  final List<String> operationTypes;
  final String functionSnippet;
  final Map<String, String> files;

  const GeneratedApiProject({
    required this.framework,
    required this.endpointName,
    required this.routePath,
    required this.method,
    required this.primaryFile,
    required this.files,
    this.operationType = 'select',
    this.operationTypes = const ['select'],
    this.functionSnippet = '',
  });

  String get primaryCode => files[primaryFile] ?? (files.isNotEmpty ? files.values.first : '');
}

/// Multi-Framework Backend API Code Generator Service (Client-Side)
class BackendCodegenService {
  static const List<Map<String, String>> supportedFrameworks = [
    {
      'id': 'php_native',
      'name': 'PHP Native (PDO)',
      'category': 'PHP',
      'ext': 'php',
      'desc': 'Clean PDO prepared statements with JSON responses and zero dependencies.',
    },
    {
      'id': 'ci4',
      'name': 'CodeIgniter 4',
      'category': 'PHP',
      'ext': 'php',
      'desc': 'ResourceController + QueryModel with modern PSR-4 namespaces.',
    },
    {
      'id': 'ci3',
      'name': 'CodeIgniter 3',
      'category': 'PHP',
      'ext': 'php',
      'desc': 'Classic CI_Controller & CI_Model with parameter binding.',
    },
    {
      'id': 'fastapi',
      'name': 'Python FastAPI',
      'category': 'Python',
      'ext': 'py',
      'desc': 'High-performance async ASGI with Pydantic validation and Swagger UI.',
    },
    {
      'id': 'python_native',
      'name': 'Python Native',
      'category': 'Python',
      'ext': 'py',
      'desc': 'Lightweight database script using psycopg2 / DB-API connector.',
    },
    {
      'id': 'express',
      'name': 'Node.js Express',
      'category': 'Node.js',
      'ext': 'js',
      'desc': 'Express.js router with connection pooling and async handlers.',
    },
    {
      'id': 'elysia',
      'name': 'Bun ElysiaJS',
      'category': 'Bun / TypeScript',
      'ext': 'ts',
      'desc': 'Ultra-fast type-safe REST endpoint powered by Bun runtime.',
    },
  ];

  /// Detects whether query is SELECT, INSERT, UPDATE, or DELETE
  String detectOperationType(String query) {
    final clean = query.trim().toUpperCase();
    if (clean.startsWith('INSERT')) return 'insert';
    if (clean.startsWith('UPDATE')) return 'update';
    if (clean.startsWith('DELETE')) return 'delete';
    return 'select';
  }

  /// Extracts the target table name from an SQL statement
  static String extractTableName(String query) {
    final match = RegExp(
      r'\b(?:FROM|INTO|UPDATE|TABLE)\s+([a-zA-Z0-9_".]+)',
      caseSensitive: false,
    ).firstMatch(query);
    if (match != null) {
      final raw = match.group(1) ?? 'records';
      return raw.replaceAll('"', '').split('.').last;
    }
    return 'records';
  }

  /// Default HTTP method associated with an operation
  static String defaultMethodForOp(String op) {
    switch (op.toLowerCase()) {
      case 'insert':
        return 'POST';
      case 'update':
        return 'PUT';
      case 'delete':
        return 'DELETE';
      case 'select':
      default:
        return 'GET';
    }
  }

  /// Sensible endpoint method name derived from base name and operation
  static String inferEndpointName(String baseName, String op) {
    final cleanOp = op.toLowerCase();
    final stripped = baseName.replaceFirst(
      RegExp(r'^(get|select|create|insert|update|delete|manage)_', caseSensitive: false),
      '',
    );
    final suffix = stripped.isEmpty ? 'records' : stripped;
    switch (cleanOp) {
      case 'select':
        return 'get_$suffix';
      case 'insert':
        return 'create_$suffix';
      case 'update':
        return 'update_$suffix';
      case 'delete':
        return 'delete_$suffix';
      default:
        return '${cleanOp}_$suffix';
    }
  }

  /// Constructs SQL for a specific operation if not matching the original query
  String getQueryForOperation(String originalQuery, String targetOp) {
    final clean = originalQuery.trim();
    final detected = detectOperationType(clean);
    if (detected == targetOp.toLowerCase()) {
      return clean;
    }
    final table = extractTableName(clean);
    final params = _extractParameters(clean);
    final paramNames = params.map((p) => p.name).toList();

    switch (targetOp.toLowerCase()) {
      case 'select':
        if (paramNames.isNotEmpty) {
          final where = paramNames.map((p) => '$p = :$p').join(' AND ');
          return 'SELECT * FROM $table WHERE $where;';
        }
        return 'SELECT * FROM $table LIMIT 100;';
      case 'insert':
        final cols = paramNames.isNotEmpty ? paramNames.join(', ') : 'name, status, created_at';
        final vals = paramNames.isNotEmpty ? paramNames.map((p) => ':$p').join(', ') : ':name, :status, NOW()';
        return 'INSERT INTO $table ($cols)\nVALUES ($vals);';
      case 'update':
        final updateParams = paramNames.where((p) => p != 'id').toList();
        final setClauses = updateParams.isNotEmpty
            ? updateParams.map((p) => '$p = :$p').join(', ')
            : 'status = :status, updated_at = NOW()';
        return 'UPDATE $table\nSET $setClauses\nWHERE id = :id;';
      case 'delete':
        return 'DELETE FROM $table\nWHERE id = :id;';
      default:
        return clean;
    }
  }

  /// Generates full project scaffolding for the requested framework and operation(s)
  GeneratedApiProject generate({
    required String framework,
    required String query,
    String endpointName = 'get_records',
    String routePath = '/api/v1/records',
    String method = 'GET',
    List<ApiQueryParam>? parameters,
    String dbType = 'postgresql',
    String? operationType,
    List<String>? operationTypes,
    Map<String, String>? operationQueries,
  }) {
    final params = parameters ?? _extractParameters(query);
    final fw = framework.toLowerCase().trim();
    final ops = (operationTypes != null && operationTypes.isNotEmpty)
        ? operationTypes.map((o) => o.toLowerCase().trim()).toList()
        : [(operationType ?? detectOperationType(query)).toLowerCase().trim()];
    final primaryOp = ops.first;

    final snippet = generateFunctionSnippet(
      framework: framework,
      query: query,
      endpointName: endpointName,
      routePath: routePath,
      method: method,
      parameters: params,
      dbType: dbType,
      operationType: primaryOp,
      operationTypes: ops,
      operationQueries: operationQueries,
    );

    // Resolve query for primary operation
    final primaryQuery = (operationQueries != null && operationQueries[primaryOp]?.trim().isNotEmpty == true)
        ? operationQueries[primaryOp]!.trim()
        : query;

    GeneratedApiProject baseProj;
    if (fw == 'ci4') {
      baseProj = _genCodeIgniter4(primaryQuery, endpointName, routePath, method, params, dbType, primaryOp);
    } else if (fw == 'ci3') {
      baseProj = _genCodeIgniter3(primaryQuery, endpointName, routePath, method, params, dbType, primaryOp);
    } else if (fw.contains('php')) {
      baseProj = _genPhpNative(primaryQuery, endpointName, routePath, method, params, dbType, primaryOp);
    } else if (fw == 'fastapi') {
      baseProj = _genFastApi(primaryQuery, endpointName, routePath, method, params, dbType, primaryOp);
    } else if (fw == 'python_native') {
      baseProj = _genPythonNative(primaryQuery, endpointName, routePath, method, params, dbType, primaryOp);
    } else if (fw.contains('express') || fw.contains('node')) {
      baseProj = _genExpress(primaryQuery, endpointName, routePath, method, params, dbType, primaryOp);
    } else if (fw.contains('elysia') || fw.contains('bun')) {
      baseProj = _genElysia(primaryQuery, endpointName, routePath, method, params, dbType, primaryOp);
    } else {
      baseProj = _genFastApi(primaryQuery, endpointName, routePath, method, params, dbType, primaryOp);
    }

    return GeneratedApiProject(
      framework: baseProj.framework,
      endpointName: baseProj.endpointName,
      routePath: baseProj.routePath,
      method: baseProj.method,
      primaryFile: baseProj.primaryFile,
      files: baseProj.files,
      operationType: primaryOp,
      operationTypes: ops,
      functionSnippet: snippet,
    );
  }

  /// Generates isolated function/method snippet ready to drop into an existing project
  String generateFunctionSnippet({
    required String framework,
    required String query,
    String endpointName = 'get_records',
    String routePath = '/api/v1/records',
    String method = 'GET',
    List<ApiQueryParam>? parameters,
    String dbType = 'postgresql',
    String? operationType,
    List<String>? operationTypes,
    Map<String, String>? operationQueries,
  }) {
    final ops = (operationTypes != null && operationTypes.isNotEmpty)
        ? operationTypes.map((o) => o.toLowerCase().trim()).toList()
        : [(operationType ?? detectOperationType(query)).toLowerCase().trim()];

    if (ops.length > 1) {
      final buffer = StringBuffer();
      for (int i = 0; i < ops.length; i++) {
        final currentOp = ops[i];
        final opEpName = inferEndpointName(endpointName, currentOp);
        final opMethod = defaultMethodForOp(currentOp);
        final opQuery = (operationQueries != null && operationQueries[currentOp]?.trim().isNotEmpty == true)
            ? operationQueries[currentOp]!.trim()
            : getQueryForOperation(query, currentOp);
        final opPath = (currentOp == 'update' || currentOp == 'delete')
            ? '${routePath.replaceAll(RegExp(r'/(:\w+|\{\w+\})$'), '')}/{id}'
            : routePath;

        final snippet = _generateSingleFunctionSnippet(
          framework: framework,
          query: opQuery,
          endpointName: opEpName,
          routePath: opPath,
          method: opMethod,
          parameters: parameters,
          dbType: dbType,
          operationType: currentOp,
        );
        buffer.writeln('// ==========================================');
        buffer.writeln('// ${i + 1}. ${currentOp.toUpperCase()} Operation ($opMethod $opPath)');
        buffer.writeln('// ==========================================');
        buffer.writeln(snippet);
        if (i < ops.length - 1) {
          buffer.writeln('\n');
        }
      }
      return buffer.toString();
    }

    final singleOp = ops.first;
    final singleQuery = (operationQueries != null && operationQueries[singleOp]?.trim().isNotEmpty == true)
        ? operationQueries[singleOp]!.trim()
        : query;

    return _generateSingleFunctionSnippet(
      framework: framework,
      query: singleQuery,
      endpointName: endpointName,
      routePath: routePath,
      method: method,
      parameters: parameters,
      dbType: dbType,
      operationType: singleOp,
    );
  }

  String _generateSingleFunctionSnippet({
    required String framework,
    required String query,
    String endpointName = 'get_records',
    String routePath = '/api/v1/records',
    String method = 'GET',
    List<ApiQueryParam>? parameters,
    String dbType = 'postgresql',
    String? operationType,
  }) {
    final fw = framework.toLowerCase().trim();
    final op = (operationType ?? detectOperationType(query)).toLowerCase().trim();
    final params = parameters ?? _extractParameters(query);
    final sql = query.trim();

    if (fw == 'ci4') {
      final ret = (op == 'select')
          ? 'return \$query->getResultArray();'
          : (op == 'insert')
              ? "return ['status' => 'success', 'insert_id' => \$db->insertID(), 'affected_rows' => \$db->affectedRows()];"
              : "return ['status' => 'success', 'affected_rows' => \$db->affectedRows()];";

      return '''/**
 * CodeIgniter 4 Model Method (${op.toUpperCase()})
 * Paste into app/Models/YourModel.php
 */
public function $endpointName(array \$params = []): array|int
{
    \$db = \\Config\\Database::connect();
    \$sql = <<<'SQL'
$sql
SQL;

    \$query = \$db->query(\$sql, \$params);
    $ret
}''';
    } else if (fw == 'ci3') {
      final ret = (op == 'select')
          ? 'return \$query->result_array();'
          : (op == 'insert')
              ? "return array('status' => 'success', 'insert_id' => \$this->db->insert_id(), 'affected_rows' => \$this->db->affected_rows());"
              : "return array('status' => 'success', 'affected_rows' => \$this->db->affected_rows());";

      return '''/**
 * CodeIgniter 3 Model Method (${op.toUpperCase()})
 * Paste into application/models/Your_model.php
 */
public function $endpointName(\$params = array())
{
    \$sql = <<<'SQL'
$sql
SQL;

    \$query = \$this->db->query(\$sql, \$params);
    $ret
}''';
    } else if (fw.contains('php')) {
      final ret = (op == 'select')
          ? 'return \$stmt->fetchAll(PDO::FETCH_ASSOC);'
          : (op == 'insert')
              ? "return ['status' => 'success', 'insert_id' => \$pdo->lastInsertId(), 'affected_rows' => \$stmt->rowCount()];"
              : "return ['status' => 'success', 'affected_rows' => \$stmt->rowCount()];";

      return '''/**
 * PHP Native Function (${op.toUpperCase()})
 * @param PDO \$pdo Active PDO connection
 * @param array \$params Parameter values
 */
function $endpointName(PDO \$pdo, array \$params = []): array
{
    \$sql = <<<'SQL'
$sql
SQL;

    \$stmt = \$pdo->prepare(\$sql);
    \$stmt->execute(\$params);
    $ret
}''';
    } else if (fw == 'fastapi') {
      final args = params.map((p) => "${p.name}: Optional[${p.type == 'int' ? 'int' : 'str'}] = None").join(', ');
      final body = (op == 'select')
          ? '''rows = await conn.fetch(sql)
        return {"status": "success", "count": len(rows), "data": [dict(r) for r in rows]}'''
          : '''res = await conn.execute(sql)
        return {"status": "success", "message": "Record ${op}d successfully", "result": res}''';

      return '''@app.${method.toLowerCase()}("$routePath", tags=["Auto-Generated API"])
async def $endpointName($args):
    """
    ${op.toUpperCase()} endpoint handler.
    """
    conn = await asyncpg.connect(DATABASE_URL)
    try:
        sql = """$sql"""
        $body
    finally:
        await conn.close()''';
    } else if (fw == 'python_native') {
      final execCode = (op == 'select')
          ? 'return cur.fetchall()'
          : "conn.commit()\n        return {'status': 'success', 'affected_rows': cur.rowcount}";

      return '''def $endpointName(conn, **params):
    """
    Executes ${op.toUpperCase()} query with active database connection.
    """
    with conn.cursor() as cur:
        sql = """$sql"""
        cur.execute(sql, params)
        $execCode''';
    } else if (fw.contains('express') || fw.contains('node')) {
      final resCode = (op == 'select')
          ? 'res.json({ status: "success", count: result.rows.length, data: result.rows });'
          : (op == 'insert')
              ? 'res.status(201).json({ status: "success", message: "Record created successfully", affected_rows: result.rowCount });'
              : 'res.json({ status: "success", message: "Record ${op}d successfully", affected_rows: result.rowCount });';

      return '''/**
 * Express Route Handler (${op.toUpperCase()} $routePath)
 */
app.${method.toLowerCase()}('$routePath', async (req, res) => {
  try {
    const sql = `$sql`;
    const result = await pool.query(sql);
    $resCode
  } catch (err) {
    console.error('$endpointName error:', err);
    res.status(500).json({ status: 'error', message: err.message });
  }
});''';
    } else if (fw.contains('elysia') || fw.contains('bun')) {
      final resCode = (op == 'select')
          ? 'return { status: "success", count: results.length, data: results };'
          : (op == 'insert')
              ? 'return { status: "success", message: "Record created", affected_rows: results.count };'
              : 'return { status: "success", message: "Record ${op}d", affected_rows: results.count };';

      return '''/**
 * ElysiaJS Route Handler (${op.toUpperCase()} $routePath)
 */
app.${method.toLowerCase()}('$routePath', async ({ set }) => {
  try {
    const results = await sql.unsafe(`$sql`);
    $resCode
  } catch (error: any) {
    set.status = 500;
    return { status: 'error', message: error.message };
  }
});''';
    }

    return '';
  }

  List<ApiQueryParam> _extractParameters(String query) {
    final named = RegExp(r':([a-zA-Z0-9_]+)').allMatches(query).map((m) => m.group(1)!).toList();
    final dollar = RegExp(r'\$(\d+)').allMatches(query).map((m) => 'param_${m.group(1)!}').toList();
    final qCount = '?'.allMatches(query).length;

    final result = <String>[];
    for (final n in named) {
      if (!result.contains(n)) result.add(n);
    }
    for (final d in dollar) {
      if (!result.contains(d)) result.add(d);
    }
    for (int i = 1; i <= qCount; i++) {
      final name = 'param_$i';
      if (!result.contains(name)) result.add(name);
    }

    return result.map((name) => ApiQueryParam(name: name)).toList();
  }

  // 1. PHP Native
  GeneratedApiProject _genPhpNative(String query, String ep, String path, String method, List<ApiQueryParam> params, String dbType, String op) {
    final readLines = params.map((p) => '    \$${p.name} = isset(\$_REQUEST["${p.name}"]) ? \$_REQUEST["${p.name}"] : null;').join('\n');
    final bindLines = params.map((p) {
      final bindType = (p.type == 'int') ? 'PDO::PARAM_INT' : (p.type == 'boolean' ? 'PDO::PARAM_BOOL' : 'PDO::PARAM_STR');
      return '    if (\$${p.name} !== null) {\n        \$stmt->bindValue(":${p.name}", \$${p.name}, $bindType);\n    }';
    }).join('\n');

    final execOutput = (op == 'select')
        ? '''    \$results = \$stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'status' => 'success',
        'count' => count(\$results),
        'data' => \$results
    ], JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);'''
        : (op == 'insert')
            ? '''    \$lastId = \$pdo->lastInsertId();
    http_response_code(201);
    echo json_encode([
        'status' => 'success',
        'message' => 'Record created successfully',
        'insert_id' => \$lastId,
        'affected_rows' => \$stmt->rowCount()
    ], JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);'''
            : '''    echo json_encode([
        'status' => 'success',
        'message' => 'Record ${op}d successfully',
        'affected_rows' => \$stmt->rowCount()
    ], JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);''';

    final indexPhp = '''<?php
/**
 * Auto-generated by RevVault API Studio
 * Operation: ${op.toUpperCase()}
 * Endpoint: $method $path
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if (\$_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once __DIR__ . '/db.php';

try {
    // 1. Read Input Parameters
$readLines

    // 2. Prepare SQL Statement
    \$sql = <<<'SQL'
${query.trim()}
SQL;

    \$stmt = \$pdo->prepare(\$sql);

    // 3. Bind Parameters
$bindLines

    // 4. Execute and Process Response
    \$stmt->execute();
$execOutput

} catch (PDOException \$e) {
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => \$e->getMessage()
    ]);
}
''';

    final dbPhp = '''<?php
\$host = getenv('DB_HOST') ?: '127.0.0.1';
\$port = getenv('DB_PORT') ?: '${dbType == "postgresql" ? "5432" : "3306"}';
\$dbname = getenv('DB_NAME') ?: 'rev_vault_db';
\$user = getenv('DB_USER') ?: 'postgres';
\$password = getenv('DB_PASS') ?: 'secret';

\$dsn = "${dbType == "postgresql" ? "pgsql:host=\$host;port=\$port;dbname=\$dbname;" : "mysql:host=\$host;port=\$port;dbname=\$dbname;charset=utf8mb4"}";

\$options = [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES => false,
];

try {
    \$pdo = new PDO(\$dsn, \$user, \$password, \$options);
} catch (PDOException \$e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Database connection failed: ' . \$e->getMessage()]);
    exit;
}
''';

    return GeneratedApiProject(
      framework: 'php_native',
      endpointName: ep,
      routePath: path,
      method: method,
      primaryFile: 'index.php',
      files: {
        'index.php': indexPhp,
        'db.php': dbPhp,
        '.env.example': 'DB_HOST=127.0.0.1\nDB_PORT=5432\nDB_NAME=rev_vault_db\nDB_USER=postgres\nDB_PASS=secret\n',
        'README.md': '# PHP Native API (${op.toUpperCase()})\n\nRun:\n```bash\nphp -S 0.0.0.0:8000\n```\n',
      },
    );
  }

  // 2. CodeIgniter 4
  GeneratedApiProject _genCodeIgniter4(String query, String ep, String path, String method, List<ApiQueryParam> params, String dbType, String op) {
    final reads = params.map((p) => "        \$${p.name} = \$this->request->getVar('${p.name}');").join('\n');
    final binds = params.map((p) => "            '${p.name}' => \$${p.name},").join('\n');

    final controllerReturn = (op == 'select')
        ? '''        return \$this->respond([
            'status' => 'success',
            'count' => count(\$results),
            'data' => \$results
        ]);'''
        : (op == 'insert')
            ? '''        return \$this->respondCreated([
            'status' => 'success',
            'message' => 'Record created successfully',
            'result' => \$results
        ]);'''
            : '''        return \$this->respond([
            'status' => 'success',
            'message' => 'Record ${op}d successfully',
            'result' => \$results
        ]);''';

    final modelReturn = (op == 'select')
        ? 'return \$query->getResultArray();'
        : (op == 'insert')
            ? "return ['insert_id' => \$db->insertID(), 'affected_rows' => \$db->affectedRows()];"
            : "return ['affected_rows' => \$db->affectedRows()];";

    final controller = '''<?php

namespace App\\Controllers;

use CodeIgniter\\RESTful\\ResourceController;
use App\\Models\\QueryModel;

class ApiController extends ResourceController
{
    protected \$format = 'json';

    public function $ep()
    {
        \$model = new QueryModel();

        // 1. Gather Request Parameters
$reads

        \$bindings = [
$binds
        ];

        // 2. Execute via Model
        \$results = \$model->executeCustomQuery(\$bindings);

$controllerReturn
    }
}
''';

    final model = '''<?php

namespace App\\Models;

use CodeIgniter\\Model;

class QueryModel extends Model
{
    public function executeCustomQuery(array \$params = []): array|int
    {
        \$db = \\Config\\Database::connect();
        
        \$sql = <<<'SQL'
${query.trim()}
SQL;

        \$query = \$db->query(\$sql, \$params);
        $modelReturn
    }
}
''';

    return GeneratedApiProject(
      framework: 'ci4',
      endpointName: ep,
      routePath: path,
      method: method,
      primaryFile: 'app/Controllers/ApiController.php',
      files: {
        'app/Controllers/ApiController.php': controller,
        'app/Models/QueryModel.php': model,
        'app/Config/Routes.php': "<?php\n\$routes->${method.toLowerCase()}('${path.replaceFirst('/', '')}', 'ApiController::$ep');\n",
        'README.md': '# CodeIgniter 4 API (${op.toUpperCase()})\n\nRun:\n```bash\nphp spark serve\n```\n',
      },
    );
  }

  // 3. CodeIgniter 3
  GeneratedApiProject _genCodeIgniter3(String query, String ep, String path, String method, List<ApiQueryParam> params, String dbType, String op) {
    final reads = params.map((p) => "        \$${p.name} = \$this->input->get_post('${p.name}', TRUE);").join('\n');
    final binds = params.map((p) => "            '${p.name}' => \$${p.name},").join('\n');

    final controllerReturn = (op == 'select')
        ? '''        echo json_encode(array(
            'status' => 'success',
            'count' => count(\$results),
            'data' => \$results
        ));'''
        : (op == 'insert')
            ? '''        echo json_encode(array(
            'status' => 'success',
            'message' => 'Record inserted successfully',
            'result' => \$results
        ));'''
            : '''        echo json_encode(array(
            'status' => 'success',
            'message' => 'Record ${op}d successfully',
            'result' => \$results
        ));''';

    final modelReturn = (op == 'select')
        ? 'return \$query->result_array();'
        : (op == 'insert')
            ? "return array('insert_id' => \$this->db->insert_id(), 'affected_rows' => \$this->db->affected_rows());"
            : "return array('affected_rows' => \$this->db->affected_rows());";

    final controller = '''<?php
defined('BASEPATH') OR exit('No direct script access allowed');

class Api extends CI_Controller {

    public function __construct()
    {
        parent::__construct();
        \$this->load->database();
        \$this->load->model('Query_model');
    }

    public function $ep()
    {
        header('Content-Type: application/json; charset=utf-8');

        // 1. Collect Input Parameters
$reads

        \$params = array(
$binds
        );

        // 2. Execute Query via Model
        \$results = \$this->Query_model->get_records(\$params);

$controllerReturn
    }
}
''';

    final model = '''<?php
defined('BASEPATH') OR exit('No direct script access allowed');

class Query_model extends CI_Model {

    public function get_records(\$params = array())
    {
        \$sql = <<<'SQL'
${query.trim()}
SQL;

        \$query = \$this->db->query(\$sql, \$params);
        $modelReturn
    }
}
''';

    return GeneratedApiProject(
      framework: 'ci3',
      endpointName: ep,
      routePath: path,
      method: method,
      primaryFile: 'application/controllers/Api.php',
      files: {
        'application/controllers/Api.php': controller,
        'application/models/Query_model.php': model,
        'README.md': '# CodeIgniter 3 API (${op.toUpperCase()})\n',
      },
    );
  }

  // 4. Python FastAPI
  GeneratedApiProject _genFastApi(String query, String ep, String path, String method, List<ApiQueryParam> params, String dbType, String op) {
    final paramArgs = params.map((p) => "${p.name}: Optional[${p.type == 'int' ? 'int' : 'str'}] = None").join(', ');

    final execBlock = (op == 'select')
        ? '''            rows = await conn.fetch(SQL_QUERY)
            results = [dict(r) for r in rows]
            return {
                "status": "success",
                "count": len(results),
                "data": results
            }'''
        : '''            status = await conn.execute(SQL_QUERY)
            return {
                "status": "success",
                "message": "Record ${op}d successfully",
                "result": status
            }''';

    final mainPy = '''from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional, List, Any, Dict
import os
import asyncpg

app = FastAPI(title="RevVault Generated API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:secret@localhost:5432/rev_vault_db")

SQL_QUERY = """${query.trim()}"""

@app.${method.toLowerCase()}("$path", tags=["Auto-Generated API"])
async def $ep($paramArgs):
    """
    Executes ${op.toUpperCase()} query with parameterized bindings.
    """
    try:
        conn = await asyncpg.connect(DATABASE_URL)
        try:
$execBlock
        finally:
            await conn.close()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
''';

    return GeneratedApiProject(
      framework: 'fastapi',
      endpointName: ep,
      routePath: path,
      method: method,
      primaryFile: 'main.py',
      files: {
        'main.py': mainPy,
        'requirements.txt': 'fastapi>=0.110.0\nuvicorn>=0.28.0\nasyncpg>=0.29.0\npydantic>=2.6.0\n',
        '.env.example': 'DATABASE_URL=postgresql://postgres:secret@localhost:5432/rev_vault_db\n',
        'README.md': '# FastAPI Service (${op.toUpperCase()})\n\nRun:\n```bash\npip install -r requirements.txt\npython main.py\n```\n',
      },
    );
  }

  // 5. Python Native
  GeneratedApiProject _genPythonNative(String query, String ep, String path, String method, List<ApiQueryParam> params, String dbType, String op) {
    final execLines = (op == 'select')
        ? '''            records = cur.fetchall()
            return records'''
        : '''            conn.commit()
            return {"status": "success", "affected_rows": cur.rowcount}''';

    final scriptPy = '''import os
import json
import psycopg2
from psycopg2.extras import RealDictCursor

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:secret@localhost:5432/rev_vault_db")

QUERY = """${query.trim()}"""

def $ep(**params):
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(QUERY, params)
$execLines
    finally:
        conn.close()

if __name__ == "__main__":
    data = $ep()
    print(json.dumps({"status": "success", "data": data}, indent=2, default=str))
''';

    return GeneratedApiProject(
      framework: 'python_native',
      endpointName: ep,
      routePath: path,
      method: method,
      primaryFile: 'script.py',
      files: {
        'script.py': scriptPy,
        'requirements.txt': 'psycopg2-binary>=2.9.9\n',
        'README.md': '# Python Native Query Script (${op.toUpperCase()})\n\nRun with `python script.py`\n',
      },
    );
  }

  // 6. Node.js Express
  GeneratedApiProject _genExpress(String query, String ep, String path, String method, List<ApiQueryParam> params, String dbType, String op) {
    final reads = params.map((p) => "    const ${p.name} = req.${method.toUpperCase() == 'GET' ? 'query' : 'body'}.${p.name};").join('\n');

    final resBlock = (op == 'select')
        ? '''    res.json({
      status: 'success',
      count: result.rows.length,
      data: result.rows,
    });'''
        : (op == 'insert')
            ? '''    res.status(201).json({
      status: 'success',
      message: 'Record created successfully',
      affected_rows: result.rowCount,
    });'''
            : '''    res.json({
      status: 'success',
      message: 'Record ${op}d successfully',
      affected_rows: result.rowCount,
    });''';

    final serverJs = '''const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://postgres:secret@localhost:5432/rev_vault_db',
});

const SQL_QUERY = `${query.trim()}`;

app.${method.toLowerCase()}('$path', async (req, res) => {
  try {
$reads
    const result = await pool.query(SQL_QUERY);
$resBlock
  } catch (err) {
    console.error('Database query error:', err);
    res.status(500).json({ status: 'error', message: err.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server listening on http://localhost:\${PORT}`);
});
''';

    final packageJson = jsonEncode({
      'name': 'rev-vault-$ep',
      'version': '1.0.0',
      'main': 'server.js',
      'scripts': {'start': 'node server.js', 'dev': 'nodemon server.js'},
      'dependencies': {'express': '^4.19.2', 'cors': '^2.8.5', 'pg': '^8.11.5', 'dotenv': '^16.4.5'},
      'devDependencies': {'nodemon': '^3.1.0'}
    });

    return GeneratedApiProject(
      framework: 'express',
      endpointName: ep,
      routePath: path,
      method: method,
      primaryFile: 'server.js',
      files: {
        'server.js': serverJs,
        'package.json': packageJson,
        '.env.example': 'DATABASE_URL=postgresql://postgres:secret@localhost:5432/rev_vault_db\nPORT=3000\n',
        'README.md': '# Express.js API (${op.toUpperCase()})\n\nRun:\n```bash\nnpm install\nnpm run dev\n```\n',
      },
    );
  }

  // 7. Bun ElysiaJS
  GeneratedApiProject _genElysia(String query, String ep, String path, String method, List<ApiQueryParam> params, String dbType, String op) {
    final resBlock = (op == 'select')
        ? '''      return {
        status: 'success',
        count: results.length,
        data: results,
      };'''
        : (op == 'insert')
            ? '''      return {
        status: 'success',
        message: 'Record created',
        affected_rows: results.count,
      };'''
            : '''      return {
        status: 'success',
        message: 'Record ${op}d',
        affected_rows: results.count,
      };''';

    final indexTs = '''import { Elysia } from 'elysia';
import { cors } from '@elysiajs/cors';
import postgres from 'postgres';

const sql = postgres(process.env.DATABASE_URL || 'postgresql://postgres:secret@localhost:5432/rev_vault_db');

const app = new Elysia()
  .use(cors())
  .${method.toLowerCase()}('$path', async ({ set }) => {
    try {
      const results = await sql.unsafe(`${query.trim()}`);
$resBlock
    } catch (error: any) {
      set.status = 500;
      return {
        status: 'error',
        message: error.message,
      };
    }
  })
  .listen(3000);

console.log(`🚀 Elysia running at http://\${app.server?.hostname}:\${app.server?.port}`);
''';

    final packageJson = jsonEncode({
      'name': 'elysia-$ep',
      'version': '1.0.0',
      'module': 'src/index.ts',
      'type': 'module',
      'scripts': {'dev': 'bun run --watch src/index.ts'},
      'dependencies': {'elysia': '^1.0.0', '@elysiajs/cors': '^1.0.0', 'postgres': '^3.4.4'},
      'devDependencies': {'@types/bun': 'latest'}
    });

    return GeneratedApiProject(
      framework: 'elysia',
      endpointName: ep,
      routePath: path,
      method: method,
      primaryFile: 'src/index.ts',
      files: {
        'src/index.ts': indexTs,
        'package.json': packageJson,
        'README.md': '# ElysiaJS API (Bun) (${op.toUpperCase()})\n\nRun:\n```bash\nbun install\nbun dev\n```\n',
      },
    );
  }
}
