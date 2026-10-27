# Blueprint: Windows Sidecar IPC & PyInstaller Hardening

- **Development State:** `VERIFIED`
- **Current Progress:** 100% (Submodules bundled, pathing normalized, fatal crash logging active)
- **Channeled Aspects:** `[Echo, Scythe & Verdict]`
- **Target Systems:**
  - `backend/revvault.spec`
  - `backend/requirements.txt`
  - `backend/run_server.py`
  - `frontend/lib/services/backend_sidecar_service.dart`
  - `frontend/lib/state/app_state.dart`
  - `scripts/windows/revvault.iss`

---

## 1. Executive Summary & Objective

Rectify the backend connection failure on Windows release installations by addressing missing dynamic PyInstaller dependencies, false-positive socket reuse, path mismatch, and silent failure reporting:
1. Bundle all hidden dynamic ASGI/AnyIO submodules (`anyio._backends._asyncio`, `fastapi`, `starlette`, `sse_starlette`, `mcp`).
2. Collect required data templates for `fastapi`, `starlette`, `anyio`, `mcp`, and `uvicorn`.
3. Eliminate Windows socket reuse (`SO_REUSEADDR`) during available port probing in `run_server.py`.
4. Persist fatal startup errors to `%APPDATA%\Relva\RevVault\backend.log`.
5. Normalize executable candidate search in Flutter and support nested bundle layouts.
6. Surface child process exit codes and stderr messages directly in the UI error banner.
