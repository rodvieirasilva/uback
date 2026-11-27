# AGENTS.md — UBack Engineering Guidelines

This repository follows clean, modular, SOLID engineering practices.

## Core Principles
1. **Short, Clean, SOLID Files**:
   - Keep every file small, focused, and single-responsibility (SRP).
   - Separate domain logic, platform bridges, configuration, and UI widgets cleanly.
   - Program against interfaces (`MediaSource`, `BackupDestination`, `MediaExporter`, `NativeBackupBridge`, `KeyValueStore`) for extensibility and testability.
   - Register backup sources via hierarchical `MediaSource` trees (`Camera` -> Images/Videos/Expert RAW, `Screenshots`, `Screen Recordings`, `WhatsApp` & `WhatsApp Business` -> Received/Sent -> Images/Videos/Audios/Documents + Chat Databases (Read-Only) + Incremental Chat Deltas (`.db`), `Telegram`, `Photo Editors & Social`, `Recorded Audios`, `Documents`, `Downloads`, `Device Snapshots`, and user-configured `Custom Folders`) with collapsible toggles and live non-blocking file-count/size impact shown directly on the main backup screen.
   - Persist full session state (destination, last exporter, mode, batch limit, enabled source toggles, custom folders, and collapsible expand/collapse state) so reopening the app restores the exact last session.
   - Register backup destinations via `BackupDestination` (`SmbNasDestination` today; future destinations selectable in config/Settings).
   - Never expose internal roadmap or phase jargon (e.g., "Phase 1") in the user-facing UI, and guard every `Row` against horizontal overflow on narrow screens.
2. **No Long Inline Strings or Embedded Scripts**:
   - Never embed long scripts (e.g., Python heredocs inside shell scripts) or large multi-line templates inline. Extract them into dedicated, focused files under `scripts/` or appropriate resource/source directories.
3. **Data Safety Invariants (Non-Negotiable)**:
   - **Always-on SHA-256 read-back verification** in both Copy and Crop modes: upload to `<target>.uback.tmp`, verify remote size + full streaming SHA-256 read-back, then atomically rename to `<target>`.
   - **Strict Deletion Gate**: In Crop Mode, local deletion (`MediaCleaner.deleteVerifiedFile` / `cleanUpItem`) MUST ONLY run immediately after post-transfer verification passes (or pre-flight confirms an exact remote SHA-256 match). Never delete unverified files, NEVER delete read-only sources (such as WhatsApp `Databases/` & `Backups/`), and NEVER delete real Contacts/SMS/Call Logs for Device Snapshots (only remove temporary cache export files).
   - **WhatsApp Incremental SQLite Delta Exporter**: On-device `.crypt15` decryption (`WhatsAppCrypt15Decryptor` + `WhatsAppDeltaExporter`) MUST export only new rows (`_id > watermark`) plus referenced `chat`, `jid`, and `message_media` context into self-contained SQLite delta `.db` files (`PRAGMA journal_mode=DELETE`). Always wipe temporary decrypted DBs from app cache immediately in `finally`, NEVER modify or delete source `.crypt15` files, and commit the persistent watermark (`WhatsAppDeltaState.commitWatermark`) **strictly after** SMB SHA-256 read-back verification passes.
   - **Zero Previews**: Never load or render image/video thumbnails or mini-previews in discovery or backup UI.
   - **Global Oldest-First Ordering**: When combining multiple enabled sources, take up to the oldest `N` candidates per source (when limited by file count), merge all sources, sort globally oldest-first across all enabled sources, and then apply the batch limit.
   - **Public Repo Privacy Gate**: Never commit private IPs, NAS credentials, 64-digit WhatsApp backup keys, device-specific `WHATSAPP_64DIGI_*` env variable names/values, personal folder listings, `config.toml`, `dart_defines.json`, or `dist-local/` APKs anywhere in code, docs, scripts, or screenshots.
4. **Secrets & Configuration**:
   - Never commit `config.toml`, `dart_defines.json`, `dist-local/`, or any NAS/WhatsApp credentials.
   - Store runtime secrets (SMB credentials and optional 64-digit WhatsApp backup key) only in Android secure storage (`FlutterSecureStorage`) and update `config.example.toml` and `scripts/parse_config.py` whenever compile-time config keys change.
5. **UI Testability (`testIds`)**:
   - Every interactive widget and status counter must expose a centralized key from `mobile/lib/core/testing/test_keys.dart` wrapped with `withTestId(...)` (`Semantics(identifier: ...)` + `ValueKey`).
6. **Tooling, Verification & Releases**:
   - Use `mise` (`mise.toml`) for all tool versions and tasks; keep Java, Flutter, Dart, and Maven dependencies up to date.
   - Support both Light and Dark Material 3 themes following `ThemeMode.system` (`mobile/lib/ui/theme/app_theme.dart`) and hinge-aware two-pane adaptive layouts for landscape & foldable dual-screen devices (`mobile/lib/ui/widgets/adaptive_layout.dart`).
   - Follow [docs/RELEASE.md](docs/RELEASE.md) when cutting a release (bump `mobile/pubspec.yaml`, run `mise run release-check`, refresh prints via `mise run screenshots`).
   - Before committing or finishing a change, run in order:
     - `mise run analyze` (zero issues)
     - `mise run coverage` (all unit & widget tests passing with >= 80% line coverage)
     - `mise run test-e2e` when changing native Android, SMB, MediaStore, or end-to-end UI flows
     - `mise run screenshots` right after E2E tests whenever UI or version changes occur (and before extra chaos/deploy runs).

---

## Secret Scanning (Pre-Commit Gate)

Before committing or pushing, always run:

```bash
mise run secrets
```

Ensure zero leaked credentials or secrets (`gitleaks`) are present in the workspace or git history.
