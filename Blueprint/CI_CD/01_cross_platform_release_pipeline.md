# Blueprint: Cross-Platform Installation & Release Automation (Windows, Linux, Android)

- **Development State:** `VERIFIED`
- **Current Progress:** 100% (Scripts hardened, workflow validated, ready for continuous delivery)
- **Channeled Aspects:** `[Verdict & Scythe]` (Verification, Packaging, and Build Guard)
- **Target Systems:**
  - `.github/workflows/build_and_release.yml`
  - `scripts/build_release.py`
  - `scripts/windows/revvault.iss`
  - `Makefile`

---

## 1. Executive Summary & Objective

Automate end-to-end production packaging and distribution for RevVault across **Windows**, **Linux**, and **Android** environments using GitHub Actions:

1. **Windows Distribution**:
   - Compiles native Flutter Windows Desktop x64 release client.
   - Compiles frozen standalone Python FastAPI + MCP backend executable via PyInstaller.
   - Packages standalone portable bundle (`revvault-windows-x64-v{version}.zip`).
   - Compiles single-file setup installer (`RevVault-Setup-v{version}.exe`) using Inno Setup compiler (`ISCC`).

2. **Linux Distribution**:
   - Installs native Linux build toolchain (`clang`, `cmake`, `ninja`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`).
   - Compiles Flutter Linux Desktop x64 release client.
   - Compiles frozen standalone Python FastAPI + MCP backend executable.
   - Packages standalone portable tarball (`revvault-linux-x64-v{version}.tar.gz`).
   - Generates standalone, zero-installation `.AppImage` (`RevVault-v{version}-x86_64.AppImage`) utilizing AppImageTool with FUSE-less execution resilience.

3. **Android Distribution**:
   - Configures Java 17 Temurin runtime and Flutter environment.
   - Compiles optimized release APK (`app-release.apk`).
   - Stashes release APK as `revvault.apk` and `RevVault-v{version}.apk`.

4. **Multi-Job Concurrency & Release Orchestration**:
   - Concurrently executes `build-windows`, `build-linux`, and `build-android` in parallel runner matrices.
   - Automatically uploads platform build artifacts to GitHub Actions run artifacts for immediate manual download.
   - Automatically publishes or drafts GitHub Releases with all five release binary assets attached on tag pushes (`v*`) or manual `workflow_dispatch` trigger.

---

## 2. Architectural Blueprint & Verification Checklist

- [x] Audit `scripts/build_release.py` and fix missing zip file writing (`zf.write`)
- [x] Configure dynamic preprocessor versioning in `scripts/windows/revvault.iss` (`#ifndef MyAppVersion`)
- [x] Equip `build_release.py` with `APPIMAGE_EXTRACT_AND_RUN=1` for headless CI environments
- [x] Parameterize `build_apk(version)` in `build_release.py` for consistent versioned asset naming
- [x] Create GitHub Actions workflow `.github/workflows/build_and_release.yml`
- [x] Validate workflow schema, trigger conditions, action versions, and permissions
- [x] Document verified milestones and patterns in `/Learn/10_cross_platform_github_actions_release_pipeline.md`
