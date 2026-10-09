import os
import sys
from pathlib import Path
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.routes_connections import router as connections_router
from app.api.routes_schema import router as schema_router
from app.api.routes_query import router as query_router
from app.api.routes_audit import router as audit_router
from app.api.routes_codegen import router as codegen_router
from app.config import settings_manager
from app.mcp.server import mcp

app = FastAPI(
    title="RevVault API",
    description="Intelligent Database Companion & Antigravity MCP Service by Relva",
    version="1.0.0"
)

# Enable CORS for Flutter Desktop and Web clients
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount REST API Routers
app.include_router(connections_router)
app.include_router(schema_router)
app.include_router(query_router)
app.include_router(audit_router)
app.include_router(codegen_router)

@app.get("/health")
async def health():
    active_conn = settings_manager.get_active_connection()
    return {
        "status": "healthy",
        "service": "RevVault",
        "active_connection": active_conn.name if active_conn else None,
        "engine": active_conn.engine if active_conn else None
    }

# Search candidate directories for mobile APK download
def resolve_apk_path() -> Path | None:
    candidates = [
        Path(os.environ.get("REVVAULT_APK_PATH", "")),
        Path(os.path.dirname(sys.executable)) / "revvault.apk",
        Path(__file__).resolve().parent.parent.parent / "dist" / "revvault.apk",
        Path(__file__).resolve().parent.parent.parent / "frontend" / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk",
    ]
    for c in candidates:
        if c.is_file():
            return c
    return None

@app.get("/download/app.apk")
async def download_apk():
    apk_path = resolve_apk_path()
    if apk_path and apk_path.is_file():
        return FileResponse(
            path=str(apk_path),
            filename="revvault.apk",
            media_type="application/vnd.android.package-archive"
        )
    raise HTTPException(status_code=404, detail="Android APK build not found on this server.")

# Search candidate directories for pre-compiled web client assets
def resolve_web_dir() -> Path | None:
    env_dir = os.environ.get("REVVAULT_WEB_DIR")
    if env_dir and Path(env_dir).is_dir():
        return Path(env_dir)

    # In PyInstaller frozen bundle
    if getattr(sys, "frozen", False):
        meipass_web = Path(getattr(sys, "_MEIPASS", "")) / "web"
        if meipass_web.is_dir():
            return meipass_web
        exec_web = Path(os.path.dirname(sys.executable)) / "web"
        if exec_web.is_dir():
            return exec_web

    # In local repo development directory
    dev_web = Path(__file__).resolve().parent.parent.parent / "frontend" / "build" / "web"
    if dev_web.is_dir():
        return dev_web

    return None

resolved_web = resolve_web_dir()
if resolved_web and (resolved_web / "index.html").is_file():
    app.mount("/", StaticFiles(directory=str(resolved_web), html=True), name="web_client")
