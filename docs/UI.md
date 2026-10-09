# RevVault — UI Architecture & Design Specification

> **Company**: Relva  
> **Product**: RevVault (Sister product to RevHelix)  
> **Platform**: Flutter Desktop (Linux & Windows)  
> **Framework**: Flutter 3.47+ / Dart 3.13+ (Material 3)

---

## 1. Visual Identity & Design Principles

RevVault adheres to Relva's design ethos: **Sleek, high-precision, and professional with clean, approachable aesthetics.**

- **Theme Palette**:
  - Primary: Deep Vault Teal / Cyan accent (`#0D9488` / `#14B8A6`) reflecting high security and clarity.
  - Surface Dark: Obsidian / Slate (`#0F172A`, `#1E293B`, `#334155`).
  - Surface Light: Crisp Snow & Pearl Grey (`#F8FAFC`, `#E2E8F0`).
  - Safe Query Accent: Emerald Green (`#10B981`) for read-only / permitted queries.
  - Danger Query Accent: Crimson Rose (`#F43F5E`) for blocked or destructive queries.
  - Warning Accent: Amber Gold (`#F59E0B`) for slow queries or missing indexes.
- **Typography**: Inter / Roboto Mono for data tables and SQL code.

---

## 2. Desktop Window Layout

The UI uses a **three-pane responsive desktop layout**:

```
+----------------------------------------------------------------------------------------------------+
|  [Relva RevVault]   Connection: [Production PG (online)] [v]   Status: [Backend: Connected (8000)] |
+-----------------------+----------------------------------------------------------------------------+
| [CONNECTIONS]         |  [Tab: Schema Explorer]  [Tab: SQL Editor]  [Tab: Live MCP Audit (3)]      |
| + Add Connection      |----------------------------------------------------------------------------+
|                       |                                                                            |
| SQLite (Local)        |  Query Editor:                                                             |
| * analytics.db        |  ```sql                                                                    |
| * dev_test.db         |  SELECT u.id, u.email, o.total                                             |
|                       |  FROM users u JOIN orders o ON u.id = o.user_id                            |
| PostgreSQL            |  WHERE o.status = 'active';                                                |
| * Relva Prod (5432)   |  ```                                                                       |
| * Staging DB          |  [ > Run Query (Ctrl+Enter) ]  [ [x] Enforce Safe Mode ]   [ Format SQL ]  |
|                       |----------------------------------------------------------------------------+
| [SCHEMA TREE]         |  Results: (42 rows, 14ms)                                                  |
| > public.users        |  +----+-------------------+-----------+                                    |
|   # id (BIGINT, PK)   |  | id | email             | total     |                                    |
|   # email (VARCHAR)   |  +----+-------------------+-----------+                                    |
|   # created_at (TS)   |  | 1  | alice@relva.io    | $120.00   |                                    |
| > public.orders       |  | 2  | bob@relva.io      | $450.50   |                                    |
| > public.audit_logs   |  +----+-------------------+-----------+                                    |
+-----------------------+----------------------------------------------------------------------------+
| Footer: Antigravity MCP: Listening on stdio / sse | Total queries today: 184 | Blocked: 7          |
+----------------------------------------------------------------------------------------------------+
```

---

## 3. Core UI Components

### 3.1 Sidebar & Connection Manager (`sidebar_connections.dart`)
- **Connection List**: Groups saved connections into **SQLite** and **PostgreSQL**.
- **State Badges**: Indicates connection status (Connected, Disconnected, Testing, Error).
- **Add Connection Dialog**:
  - SQLite: File picker for `.db`, `.sqlite`, `.sqlite3`.
  - PostgreSQL: Host, Port (default 5432), Database, User, Password, SSL mode (`disable`, `prefer`, `require`).
  - Action buttons: `Test Connection` (calls backend `/api/connections/test`) and `Save & Connect`.

### 3.2 Schema Explorer Tree (`schema_tree_view.dart`)
- Hierarchical tree representation of the active database:
  - Database -> Schema (e.g. `public`) -> Tables & Views.
  - Table children: Columns with datatype badges (`INT`, `VARCHAR`, `TIMESTAMP`), PK key icons, and NOT NULL indicators.
- **Context Actions**:
  - `Preview Top 50 Rows`: Instantly loads sample data into the grid.
  - `Generate SELECT Query`: Inserts template SQL into the active editor tab.
  - `Copy Table Name / DDL`: Fast clipboard helper.

### 3.3 SQL Editor & Result Grid (`sql_editor_view.dart`)
- Multi-tab query workspace allowing multiple parallel queries.
- SQL syntax highlighting with keyword coloring (`SELECT`, `FROM`, `WHERE`, `JOIN`).
- Action bar:
  - `Execute` (`Ctrl+Enter` / `F5`).
  - `Safe Mode Toggle`: When enabled, local queries pass through the exact same AST guardrail used by MCP!
  - `Format SQL`: Auto-indents and formats SQL statements.
  - `Export Results`: CSV, JSON, or Markdown table export.
- Results DataGrid:
  - Virtualized, high-performance scrolling.
  - Column sorting and quick filtering.
  - Timing summary: execution duration (e.g. `12ms`) and row count.

### 3.4 Live MCP Audit & Guardrail Monitor (`mcp_monitor_view.dart`)
- Real-time event log powered by the backend WebSocket stream (`/ws/audit`).
- Shows every query issued by Antigravity or the AI agent:
  - **Timestamp** and **Client ID**.
  - **Query Statement** with syntax highlights.
  - **Security Decision Badge**:
    - `PASSED`: Safe `SELECT`/`EXPLAIN` statement executed successfully.
    - `BLOCKED`: Dangerous query intercepted (e.g., `BLOCKED: DROP TABLE attempt`).
  - **Rejection Reason**: Displays the AST rule triggered (e.g., `Disallowed AST node: DropTable`).
- **Guardrail Configuration Controls**:
  - Slider for Default Row Limit (e.g., 25, 50, 100, 500).
  - Toggles for query inspection severity (Strict Read-Only vs. Permissive DML).

### 3.5 Multi-Framework Backend API Generator (`api_generator_modal.dart`)
- Direct launch from SQL Editor toolbar via the **Generate API** button.
- Framework selector with multi-file preview:
  - **PHP Native (PDO)**
  - **PHP CodeIgniter 4 (CI4)**
  - **PHP CodeIgniter 3 (CI3)**
  - **Python FastAPI**
  - **Python Native**
  - **Node.js Express.js**
  - **Bun / TypeScript ElysiaJS**
- **Copy File Code**: Instantly copies the active file or isolated function snippet to clipboard.
- **Download Project ZIP**: Calls backend endpoint `POST /api/codegen/backend/export-zip` to download full project scaffold.

---

## 4. State Management & Data Flow

- Uses **Provider / ChangeNotifier** (`AppState`) for clean, predictable reactive updates.
- Decoupled API service (`ApiService`) handling HTTP REST calls with comprehensive error handling.
- Real-time `WebSocketChannel` subscription that auto-reconnects on disconnection.
