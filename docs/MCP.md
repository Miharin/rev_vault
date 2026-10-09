# RevVault — Model Context Protocol (MCP) Server Specification

> **Company**: Relva  
> **Product**: RevVault  
> **Protocol**: Model Context Protocol (MCP)  
> **Client Target**: Antigravity AI Agent

---

## 1. Role in Antigravity Ecosystem

RevVault exposes a dedicated MCP server to Google Antigravity. This allows the AI agent to:
- Dynamically understand database structures without manual schema dumps.
- Safely query live databases to assist in writing migrations, building features, or debugging bugs.
- **Guarantee safety**: Antigravity is strictly prevented from executing destructive queries (`DROP`, `DELETE`, `TRUNCATE`, `ALTER`, etc.) through deep AST parsing.

---

## 2. MCP Tools Exposed to Antigravity

RevVault registers four primary tools adhering to the MCP schema:

### 2.1 `list_tables`
- **Description**: Returns all user tables and views present in the active database connection.
- **Parameters**:
  - `include_views` (*boolean, optional, default: true*): Include database views in the listing.
- **Output**: JSON array of table metadata objects containing table name, schema, and type (`TABLE` or `VIEW`).

### 2.2 `describe_table`
- **Description**: Returns detailed schema information for a specific table.
- **Parameters**:
  - `table_name` (*string, required*): The target table name (e.g. `users` or `public.orders`).
- **Output**:
  - Column names and data types (e.g., `id: integer`, `email: varchar(255)`).
  - Primary key indicators (`is_primary_key: true`).
  - Nullability (`is_nullable: false`).
  - Default values.
  - Foreign key references and existing indexes.

### 2.3 `execute_safe_query`
- **Description**: Safely executes a read-only SQL query (`SELECT` / `EXPLAIN`) against the active database. Automatically limits returned rows to prevent context window overflow.
- **Parameters**:
  - `sql` (*string, required*): The SQL query to execute.
  - `max_rows` (*integer, optional, default: 50, maximum: 200*): Maximum rows to return.
- **Safety Interception Behavior**:
  - The query is parsed via AST.
  - If any destructive operation is found (`DROP`, `DELETE`, `TRUNCATE`, `ALTER`, `UPDATE`, `INSERT`, multi-statement injection), the tool raises an MCP Tool Error with code `GUARDRAIL_VIOLATION`.
  - The tool returns:
    ```json
    {
      "isError": true,
      "content": [{
        "type": "text",
        "text": "GUARDRAIL BLOCKED: Dangerous query detected. Statement contains prohibited AST node 'DropTable'. Only read-only queries (SELECT, EXPLAIN) are permitted via Antigravity MCP."
      }]
    }
    ```

### 2.4 `get_table_preview`
- **Description**: Fetches top sample rows from a table.
- **Parameters**:
  - `table_name` (*string, required*): The table name to sample.
  - `limit` (*integer, optional, default: 15, maximum: 50*): Number of rows to sample.
- **Output**: Array of row objects formatted as JSON key-value pairs.

---

## 3. Transports & Launch Modes

### Mode A: Stdio Transport (Direct CLI Launcher)
Antigravity launches the Python script directly as a subprocess and communicates via standard input/output (`stdin`/`stdout`).

Configuration in `~/.gemini/config/mcp_config.json`:
```json
{
  "mcpServers": {
    "revvault": {
      "command": "python3",
      "args": [
        "/home/miharin/.gemini/antigravity/scratch/rev_vault/backend/run_mcp_stdio.py"
      ],
      "env": {
        "REVVAULT_DIR": "/home/miharin/.revvault"
      }
    }
  }
}
```

### Mode B: SSE Transport (Remote / Shared Service)
Antigravity connects via Server-Sent Events over HTTP to the running RevVault backend service. This mode allows the Flutter UI to display live query events simultaneously as Antigravity executes them.

Configuration in `~/.gemini/config/mcp_config.json`:
```json
{
  "mcpServers": {
    "revvault-sse": {
      "serverUrl": "http://127.0.0.1:8000/sse"
    }
  }
}
```

---

## 4. Security Guarantees & AST Analysis

| Query Example | AST Result | MCP Verdict |
| :--- | :--- | :--- |
| `SELECT * FROM users WHERE active = true` | `Select` | ✅ **PERMITTED** |
| `EXPLAIN SELECT count(*) FROM orders` | `Explain -> Select` | ✅ **PERMITTED** |
| `WITH q AS (SELECT * FROM log) SELECT * FROM q` | `Select (CTE)` | ✅ **PERMITTED** |
| `DROP TABLE users` | `Drop` | ❌ **BLOCKED** |
| `DELETE FROM users WHERE id = 1` | `Delete` | ❌ **BLOCKED** |
| `SELECT 1; TRUNCATE TABLE users;` | `Select, Truncate` | ❌ **BLOCKED** |
| `SELECT /* trick */ 1; DROP TABLE users;` | `Select, Drop` | ❌ **BLOCKED** |
| `UPDATE users SET role = 'admin'` | `Update` | ❌ **BLOCKED** |
| `ALTER TABLE users ADD COLUMN token TEXT` | `AlterTable` | ❌ **BLOCKED** |
