import argparse
import os
import socket
import sys
import multiprocessing
from pathlib import Path

# Add backend directory to sys.path for both standard and frozen environments
if getattr(sys, "frozen", False):
    backend_dir = Path(sys._MEIPASS)
else:
    backend_dir = Path(__file__).resolve().parent

if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

import uvicorn
from app.main import app

def find_available_port(start_port: int, max_attempts: int = 30) -> int:
    """Attempts to find an open TCP port starting from start_port."""
    for p in range(start_port, start_port + max_attempts):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                s.bind(("0.0.0.0", p))
                return p
            except OSError:
                continue
    return start_port

def main():
    multiprocessing.freeze_support()

    parser = argparse.ArgumentParser(description="RevVault Backend & API Service")
    parser.add_argument(
        "--port",
        "-p",
        type=int,
        default=int(os.environ.get("REVVAULT_PORT", 8000)),
        help="Port to bind backend server (default: 8000)"
    )
    parser.add_argument(
        "--host",
        "-H",
        type=str,
        default=os.environ.get("REVVAULT_HOST", "0.0.0.0"),
        help="Host interface to bind backend (default: 0.0.0.0)"
    )
    parser.add_argument(
        "--auto-port",
        action="store_true",
        default=True,
        help="Automatically probe for an available port if requested port is busy"
    )
    parser.add_argument(
        "--reload",
        action="store_true",
        default=os.environ.get("REVVAULT_RELOAD", "false").lower() in ("true", "1"),
        help="Enable auto-reload for development"
    )
    args, unknown = parser.parse_known_args()

    port = find_available_port(args.port) if args.auto_port else args.port
    os.environ["REVVAULT_PORT"] = str(port)

    # Output marker for parent processes (e.g. Flutter desktop sidecar manager)
    print(f"REVVAULT_ASSIGNED_PORT={port}", flush=True)
    print(f"Starting RevVault Backend & API on http://{args.host}:{port}", flush=True)

    if args.reload and not getattr(sys, "frozen", False):
        uvicorn.run("app.main:app", host=args.host, port=port, reload=True, log_level="info")
    else:
        uvicorn.run(app, host=args.host, port=port, reload=False, log_level="info")

if __name__ == "__main__":
    main()
