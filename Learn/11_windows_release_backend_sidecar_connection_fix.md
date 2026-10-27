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
3. **Windows `SO_REUSEADDR` False Availability Detection:**
   - In `backend/run_server.py`, `find_available_port()` set `SO_REUSEADDR = 1` across all platforms. On Windows, `SO_REUSEADDR` enables port hijacking and allows binding to already active ports without error, misleading the server into selecting an occupied port.
4. **Path Resolution & Nested Bundle Detection:**
   - `frontend/lib/services/backend_sidecar_service.dart` used raw backslash string concatenation which could mismatch mixed slash conventions, and did not search nested PyInstaller output folders (`backend/revvault-backend/revvault-backend.exe`).
5. **Silent Diagnostic Failure:**
   - In Flutter release builds, `debugPrint` is suppressed, and stderr was not captured into state, masking the fatal backend crash reason from the user.

---

## 3. Step-by-Step Surgical Fix Procedure

1. **Expose All Dynamic Submodules & Data in `backend/revvault.spec`:**
   - Collected all submodules for `fastapi`, `starlette`, `anyio`, `sse_starlette`, `mcp.server`, `mcp.types`, `mcp.shared`, and `sqlite3`.
   - Added explicit entries for `anyio._backends._asyncio`, `anyio._core._asyncio_selector_thread`, and all Uvicorn protocols/loops.
   - Added data files collection for `sqlglot`, `fastapi`, `starlette`, `anyio`, `mcp`, and `uvicorn`.
2. **Harden `backend/run_server.py`:**
   - Disabled `SO_REUSEADDR` on Windows to prevent port-probing false positives.
   - Implemented persistent fatal crash logging (`log_fatal_error()`) writing directly to `%APPDATA%\Relva\RevVault\backend.log` and the executable directory.
   - In interactive development mode, prevented immediate console closure on unhandled crash.
3. **Equip `backend/requirements.txt` with Explicit Core Runtime Dependencies:**
   - Added explicit `anyio>=4.0.0`, `starlette>=0.38.0`, `sse-starlette>=2.0.0`, and `httpx>=0.27.0`.
4. **Harden Flutter `BackendSidecarService`:**
   - Imported `package:path/path.dart as p;` and used `p.normalize(p.join(...))` for all candidate paths on Windows and Linux.
   - Added candidates for both direct `backend/revvault-backend.exe` and nested `backend/revvault-backend/revvault-backend.exe`.
   - Added `_lastStderr` and `_lastExitCode` tracking, passing `REVVAULT_HEADLESS: '1'`.
   - Increased port announcement timeout to 8 seconds to accommodate cold starts with Windows Defender.
   - Added early polling exit when child process dies during health check.
5. **Surface Diagnostics in `AppState`:**
   - Enhanced `app_state.dart` to display the exact backend exit code and error detail in `errorMessage`.
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
