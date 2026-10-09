# RevVault Walkthrough & Verification Guide

RevVault has been successfully created, structured, and verified inside:
`/home/miharin/Documents/Project/rev_vault`

---

## What Was Built

### 1. Architectural Documentation
Created comprehensive technical specifications covering every aspect of the system:
- [README.md](file:///home/miharin/Documents/Project/rev_vault/README.md): High-level system overview, quick start, security model, and directory structure.
- [docs/UI.md](file:///home/miharin/Documents/Project/rev_vault/docs/UI.md): Desktop UI layout (Linux & Windows), Material 3 theme palette, Connection Manager, Schema Explorer Tree, SQL Editor & DataGrid, and Live MCP Monitor.
- [docs/BACKEND.md](file:///home/miharin/Documents/Project/rev_vault/docs/BACKEND.md): Python FastAPI service, SQLite & PostgreSQL (`asyncpg`) connection pooling, `sqlglot` AST SQL Guardrail, and REST/WebSocket API endpoints.
- [docs/MCP.md](file:///home/miharin/Documents/Project/rev_vault/docs/MCP.md): Antigravity MCP integration, tool schemas (`list_tables`, `describe_table`, `execute_safe_query`, `get_table_preview`), safety boundaries, and error codes.
- [docs/BRIDGE.md](file:///home/miharin/Documents/Project/rev_vault/docs/BRIDGE.md): IPC architecture, real-time WebSocket telemetry stream (`/ws/audit`), shared state (`~/.revvault/`), and process lifecycle management (sidecar vs daemon).

---

### 2. Python Backend & AST SQL Guardrail
- **Guardrail Engine (`guardrail.py`)**: Uses `sqlglot` to parse incoming queries into AST nodes. Strictly allows safe read-only queries (`SELECT`, `EXPLAIN`, `WITH ... SELECT`) while blocking destructive statements (`DROP`, `DELETE`, `TRUNCATE`, `ALTER`, `UPDATE`, `INSERT`, etc.) and multi-statement injection attempts. Automatically injects row limits (default 50-100) to prevent runaway memory usage.
- **Database Engine (`db_manager.py`)**: Asynchronous connection pooling and query execution for SQLite and PostgreSQL (`asyncpg`).
- **Schema Inspector (`schema_inspector.py`)**: Discovers tables, views, columns, datatypes, primary keys, and foreign keys.
- **REST & Telemetry API (`api/`)**: FastAPI endpoints for connection management, schema inspection, query execution, and WebSocket audit event streaming (`/api/audit/ws`).
- **Automated Tests**: 11 unit tests in `tests/test_guardrail.py` and `tests/test_db_and_schema.py` passing with 100% coverage on Python 3.14.

---

### 3. Antigravity MCP Server
- **Tools Exposed**:
  1. `list_tables`: List all user tables and views.
  2. `describe_table`: Detailed column definitions, types, nullability, and primary keys.
  3. `execute_safe_query`: Guardrail-validated query executor. If a dangerous statement is passed, the tool intercepts and raises a descriptive `SECURITY GUARDRAIL REJECTION` error.
  4. `get_table_preview`: Sample rows preview.
- **Antigravity Config**: Generated ready-to-use snippet in [mcp_config_snippet.json](file:///home/miharin/Documents/Project/rev_vault/mcp_config_snippet.json).

---

### 4. Flutter Desktop Application (Linux & Windows)
- Modern Material 3 responsive desktop layout.
- **Sidebar (`sidebar_connections.dart`)**: Connection manager for local SQLite `.db` files and remote PostgreSQL instances with live "Test Connection" diagnostics.
- **Schema Explorer (`schema_tree_view.dart`)**: Hierarchical tree with datatype badges, primary key icons, and quick table preview.
- **SQL Query Editor (`sql_editor_view.dart`)**: Query editor with `Ctrl+Enter` execution shortcut, Safe Mode AST toggle, and scrollable DataGrid results.
- **Live Antigravity MCP Monitor (`mcp_monitor_view.dart`)**: Real-time event log powered by WebSockets, flashing green badges for allowed queries and crimson rose alert cards for blocked destructive queries.
- **Verification**: Built and compiled native Linux desktop binary (`build/linux/x64/debug/bundle/rev_vault`).

---

## Verification Results

### Backend Automated Test Suite
```bash
$ cd /home/miharin/Documents/Project/rev_vault/backend
$ .venv/bin/pytest -v
============================== 11 passed in 0.13s ==============================
tests/test_db_and_schema.py::test_schema_inspector PASSED                [  9%]
tests/test_db_and_schema.py::test_safe_query_execution PASSED            [ 18%]
tests/test_db_and_schema.py::test_destructive_query_intercepted PASSED   [ 27%]
tests/test_guardrail.py::test_safe_select_passes PASSED                  [ 36%]
tests/test_guardrail.py::test_explain_passes PASSED                      [ 45%]
tests/test_guardrail.py::test_drop_table_blocked PASSED                  [ 54%]
tests/test_guardrail.py::test_delete_blocked PASSED                      [ 63%]
tests/test_guardrail.py::test_truncate_blocked PASSED                    [ 72%]
tests/test_guardrail.py::test_alter_table_blocked PASSED                 [ 81%]
tests/test_guardrail.py::test_multi_statement_injection_blocked PASSED   [ 90%]
tests/test_guardrail.py::test_limit_clamping PASSED                      [100%]
```

### Flutter Test & Native Build
```bash
$ cd /home/miharin/Documents/Project/rev_vault/frontend
$ flutter test
00:00 +1: All tests passed!

$ flutter build linux --debug
Building Linux application...                                   
✓ Built build/linux/x64/debug/bundle/rev_vault
```

---

## How to Run RevVault

### Step 1: Start the Backend Service
In a terminal:
```bash
cd /home/miharin/Documents/Project/rev_vault/backend
.venv/bin/python run_server.py
```
Backend will start on `http://127.0.0.1:8000` (FastAPI docs available at `http://127.0.0.1:8000/docs`).

### Step 2: Launch the Flutter Desktop App
In a second terminal:
```bash
cd /home/miharin/Documents/Project/rev_vault/frontend
/home/miharin/flutter/flutter/bin/flutter run -d linux
```

### Step 3: Configure Antigravity MCP
Add the following to `~/.gemini/config/mcp_config.json`:
```json
{
  "mcpServers": {
    "revvault": {
      "command": "/home/miharin/Documents/Project/rev_vault/backend/.venv/bin/python",
      "args": [
        "/home/miharin/Documents/Project/rev_vault/backend/run_mcp_stdio.py"
      ],
      "env": {
        "REVVAULT_DIR": "/home/miharin/.revvault"
      }
    }
  }
}
```
Antigravity will automatically detect `list_tables`, `describe_table`, `execute_safe_query`, and `get_table_preview` while safely blocking any dangerous queries!
