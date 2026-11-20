# AGENTS.md — UBack Engineering Guidelines

This repository follows clean, modular, SOLID engineering practices.

## Core Principles
1. **Short, Clean, SOLID Files**:
   - Keep every file small, focused, and single-responsibility (SRP).
   - Separate domain logic, platform bridges, configuration, and UI widgets cleanly.
   - Program against interfaces (`MediaSource`, `BackupDestination`, `MediaExporter`, `NativeBackupBridge`, `KeyValueStore`) for extensibility and testability.
   - Register backup sources via hierarchical `MediaSource` trees (`Camera` -> Images/Videos/Expert RAW, `Screenshots`, `Screen Recordings`, `WhatsApp` & `WhatsApp Business` -> Received/Sent -> Images/Videos/Audios/Documents, `Telegram`, `Photo Editors & Social`, `Recorded Audios`, `Documents`, `Downloads`, `Device Snapshots`, and user-configured `Custom Folders`) with collapsible toggles and live non-blocking file-count/size impact shown directly on the main backup screen.
   - Persist full session state (destination, last exporter, mode, batch limit, enabled source toggles, custom folders, and collapsible expand/collapse state) so reopening the app restores the exact last session.
   - Register backup destinations via `BackupDestination` (`SmbNasDestination` today; future destinations selectable in config/Settings).
   - Never expose internal roadmap or phase jargon (e.g., "Phase 1") in the user-facing UI, and guard every `Row` against horizontal overflow on narrow screens.
2. **No Long Inline Strings or Embedded Scripts**:
   - Never embed long scripts (e.g., Python heredocs inside shell scripts) or large multi-line templates inline. Extract them into dedicated, focused files under `scripts/` or appropriate resource/source directories.
3. **Data Safety Invariants (Non-Negotiable)**:
   - **Always-on SHA-256 read-back verification** in both Copy and Crop modes: upload to `<target>.uback.tmp`, verify remote size + full streaming SHA-256 read-back, then atomically rename to `<target>`.
   - **Strict Deletion Gate**: In Crop Mode, local deletion (`MediaCleaner.deleteVerifiedFile` / `cleanUpItem`) MUST ONLY run immediately after post-transfer verification passes (or pre-flight confirms an exact remote SHA-256 match). Never delete unverified files, and NEVER delete real Contacts/SMS/Call Logs for read-only Device Snapshots (only remove temporary cache export files).
   - **Zero Previews**: Never load or render image/video thumbnails or mini-previews in discovery or backup UI.
   - **Global Oldest-First Ordering**: When combining multiple enabled sources, take up to the oldest `N` candidates per source (when limited by file count), merge all sources, sort globally oldest-first across all enabled sources, and then apply the batch limit.
   - **Public Repo Privacy Gate**: Never commit private IPs, NAS credentials, personal folder listings, `config.toml`, or `dart_defines.json` anywhere in code, docs, scripts, or screenshots.
4. **Secrets & Configuration**:
   - Never commit `config.toml`, `dart_defines.json`, or any NAS credentials.
   - Update `config.example.toml` and `scripts/parse_config.py` whenever compile-time config keys change.
5. **UI Testability (`testIds`)**:
   - Every interactive widget and status counter must expose a centralized key from `mobile/lib/core/testing/test_keys.dart` wrapped with `withTestId(...)` (`Semantics(identifier: ...)` + `ValueKey`).
6. **Tooling, Verification & Releases**:
   - Use `mise` (`mise.toml`) for all tool versions and tasks; keep Java, Flutter, Dart, and Maven dependencies up to date.
   - Support both Light and Dark Material 3 themes following `ThemeMode.system` (`mobile/lib/ui/theme/app_theme.dart`).
   - Follow [docs/RELEASE.md](docs/RELEASE.md) when cutting a release (bump `mobile/pubspec.yaml`, run `mise run release-check`, refresh prints via `mise run screenshots`).
   - Before committing or finishing a change, run in order:
     - `mise run analyze` (zero issues)
     - `mise run coverage` (all unit & widget tests passing with >= 80% line coverage)
     - `mise run test-e2e` when changing native Android, SMB, MediaStore, or end-to-end UI flows
     - `mise run screenshots` right after E2E tests whenever UI or version changes occur (and before extra chaos/deploy runs).
