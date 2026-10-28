# -*- mode: python ; coding: utf-8 -*-
import sys
from pathlib import Path
from PyInstaller.utils.hooks import collect_submodules, collect_data_files

block_cipher = None
backend_dir = Path(SPECPATH).resolve()

# Collect all dynamic submodules for key libraries
hidden_imports = (
    collect_submodules("uvicorn")
    + collect_submodules("fastapi")
    + collect_submodules("starlette")
    + collect_submodules("anyio")
    + collect_submodules("sse_starlette")
    + collect_submodules("mcp.server")
    + collect_submodules("mcp.types")
    + collect_submodules("mcp.shared")
    + collect_submodules("sqlglot")
    + collect_submodules("aiosqlite")
    + collect_submodules("asyncpg")
    + collect_submodules("pydantic")
    + collect_submodules("pydantic_core")
    + collect_submodules("websockets")
    + collect_submodules("sqlite3")
    + collect_submodules("app")
)

# Optional HTTP client module collection
for _pkg in ["httpx", "httpx2", "httpcore", "httpcore2"]:
    try:
        hidden_imports += collect_submodules(_pkg)
    except Exception:
        pass

hidden_imports += (
    [
        "anyio._backends._asyncio",
        "anyio._core._asyncio_selector_thread",
        "uvicorn.loops.auto",
        "uvicorn.loops.asyncio",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.http.h11_impl",
        "uvicorn.protocols.http.httptools_impl",
        "uvicorn.protocols.websockets.auto",
        "uvicorn.protocols.websockets.websockets_impl",
        "uvicorn.protocols.websockets.wsproto_impl",
        "uvicorn.lifespan.on",
        "uvicorn.lifespan.off",
        "multipart",
        "python_multipart",
    ]
)

# Collect required runtime data files (sqlglot dialects, templates, etc.)
datas = (
    collect_data_files("sqlglot")
    + collect_data_files("fastapi")
    + collect_data_files("starlette")
    + collect_data_files("anyio")
    + collect_data_files("mcp")
    + collect_data_files("uvicorn")
)

# If pre-compiled web assets exist, embed them directly
web_dir = backend_dir.parent / "frontend" / "build" / "web"
if web_dir.is_dir():
    datas.append((str(web_dir), "web"))

a = Analysis(
    ["run_server.py"],
    pathex=[str(backend_dir)],
    binaries=[],
    datas=datas,
    hiddenimports=hidden_imports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "tkinter",
        "matplotlib",
        "pytest",
        "pytest_asyncio",
        "unittest",
        "IPython",
        "pdb",
        "turtle",
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="revvault-backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=True if sys.platform != "win32" else False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=True if sys.platform != "win32" else False,
    upx=True,
    upx_exclude=[],
    name="revvault-backend",
)
