"""
Multi-framework Backend API Code Generator for RevVault.
Supports:
- PHP Native (PDO)
- PHP CodeIgniter 4 (CI4)
- PHP CodeIgniter 3 (CI3)
- Python FastAPI
- Python Native
- Node.js Express.js
- Bun / TypeScript ElysiaJS

Supports CRUD operations:
- SELECT (Read)
- INSERT (Create)
- UPDATE (Update)
- DELETE (Delete)

Supports both:
- Full Project Scaffolding (ZIP / files)
- Function / Method Snippet Only
"""

from typing import Dict, List, Any, Optional
import re
import json

class BackendCodeGen:
    @staticmethod
    def detect_operation_type(query: str) -> str:
        """Detects if query is SELECT, INSERT, UPDATE, or DELETE."""
        clean = query.strip().upper()
        if clean.startswith("INSERT"):
            return "insert"
        elif clean.startswith("UPDATE"):
            return "update"
        elif clean.startswith("DELETE"):
            return "delete"
        return "select"

    @staticmethod
    def extract_parameters(query: str) -> List[str]:
        """Extracts parameters such as :param, $1, ? from the query."""
        named = re.findall(r":([a-zA-Z0-9_]+)", query)
        dollar = re.findall(r"\$(\d+)", query)
        qmarks = query.count("?")

        params = []
        for n in named:
            if n not in params:
                params.append(n)
        for d in dollar:
            var_name = f"param_{d}"
            if var_name not in params:
                params.append(var_name)
        for i in range(1, qmarks + 1):
            var_name = f"param_{i}"
            if var_name not in params:
                params.append(var_name)

        return params

    @staticmethod
    def extract_table_name(query: str) -> str:
        match = re.search(r'\b(?:FROM|INTO|UPDATE|TABLE)\s+([a-zA-Z0-9_".]+)', query, re.IGNORECASE)
        if match:
            raw = match.group(1).replace('"', '').split('.')[-1]
            return raw
        return "records"

    @staticmethod
    def default_method_for_op(op: str) -> str:
        op = op.lower()
        if op == "insert":
            return "POST"
        elif op == "update":
            return "PUT"
        elif op == "delete":
            return "DELETE"
        return "GET"

    @staticmethod
    def infer_endpoint_name(base_name: str, op: str) -> str:
        clean_op = op.lower()
        stripped = re.sub(r'^(get|select|create|insert|update|delete|manage)_', '', base_name, flags=re.IGNORECASE)
        suffix = stripped or "records"
        if clean_op == "select":
            return f"get_{suffix}"
        elif clean_op == "insert":
            return f"create_{suffix}"
        elif clean_op == "update":
            return f"update_{suffix}"
        elif clean_op == "delete":
            return f"delete_{suffix}"
        return f"{clean_op}_{suffix}"

    @classmethod
    def get_query_for_operation(cls, original_query: str, target_op: str) -> str:
        clean = original_query.strip()
        detected = cls.detect_operation_type(clean)
        if detected == target_op.lower():
            return clean
        table = cls.extract_table_name(clean)
        params = cls.extract_parameters(clean)

        target = target_op.lower()
        if target == "select":
            if params:
                where = " AND ".join([f"{p} = :{p}" for p in params])
                return f"SELECT * FROM {table} WHERE {where};"
            return f"SELECT * FROM {table} LIMIT 100;"
        elif target == "insert":
            cols = ", ".join(params) if params else "name, status, created_at"
            vals = ", ".join([f":{p}" for p in params]) if params else ":name, :status, NOW()"
            return f"INSERT INTO {table} ({cols})\nVALUES ({vals});"
        elif target == "update":
            update_params = [p for p in params if p != "id"]
            set_clauses = ", ".join([f"{p} = :{p}" for p in update_params]) if update_params else "status = :status, updated_at = NOW()"
            return f"UPDATE {table}\nSET {set_clauses}\nWHERE id = :id;"
        elif target == "delete":
            return f"DELETE FROM {table}\nWHERE id = :id;"
        return clean

    @classmethod
    def generate_project(
        cls,
        framework: str,
        query: str,
        endpoint_name: str = "get_records",
        route_path: str = "/api/v1/records",
        method: str = "GET",
        parameters: Optional[List[Dict[str, Any]]] = None,
        db_type: str = "postgresql",
        operation_type: Optional[str] = None,
        operation_types: Optional[List[str]] = None,
        operation_queries: Optional[Dict[str, str]] = None
    ) -> Dict[str, str]:
        """
        Generates complete file map { filepath: content } for a given framework.
        """
        fw = framework.lower().strip()
        params = parameters or []
        if not params:
            raw_params = cls.extract_parameters(query)
            params = [{"name": p, "type": "string", "required": True, "default": ""} for p in raw_params]

        ops = operation_types if (operation_types and len(operation_types) > 0) else [(operation_type or cls.detect_operation_type(query)).lower().strip()]
        
        # Build per-operation queries mapping
        resolved_queries = {}
        for op_item in ops:
            resolved_queries[op_item] = (
                operation_queries.get(op_item).strip()
                if operation_queries and operation_queries.get(op_item) and operation_queries.get(op_item).strip()
                else cls.get_query_for_operation(query, op_item)
            )

        op = ops[0]
        primary_query = resolved_queries[op]

        if "ci4" in fw or "codeigniter4" in fw:
            return cls._gen_codeigniter4(primary_query, endpoint_name, route_path, method, params, db_type, op)
        elif "ci3" in fw or "codeigniter3" in fw:
            return cls._gen_codeigniter3(primary_query, endpoint_name, route_path, method, params, db_type, op)
        elif "php" in fw:
            return cls._gen_php_native(primary_query, endpoint_name, route_path, method, params, db_type, op)
        elif "fastapi" in fw:
            return cls._gen_fastapi(primary_query, endpoint_name, route_path, method, params, db_type, op)
        elif "python" in fw:
            return cls._gen_python_native(primary_query, endpoint_name, route_path, method, params, db_type, op)
        elif "express" in fw or "node" in fw:
            return cls._gen_express(primary_query, endpoint_name, route_path, method, params, db_type, op)
        elif "elysia" in fw or "bun" in fw:
            return cls._gen_elysia(primary_query, endpoint_name, route_path, method, params, db_type, op)
        else:
            return cls._gen_fastapi(primary_query, endpoint_name, route_path, method, params, db_type, op)

    @classmethod
    def generate_function_snippet(
        cls,
        framework: str,
        query: str,
        endpoint_name: str = "get_records",
        route_path: str = "/api/v1/records",
        method: str = "GET",
        parameters: Optional[List[Dict[str, Any]]] = None,
        db_type: str = "postgresql",
        operation_type: Optional[str] = None,
        operation_types: Optional[List[str]] = None,
        operation_queries: Optional[Dict[str, str]] = None
    ) -> str:
        """
        Generates isolated function/method snippet(s) ready to drop into an existing project.
        """
        ops = operation_types if (operation_types and len(operation_types) > 0) else [(operation_type or cls.detect_operation_type(query)).lower().strip()]
        if len(ops) > 1:
            snippets = []
            for i, current_op in enumerate(ops):
                op_ep_name = cls.infer_endpoint_name(endpoint_name, current_op)
                op_method = cls.default_method_for_op(current_op)
                op_query = (
                    operation_queries.get(current_op).strip()
                    if operation_queries and operation_queries.get(current_op) and operation_queries.get(current_op).strip()
                    else cls.get_query_for_operation(query, current_op)
                )
                op_path = f"{route_path.rstrip('/')}/{{id}}" if current_op in ["update", "delete"] else route_path
                snip = cls._generate_single_function_snippet(
                    framework=framework,
                    query=op_query,
                    endpoint_name=op_ep_name,
                    route_path=op_path,
                    method=op_method,
                    parameters=parameters,
                    db_type=db_type,
                    operation_type=current_op
                )
                header = f"// ==========================================\n// {i + 1}. {current_op.upper()} Operation ({op_method} {op_path})\n// =========================================="
                snippets.append(f"{header}\n{snip}")
            return "\n\n".join(snippets)

        single_op = ops[0]
        single_query = (
            operation_queries.get(single_op).strip()
            if operation_queries and operation_queries.get(single_op) and operation_queries.get(single_op).strip()
            else query
        )
        return cls._generate_single_function_snippet(
            framework=framework,
            query=single_query,
            endpoint_name=endpoint_name,
            route_path=route_path,
            method=method,
            parameters=parameters,
            db_type=db_type,
            operation_type=single_op
        )

    @classmethod
    def _generate_single_function_snippet(
        cls,
        framework: str,
        query: str,
        endpoint_name: str = "get_records",
        route_path: str = "/api/v1/records",
        method: str = "GET",
        parameters: Optional[List[Dict[str, Any]]] = None,
        db_type: str = "postgresql",
        operation_type: Optional[str] = None
    ) -> str:
        fw = framework.lower().strip()
        params = parameters or []
        if not params:
            raw_params = cls.extract_parameters(query)
            params = [{"name": p, "type": "string", "required": True, "default": ""} for p in raw_params]
        op = (operation_type or cls.detect_operation_type(query)).lower().strip()
        sql_clean = query.strip()

        if "ci4" in fw:
            if op == "select":
                return_code = "return $query->getResultArray();"
            elif op == "insert":
                return_code = "return ['status' => 'success', 'insert_id' => $db->insertID(), 'affected_rows' => $db->affectedRows()];"
            else:
                return_code = f"return ['status' => 'success', 'affected_rows' => $db->affectedRows()];"

            return f"""/**
 * CodeIgniter 4 Model Method ({op.upper()})
 * Paste into app/Models/YourModel.php
 */
public function {endpoint_name}(array $params = []): array|int
{{
    $db = \\Config\\Database::connect();
    $sql = <<<'SQL'
{sql_clean}
SQL;

    $query = $db->query($sql, $params);
    {return_code}
}}"""

        elif "ci3" in fw:
            if op == "select":
                return_code = "return $query->result_array();"
            elif op == "insert":
                return_code = "return array('status' => 'success', 'insert_id' => $this->db->insert_id(), 'affected_rows' => $this->db->affected_rows());"
            else:
                return_code = "return array('status' => 'success', 'affected_rows' => $this->db->affected_rows());"

            return f"""/**
 * CodeIgniter 3 Model Method ({op.upper()})
 * Paste into application/models/Your_model.php
 */
public function {endpoint_name}($params = array())
{{
    $sql = <<<'SQL'
{sql_clean}
SQL;

    $query = $this->db->query($sql, $params);
    {return_code}
}}"""

        elif "php" in fw:
            if op == "select":
                fetch_code = "return $stmt->fetchAll(PDO::FETCH_ASSOC);"
            elif op == "insert":
                fetch_code = "return ['status' => 'success', 'insert_id' => $pdo->lastInsertId(), 'affected_rows' => $stmt->rowCount()];"
            else:
                fetch_code = f"return ['status' => 'success', 'affected_rows' => $stmt->rowCount()];"

            return f"""/**
 * PHP Function ({op.upper()})
 * @param PDO $pdo Active PDO connection
 * @param array $params Parameter values associative array
 */
function {endpoint_name}(PDO $pdo, array $params = []): array
{{
    $sql = <<<'SQL'
{sql_clean}
SQL;

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    {fetch_code}
}}"""

        elif "fastapi" in fw:
            param_args = ", ".join([f"{p['name']}: Optional[{'int' if p.get('type') in ('int', 'integer') else 'str'}] = None" for p in params])
            decorator = f"@app.{method.lower()}"
            if op == "select":
                body_code = """rows = await conn.fetch(sql)
        return {"status": "success", "count": len(rows), "data": [dict(r) for r in rows]}"""
            elif op == "insert":
                body_code = """res = await conn.execute(sql)
        return {"status": "success", "message": "Record inserted successfully", "result": res}"""
            else:
                body_code = f"""res = await conn.execute(sql)
        return {{"status": "success", "message": "Record {op}d successfully", "result": res}}"""

            return f"""{decorator}("{route_path}", tags=["Auto-Generated API"])
async def {endpoint_name}({param_args}):
    \"\"\"
    {op.upper()} endpoint handler.
    \"\"\"
    conn = await asyncpg.connect(DATABASE_URL)
    try:
        sql = \"\"\"{sql_clean}\"\"\"
        {body_code}
    finally:
        await conn.close()"""

        elif "python" in fw:
            if op == "select":
                exec_code = "return cur.fetchall()"
            elif op == "insert":
                exec_code = "conn.commit()\n        return {'status': 'success', 'affected_rows': cur.rowcount}"
            else:
                exec_code = f"conn.commit()\n        return {{'status': 'success', 'affected_rows': cur.rowcount}}"

            return f"""def {endpoint_name}(conn, **params):
    \"\"\"
    Executes {op.upper()} query with active database connection.
    \"\"\"
    with conn.cursor() as cur:
        sql = \"\"\"{sql_clean}\"\"\"
        cur.execute(sql, params)
        {exec_code}"""

        elif "express" in fw or "node" in fw:
            if op == "select":
                res_code = "res.json({ status: 'success', count: result.rows.length, data: result.rows });"
            elif op == "insert":
                res_code = "res.status(201).json({ status: 'success', message: 'Record created successfully', affected_rows: result.rowCount });"
            else:
                res_code = f"res.json({{ status: 'success', message: 'Record {op}d successfully', affected_rows: result.rowCount }});"

            return f"""/**
 * Express Route Handler ({op.upper()} {route_path})
 */
app.{method.lower()}('{route_path}', async (req, res) => {{
  try {{
    const sql = `{sql_clean}`;
    const result = await pool.query(sql);
    {res_code}
  }} catch (err) {{
    console.error('{endpoint_name} error:', err);
    res.status(500).json({{ status: 'error', message: err.message }});
  }}
}});"""

        elif "elysia" in fw or "bun" in fw:
            if op == "select":
                res_code = "return { status: 'success', count: results.length, data: results };"
            elif op == "insert":
                res_code = "return { status: 'success', message: 'Record created', affected_rows: results.count };"
            else:
                res_code = f"return {{ status: 'success', message: 'Record {op}d', affected_rows: results.count }};"

            return f"""/**
 * ElysiaJS Route Handler ({op.upper()} {route_path})
 */
app.{method.lower()}('{route_path}', async ({{ set }}) => {{
  try {{
    const results = await sql.unsafe(`{sql_clean}`);
    {res_code}
  }} catch (error: any) {{
    set.status = 500;
    return {{ status: 'error', message: error.message }};
  }}
}});"""

        return ""

    # -------------------------------------------------------------
    # 1. PHP Native (PDO)
    # -------------------------------------------------------------
    @classmethod
    def _gen_php_native(cls, query: str, ep: str, path: str, method: str, params: List[Dict[str, Any]], db_type: str, op: str) -> Dict[str, str]:
        bind_lines = []
        param_reads = []
        for p in params:
            name = p["name"]
            ptype = p.get("type", "string")
            param_reads.append(f'${name} = isset($_REQUEST["{name}"]) ? $_REQUEST["{name}"] : null;')
            bind_type = "PDO::PARAM_STR"
            if ptype in ("int", "integer"):
                bind_type = "PDO::PARAM_INT"
            elif ptype in ("bool", "boolean"):
                bind_type = "PDO::PARAM_BOOL"
            bind_lines.append(f'    if (${name} !== null) {{\n        $stmt->bindValue(":{name}", ${name}, {bind_type});\n    }}')

        bind_code = "\n".join(bind_lines)
        read_code = "\n".join(param_reads)

        if op == "select":
            exec_output = """    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'status' => 'success',
        'count' => count($results),
        'data' => $results
    ], JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);"""
        elif op == "insert":
            exec_output = """    $lastId = $pdo->lastInsertId();
    http_response_code(201);
    echo json_encode([
        'status' => 'success',
        'message' => 'Record created successfully',
        'insert_id' => $lastId,
        'affected_rows' => $stmt->rowCount()
    ], JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);"""
        else:
            exec_output = f"""    echo json_encode([
        'status' => 'success',
        'message' => 'Record {op}d successfully',
        'affected_rows' => $stmt->rowCount()
    ], JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);"""

        index_php = f"""<?php
/**
 * Auto-generated by RevVault API Studio
 * Operation: {op.upper()}
 * Endpoint: {method} {path}
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {{
    http_response_code(204);
    exit;
}}

require_once __DIR__ . '/db.php';

try {{
    // 1. Read Input Parameters
{read_code}

    // 2. Prepare SQL Statement
    $sql = <<<'SQL'
{query.strip()}
SQL;

    $stmt = $pdo->prepare($sql);

    // 3. Bind Parameters
{bind_code}

    // 4. Execute and Process Response
    $stmt->execute();
{exec_output}

}} catch (PDOException $e) {{
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}}
"""

        db_php = f"""<?php
// Database configuration & PDO factory
$host = getenv('DB_HOST') ?: '127.0.0.1';
$port = getenv('DB_PORT') ?: '{"5432" if db_type == "postgresql" else "3306"}';
$dbname = getenv('DB_NAME') ?: 'rev_vault_db';
$user = getenv('DB_USER') ?: 'postgres';
$password = getenv('DB_PASS') ?: 'secret';

{"$dsn = \"pgsql:host=$host;port=$port;dbname=$dbname;\";" if db_type == "postgresql" else "$dsn = \"mysql:host=$host;port=$port;dbname=$dbname;charset=utf8mb4\";"}

$options = [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES => false,
];

try {{
    $pdo = new PDO($dsn, $user, $password, $options);
}} catch (PDOException $e) {{
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Database connection failed: ' . $e->getMessage()]);
    exit;
}}
"""

        return {
            "index.php": index_php,
            "db.php": db_php,
            ".env.example": f"DB_HOST=127.0.0.1\nDB_PORT=5432\nDB_NAME=rev_vault_db\nDB_USER=postgres\nDB_PASS=secret\n",
            "README.md": f"# PHP Native API Endpoint ({op.upper()})\n\nRun:\n```bash\nphp -S 0.0.0.0:8000\n```\n"
        }

    # -------------------------------------------------------------
    # 2. PHP CodeIgniter 4 (CI4)
    # -------------------------------------------------------------
    @classmethod
    def _gen_codeigniter4(cls, query: str, ep: str, path: str, method: str, params: List[Dict[str, Any]], db_type: str, op: str) -> Dict[str, str]:
        param_reads = []
        bind_array = []
        for p in params:
            name = p["name"]
            param_reads.append(f"        ${name} = $this->request->getVar('{name}');")
            bind_array.append(f"            '{name}' => ${name},")

        param_read_str = "\n".join(param_reads)
        bind_array_str = "\n".join(bind_array)

        if op == "select":
            controller_return = """        return $this->respond([
            'status' => 'success',
            'count' => count($results),
            'data' => $results
        ]);"""
            model_return = "return $query->getResultArray();"
        elif op == "insert":
            controller_return = """        return $this->respondCreated([
            'status' => 'success',
            'message' => 'Record created successfully',
            'result' => $results
        ]);"""
            model_return = "return ['insert_id' => $db->insertID(), 'affected_rows' => $db->affectedRows()];"
        else:
            controller_return = f"""        return $this->respond([
            'status' => 'success',
            'message' => 'Record {op}d successfully',
            'result' => $results
        ]);"""
            model_return = "return ['affected_rows' => $db->affectedRows()];"

        controller = f"""<?php

namespace App\\\\Controllers;

use CodeIgniter\\\\RESTful\\\\ResourceController;
use App\\\\Models\\\\QueryModel;

class ApiController extends ResourceController
{{
    protected $format = 'json';

    public function {ep}()
    {{
        $model = new QueryModel();

        // 1. Gather Request Parameters
{param_read_str}

        $bindings = [
{bind_array_str}
        ];

        // 2. Execute via Model
        $results = $model->executeCustomQuery($bindings);

{controller_return}
    }}
}}
"""

        model = f"""<?php

namespace App\\\\Models;

use CodeIgniter\\\\Model;

class QueryModel extends Model
{{
    public function executeCustomQuery(array $params = []): array|int
    {{
        $db = \\\\Config\\\\Database::connect();
        
        $sql = <<<'SQL'
{query.strip()}
SQL;

        $query = $db->query($sql, $params);
        {model_return}
    }}
}}
"""

        return {
            "app/Controllers/ApiController.php": controller,
            "app/Models/QueryModel.php": model,
            "app/Config/Routes.php": f"<?php\n$routes->{method.lower()}('{path.lstrip('/')}', 'ApiController::{ep}');\n",
            "README.md": f"# CodeIgniter 4 API Endpoint ({op.upper()})\n\nRun:\n```bash\nphp spark serve\n```\n"
        }

    # -------------------------------------------------------------
    # 3. PHP CodeIgniter 3 (CI3)
    # -------------------------------------------------------------
    @classmethod
    def _gen_codeigniter3(cls, query: str, ep: str, path: str, method: str, params: List[Dict[str, Any]], db_type: str, op: str) -> Dict[str, str]:
        param_reads = []
        bind_array = []
        for p in params:
            name = p["name"]
            param_reads.append(f"        ${name} = $this->input->get_post('{name}', TRUE);")
            bind_array.append(f"            '{name}' => ${name},")

        param_read_str = "\n".join(param_reads)
        bind_array_str = "\n".join(bind_array)

        if op == "select":
            exec_return = "return $query->result_array();"
            controller_return = """        echo json_encode(array(
            'status' => 'success',
            'count' => count($results),
            'data' => $results
        ));"""
        elif op == "insert":
            exec_return = "return array('insert_id' => $this->db->insert_id(), 'affected_rows' => $this->db->affected_rows());"
            controller_return = """        echo json_encode(array(
            'status' => 'success',
            'message' => 'Record inserted successfully',
            'result' => $results
        ));"""
        else:
            exec_return = "return array('affected_rows' => $this->db->affected_rows());"
            controller_return = f"""        echo json_encode(array(
            'status' => 'success',
            'message' => 'Record {op}d successfully',
            'result' => $results
        ));"""

        controller = f"""<?php
defined('BASEPATH') OR exit('No direct script access allowed');

class Api extends CI_Controller {{

    public function __construct()
    {{
        parent::__construct();
        $this->load->database();
        $this->load->model('Query_model');
    }}

    public function {ep}()
    {{
        header('Content-Type: application/json; charset=utf-8');

        // 1. Collect Input Parameters
{param_read_str}

        $params = array(
{bind_array_str}
        );

        // 2. Execute Query via Model
        $results = $this->Query_model->get_records($params);

{controller_return}
    }}
}}
"""

        model = f"""<?php
defined('BASEPATH') OR exit('No direct script access allowed');

class Query_model extends CI_Model {{

    public function get_records($params = array())
    {{
        $sql = <<<'SQL'
{query.strip()}
SQL;

        $query = $this->db->query($sql, $params);
        {exec_return}
    }}
}}
"""

        return {
            "application/controllers/Api.php": controller,
            "application/models/Query_model.php": model,
            "README.md": f"# CodeIgniter 3 API Endpoint ({op.upper()})\n"
        }

    # -------------------------------------------------------------
    # 4. Python FastAPI
    # -------------------------------------------------------------
    @classmethod
    def _gen_fastapi(cls, query: str, ep: str, path: str, method: str, params: List[Dict[str, Any]], db_type: str, op: str) -> Dict[str, str]:
        param_fields = []
        for p in params:
            name = p["name"]
            ptype = "int" if p.get("type") in ("int", "integer") else "str"
            param_fields.append(f"    {name}: Optional[{ptype}] = None")

        schema_class = ""
        if param_fields:
            schema_class = f"""class RequestParams(BaseModel):\n""" + "\n".join(param_fields) + "\n\n"

        if op == "select":
            exec_block = """            rows = await conn.fetch(SQL_QUERY)
            results = [dict(r) for r in rows]
            return {
                "status": "success",
                "count": len(results),
                "data": results
            }"""
        elif op == "insert":
            exec_block = """            status = await conn.execute(SQL_QUERY)
            return {
                "status": "success",
                "message": "Record created successfully",
                "result": status
            }"""
        else:
            exec_block = f"""            status = await conn.execute(SQL_QUERY)
            return {{
                "status": "success",
                "message": "Record {op}d successfully",
                "result": status
            }}"""

        main_py = f"""from fastapi import FastAPI, Depends, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
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

async def get_db_pool():
    pool = await asyncpg.create_pool(DATABASE_URL)
    try:
        yield pool
    finally:
        await pool.close()

{schema_class}SQL_QUERY = \"\"\"{query.strip()}\"\"\"

{"@app.get" if method.upper() == "GET" else "@app.post" if method.upper() == "POST" else f"@app.{method.lower()}"}("{path}", tags=["Auto-Generated API"])
async def {ep}(
    {", ".join([f"{p['name']}: Optional[str] = None" for p in params]) if params else ""}
):
    \"\"\"
    Executes {op.upper()} query with parameterized bindings.
    \"\"\"
    try:
        conn = await asyncpg.connect(DATABASE_URL)
        try:
{exec_block}
        finally:
            await conn.close()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
"""

        requirements = f"""fastapi>=0.110.0\nuvicorn>=0.28.0\nasyncpg>=0.29.0\npydantic>=2.6.0\npython-dotenv>=1.0.0\n"""

        return {
            "main.py": main_py,
            "requirements.txt": requirements,
            ".env.example": "DATABASE_URL=postgresql://postgres:secret@localhost:5432/rev_vault_db\n",
            "README.md": f"# FastAPI Service ({op.upper()})\n\nRun:\n```bash\npip install -r requirements.txt\npython main.py\n```\n"
        }

    # -------------------------------------------------------------
    # 5. Python Native
    # -------------------------------------------------------------
    @classmethod
    def _gen_python_native(cls, query: str, ep: str, path: str, method: str, params: List[Dict[str, Any]], db_type: str, op: str) -> Dict[str, str]:
        if op == "select":
            exec_lines = """            records = cur.fetchall()
            return records"""
        else:
            exec_lines = f"""            conn.commit()
            return {{"status": "success", "affected_rows": cur.rowcount}}"""

        script = f"""import os
import json
import psycopg2
from psycopg2.extras import RealDictCursor

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:secret@localhost:5432/rev_vault_db")

QUERY = \"\"\"{query.strip()}\"\"\"

def {ep}(**params):
    conn = psycopg2.connect(DATABASE_URL)
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(QUERY, params)
{exec_lines}
    finally:
        conn.close()

if __name__ == "__main__":
    data = {ep}()
    print(json.dumps({{"status": "success", "data": data}}, indent=2, default=str))
"""
        return {
            "script.py": script,
            "requirements.txt": "psycopg2-binary>=2.9.9\n",
            "README.md": f"# Python Native Database Script ({op.upper()})\n"
        }

    # -------------------------------------------------------------
    # 6. Node.js Express.js
    # -------------------------------------------------------------
    @classmethod
    def _gen_express(cls, query: str, ep: str, path: str, method: str, params: List[Dict[str, Any]], db_type: str, op: str) -> Dict[str, str]:
        param_reads = []
        for p in params:
            name = p["name"]
            param_reads.append(f"    const {name} = req.{'query' if method.upper() == 'GET' else 'body'}.{name};")

        if op == "select":
            res_block = """    res.json({
      status: 'success',
      count: result.rows.length,
      data: result.rows,
    });"""
        elif op == "insert":
            res_block = """    res.status(201).json({
      status: 'success',
      message: 'Record created successfully',
      affected_rows: result.rowCount,
    });"""
        else:
            res_block = f"""    res.json({{
      status: 'success',
      message: 'Record {op}d successfully',
      affected_rows: result.rowCount,
    }});"""

        server_js = f"""const express = require('express');
const cors = require('cors');
const {{ Pool }} = require('pg');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

const pool = new Pool({{
  connectionString: process.env.DATABASE_URL || 'postgresql://postgres:secret@localhost:5432/rev_vault_db',
}});

const SQL_QUERY = `{query.strip()}`;

app.{method.lower()}('{path}', async (req, res) => {{
  try {{
{chr(10).join(param_reads)}
    const result = await pool.query(SQL_QUERY);
{res_block}
  }} catch (err) {{
    console.error('Database query error:', err);
    res.status(500).json({{ status: 'error', message: err.message }});
  }}
}});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {{
  console.log(`Server listening on http://localhost:${{PORT}}`);
}});
"""

        package_json = json.dumps({
            "name": f"rev-vault-{ep}",
            "version": "1.0.0",
            "main": "server.js",
            "scripts": {"start": "node server.js", "dev": "nodemon server.js"},
            "dependencies": {"express": "^4.19.2", "cors": "^2.8.5", "pg": "^8.11.5", "dotenv": "^16.4.5"},
            "devDependencies": {"nodemon": "^3.1.0"}
        }, indent=2)

        return {
            "server.js": server_js,
            "package.json": package_json,
            ".env.example": "DATABASE_URL=postgresql://postgres:secret@localhost:5432/rev_vault_db\nPORT=3000\n",
            "README.md": f"# Express.js API Service ({op.upper()})\n"
        }

    # -------------------------------------------------------------
    # 7. Bun / TypeScript ElysiaJS
    # -------------------------------------------------------------
    @classmethod
    def _gen_elysia(cls, query: str, ep: str, path: str, method: str, params: List[Dict[str, Any]], db_type: str, op: str) -> Dict[str, str]:
        if op == "select":
            res_block = """      return {
        status: 'success',
        count: results.length,
        data: results,
      };"""
        elif op == "insert":
            res_block = """      return {
        status: 'success',
        message: 'Record created successfully',
        affected_rows: results.count,
      };"""
        else:
            res_block = f"""      return {{
        status: 'success',
        message: 'Record {op}d successfully',
        affected_rows: results.count,
      }};"""

        index_ts = f"""import {{ Elysia }} from 'elysia';
import {{ cors }} from '@elysiajs/cors';
import postgres from 'postgres';

const sql = postgres(process.env.DATABASE_URL || 'postgresql://postgres:secret@localhost:5432/rev_vault_db');

const app = new Elysia()
  .use(cors())
  .{method.lower()}('{path}', async ({{ set }}) => {{
    try {{
      const results = await sql.unsafe(`{query.strip()}`);
{res_block}
    }} catch (error: any) {{
      set.status = 500;
      return {{
        status: 'error',
        message: error.message,
      }};
    }}
  }})
  .listen(3000);

console.log(`🚀 Elysia running at http://${{app.server?.hostname}}:${{app.server?.port}}`);
"""

        package_json = json.dumps({
            "name": f"elysia-{ep}",
            "version": "1.0.0",
            "module": "src/index.ts",
            "type": "module",
            "scripts": {"dev": "bun run --watch src/index.ts"},
            "dependencies": {"elysia": "^1.0.0", "@elysiajs/cors": "^1.0.0", "postgres": "^3.4.4"},
            "devDependencies": {"@types/bun": "latest"}
        }, indent=2)

        return {
            "src/index.ts": index_ts,
            "package.json": package_json,
            "README.md": f"# ElysiaJS (Bun) API Service ({op.upper()})\n"
        }

    @classmethod
    def generate_openapi_spec(
        cls,
        query: str,
        endpoint_name: str = "get_records",
        route_path: str = "/api/v1/records",
        method: str = "GET",
        parameters: Optional[List[Dict[str, Any]]] = None,
        db_type: str = "postgresql",
        summary: Optional[str] = None,
        tags: Optional[List[str]] = None,
        operation_types: Optional[List[str]] = None,
        operation_queries: Optional[Dict[str, str]] = None
    ) -> Dict[str, Any]:
        clean_name = endpoint_name.strip().replace(" ", "_")
        ops = operation_types if (operation_types and len(operation_types) > 0) else [cls.detect_operation_type(query)]
        tag_list = tags or ["Database Service"]

        paths_dict: Dict[str, Any] = {}
        clean_route = "/" + route_path.strip("/")

        for op in ops:
            op_method = cls.default_method_for_op(op)
            op_id = cls.infer_endpoint_name(clean_name, op)
            op_summary = summary or f"{op.upper()} database records"

            # Parse parameters
            query_params = []
            body_props: Dict[str, Any] = {}
            body_required: List[str] = []

            if parameters:
                for p in parameters:
                    p_name = p.get("name", "param")
                    p_type = p.get("type", "string")
                    p_req = p.get("required", False)
                    schema_type = "integer" if p_type in ("int", "integer") else ("number" if p_type in ("float", "double", "real") else "string")

                    if op_method in ("GET", "DELETE"):
                        query_params.append({
                            "name": p_name,
                            "in": "query",
                            "required": p_req,
                            "schema": {"type": schema_type, "default": p.get("default", "")},
                            "description": f"Query filter for {p_name}"
                        })
                    else:
                        body_props[p_name] = {
                            "type": schema_type,
                            "default": p.get("default", ""),
                            "description": f"Field value for {p_name}"
                        }
                        if p_req:
                            body_required.append(p_name)

            op_def: Dict[str, Any] = {
                "tags": tag_list,
                "summary": op_summary,
                "description": f"Auto-generated by RevVault for {db_type.upper()}.",
                "operationId": op_id,
                "responses": {
                    "200": {
                        "description": "Successful operation",
                        "content": {
                            "application/json": {
                                "schema": {
                                    "type": "object",
                                    "properties": {
                                        "status": {"type": "string", "example": "success"},
                                        "data": {"type": "array", "items": {"type": "object"}},
                                        "count": {"type": "integer", "example": 10}
                                    }
                                }
                            }
                        }
                    },
                    "400": {
                        "description": "Invalid parameter input",
                        "content": {
                            "application/json": {
                                "schema": {
                                    "type": "object",
                                    "properties": {
                                        "status": {"type": "string", "example": "error"},
                                        "message": {"type": "string", "example": "Validation failed"}
                                    }
                                }
                            }
                        }
                    },
                    "500": {
                        "description": "Database query error",
                        "content": {
                            "application/json": {
                                "schema": {
                                    "type": "object",
                                    "properties": {
                                        "status": {"type": "string", "example": "error"},
                                        "message": {"type": "string"}
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if query_params:
                op_def["parameters"] = query_params

            if op_method in ("POST", "PUT", "PATCH") and body_props:
                op_def["requestBody"] = {
                    "required": True,
                    "content": {
                        "application/json": {
                            "schema": {
                                "type": "object",
                                "properties": body_props,
                                "required": body_required
                            }
                        }
                    }
                }

            paths_dict.setdefault(clean_route, {})[op_method.lower()] = op_def

        spec = {
            "openapi": "3.1.0",
            "info": {
                "title": f"{clean_name.title()} API",
                "version": "1.0.0",
                "description": f"Production database API service generated by RevVault ({db_type.upper()})."
            },
            "servers": [
                {
                    "url": "http://localhost:8000",
                    "description": "Local development environment"
                }
            ],
            "paths": paths_dict,
            "components": {
                "schemas": {
                    "StandardResponse": {
                        "type": "object",
                        "properties": {
                            "status": {"type": "string"},
                            "data": {"type": "array", "items": {"type": "object"}}
                        }
                    }
                }
            }
        }
        return spec

    @classmethod
    def generate_postman_collection(
        cls,
        query: str,
        endpoint_name: str = "get_records",
        route_path: str = "/api/v1/records",
        method: str = "GET",
        parameters: Optional[List[Dict[str, Any]]] = None,
        collection_name: Optional[str] = None,
        base_url: str = "http://localhost:8000",
        operation_types: Optional[List[str]] = None,
        operation_queries: Optional[Dict[str, str]] = None
    ) -> Dict[str, Any]:
        clean_name = endpoint_name.strip().replace(" ", "_")
        col_name = collection_name or f"RevVault - {clean_name.title()} Service"
        ops = operation_types if (operation_types and len(operation_types) > 0) else [cls.detect_operation_type(query)]

        clean_path = route_path.strip("/")
        path_segments = clean_path.split("/")

        items = []
        for op in ops:
            op_method = cls.default_method_for_op(op)
            item_name = f"{op.upper()} - {cls.infer_endpoint_name(clean_name, op)}"

            query_items = []
            raw_body_dict = {}

            if parameters:
                for p in parameters:
                    p_name = p.get("name", "param")
                    p_val = p.get("default", "")
                    if op_method in ("GET", "DELETE"):
                        query_items.append({
                            "key": p_name,
                            "value": str(p_val),
                            "description": f"Filter parameter for {p_name}"
                        })
                    else:
                        raw_body_dict[p_name] = p_val or "sample_value"

            request_dict: Dict[str, Any] = {
                "method": op_method,
                "header": [
                    {"key": "Accept", "value": "application/json", "type": "text"}
                ],
                "url": {
                    "raw": f"{{{{base_url}}}}/{clean_path}" + (("?" + "&".join(f"{q['key']}={q['value']}" for q in query_items)) if query_items else ""),
                    "host": ["{{base_url}}"],
                    "path": path_segments,
                }
            }

            if query_items:
                request_dict["url"]["query"] = query_items

            if op_method in ("POST", "PUT", "PATCH"):
                request_dict["header"].append({"key": "Content-Type", "value": "application/json", "type": "text"})
                request_dict["body"] = {
                    "mode": "raw",
                    "raw": json.dumps(raw_body_dict, indent=2),
                    "options": {"raw": {"language": "json"}}
                }

            items.append({
                "name": item_name,
                "request": request_dict,
                "response": [],
                "event": [
                    {
                        "listen": "test",
                        "script": {
                            "type": "text/javascript",
                            "exec": [
                                "pm.test('Status code is 200', function () {",
                                "    pm.response.to.have.status(200);",
                                "});",
                                "pm.test('Response is valid JSON', function () {",
                                "    pm.response.to.be.json;",
                                "});"
                            ]
                        }
                    }
                ]
            })

        collection = {
            "info": {
                "name": col_name,
                "description": f"Automated test collection generated by RevVault for endpoint {clean_name}.",
                "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
            },
            "variable": [
                {
                    "key": "base_url",
                    "value": base_url.rstrip("/"),
                    "type": "string"
                }
            ],
            "item": items
        }
        return collection

