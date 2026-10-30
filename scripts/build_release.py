#!/usr/bin/env python3
"""
RevVault — Cross-Platform Release Packaging Pipeline
Builds and packages self-contained distribution bundles for:
  - Linux (tar.gz and AppImage)
  - Windows (.zip bundle)
  - Android (.apk release)
  - Standalone Frozen Backend (PyInstaller)
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
FRONTEND_DIR = ROOT_DIR / "frontend"
BACKEND_DIR = ROOT_DIR / "backend"
DIST_DIR = ROOT_DIR / "dist"

def log(msg: str):
    print(f"\033[1;36m[RevVault Builder]\033[0m {msg}", flush=True)

def error(msg: str):
    print(f"\033[1;31m[RevVault Builder ERROR]\033[0m {msg}", file=sys.stderr, flush=True)

def find_flutter() -> str:
    env_bin = os.environ.get("FLUTTER_BIN")
    if env_bin and os.path.isfile(env_bin):
        return env_bin
    which = shutil.which("flutter")
    if which:
        return which
    # Common local paths
    local_candidates = [
        Path.home() / "flutter" / "flutter" / "bin" / "flutter",
        Path.home() / "flutter" / "bin" / "flutter",
        Path("/usr/local/bin/flutter"),
    ]
    for c in local_candidates:
        if c.is_file():
            return str(c)
    raise RuntimeError("Flutter binary not found in PATH or standard directories.")

def find_python() -> str:
    if sys.platform == "win32":
        venv_py = BACKEND_DIR / ".venv" / "Scripts" / "python.exe"
    else:
        venv_py = BACKEND_DIR / ".venv" / "bin" / "python"
    if venv_py.is_file():
        return str(venv_py)
    return sys.executable

def run_cmd(cmd: list[str], cwd: Path | None = None, env: dict | None = None):
    log(f"Executing: {' '.join(str(c) for c in cmd)}")
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    res = subprocess.run(cmd, cwd=str(cwd) if cwd else None, env=merged_env)
    if res.returncode != 0:
        raise RuntimeError(f"Command failed with code {res.returncode}: {' '.join(str(c) for c in cmd)}")

def build_web():
    log("Building optimized static Flutter Web client...")
    flutter = find_flutter()
    run_cmd([flutter, "build", "web", "--release"], cwd=FRONTEND_DIR)
    web_dist = FRONTEND_DIR / "build" / "web"
    if not (web_dist / "index.html").is_file():
        raise RuntimeError("Flutter Web build finished but index.html was not produced.")
    log("Web client successfully built.")
    return web_dist

def build_backend():
    log("Compiling standalone Python backend executable via PyInstaller...")
    python = find_python()

    # Verify PyInstaller is installed in venv
    check = subprocess.run([python, "-m", "PyInstaller", "--version"], capture_output=True, text=True)
    if check.returncode != 0:
        log("PyInstaller not found in venv. Installing pyinstaller...")
        run_cmd([python, "-m", "pip", "install", "pyinstaller>=6.5.0"])

    spec_file = BACKEND_DIR / "revvault.spec"
    dist_build_dir = DIST_DIR / "backend_build"
    work_dir = DIST_DIR / "backend_work"

    run_cmd(
        [
            python,
            "-m",
            "PyInstaller",
            "--clean",
            "-y",
            str(spec_file),
            "--distpath",
            str(dist_build_dir),
            "--workpath",
            str(work_dir),
        ],
        cwd=BACKEND_DIR,
    )

    backend_exe_dir = dist_build_dir / "revvault-backend"
    if not backend_exe_dir.is_dir():
        raise RuntimeError("PyInstaller build completed but output directory was not found.")

    log(f"Standalone backend successfully compiled at: {backend_exe_dir}")
    return backend_exe_dir

def build_linux(version: str, make_appimage: bool = True):
    if sys.platform != "linux":
        error("Linux desktop builds must be compiled on a Linux host.")
        return

    flutter = find_flutter()
    log("Building Flutter Linux Desktop release binary...")
    run_cmd([flutter, "build", "linux", "--release"], cwd=FRONTEND_DIR)

    flutter_bundle = FRONTEND_DIR / "build" / "linux" / "x64" / "release" / "bundle"
    if not (flutter_bundle / "rev_vault").is_file():
        raise RuntimeError("Flutter Linux release binary not found in bundle.")

    # 1. Compile backend
    backend_dist = build_backend()

    # 2. Assemble release staging directory
    staging = DIST_DIR / f"revvault-linux-x64-v{version}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True, exist_ok=True)

    log("Assembling release bundle...")
    # Copy Flutter bundle contents
    for item in flutter_bundle.iterdir():
        dest = staging / item.name
        if item.is_dir():
            shutil.copytree(item, dest, symlinks=True)
        else:
            shutil.copy2(item, dest)

    # Copy backend distribution into ./backend subdirectory of bundle
    backend_dest = staging / "backend"
    shutil.copytree(backend_dist, backend_dest, symlinks=True)

    # Optional binary stripping
    strip = shutil.which("strip")
    if strip:
        log("Stripping debug symbols from Linux binaries for size optimization...")
        try:
            subprocess.run([strip, str(staging / "rev_vault")], capture_output=True)
        except Exception:
            pass

    # 3. Create .tar.gz archive
    archive_name = f"revvault-linux-x64-v{version}.tar.gz"
    archive_path = DIST_DIR / archive_name
    log(f"Packaging {archive_name}...")
    with tarfile.open(archive_path, "w:gz") as tar:
        tar.add(staging, arcname=staging.name)

    log(f"Linux tarball release ready: {archive_path}")

    # 4. Optional AppImage generation
    if make_appimage:
        generate_appimage(staging, version)

def generate_appimage(bundle_dir: Path, version: str):
    log("Preparing AppDir for AppImage creation...")
    appdir = DIST_DIR / "AppDir"
    if appdir.exists():
        shutil.rmtree(appdir)
    appdir.mkdir(parents=True, exist_ok=True)

    # Copy bundle into AppDir
    for item in bundle_dir.iterdir():
        dest = appdir / item.name
        if item.is_dir():
            shutil.copytree(item, dest, symlinks=True)
        else:
            shutil.copy2(item, dest)

    # Copy AppImage metadata
    shutil.copy2(ROOT_DIR / "scripts" / "appimage" / "AppRun", appdir / "AppRun")
    os.chmod(appdir / "AppRun", 0o755)

    shutil.copy2(ROOT_DIR / "scripts" / "appimage" / "revvault.desktop", appdir / "revvault.desktop")
    shutil.copy2(ROOT_DIR / "scripts" / "appimage" / "revvault.png", appdir / "revvault.png")

    appimagetool = shutil.which("appimagetool")
    if not appimagetool:
        # Check if downloaded in scripts/
        local_tool = ROOT_DIR / "scripts" / "appimagetool-x86_64.AppImage"
        if local_tool.is_file():
            appimagetool = str(local_tool)

    if appimagetool:
        out_appimage = DIST_DIR / f"RevVault-v{version}-x86_64.AppImage"
        log(f"Invoking appimagetool to create {out_appimage.name}...")
        env = os.environ.copy()
        env["ARCH"] = "x86_64"
        env["APPIMAGE_EXTRACT_AND_RUN"] = "1"
        run_cmd([appimagetool, str(appdir), str(out_appimage)], env=env)
        log(f"AppImage successfully generated: {out_appimage}")
    else:
        log("Notice: 'appimagetool' not found in PATH. AppDir prepared at dist/AppDir for manual conversion.")

def build_windows(version: str):
    if sys.platform != "win32":
        error("Windows desktop builds must be compiled on a Windows host or CI runner.")
        return

    flutter = find_flutter()
    log("Building Flutter Windows Desktop release binary...")
    run_cmd([flutter, "build", "windows", "--release"], cwd=FRONTEND_DIR)

    flutter_bundle = FRONTEND_DIR / "build" / "windows" / "x64" / "runner" / "Release"
    backend_dist = build_backend()

    staging = DIST_DIR / f"revvault-windows-x64-v{version}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True, exist_ok=True)

    # Copy Flutter bundle
    for item in flutter_bundle.iterdir():
        dest = staging / item.name
        if item.is_dir():
            shutil.copytree(item, dest)
        else:
            shutil.copy2(item, dest)

    # Copy backend bundle
    shutil.copytree(backend_dist, staging / "backend")

    # Create zip
    zip_name = f"revvault-windows-x64-v{version}.zip"
    zip_path = DIST_DIR / zip_name
    log(f"Packaging {zip_name}...")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _, files in os.walk(staging):
            for file in files:
                full_path = Path(root) / file
                arcname = full_path.relative_to(DIST_DIR)
                zf.write(full_path, arcname)
    log(f"Windows zip release ready: {zip_path}")

    # Check for Inno Setup compiler to create single-file Setup.exe
    iscc = shutil.which("iscc") or shutil.which("ISCC.exe")
    if not iscc:
        common_iscc = [
            Path(os.environ.get("ProgramFiles(x86)", "C:\\Program Files (x86)")) / "Inno Setup 6" / "ISCC.exe",
            Path(os.environ.get("ProgramFiles", "C:\\Program Files")) / "Inno Setup 6" / "ISCC.exe",
        ]
        for c in common_iscc:
            if c.is_file():
                iscc = str(c)
                break

    if iscc:
        log("Compiling single-file Windows installer using Inno Setup (ISCC)...")
        iss_file = ROOT_DIR / "scripts" / "windows" / "revvault.iss"
        run_cmd([iscc, f"/DMyAppVersion={version}", str(iss_file)])
        setup_exe = DIST_DIR / f"RevVault-Setup-v{version}.exe"
        if setup_exe.is_file():
            log(f"Single-file Windows setup installer ready: {setup_exe}")
    else:
        log("Notice: Inno Setup (ISCC.exe) not found in PATH or standard Program Files directories.")
        log("To generate a single-file 'RevVault-Setup.exe', install Inno Setup (https://jrsoftware.org/isdl.php).")

def build_apk(version: str = "1.0.0"):
    flutter = find_flutter()
    log("Compiling Flutter Android Release APK...")
    run_cmd([flutter, "build", "apk", "--release"], cwd=FRONTEND_DIR)

    apk_source = FRONTEND_DIR / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    if not apk_source.is_file():
        raise RuntimeError(f"APK compilation succeeded but file not found at {apk_source}")

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    out_apk = DIST_DIR / "revvault.apk"
    versioned_apk = DIST_DIR / f"RevVault-v{version}.apk"
    shutil.copy2(apk_source, out_apk)
    shutil.copy2(apk_source, versioned_apk)
    log(f"Android APK successfully packaged: {out_apk} and {versioned_apk}")

def main():
    parser = argparse.ArgumentParser(description="RevVault Unified Release Builder")
    parser.add_argument("--version", default="1.0.0", help="Release version string (default: 1.0.0)")
    parser.add_argument("--linux", action="store_true", help="Build Linux release (.tar.gz and AppImage)")
    parser.add_argument("--windows", action="store_true", help="Build Windows release (.zip)")
    parser.add_argument("--apk", action="store_true", help="Build Android release (.apk)")
    parser.add_argument("--backend-only", action="store_true", help="Build only standalone backend binary")
    parser.add_argument("--web-only", action="store_true", help="Build only Flutter web client assets")
    parser.add_argument("--all", action="store_true", help="Build all supported platforms for current host")
    parser.add_argument("--no-appimage", action="store_true", help="Skip AppImage packaging on Linux")

    args = parser.parse_args()
    DIST_DIR.mkdir(parents=True, exist_ok=True)

    if args.web_only:
        build_web()
        return

    if args.backend_only:
        build_backend()
        return

    if args.apk:
        build_apk(args.version)
        return

    if args.linux or (args.all and sys.platform == "linux"):
        # Pre-build web first so it can be embedded in backend
        try:
            build_web()
        except Exception as e:
            log(f"Web build warning (continuing without embedded web): {e}")
        build_linux(args.version, make_appimage=not args.no_appimage)

    if args.windows or (args.all and sys.platform == "win32"):
        if sys.platform != "win32":
            error("Windows desktop builds must be compiled on a Windows host or via GitHub Actions (windows-latest runner).")
            return
        try:
            build_web()
        except Exception as e:
            log(f"Web build warning (continuing without embedded web): {e}")
        build_windows(args.version)

    if not any([args.linux, args.windows, args.apk, args.backend_only, args.web_only, args.all]):
        # Default behavior: build native platform for current host
        if sys.platform == "linux":
            try:
                build_web()
            except Exception as e:
                log(f"Web build warning: {e}")
            build_linux(args.version, make_appimage=not args.no_appimage)
        elif sys.platform == "win32":
            build_web()
            build_windows(args.version)
        else:
            log("Current platform not supported for desktop build. Use --backend-only or --apk.")

if __name__ == "__main__":
    main()
