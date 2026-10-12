#!/usr/bin/env bash
# ==============================================================================
# RevVault — Linux Tarball Installer & Desktop Integrator
# Installs or uninstalls RevVault from a compiled .tar.gz distribution archive.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="install"
SCOPE="user"
ARCHIVE_PATH=""

print_usage() {
    cat << 'EOF'
RevVault Tarball Installer

Usage:
  install_tarball.sh [OPTIONS] [ARCHIVE_PATH]

Options:
  --user         Install for the current user into ~/.local (default)
  --system       Install system-wide into /opt and /usr/local/bin (requires root)
  --uninstall    Remove an existing RevVault installation
  -h, --help     Show this help message

Arguments:
  ARCHIVE_PATH   Path to revvault-linux-x64-v*.tar.gz
                 (Auto-detected from current dir or dist/ if omitted)

Examples:
  ./scripts/install_tarball.sh
  ./scripts/install_tarball.sh dist/revvault-linux-x64-v1.0.0.tar.gz
  sudo ./scripts/install_tarball.sh --system
  ./scripts/install_tarball.sh --uninstall
EOF
}

# Parse CLI options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            SCOPE="user"
            shift
            ;;
        --system)
            SCOPE="system"
            shift
            ;;
        --uninstall)
            MODE="uninstall"
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            echo "Error: Unknown option '$1'" >&2
            print_usage
            exit 1
            ;;
        *)
            if [[ -z "$ARCHIVE_PATH" ]]; then
                ARCHIVE_PATH="$1"
            else
                echo "Error: Unexpected argument '$1'" >&2
                print_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Configure target paths based on scope
if [[ "$SCOPE" == "system" ]]; then
    if [[ $EUID -ne 0 ]]; then
        echo "Error: System-wide installation requires root privileges. Please re-run with sudo." >&2
        exit 1
    fi
    INSTALL_DIR="/opt/revvault"
    BIN_DIR="/usr/local/bin"
    DESKTOP_DIR="/usr/share/applications"
    ICON_DIR="/usr/share/icons/hicolor/256x256/apps"
else
    XDG_DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
    XDG_BIN="${XDG_BIN_HOME:-$HOME/.local/bin}"
    INSTALL_DIR="${XDG_DATA}/revvault"
    BIN_DIR="${XDG_BIN}"
    DESKTOP_DIR="${XDG_DATA}/applications"
    ICON_DIR="${XDG_DATA}/icons/hicolor/256x256/apps"
fi

# ==============================================================================
# Uninstallation Routine
# ==============================================================================
if [[ "$MODE" == "uninstall" ]]; then
    echo "Uninstalling RevVault (${SCOPE} scope)..."

    if [[ -d "$INSTALL_DIR" ]]; then
        echo "Removing: ${INSTALL_DIR}"
        rm -rf "$INSTALL_DIR"
    fi

    if [[ -L "${BIN_DIR}/revvault" || -f "${BIN_DIR}/revvault" ]]; then
        echo "Removing: ${BIN_DIR}/revvault"
        rm -f "${BIN_DIR}/revvault"
    fi

    if [[ -f "${DESKTOP_DIR}/revvault.desktop" ]]; then
        echo "Removing: ${DESKTOP_DIR}/revvault.desktop"
        rm -f "${DESKTOP_DIR}/revvault.desktop"
    fi

    if [[ -f "${ICON_DIR}/revvault.png" ]]; then
        echo "Removing: ${ICON_DIR}/revvault.png"
        rm -f "${ICON_DIR}/revvault.png"
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    fi

    echo "RevVault uninstalled successfully."
    exit 0
fi

# ==============================================================================
# Archive Resolution Routine
# ==============================================================================
find_archive() {
    # 1. Explicit path given
    if [[ -n "$ARCHIVE_PATH" ]]; then
        if [[ -f "$ARCHIVE_PATH" ]]; then
            echo "$ARCHIVE_PATH"
            return 0
        else
            echo "Error: Specified archive not found: ${ARCHIVE_PATH}" >&2
            return 1
        fi
    fi

    # 2. Look in current working directory
    local local_match
    local_match=$(find . -maxdepth 1 -name "revvault-linux-x64-*.tar.gz" 2>/dev/null | sort -V | tail -n 1 || true)
    if [[ -n "$local_match" && -f "$local_match" ]]; then
        echo "$local_match"
        return 0
    fi

    # 3. Look in repo dist/ directory
    local dist_match
    dist_match=$(find "${REPO_ROOT}/dist" -maxdepth 1 -name "revvault-linux-x64-*.tar.gz" 2>/dev/null | sort -V | tail -n 1 || true)
    if [[ -n "$dist_match" && -f "$dist_match" ]]; then
        echo "$dist_match"
        return 0
    fi

    echo "Error: No revvault-linux-x64-*.tar.gz archive found." >&2
    echo "Provide path explicitly or run 'make release-linux' first." >&2
    return 1
}

RESOLVED_ARCHIVE="$(find_archive)"

echo "=== RevVault Linux Installer ==="
echo "Target Scope : ${SCOPE}"
echo "Archive Path : ${RESOLVED_ARCHIVE}"
echo "Install Dir  : ${INSTALL_DIR}"
echo "Bin Symlink  : ${BIN_DIR}/revvault"
echo "Desktop File : ${DESKTOP_DIR}/revvault.desktop"
echo "================================"

# Verify prerequisites
if ! command -v tar >/dev/null 2>&1; then
    echo "Error: 'tar' utility is required to extract the release." >&2
    exit 1
fi

# Prepare target directories
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

# Clean prior installation directory to prevent stale files
if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "${INSTALL_DIR:?}"/*
fi

echo "Extracting archive to ${INSTALL_DIR}..."
tar -xzf "$RESOLVED_ARCHIVE" -C "$INSTALL_DIR" --strip-components=1

# Verify primary binary
if [[ ! -f "${INSTALL_DIR}/rev_vault" ]]; then
    echo "Error: Extraction failed; ${INSTALL_DIR}/rev_vault not found." >&2
    exit 1
fi

# Set executable permissions
chmod 0755 "${INSTALL_DIR}/rev_vault"
if [[ -f "${INSTALL_DIR}/backend/revvault-backend" ]]; then
    chmod 0755 "${INSTALL_DIR}/backend/revvault-backend"
fi

# Symlink to bin path
ln -sf "${INSTALL_DIR}/rev_vault" "${BIN_DIR}/revvault"

# Install application icon
ICON_SOURCE=""
if [[ -f "${SCRIPT_DIR}/appimage/revvault.png" ]]; then
    ICON_SOURCE="${SCRIPT_DIR}/appimage/revvault.png"
elif [[ -f "${INSTALL_DIR}/data/flutter_assets/assets/icon/app_icon.png" ]]; then
    ICON_SOURCE="${INSTALL_DIR}/data/flutter_assets/assets/icon/app_icon.png"
fi

if [[ -n "$ICON_SOURCE" && -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "${ICON_DIR}/revvault.png"
fi

# Create Desktop launcher entry
cat << EOF > "${DESKTOP_DIR}/revvault.desktop"
[Desktop Entry]
Name=RevVault
GenericName=Database Companion & Agent Hub
Comment=Intelligent Database Companion & Antigravity MCP Service
Exec=${INSTALL_DIR}/rev_vault %u
Icon=revvault
Terminal=false
Type=Application
Categories=Development;Database;IDE;Utility;
Keywords=database;sql;sqlite;postgres;antigravity;mcp;
StartupNotify=true
EOF

chmod 0644 "${DESKTOP_DIR}/revvault.desktop"

# Refresh desktop launcher cache
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
fi

echo ""
echo "Installation complete!"
echo "Launch RevVault with: ${BIN_DIR}/revvault"
if [[ "$SCOPE" == "user" ]] && [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "Note: '${BIN_DIR}' is not currently in your PATH. Consider adding it to ~/.bashrc or ~/.zshrc."
fi
