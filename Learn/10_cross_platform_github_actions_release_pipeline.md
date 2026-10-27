# Learning Record: Cross-Platform GitHub Actions Release Matrix

- **Date:** 2026-10-27
- **Target Platforms:** Windows x64, Linux x64, Android
- **Auditors & Guardians:** `[Verdict & Scythe]` (Verification, Packaging, and Build Guard)

---

## 1. Executive Summary & Objective

Automated the complete build, packaging, and release workflow for RevVault across Windows, Linux, and Android using GitHub Actions (`.github/workflows/build_and_release.yml`).

Every push to `main` or release tag (`v*`), or manual dispatch triggers parallel CI builders compiling:
- **Windows**: Portable ZIP bundle (`revvault-windows-x64-v*.zip`) and Inno Setup single-file installer (`RevVault-Setup-v*.exe`).
- **Linux**: Standalone portable tarball (`revvault-linux-x64-v*.tar.gz`) and self-contained zero-install AppImage (`RevVault-v*-x86_64.AppImage`).
- **Android**: Release APK (`revvault.apk` and `RevVault-v*.apk`).
- **Publish Job**: Aggregates all matrix artifacts and publishes a unified GitHub Release with full release notes and attached assets.

---

## 2. Decisive Rectifications Caught & Resolved

### Mistake 1: Empty Windows Zip Packaging
- **Symptom:** In `scripts/build_release.py`, `build_windows()` traversed staging files, calculated `arcname`, but omitted `zf.write(full_path, arcname)`.
- **Root Cause:** A missing call to `zf.write` left the generated zip file devoid of files.
- **Surgical Fix:** Added `zf.write(full_path, arcname)` inside the file iteration loop.
- **Verification Proof:** Verified via syntax compilation and structural code walk.

### Mistake 2: Inno Setup Dynamic Versioning Override
- **Symptom:** `scripts/windows/revvault.iss` hardcoded `#define MyAppVersion "1.0.0"`. Any tag or dynamic version passed to `build_release.py --version` was ignored by Inno Setup.
- **Root Cause:** Inno Setup preprocessor definitions cannot be redefined if defined unconditionally with `#define`.
- **Surgical Fix:** Wrapped `#define MyAppVersion "1.0.0"` in `#ifndef MyAppVersion ... #endif`, and updated `build_release.py` to pass `/DMyAppVersion={version}` to `iscc`.

### Mistake 3: AppImage FUSE-less CI Execution
- **Symptom:** Standard GitHub Actions Ubuntu runners lack FUSE permissions, causing `appimagetool` to crash when executed directly as an AppImage.
- **Root Cause:** AppImage runtime requires either kernel FUSE support, extraction, or `APPIMAGE_EXTRACT_AND_RUN=1`.
- **Surgical Fix:** 
  1. Extracted `appimagetool` via `--appimage-extract` during CI runner setup and symlinked `squashfs-root/AppRun` to `/usr/local/bin/appimagetool`.
  2. Injected `APPIMAGE_EXTRACT_AND_RUN=1` environment variable in `scripts/build_release.py` to guarantee headless operation everywhere.

---

## 3. Permanent Invariant & Architectural Best Practice

1. **Parity Between Local & CI Builds:** Never duplicate packaging logic between CI YAML and local developer scripts. Both must call `scripts/build_release.py` so local and CI builds produce identical byte-for-byte structures.
2. **Matrix Concurrency:** Always run desktop and mobile builds in parallel matrix jobs to minimize developer feedback cycles and GitHub Actions billing minutes.
