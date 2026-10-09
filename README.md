# RevVault 🛡️📦
> **A secure, intelligent database companion for developers and AI agents.**  
> Built by **Relva**, alongside products like **RevHelix**.

RevVault is a dual-layer database management platform featuring a high-performance **Flutter Desktop** interface (Linux & Windows) and an intelligent **Python backend** equipped with a **Model Context Protocol (MCP)** server.

RevVault bridges your databases (PostgreSQL & SQLite) with **Google Antigravity**, allowing AI agents to safely explore schemas and run analytical queries while strictly preventing destructive operations (`DROP`, `DELETE`, `TRUNCATE`, `ALTER`, `UPDATE`, `INSERT`) through Abstract Syntax Tree (AST) guardrails.

---

## 📚 Comprehensive Documentation

The architecture and technical specifications are documented across four dedicated modules:

| Document | Scope | Description |
| :--- | :--- | :--- |
| 🖥️ [**docs/UI.md**](./docs/UI.md) | **Flutter Desktop UI** | Layout, Connection Manager, Schema Explorer Tree, SQL Editor & DataGrid, Live MCP Monitor, Theme |
| ⚙️ [**docs/BACKEND.md**](./docs/BACKEND.md) | **Python Engine & API** | FastAPI service, SQLite & PostgreSQL adapters, AST SQL Guardrail (`sqlglot`), Connection pooling |
| 🤖 [**docs/MCP.md**](./docs/MCP.md) | **Antigravity MCP** | Tool definitions (`list_tables`, `describe_table`, `execute_safe_query`), safety interception & error codes |
| 🌉 [**docs/BRIDGE.md**](./docs/BRIDGE.md) | **The Bridge (IPC & Sync)**| REST & WebSocket telemetry, sidecar process lifecycle, shared state (`~/.revvault/`) |

---

## 🌟 Key Features

- **AST SQL Guardrails**: Queries from Antigravity are parsed into AST nodes using `sqlglot`. Only safe, read-only statements (`SELECT`, `WITH`, `EXPLAIN`) are permitted. Dangerous commands (`DROP`, `DELETE`, `TRUNCATE`, `ALTER`, etc.) or multi-statement injections are immediately intercepted and blocked.
- **Auto Row Limits**: Prevents runaway queries and memory crashes by automatically enforcing safe row limits (default 50-100 rows).
- **Dual Database Engines**: First-class support for local **SQLite** files and remote **PostgreSQL** instances.
- **Live Antigravity Monitor**: Watch AI queries execute in real time on the Flutter desktop UI, with instant color-coded visual indicators for allowed and blocked queries.
- **Cross-Platform Desktop**: Native support for **Linux** and **Windows** desktop environments.

---

## ⚡ Quick Start

### 🚀 One-Command Start (Frontend + Backend)

Start both the FastAPI backend service and the Flutter desktop application concurrently with a single command:

```bash
./start.sh
# or using make:
make
```

> **Note**: `./start.sh` automatically launches the Python backend, waits for it to become healthy on `http://127.0.0.1:8000`, starts the Flutter Desktop application, and cleanly shuts down the backend process when you close the app or press `Ctrl+C`.

---

### Manual / Component Start

#### 1. Backend & MCP Service
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Start the backend server (FastAPI + MCP SSE on port 8000)
python run_server.py
```

### 2. Antigravity MCP Setup
Add RevVault to your `~/.gemini/config/mcp_config.json`:

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

### 3. Flutter Desktop App
```bash
cd frontend
/home/miharin/flutter/flutter/bin/flutter pub get
/home/miharin/flutter/flutter/bin/flutter run -d linux   # On Linux
# Or: flutter run -d windows                            # On Windows
```

---

## 🔒 Security Summary

| Operation | From Flutter UI | From Antigravity MCP |
| :--- | :--- | :--- |
| `SELECT ...` | ✅ Allowed | ✅ Allowed (AST Validated) |
| `EXPLAIN SELECT ...` | ✅ Allowed | ✅ Allowed |
| `INSERT / UPDATE` | ✅ Allowed (Safe Mode toggleable) | ❌ **BLOCKED** |
| `DROP / TRUNCATE / ALTER` | ⚠️ Confirmation Prompt | ❌ **STRICTLY BLOCKED** |
| `Multi-statement Injection` | ⚠️ Analyzed | ❌ **STRICTLY BLOCKED** |
