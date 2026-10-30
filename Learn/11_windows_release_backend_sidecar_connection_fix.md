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

1. **PyInstaller Missing Subpackages Due to Namespace Directories Without `__init__.py`:**
   - In Python, directories without `__init__.py` are treated as implicit namespace packages (PEP 420).
   - PyInstaller's `collect_submodules("app")` relies on `pkgutil.walk_packages()`, which does not traverse directories without `__init__.py`.
   - As a result, `app.core` (including `agent_service`, `db_manager`, `schema_inspector`), `app.api` (all routes), and `app.mcp` were completely omitted from `PYZ.pyz` in release bundles!
2. **Missing Dynamic Dependencies in `revvault.spec`:**
   - The MCP SDK 2.2.0 dynamically requires top-level packages `mcp_types` (`mcp-types`), `jwt` (`pyjwt`), `typing_inspection`, `jsonschema`, and `opentelemetry`.
   - Uvicorn dynamically requires `httptools`, `h11`, and `websockets_sansio_impl`.
   - Without these in `hidden_imports` and `datas`, `mcp.server.mcpserver` failed immediately with `ModuleNotFoundError: No module named 'mcp_types'`.
3. **Windows `TIME_WAIT` Socket Exhaustion During Port Probing:**
   - `find_available_port()` in `backend/run_server.py` probed for open ports by binding and immediately closing a socket.
   - On Windows, a socket closed without `SO_LINGER (1, 0)` enters `TIME_WAIT` with exclusive address lock.
   - When Uvicorn attempted to bind to the same port milliseconds later, Windows rejected it with `[WinError 10048] Only one usage of each socket address is normally permitted`, causing Uvicorn to crash with exit code 3 (`STARTUP_FAILURE`).
4. **Desktop Sidecar URL Hijack in `app_state.dart`:**
   - If an unreachable custom backend URL was stored in preferences (e.g., from LAN or mobile testing), `AppState.init()` spawned the local desktop sidecar but then set `defaultUrl = savedUrl ?? 'http://127.0.0.1:$port'`.
   - Because `savedUrl` was truthy, it attempted to connect to the dead remote endpoint instead of the freshly spawned local sidecar.
5. **Missing `import json` in `routes_codegen.py`:**
   - Export endpoints in `routes_codegen.py` referenced `json.dumps()` without importing `json`.
6. **Windows PyInstaller Cold-Start Timeout & Path Discovery:**
   - Windows Defender Real-Time Protection scans newly spawned frozen binaries, causing cold-starts to exceed 8 seconds.
   - Candidate search paths in `backend_sidecar_service.dart` lacked fallback coordinates for direct runner testing.

---

## 3. Step-by-Step Surgical Fix Procedure

1. **Instituted Standard Package Markers (`__init__.py`):**
   - Added standard `__init__.py` with Luna's territorial ASCII signature across `backend/app/`, `backend/app/api/`, `backend/app/core/`, and `backend/app/mcp/`.
   - Verified that `collect_submodules("app")` now discovers all 22 internal application modules.
2. **Expose All Dynamic Submodules & Data in `backend/revvault.spec`:**
   - Added `mcp_types`, `jwt`, `typing_inspection`, `jsonschema`, `opentelemetry`, `httptools`, `h11`, and `websockets_sansio_impl` to `hidden_imports`.
   - Added data file collection for `mcp_types`, `jwt`, and `jsonschema`.
3. **Erased Windows Socket `TIME_WAIT` with `SO_LINGER (1, 0)`:**
   - Configured `SO_LINGER` to `(1, 0)` in `find_available_port()` on Windows, ensuring sockets close with an immediate `RST` and release the port instantly for Uvicorn.
4. **Enforced Local Sidecar Precedence on Desktop in `app_state.dart`:**
   - Hardened `AppState.init()` so that fallback to desktop sidecar explicitly binds to `http://127.0.0.1:$port`, preventing stalled remote URLs from hijacking local operation.
5. **Added Missing `import json` in `routes_codegen.py`:**
   - Added top-level `import json` in `backend/app/api/routes_codegen.py`.
6. **Hardened `BackendSidecarService` Timeouts and Discovery:**
   - Extended port announcement timeout to 15s and health check timeout to 20s for Windows Defender cold starts.
   - Added candidate paths covering nested release directories, runner directories, and direct repository execution.
7. **Platform-Guarded Release Script (`scripts/build_release.py`):**
   - Guarded `--windows` build target on Linux host before attempting Flutter web builds, providing clear actionable instructions for CI and Windows compilation.

---

## 4. Verification Proof

- **Module Discovery:** `collect_submodules("app")` confirmed collecting 22 modules (including all core and API routes).
- **Dependency Collection:** Confirmed clean collection of all 760 hidden imports including `mcp_types`, `jwt`, `typing_inspection`, `h11`, and `httptools`.
- **PyInstaller Build & Health Check:** Successfully built frozen executable and verified `GET /health` returning `200 OK` with JSON telemetry.
- **Python Test Suite:** 57/57 tests passing in `backend/tests`.
- **Dart Static Analysis:** 0 errors reported via Dart Tooling Daemon across all modified Flutter files.

---

## 5. Prevention Invariants

1. **Package Directory Standard:** Every subpackage folder inside `backend/app/` must always contain an `__init__.py` file to ensure PyInstaller's AST walker correctly collects all modules.
2. **Windows Socket Linger Standard:** Any port-checking utility that binds before server startup on Windows must set `SO_LINGER (1, 0)` to prevent Winsock address exhaustion (`WSAEADDRINUSE`).
3. **Local Desktop Precedence:** Desktop application startup must never prioritize unreachable cached remote network endpoints over the local embedded sidecar.
