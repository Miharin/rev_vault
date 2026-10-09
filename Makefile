.PHONY: start run backend frontend web web-dev build-web test clean release-linux release-windows release-apk release-backend release-all help

# Default target starts both frontend and backend in one command
start:
	@./start.sh

run:
	@./start.sh

# Run only the Python backend
backend:
	@./backend/.venv/bin/python backend/run_server.py

# Run only the Flutter desktop frontend
frontend:
	@cd frontend && flutter run -d linux

# Run RevVault in resource-optimized single-process web mode
web:
	@./start.sh -w

# Run RevVault web in development hot-reload mode
web-dev:
	@./start.sh -w --dev

# Build the optimized static Flutter web bundle
build-web:
	@cd frontend && flutter build web --release

# Run backend test suite
test:
	@./backend/.venv/bin/pytest backend/tests

# ------------------------------------------------------------------------------
# Release Packaging & Distribution Targets
# ------------------------------------------------------------------------------

# Package Linux release (.tar.gz and AppImage with embedded backend)
release-linux:
	@python3 scripts/build_release.py --linux

# Package Windows release (.zip bundle with embedded backend)
release-windows:
	@python3 scripts/build_release.py --windows

# Compile Android Release APK companion
release-apk:
	@python3 scripts/build_release.py --apk

# Compile standalone PyInstaller backend binary only
release-backend:
	@python3 scripts/build_release.py --backend-only

# Build full distribution
release-all:
	@python3 scripts/build_release.py --all

help:
	@echo "RevVault Commands:"
	@echo "  make (or make start)   - Start both backend & Flutter desktop UI (dev)"
	@echo "  make web               - Start resource-optimized single-process Web UI"
	@echo "  make web-dev           - Start Web UI in dev mode with hot reload"
	@echo "  make build-web         - Compile optimized static Flutter web bundle"
	@echo "  make backend           - Start only the FastAPI backend server"
	@echo "  make frontend          - Start only the Flutter desktop client"
	@echo "  make test              - Run backend pytest test suite"
	@echo ""
	@echo "Release & Deployment Packaging:"
	@echo "  make release-linux     - Build standalone Linux .tar.gz and .AppImage"
	@echo "  make release-windows   - Build standalone Windows .zip bundle"
	@echo "  make release-apk       - Build Android companion APK"
	@echo "  make release-backend   - Build frozen PyInstaller backend executable"
	@echo "  make release-all       - Build all platform targets for current host"
