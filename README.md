<p align="center">
  <img src="docs/logo.png" alt="UBack Logo" width="110" />
</p>

<h1 align="center">UBack (Ultimate Backup)</h1>

<p align="center">
  Reliable Android backup app for transferring thousands of Camera &amp; Screenshots photos and videos over <strong>SMB2/SMB3</strong> with mandatory full <strong>SHA-256 read-back verification</strong>.
</p>

See [docs/RELEASE.md](docs/RELEASE.md) for the release process and [AGENTS.md](AGENTS.md) for engineering guidelines.

## Screenshots

| Home (Dark) | Home (Light) | Settings (Dark) | Settings (Light) |
| :---: | :---: | :---: | :---: |
| ![Home Dark](docs/screenshots/home-dark.png) | ![Home Light](docs/screenshots/home-light.png) | ![Settings Dark](docs/screenshots/settings-dark.png) | ![Settings Light](docs/screenshots/settings-light.png) |

## Key Features (Phase 1)
- **Sources**: Camera (`DCIM/Camera`) and Screenshots (`DCIM/Screenshots` & `Pictures/Screenshots`) only — WhatsApp and other third-party folders are excluded.
- **Destination Layout**: `smb://{host}:{port}/{share}/{base_path}/{device_name}/{camera|screenshots}/{YYYY}/{MM}/{filename}`.
- **Modes**:
  - **Copy**: Transfers and verifies files on the NAS, leaving local files untouched.
  - **Crop (Free Space)**: Verifies every file on the NAS via full SHA-256 read-back before deleting the local file and refreshing Android MediaStore.
- **Oldest-First & Batch Limits**: Always starts from the oldest files first; optionally limit a run to `All`, `Oldest X files`, or `Oldest X MB`.
- **High-Volume UX**: Zero media thumbnails or previews — lightweight progress counters (`Transferred`, `Remaining`, `Total`, `Skipped`, `Failed`) running inside an Android Foreground Service.
- **Adaptive System Theme**: Material 3 Light and Dark themes automatically follow your phone's system theme.
- **Compile-Time Defaults + In-App Settings**: Local gitignored `config.toml` injects default NAS credentials/paths at build time, while Settings lets you edit or override them at runtime (credentials stored with Android secure storage).

## Quick Start

### 1. Install Toolchain with `mise`
```bash
mise trust
mise install
```

### 2. Configure Local NAS Defaults (Never Committed)
```bash
cp config.example.toml config.toml
# Edit config.toml with your NAS host, share, base_path, username, and password
```

### 3. Common Tasks
```bash
mise run analyze         # Flutter static analysis
mise run test            # Dart unit & widget tests
mise run test-e2e        # Full Android Emulator E2E tests against a real local SMB2 server
mise run screenshots     # Refresh Dark & Light screenshots in docs/screenshots/
mise run release-check   # Run analyze + unit/widget + Emulator E2E tests
mise run build-apk       # Build debug APK with config.toml defaults injected
mise run build-release   # Build release APK with config.toml defaults injected
mise run deploy-device   # Build & install debug APK onto connected wireless ADB phone
mise run deploy-release  # Build & install release APK onto connected wireless ADB phone
```

## Project Layout
- `docs/RELEASE.md` — Version bump, screenshot refresh, and release checklist
- `docs/logo.png` & `docs/screenshots/` — App icon and Dark/Light UI screenshots
- `mise.toml` — Tooling versions (`java`, `flutter`, Android SDK env) and automation tasks
- `config.example.toml` — Template for gitignored `config.toml`
- `scripts/` — Build, config-injection, icon generation, screenshot capture, ADB deployment, and Emulator E2E scripts
- `mobile/` — Flutter Android application + native Kotlin `smbj` engine & Foreground Service
