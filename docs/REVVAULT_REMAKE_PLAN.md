# RevVault Remake & Full-Stack Evolution Roadmap 🛡️⚡

> **Architecture Plan**: Full-Stack Query Engine, Intelligent Autocomplete, Auto Backend API, and Drag & Drop UI Generator.  
> **Status**: Planned (Phase-by-Phase Roadmap)

---

## 🧭 Executive Summary & Core Pivot

RevVault is evolving from an exploratory database tool into an end-to-end **Query-to-API-to-UI Stack Engine**.

### Key Decisions
1. **Remove Cluttered Legacy Builders**: The legacy Shader Node canvas and Visual Form builders are removed. They were inadequate for complex queries, nested subqueries, and grouping, and cluttered the application.
2. **Raw SQL as the Primary Workstation**: The SQL editor is elevated into an intelligent, schema-aware workstation featuring autocomplete for tables and columns, subquery and CTE snippets, and dynamic parameter detection (`:param_name`, `$1`, `?`).
3. **Automated Backend API Generation**: Direct conversion of tested queries into production-ready API routes across **PHP Native (PDO)**, **PHP CodeIgniter (CI3 & CI4)**, **Python Native**, **Python FastAPI**, **Node.js Express.js**, and **Bun / TypeScript ElysiaJS**.
4. **Drag & Drop UI Studio & Multi-Framework Exporter**: Visual component canvas to arrange Data Tables, Search Filters, Dropdowns, Date Pickers, and Metric Cards bound to query results, with **Single-File Copy / Download** and **Scaffolded Project ZIP Archive** exports for **Pure HTML/CSS/JS**, **React + Tailwind**, and **Flutter**.

```
+-----------------------------------------------------------------------------------------------+
|                                 REVVAULT FULL-STACK PIPELINE                                  |
|                                                                                               |
|  [1. Intelligent Raw SQL]           [2. Auto Backend API]       [3. Drag & Drop UI Studio]    |
|  * Table & Column Autocomplete      * PHP (Native & CI 3/4)     * Data Tables & KPI Cards     |
|  * Subquery & CTE Helpers           * Python & FastAPI          * Filters (Search, Dropdown)  |
|  * Parameter Extraction (:id)   ->  * Express.js & ElysiaJS ->  * Single Copy OR Project ZIP  |
|                                                                 (HTML, React, Flutter)        |
+-----------------------------------------------------------------------------------------------+
```

---

## 🗓️ Phase-by-Phase Execution Roadmap

### ✅ Phase 1: Streamlined SQL Workstation (Auto-Complete & Subqueries) — COMPLETED
**Objective**: Clean up legacy visual builder files and equip the Raw SQL editor with schema-aware autocomplete, subquery intelligence, and an unobtrusive docked assistant.

1. **Cleaned Up Legacy Visual Builders**:
   - Removed `shader_node_canvas_view.dart`, `visual_query_builder_view.dart`, `shader_node_models.dart`, and `query_builder_models.dart`.
   - Refactored `AppState` to remove legacy node synchronization boilerplate and streamline schema state.
   - SQL editor and virtualized results table now enjoy full workstation screen estate.
2. **Schema-Aware Autocomplete Engine (`sql_autocomplete_service.dart`)**:
   - Suggests keywords (`SELECT`, `FROM`, `WHERE`, `JOIN`, `GROUP BY`, `ORDER BY`, `LIMIT`, `WITH`, etc.).
   - Schema-aware table and column suggestions with alias resolution (`u.` -> `users` columns).
   - Dynamic parameter detection (`:param_name`, `$1`, `?`).
   - Built-in SQL formatter (`formatSql()`).
3. **Subquery & CTE Intelligence & Modal (`sql_subquery_snippets_modal.dart`)**:
   - Searchable, categorized modal library for 1-click subquery insertions:
     - `IN Subquery`: `WHERE <col> IN (SELECT <col> FROM <table> WHERE <cond>)`
     - `EXISTS Subquery`: `WHERE EXISTS (SELECT 1 FROM <table> WHERE <cond>)`
     - `Common Table Expression (CTE)`: `WITH cte_name AS (...) SELECT * FROM cte_name;`
     - `Scalar Subqueries & Window Functions`: `OVER (PARTITION BY <col>)`
4. **Docked IntelliSense Assistant (`sql_autocomplete_dock.dart`)**:
   - **Zero Text Obstruction**: Instead of an intrusive floating popup that covers the SQL editor lines, the assistant docks neatly directly *below* the editor container.
   - **Two-Panel Layout**: Full-width dual pane showing list of matching keywords/tables/columns/subqueries on the left, and a syntax-highlighted multi-line code template preview on the right.
   - **Auto-Helper Toggle**: Dedicated toolbar button (`Auto-Helper: ON / OFF`) allowing users to disable popup suggestions on demand and use manual shortcuts or snippet modals.
   - Fully keyboard-driven (`↑` / `↓` navigation, `Tab` / `Enter` insertion, `Esc` dismiss).

---

### ✅ Phase 2: Multi-Language Backend API Generator — COMPLETED
**Objective**: Generate production-ready, secure API endpoints directly from verified database queries with single-file copy and scaffolded project ZIP exports.

1. **Parameter Detection & Endpoint Specification**:
   - Automatically extracts parameters from SQL (`:id`, `:status`, `$1`, `?`).
   - Customizable endpoint function name, HTTP route path (`/api/v1/records`), and HTTP Method (`GET` / `POST`).
2. **Multi-Language Framework Generators (`backend_codegen_service.dart` & `backend_codegen.py`)**:
   - **PHP Native (PDO)**: Production PDO prepared statements, input parameter handling, JSON response, and `db.php` connection helper.
   - **PHP CodeIgniter 4 (CI4)**: `ApiController.php` (`ResourceController`) + `QueryModel.php` (`executeCustomQuery`) + `Routes.php`.
   - **PHP CodeIgniter 3 (CI3)**: Classic `Api.php` (`CI_Controller`) + `Query_model.php` (`CI_Model`).
   - **Python FastAPI**: Async database dependency injection (`asyncpg`), Pydantic validation, typed route handler, and automatic Swagger docs.
   - **Python Native**: Standalone database script with parameterized queries (`psycopg2` / RealDictCursor).
   - **Node.js Express.js**: Express app with `pg.Pool`, async route handler, error middleware, and `package.json`.
   - **Bun / TypeScript ElysiaJS**: Type-safe high-speed endpoint using `Elysia`, `@elysiajs/cors`, `postgres`, and `package.json`.
3. **API Studio Dialog (`api_generator_modal.dart`)**:
   - Direct launch from SQL Editor toolbar via the **Generate API** action.
   - Framework selector with instant multi-file syntax-styled code preview.
   - **Copy File Code**: Instantly copies the active file to clipboard.
   - **Download Project ZIP**: Calls backend endpoint `POST /api/codegen/backend/export-zip` to download full project scaffold (configs, `.env.example`, connection pool, and `README.md`).
4. **Backend FastAPI Codegen Engine (`routes_codegen.py`)**:
   - `POST /api/codegen/backend/generate`: Generates file maps for automated tooling.
   - `POST /api/codegen/backend/export-zip`: Generates in-memory ZIP archives with `zipfile.ZIP_DEFLATED`.

---

### 🛡️ Phase 3: Specialization Pivot — Database Workstation & Backend Engineering Powerhouse
**Objective**: Focus 100% on high-performance database management, AST security guardrails, intelligent autocomplete, Antigravity MCP AI Bridge, and multi-framework backend API code generation.

1. **Complete Removal of UI Studio**:
   - Dropped frontend builder views, canvas widgets, drag-and-drop palettes, and client template assets.
   - Streamlined workstation into clean 2-tab interface: **Explorer & SQL** and **MCP Audit**.
2. **Next Up — Database Engine & Schema Intelligence**:
   - Foreign Key & Relational Schema Intelligence (badges, constraint extraction, smart JOIN suggestions).
   - Visual EXPLAIN & EXPLAIN ANALYZE Performance Inspector & Query Cost Profiler.
3. **Next Up — Microservice Backend API & Standards**:
   - OpenAPI 3.1 Spec & Postman Collection Exporter.
   - Microservice expansions (Go Gin/Fiber, Rust Axum).

