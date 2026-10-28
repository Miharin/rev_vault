# Learning Record: Windows Release Backend Sidecar Connection Fix

- **Date:** 2026-10-27
- **Target Systems:** Windows x64 Release Bundle & Sidecar IPC
- **Auditors & Guardians:** `[Echo, Scythe & Verdict]` (API Consumer, Backend & Verification Guard)

---

## 1. Symptom & Stack Trace

When running RevVault on Windows from the packaged release installer (`RevVault-Setup-v*.exe`) or portable ZIP (`revvault-windows-x64-v*.zip`), the Flutter desktop client launches but displays:
```
RevVault backend service is not reachable at http://127.0.0.1:8000.
```
The application fails to connect to the backend, schema explorer remains empty, and database connections cannot be tested.

---

## 2. Root Cause Analysis

1. **PyInstaller Missing Dynamic ASGI / AnyIO Submodules:**
   - FastAPI and Starlette depend on AnyIO to run asynchronous event loops and tasks.
   - AnyIO dynamically loads its backend via `importlib.import_module("anyio._backends._asyncio")`.
   - In `backend/revvault.spec`, `anyio`, `fastapi`, `starlette`, `sse_starlette`, and `mcp` were missing from `hidden_imports`.
   - When `revvault-backend.exe` launched on Windows, Python crashed immediately on startup with:
     ```
     ModuleNotFoundError: No module named 'anyio._backends._asyncio'
     ```
2. **Missing Package Data Files in Spec:**
   - FastAPI, Starlette, AnyIO, MCP, and Uvicorn runtime data files (such as OpenAPI templates and metadata) were omitted from `datas` in `backend/revvault.spec`.
3. **Hard-coded `httpx2` Dependency in `agent_service.py`:**
   - `backend/app/core/agent_service.py` imported `httpx2` unconditionally. In environments installing standard `httpx` from PyPI, Python immediately halted on startup with `ModuleNotFoundError: No module named 'httpx2'`.
4. **Windows `SO_REUSEADDR` & Default `0.0.0.0` Host Binding:**
   - In `backend/run_server.py`, `find_available_port()` set `SO_REUSEADDR = 1` across all platforms. On Windows, `SO_REUSEADDR` enables port hijacking and allows binding to already active ports without error.
   - Binding by default to `0.0.0.0` triggered Windows Defender Firewall prompts or silent socket blocking on Windows Public networks.
5. **Path Resolution, Python Pipe Buffering & Silent Diagnostic Failure:**
   - Without `PYTHONUNBUFFERED=1`, Python pipes on Windows buffer standard I/O streams, delaying port announcement signals.
   - `frontend/lib/services/backend_sidecar_service.dart` used raw backslash string concatenation and only captured the last line of stderr (which was often blank).
   - In `app_state.dart`, `sidecarErr` was discarded if `exitCode == null`, concealing process launch and candidate path errors.

---

## 3. Step-by-Step Surgical Fix Procedure

1. **Expose All Dynamic Submodules & Data in `backend/revvault.spec`:**
   - Collected all submodules for `fastapi`, `starlette`, `anyio`, `sse_starlette`, `mcp.server`, `mcp.types`, `mcp.shared`, `sqlite3`, `httpx`, and `httpx2`.
   - Added explicit entries for `anyio._backends._asyncio`, `anyio._core._asyncio_selector_thread`, and all Uvicorn protocols/loops.
   - Added data files collection for `sqlglot`, `fastapi`, `starlette`, `anyio`, `mcp`, and `uvicorn`.
2. **Dynamic `httpx2` / `httpx` Dual-Compatibility:**
   - Wrapped `import httpx2 as httpx` with `except ImportError: import httpx` in `agent_service.py` and converted all calls to `httpx.AsyncClient`.
3. **Protected Startup Imports & Server Hardening in `backend/run_server.py`:**
   - Moved heavy ASGI imports (`uvicorn`, `app.main`) inside `main()` under the top-level `try ... except` so any import failure triggers fatal file logging to `%APPDATA%\Relva\RevVault\backend.log`.
   - Disabled `SO_REUSEADDR` on Windows to prevent port-probing false positives.
4. **Harden Flutter `BackendSidecarService` & Loopback Isolation:**
   - Explicitly passed `--host 127.0.0.1` to completely bypass Windows Firewall network barriers.
   - Passed `PYTHONUNBUFFERED: '1'` in `environment` to prevent pipe stdout latency.
   - Maintained a 30-line rolling buffer for `stderr` and increased `_probeHealth` timeout from 600ms to 1500ms.
   - Added explicit diagnostic reporting if no binary is found across candidate paths.
5. **Surface Complete Diagnostics in `AppState`:**
   - Enhanced `app_state.dart` to display `sidecarErr` even when `exitCode == null`.
6. **Set Working Directory in Inno Setup (`scripts/windows/revvault.iss`):**
   - Configured `WorkingDir: "{app}"` on desktop/start menu shortcuts and post-install execution.

---

## 4. Verification Proof

- **Python Tests:** 57/57 tests passing in `backend/tests`.
- **Dart Analysis:** Clean analysis with 0 errors across `backend_sidecar_service.dart` and `app_state.dart`.
- **PyInstaller Compilation:** Verified on standalone bundle with clean CLI execution (`--help`).

---

## 5. Prevention Invariants

1. **Universal ASGI/AnyIO Spec Standard:** Any PyInstaller build utilizing Starlette or FastAPI must explicitly include `anyio._backends._asyncio` and `collect_submodules("anyio")`.
2. **Persistent Sidecar Diagnostics:** Every background headless sidecar must write uncaught exceptions to disk (`backend.log`) so post-mortem analysis does not depend on ephemeral console windows.
