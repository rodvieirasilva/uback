<p align="center">
  <img src="docs/logo.png" alt="UBack Logo" width="110" />
</p>

<h1 align="center">UBack (Ultimate Backup)</h1>

<p align="center">
  Reliable Android backup app for transferring thousands of photos, videos, WhatsApp media, and recorded audios over <strong>SMB2/SMB3</strong> with mandatory full <strong>SHA-256 read-back verification</strong>.
</p>

See [docs/RELEASE.md](docs/RELEASE.md) for the release process and [AGENTS.md](AGENTS.md) for engineering guidelines.

## Screenshots

| Home (Dark) | Home (Light) | Settings (Dark) | Settings (Light) |
| :---: | :---: | :---: | :---: |
| ![Home Dark](docs/screenshots/home-dark.png) | ![Home Light](docs/screenshots/home-light.png) | ![Settings Dark](docs/screenshots/settings-dark.png) | ![Settings Light](docs/screenshots/settings-light.png) |

## Key Features
- **Collapsible Hierarchical Media Sources**: Toggle sources and nested sub-items directly on the backup screen with live file-count and byte-size estimates:
  - **Camera** (`Images`, `Videos`)
  - **Screenshots**
  - **WhatsApp** (`Received` & `Sent` -> `Images`, `Videos`, `Audios & Voice Notes`)
  - **Recorded Audios** (`Voice Recorder` / `Recordings`)
- **Extensible Destinations**: Built on an abstract `BackupDestination` interface (`SMB NAS` active now, configurable for additional destinations in `config.toml` and Settings).
- **Destination Layout**: `smb://{host}:{port}/{share}/{base_path}/{device_name}/{source}/{YYYY}/{MM}/{filename}` (e.g., `.../camera/2025/04/`, `.../whatsapp/sent/videos/2025/04/`, `.../recordings/2025/04/`).
- **Modes**:
  - **Copy**: Transfers and verifies files on the destination, leaving local files untouched.
  - **Crop (Free Space)**: Verifies every file via full SHA-256 read-back before deleting the local file and refreshing Android MediaStore.
- **Global Oldest-First & Batch Limits**: Always orders oldest-first across **all** enabled sources combined; optionally limit a run to `All`, `Oldest X files`, or `Oldest X MB`.
- **High-Volume UX**: Zero media thumbnails or previews — lightweight progress counters (`Transferred`, `Remaining`, `Total`, `Skipped`, `Failed`) with a pinned Android Foreground Service progress notification.
- **Adaptive System Theme**: Material 3 Light and Dark themes automatically follow your phone's system theme.
- **Compile-Time Defaults + In-App Settings**: Local gitignored `config.toml` injects default destination settings at build time, while Settings lets you edit or override them at runtime (credentials stored with Android secure storage).

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
