.PHONY: start run backend frontend web web-dev build-web test clean release-linux release-windows release-apk release-backend release-all install uninstall allow-firewall help

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

# Install current Linux release bundle into user environment
install:
	@mkdir -p ~/.local/share/revvault ~/.local/bin ~/.local/share/icons/hicolor/256x256/apps ~/.local/share/applications
	@latest_dir=$$(ls -td dist/revvault-linux-x64-v* 2>/dev/null | head -n 1); \
	if [ -n "$$latest_dir" ] && [ -d "$$latest_dir" ]; then \
		echo "Installing RevVault from $$latest_dir to ~/.local/share/revvault..."; \
		cp -rT "$$latest_dir" ~/.local/share/revvault; \
	elif [ -f dist/revvault-linux-x64-v*.tar.gz ]; then \
		echo "Extracting RevVault tarball to ~/.local/share/revvault..."; \
		tar -xzf dist/revvault-linux-x64-v*.tar.gz -C ~/.local/share/revvault --strip-components=1; \
	else \
		echo "Error: No release build found in dist/. Run 'make release-linux' first."; \
		exit 1; \
	fi
	@chmod +x ~/.local/share/revvault/rev_vault ~/.local/share/revvault/backend/revvault-backend
	@ln -sf ~/.local/share/revvault/rev_vault ~/.local/bin/revvault
	@cp scripts/appimage/revvault.png ~/.local/share/icons/hicolor/256x256/apps/revvault.png
	@printf '[Desktop Entry]\nName=RevVault\nGenericName=Database Companion & Agent Hub\nComment=Intelligent Database Companion & Antigravity MCP Service\nExec=%s/.local/share/revvault/rev_vault %%u\nIcon=revvault\nTerminal=false\nType=Application\nCategories=Development;Database;IDE;Utility;\nKeywords=database;sql;sqlite;postgres;antigravity;mcp;\nStartupNotify=true\n' "$$HOME" > ~/.local/share/applications/revvault.desktop
	@update-desktop-database ~/.local/share/applications 2>/dev/null || true
	@echo "RevVault successfully installed to ~/.local/share/revvault and ~/.local/bin/revvault."

# Remove RevVault from user environment
uninstall:
	@rm -rf ~/.local/share/revvault
	@rm -f ~/.local/bin/revvault
	@rm -f ~/.local/share/applications/revvault.desktop
	@rm -f ~/.local/share/icons/hicolor/256x256/apps/revvault.png
	@update-desktop-database ~/.local/share/applications 2>/dev/null || true
	@echo "RevVault uninstalled successfully."

# Configure Linux firewall to allow RevVault port range (8000-8010/tcp)
allow-firewall:
	@echo "Allowing RevVault port range (8000:8010/tcp) through Linux firewall..."
	@sudo ufw allow 8000:8010/tcp 2>/dev/null || sudo firewall-cmd --add-port=8000-8010/tcp --permanent 2>/dev/null || sudo iptables -A INPUT -p tcp --match multiport --dports 8000:8010 -j ACCEPT
	@echo "Firewall rule successfully applied."

help:
	@echo "RevVault Commands:"
	@echo "  make (or make start)   - Start both backend & Flutter desktop UI (dev)"
	@echo "  make web               - Start resource-optimized single-process Web UI"
	@echo "  make web-dev           - Start Web UI in dev mode with hot reload"
	@echo "  make build-web         - Compile optimized static Flutter web bundle"
	@echo "  make backend           - Start only the FastAPI backend server"
	@echo "  make frontend          - Start only the Flutter desktop client"
	@echo "  make test              - Run backend pytest test suite"
	@echo "  make allow-firewall    - Open ports 8000-8010 in Linux firewall (UFW/Firewalld)"
	@echo ""
	@echo "Release & Deployment Packaging:"
	@echo "  make release-linux     - Build standalone Linux .tar.gz and .AppImage"
	@echo "  make release-windows   - Build standalone Windows .zip bundle"
	@echo "  make release-apk       - Build Android companion APK"
	@echo "  make release-backend   - Build frozen PyInstaller backend executable"
	@echo "  make release-all       - Build all platform targets for current host"
	@echo "  make install           - Install Linux release bundle to ~/.local"
	@echo "  make uninstall         - Remove Linux release bundle from ~/.local"
