#!/usr/bin/env bash
# ==============================================================================
# RevVault — Single-Command Startup Script (Frontend + Resilient Backend)
# ==============================================================================
set -e

# Resolve project root directory regardless of current working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"

# Text styles & colors
if [ -t 1 ]; then
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    CYAN=''
    GREEN=''
    YELLOW=''
    RED=''
    BOLD=''
    NC=''
fi

echo -e "${CYAN}${BOLD}"
echo "=========================================================="
echo "          🛡️  RevVault — Relva Database Companion         "
echo "=========================================================="
echo -e "${NC}"

# Locate Python environment
if [ -x "$ROOT_DIR/backend/.venv/bin/python" ]; then
    PYTHON_BIN="$ROOT_DIR/backend/.venv/bin/python"
elif command -v python3 &>/dev/null; then
    PYTHON_BIN="$(command -v python3)"
elif command -v python &>/dev/null; then
    PYTHON_BIN="$(command -v python)"
else
    echo -e "${RED}❌ Error: Python not found. Please install Python 3.10+.${NC}"
    exit 1
fi

# Locate Flutter binary
if command -v flutter &>/dev/null; then
    FLUTTER_BIN="$(command -v flutter)"
elif [ -x "$HOME/flutter/flutter/bin/flutter" ]; then
    FLUTTER_BIN="$HOME/flutter/flutter/bin/flutter"
elif [ -x "$HOME/flutter/bin/flutter" ]; then
    FLUTTER_BIN="$HOME/flutter/bin/flutter"
elif [ -n "$FLUTTER_HOME" ] && [ -x "$FLUTTER_HOME/bin/flutter" ]; then
    FLUTTER_BIN="$FLUTTER_HOME/bin/flutter"
else
    echo -e "${RED}❌ Error: Flutter CLI not found in PATH.${NC}"
    exit 1
fi

PORT="${REVVAULT_PORT:-8000}"
HOST="${REVVAULT_HOST:-127.0.0.1}"
WEB_PORT="${REVVAULT_WEB_PORT:-3000}"

# Parse custom flags
FORCE_RESTART_BACKEND=1
IS_WEB=0
IS_LAN=0
IS_DEV_WEB=0
FORCE_REBUILD=0
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-backend|-k)
            FORCE_RESTART_BACKEND=0
            shift
            ;;
        --web|-w)
            IS_WEB=1
            shift
            ;;
        --dev|-D)
            IS_DEV_WEB=1
            shift
            ;;
        --rebuild)
            FORCE_REBUILD=1
            shift
            ;;
        --lan|-l)
            IS_LAN=1
            IS_WEB=1
            HOST="0.0.0.0"
            shift
            ;;
        --web-port|-wp)
            WEB_PORT="$2"
            shift 2
            ;;
        --port|-p)
            PORT="$2"
            shift 2
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: ./start.sh [options] [-- flutter_args]"
            echo ""
            echo "Options:"
            echo "  -w, --web          Launch RevVault in web browser (resource-optimized single process)"
            echo "  -D, --dev          Run Flutter Web in dev mode with hot reload (higher RAM/CPU)"
            echo "      --rebuild      Rebuild static web release bundle before starting"
            echo "  -l, --lan          Expose RevVault across Local Area Network (LAN) on 0.0.0.0"
            echo "  -wp, --web-port P  Port for Flutter dev server if --dev is used (default: 3000)"
            echo "  -p, --port P       Port for Python backend API & static Web UI (default: 8000)"
            echo "  --host H           Host interface to bind backend (default: 127.0.0.1)"
            echo "  -k, --keep-backend Reuse running backend instance without restart"
            echo "  -d, --device DEV   Specify Flutter target device (linux, windows, chrome, web-server)"
            echo "  -h, --help         Show this help message"
            exit 0
            ;;
        *)
            FORWARD_ARGS+=("$1")
            shift
            ;;
    esac
done

export REVVAULT_PORT="$PORT"
export REVVAULT_HOST="$HOST"
export REVVAULT_WEB_PORT="$WEB_PORT"

# When bound to 0.0.0.0, internal healthcheck must query 127.0.0.1
if [ "$HOST" == "0.0.0.0" ]; then
    CHECK_HOST="127.0.0.1"
else
    CHECK_HOST="$HOST"
fi
HEALTH_URL="http://${CHECK_HOST}:${PORT}/health"

# Detect primary LAN IP for network display
LAN_IP="$("$PYTHON_BIN" -c "import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('8.8.8.8', 80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")"

# Function to check if backend is responding
check_backend_healthy() {
    "$PYTHON_BIN" -c "import urllib.request, sys; sys.exit(0 if urllib.request.urlopen('$HEALTH_URL', timeout=1).getcode() == 200 else 1)" 2>/dev/null
}

# Function to check if TCP port is actively listened on
is_port_in_use() {
    "$PYTHON_BIN" -c "import socket, sys; s = socket.socket(socket.AF_INET, socket.SOCK_STREAM); res = s.connect_ex(('$CHECK_HOST', int('$PORT'))); s.close(); sys.exit(0 if res == 0 else 1)" 2>/dev/null
}

# Function to resolve PIDs listening on PORT via lsof, fuser, or ss
get_port_pids() {
    local pids=""
    if command -v lsof &>/dev/null; then
        pids="$(lsof -t -i:"$PORT" 2>/dev/null || true)"
    fi
    if [ -z "$pids" ] && command -v fuser &>/dev/null; then
        pids="$(fuser "$PORT/tcp" 2>/dev/null || true)"
    fi
    if [ -z "$pids" ] && command -v ss &>/dev/null; then
        pids="$(ss -tulpn "sport = :$PORT" 2>/dev/null | grep -o 'pid=[0-9]*' | cut -d= -f2 | sort -u || true)"
    fi
    echo "$pids"
}

BACKEND_PID=""
WATCHDOG_PID=""
CLEANUP_DONE=0
SHUTDOWN_FILE="$ROOT_DIR/.shutdown_flag"

rm -f "$SHUTDOWN_FILE" 2>/dev/null || true

cleanup() {
    if [ "$CLEANUP_DONE" -eq 1 ]; then
        return
    fi
    CLEANUP_DONE=1
    touch "$SHUTDOWN_FILE" 2>/dev/null || true

    if [ -n "$WATCHDOG_PID" ] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
        kill "$WATCHDOG_PID" 2>/dev/null || true
    fi

    if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo -e "\n${YELLOW}🛑 Shutting down RevVault backend (PID $BACKEND_PID)...${NC}"
        kill "$BACKEND_PID" 2>/dev/null || true
        for _ in {1..5}; do
            if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
                break
            fi
            sleep 0.4
        done
        kill -9 "$BACKEND_PID" 2>/dev/null || true
        echo -e "${GREEN}✅ Backend successfully terminated.${NC}"
    fi

    rm -f "$SHUTDOWN_FILE" 2>/dev/null || true
}

trap cleanup EXIT INT TERM HUP

# Step 1: Handle Backend auto-restart / initial launch
if [ "$FORCE_RESTART_BACKEND" -eq 1 ]; then
    if is_port_in_use || check_backend_healthy; then
        echo -e "${YELLOW}🔄 Existing process or backend detected on port ${PORT}. Clearing port...${NC}"
        OLD_PIDS="$(get_port_pids)"
        if [ -n "$OLD_PIDS" ]; then
            for pid in $OLD_PIDS; do
                kill "$pid" 2>/dev/null || true
            done
            sleep 0.5
            for pid in $OLD_PIDS; do
                kill -9 "$pid" 2>/dev/null || true
            done
            sleep 0.3
        fi
    fi
fi

if check_backend_healthy && [ "$FORCE_RESTART_BACKEND" -eq 0 ]; then
    echo -e "${GREEN}⚡ Reusing existing RevVault backend at ${HEALTH_URL}${NC}"
else
    echo -e "${CYAN}⚙️  Starting RevVault Backend Watchdog service on ${HEALTH_URL}...${NC}"

    # Launch watchdog loop that auto-restarts backend process if it ever crashes
    (
        cd "$ROOT_DIR/backend"
        while true; do
            if [ -f "$SHUTDOWN_FILE" ]; then
                break
            fi
            "$PYTHON_BIN" run_server.py &
            CURR_BACKEND_PID=$!
            echo "$CURR_BACKEND_PID" > "$ROOT_DIR/.backend_pid" 2>/dev/null || true

            wait "$CURR_BACKEND_PID" || true

            if [ -f "$SHUTDOWN_FILE" ]; then
                break
            fi
            echo -e "\n${YELLOW}⚠️  Backend process exited unexpectedly. Auto-restarting backend service...${NC}"
            sleep 1
        done
    ) &
    WATCHDOG_PID=$!

    # Wait for initial backend PID and health check
    for _ in {1..10}; do
        if [ -f "$ROOT_DIR/.backend_pid" ]; then
            BACKEND_PID="$(cat "$ROOT_DIR/.backend_pid" 2>/dev/null || true)"
            break
        fi
        sleep 0.2
    done
    rm -f "$ROOT_DIR/.backend_pid" 2>/dev/null || true

    echo -n "   Waiting for backend to initialize"
    READY=0
    for _ in {1..30}; do
        if check_backend_healthy; then
            READY=1
            break
        fi
        echo -n "."
        sleep 0.5
    done
    echo ""

    if [ "$READY" -ne 1 ]; then
        echo -e "${RED}❌ Timeout waiting for RevVault backend to start on ${HEALTH_URL}.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Backend is live and auto-monitored! (PID: ${BACKEND_PID:-active})${NC}"
fi

# Step 2: Determine target device / platform
DETECTED_OS="$(uname -s)"
DEVICE_ARGS=()

HAS_DEVICE_ARG=0
for arg in "${FORWARD_ARGS[@]}"; do
    if [[ "$arg" == "-d" || "$arg" == "--device" || "$arg" == -d* ]]; then
        HAS_DEVICE_ARG=1
        break
    fi
done

if [ "$HAS_DEVICE_ARG" -eq 0 ]; then
    if [ "$IS_WEB" -eq 1 ]; then
        if [ "$IS_LAN" -eq 1 ]; then
            DEVICE_ARGS=("-d" "web-server" "--web-hostname=0.0.0.0" "--web-port=$WEB_PORT")
        elif command -v google-chrome &>/dev/null || command -v chromium &>/dev/null || command -v chromium-browser &>/dev/null; then
            DEVICE_ARGS=("-d" "chrome" "--web-port=$WEB_PORT")
        else
            DEVICE_ARGS=("-d" "web-server" "--web-hostname=127.0.0.1" "--web-port=$WEB_PORT")
        fi
    else
        case "$DETECTED_OS" in
            Linux*)  DEVICE_ARGS=("-d" "linux") ;;
            Darwin*) DEVICE_ARGS=("-d" "macos") ;;
            CYGWIN*|MINGW*|MSYS*) DEVICE_ARGS=("-d" "windows") ;;
        esac
    fi
fi

# Step 3: Launch Flutter App
if [ "$IS_WEB" -eq 1 ]; then
    if [ "$IS_DEV_WEB" -eq 1 ]; then
        echo -e "${CYAN}${BOLD}🌐 Launching RevVault Web UI in Dev Hot-Reload Mode...${NC}"
        if [ "$IS_LAN" -eq 1 ]; then
            echo -e "${GREEN}   📡 Local PC Access:    ${BOLD}http://localhost:${WEB_PORT}${NC}"
            echo -e "${GREEN}   📡 LAN Network Access:  ${BOLD}http://${LAN_IP}:${WEB_PORT}${NC}"
            echo -e "${CYAN}   ⚙️  Backend API:         http://${LAN_IP}:${PORT}${NC}"
        else
            echo -e "${GREEN}   📡 Web URL:             ${BOLD}http://localhost:${WEB_PORT}${NC}"
            echo -e "${CYAN}   ⚙️  Backend API:         http://localhost:${PORT}${NC}\n"
        fi
        echo -e "${YELLOW}   (Running with Dart DevTools & VM observatory active)${NC}\n"
        cd "$ROOT_DIR/frontend"
        "$FLUTTER_BIN" run "${DEVICE_ARGS[@]}" "${FORWARD_ARGS[@]}"
    else
        WEB_INDEX="$ROOT_DIR/frontend/build/web/index.html"
        if [ ! -f "$WEB_INDEX" ] || [ "$FORCE_REBUILD" -eq 1 ]; then
            echo -e "${CYAN}🔨 Compiling optimized static Flutter Web client (release mode)...${NC}"
            cd "$ROOT_DIR/frontend"
            "$FLUTTER_BIN" build web --release
        fi

        echo -e "${GREEN}${BOLD}🌐 RevVault Web UI is LIVE in Resource-Optimized Single-Process Mode!${NC}"
        if [ "$IS_LAN" -eq 1 ]; then
            echo -e "${GREEN}   📡 Local PC Access:    ${BOLD}http://localhost:${PORT}${NC}"
            echo -e "${GREEN}   📡 LAN Network Access:  ${BOLD}http://${LAN_IP}:${PORT}${NC}"
            echo -e "${CYAN}   ⚙️  Unified Backend:    http://${LAN_IP}:${PORT}/health${NC}"
            TARGET_OPEN_URL="http://localhost:${PORT}"
        else
            echo -e "${GREEN}   📡 Web URL:             ${BOLD}http://localhost:${PORT}${NC}"
            echo -e "${CYAN}   ⚙️  Unified Backend:    http://localhost:${PORT}/health${NC}"
            TARGET_OPEN_URL="http://localhost:${PORT}"
        fi
        echo -e "\n${CYAN}💡 RAM & CPU Optimization Active:${NC}"
        echo -e "   - Single process: Python FastAPI serves both API & pre-compiled web client."
        echo -e "   - Host Flutter dev toolchain is idle (saving ~600MB host RAM)."
        echo -e "   - To run with interactive hot reload instead, use: ${BOLD}./start.sh -w --dev${NC}\n"
        echo -e "${YELLOW}Press Ctrl+C or 'q' to stop RevVault.${NC}\n"

        # Attempt to open browser automatically if available
        if command -v xdg-open &>/dev/null; then
            xdg-open "$TARGET_OPEN_URL" 2>/dev/null &
        elif command -v google-chrome &>/dev/null; then
            google-chrome "$TARGET_OPEN_URL" 2>/dev/null &
        elif command -v chromium &>/dev/null; then
            chromium "$TARGET_OPEN_URL" 2>/dev/null &
        fi

        # Keep alive on watchdog process
        wait "$WATCHDOG_PID" 2>/dev/null || while true; do sleep 1; done
    fi
else
    echo -e "${CYAN}🖥️  Launching RevVault Flutter Desktop UI...${NC}"
    echo -e "${CYAN}   (Closing the application or pressing 'q' / Ctrl+C will stop everything)${NC}\n"
    cd "$ROOT_DIR/frontend"
    "$FLUTTER_BIN" run "${DEVICE_ARGS[@]}" "${FORWARD_ARGS[@]}"
fi

