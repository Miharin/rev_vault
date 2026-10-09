# RevVault — Backend Architecture & Service Specification

> **Company**: Relva  
> **Product**: RevVault  
> **Runtime**: Python 3.10+ (Tested on Python 3.14)  
> **Core Framework**: FastAPI, Uvicorn, SQLGlot, Asyncpg, Aiosqlite, Pydantic

---

## 1. Overview & Responsibilities

The RevVault backend is a lightweight, high-performance asynchronous service responsible for:
1. **Connection Lifecycle**: Managing persistent connections and pooling for SQLite and PostgreSQL.
2. **Schema Introspection**: Extracting metadata (tables, views, columns, datatypes, constraints, indexes).
3. **AST SQL Guardrail**: Parsing incoming queries into abstract syntax trees to detect and reject dangerous operations before hitting the database.
4. **REST & WebSocket API**: Serving the Flutter Desktop application.
5. **Audit Logging & Event Streaming**: Recording and broadcasting query executions and security interventions in real time.

---

## 2. Directory Layout

```
backend/
├── pyproject.toml
├── requirements.txt
├── run_server.py                # Starts FastAPI + Uvicorn server (default port 8000)
├── run_mcp_stdio.py             # Direct stdio MCP launcher for Antigravity
└── app/
    ├── __init__.py
    ├── config.py                # Environment configs & storage path (~/.revvault/)
    ├── core/
    │   ├── guardrail.py         # SQLGlot AST analyzer & security evaluator
    │   ├── db_manager.py        # SQLite & PostgreSQL pool & execution engine
    │   └── schema_inspector.py  # Schema reflection queries for PG & SQLite
    ├── mcp/
    │   ├── server.py            # Model Context Protocol tools & resources
    │   └── bridge.py            # Bridge forwarding MCP events to audit stream
    └── api/
        ├── routes_connections.py# /api/connections (CRUD & Test)
        ├── routes_query.py      # /api/query (Execute & Preview)
        ├── routes_schema.py     # /api/schema (Tree & Details)
        └── routes_audit.py      # /api/audit & /ws/audit (Live stream)
```

---

## 3. Database Adapters & Management (`db_manager.py`)

### 3.1 SQLite Adapter
- Uses Python `sqlite3` and `aiosqlite` for asynchronous disk I/O.
- Supports file-based databases with connection caching and timeout locks.
- Pragmas configured: `PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;`.

### 3.2 PostgreSQL Adapter
- Uses `asyncpg` for native, binary-level high-performance connection pooling.
- Connection parameters: `host`, `port`, `database`, `user`, `password`, `ssl`.
- Handles type conversions (JSON, UUID, Arrays, Datetime) cleanly into JSON-serializable payloads.

### 3.3 Connection Persistence
- Saved configurations stored securely in `~/.revvault/connections.json`.
- Passwords can be stored encrypted or managed via standard connection strings.
- Active connection state is maintained in-memory for instant switching.

---

## 4. AST SQL Guardrail Engine (`guardrail.py`)

Rather than relying on naive regex matching (which can be easily bypassed with comments like `/* DROP */` or string concatenation), RevVault parses the complete **Abstract Syntax Tree (AST)** using `sqlglot`.

### 4.1 Safety Rules
1. **Root Statement Whitelist**:
   - Allowed root AST nodes: `sqlglot.exp.Select`, `sqlglot.exp.Union`, `sqlglot.exp.Explain`.
2. **Disallowed Statement Blacklist**:
   - Explicitly rejects AST nodes: `Delete`, `Drop`, `Truncate`, `Insert`, `Update`, `AlterTable`, `Create`, `Merge`, `Command`, `Grant`, `Revoke`.
3. **Multi-Statement Analysis**:
   - Analyzes all parsed expressions in input. If query contains multiple statements (e.g. `SELECT 1; DROP TABLE users;`), **all statements must be safe**. If any statement is modifying or dangerous, the entire execution is aborted.
4. **Row Limit Capping**:
   - Automatically inspects the `Select` AST for a `Limit` expression.
   - If no `LIMIT` is specified, injects `LIMIT <configured_default>` (default: 100).
   - If a specified limit exceeds `<configured_max>` (e.g., > 1,000), clamps it down to the safety threshold.

---

## 5. REST & WebSocket Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/health` | Server health check and active DB indicator |
| `GET` | `/api/connections` | List all saved database connections |
| `POST` | `/api/connections` | Add or update a database connection |
| `POST` | `/api/connections/test` | Test connectivity to SQLite file or PostgreSQL host |
| `POST` | `/api/connections/active` | Switch current active database connection |
| `GET` | `/api/schema` | Get hierarchical tree of tables, views, and columns |
| `POST` | `/api/query` | Execute SQL query from UI (supports safe mode toggle) |
| `GET` | `/api/table/:name/preview` | Preview top N rows of a specific table |
| `GET` | `/api/audit` | Fetch recent query audit history |
| `WS` | `/ws/audit` | Real-time WebSocket stream of query attempts and guardrail events |
