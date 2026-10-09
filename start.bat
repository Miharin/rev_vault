@echo off
setlocal

set "ROOT_DIR=%~dp0"
echo ==========================================================
echo           RevVault - Relva Database Companion            
echo ==========================================================

:: Resolve Python binary
if exist "%ROOT_DIR%backend\.venv\Scripts\python.exe" (
    set "PYTHON_BIN=%ROOT_DIR%backend\.venv\Scripts\python.exe"
) else (
    set "PYTHON_BIN=python"
)

:: Start Backend in a minimized window
echo [RevVault] Starting Backend service on http://127.0.0.1:8000...
start "RevVault Backend" /min "%PYTHON_BIN%" "%ROOT_DIR%backend\run_server.py"

:: Give backend 3 seconds to spin up
echo [RevVault] Waiting for backend initialization...
timeout /t 3 /nobreak >nul

:: Launch Flutter Desktop App
echo [RevVault] Launching Flutter Desktop UI...
cd /d "%ROOT_DIR%frontend"
flutter run -d windows %*

echo [RevVault] Frontend session ended.
pause
