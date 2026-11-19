# UBack Mobile App Specification

This document details the specifications for the **UBack (Ultimate Backup)** mobile application, following Spec-Driven Development principles.

---

## 1. App Overview
- **Framework**: Flutter (latest stable, Dart null-safety).
- **Target Platform**: Android (Mobile).
- **Project Location**: `/mobile` directory inside the `uback` repository (managed with `mise` at the repository root).
- **Package Name**: `uback.rodvieirasilva.github.io` (kept modular/configurable for easy future renaming).
- **Initial Scope (Phase 1)**: **Camera and Screenshots (Images and Videos) only**. WhatsApp and other sources (Documents, SMS, etc.) are deferred to future phases; the architecture remains extensible via abstract interfaces.
- **Primary Goal**: Reliably copy or move thousands of Camera and Screenshots photos and videos from the phone's internal storage to a remote NAS share (`{base_path}/{device_name}/{source}/{YYYY}/{MM}/{filename}`, e.g., `N:\safe\local\phone\{device_name}\camera\2025\04\...`, `...\screenshots\...`) over **SMB**, with strict post-transfer verification.

---

## 2. Configuration & Compile-Time Default Injection

NAS connection settings must be editable inside the app while supporting convenient compile-time defaults during local builds.

### 2.1 Configurable Fields
- **SMB Host / IP** (e.g., `192.168.1.100`)
- **SMB Port** (default: `445`)
- **SMB Share Name** (e.g., `safe`)
- **Base Path** inside the share (e.g., `local/phone`)
- **Username**
- **Password**
- **Domain / Workgroup** (optional, default empty)
- **Device Folder Name Override** (optional; defaults to auto-detected sanitized device name)

### 2.2 Compile-Time Defaults (`config.toml`)
- A local `config.toml` file at the repository root stores default NAS credentials and paths for builds.
- `config.toml` **MUST NOT be committed to Git** (listed in `.gitignore`).
- A tracked `config.example.toml` serves as the schema template.
- During compilation (via `mise` build/run tasks), values from `config.toml` are injected into Flutter via `--dart-define` / `--dart-define-from-file`.
- **Runtime Precedence**:
  1. Values saved by the user in the app's Settings screen (persisted locally using Android encrypted/secure storage for credentials).
  2. Fallback to compile-time defaults injected from `config.toml`.
  3. A "Reset to Defaults" action in Settings restores compile-time defaults.

---

## 3. Dynamic Destination Pathing

The destination subdirectory adapts automatically to the device running the app.

- **Sanitization Rules** (applied to the phone's hardware/device name):
  - Remove all occurrences of `'s` (case-insensitive, including curly apostrophe `’s`).
  - Remove the word `phone` (case-insensitive).
  - Remove all whitespace (and any invalid path characters).
  - Convert the final string to lowercase.
- **Examples**:
  - `"Alice's Phone"` -> `alice`
  - `"Rodrigo's phone"` -> `rodrigo`
- **Source Folder (`{source}`) Sanitization & Phase 1 Sources**:
  - Phase 1 covers **Camera** and **Screenshots** only:
    - `DCIM/Camera` -> `camera`
    - `DCIM/Screenshots` (Samsung One UI) & `Pictures/Screenshots` (stock Android / emulator) -> `screenshots`
  - General sanitization rules for future sources (derived from Android MediaStore `BUCKET_DISPLAY_NAME`, falling back to parent directory name or `other`): trim whitespace, lowercase, replace spaces/separators with `-`, strip invalid filesystem/SMB path characters.
- **Target Path**:
  - `smb://{host}:{port}/{share}/{base_path}/{device_name}/{source}/{YYYY}/{MM}/{filename}`
  - Files are grouped right under `{device_name}` by where they came from (`{source}`), then into `YYYY/MM` subfolders based on each file's `createdAt` timestamp (faster SMB directory listings and cleaner browsing for thousands of files).
  - Examples:
    - `smb://192.168.1.100:445/safe/local/phone/rodrigo/camera/2025/04/IMG_20250412_143022.jpg`
    - `smb://192.168.1.100:445/safe/local/phone/rodrigo/screenshots/2025/04/Screenshot_20250412.png`
- If the OS cannot provide a readable user-assigned device name, fall back to the sanitized device model and allow overriding it in Settings.
- Preserve the original file's `lastModified` timestamp on the NAS where supported by the SMB server.

### 3.1 Source Folder Selection
- Phase 1 includes **Camera** (`DCIM/Camera`) and **Screenshots** (`DCIM/Screenshots`, `Pictures/Screenshots`) only — WhatsApp and other third-party app folders are excluded for now.
- Settings provides simple text-only checkboxes (with file counts, **no thumbnails**) to toggle `Camera` and `Screenshots` on or off individually (both enabled by default).

---

## 4. Backup Modes, Ordering & Batch Limits

### 4.1 Operation Modes
1. **Copy Mode**: Transfers and verifies files on the SMB server, leaving original files untouched on the phone.
2. **Crop Mode (Free Space / Move)**: Transfers files to the SMB server, **strictly verifies** each file post-transfer, and **only then** deletes the original local file to free up device storage.

### 4.2 Processing Order (Oldest First)
- Discovered images and videos are sorted **chronologically ascending (oldest -> newest)** using media creation date (`dateTaken` / EXIF timestamp, falling back to file modification timestamp).
- Every backup run starts from the **oldest unbacked-up files first**.

### 4.3 Optional Batch Limits
Before starting a backup, the user can choose how much to back up in the current run:
- **All files** (no limit — default).
- **Limit by File Count**: Back up only the oldest `X` files (e.g., `50`, `100`, `500`, or custom number).
- **Limit by Size (MB)**: Back up oldest files until cumulative size reaches `X` MB (e.g., `500 MB`, `1024 MB`, `5000 MB`, or custom value).
  - Files are accumulated in oldest-first order until adding the next file would exceed `X` MB (if the very first/oldest single file exceeds `X` MB, still allow or prompt clearly so progress is never deadlocked).

---

## 5. High-Volume UX (Thousands of Files, No Previews)

The app is built specifically to handle **thousands of files** without memory pressure, jank, or wasted bandwidth/CPU.

- **No File Previews or Thumbnails**:
  - Do **not** render image grids, thumbnails, or mini-previews during discovery or transfer.
  - Keep memory usage flat regardless of whether 100 or 20,000 files are queued.
- **Simple, Modern Dark-Mode-First UI**:
  - Clean primary screen with:
    - Mode selector (**Copy** vs **Crop / Free Space**)
    - Batch limit selector (**All**, **Oldest X files**, **Oldest X MB**)
    - Primary **"Start Backup"** / **"Stop Backup"** action
    - Connection test button / status indicator and quick link to **Settings**
- **Progress Dashboard (Text & Counters Only)**:
  - **Transferred**: count of files fully transferred & verified
  - **Remaining**: count of files left in the current run
  - **Total**: total files queued in the current run
  - **Skipped**: files already present and verified on the NAS
  - **Failed**: files that failed after retries (with a lightweight text-only error log view)
  - **Data Progress**: bytes transferred / total bytes + overall progress bar
  - **Current Activity**: plain-text filename and stage (`Scanning`, `Uploading`, `Verifying`, `Cleaning up`, `Retrying`)
- **Background Resilience**:
  - Run active backups inside an Android **Foreground Service** with a persistent progress notification (`Transferred X / Y`) and wake/Wi-Fi lock so Android does not kill long-running backups when the screen turns off.

---

## 6. SMB Transport & Mandatory Post-Transfer Verification

SMB over mobile Wi-Fi can silently truncate files, drop sockets mid-stream, or leave partial/0-byte artifacts. Data integrity is the highest priority across **both Copy and Crop modes**.

### 6.1 Native Android SMB Engine
- Implement SMB2/SMB3 transport natively in Android **Kotlin** (using `smbj`) exposed to Flutter via Platform Channels, running inside the Android Foreground Service.
- Streaming I/O with fixed-size buffers ensures flat memory usage even for multi-gigabyte 4K videos.

### 6.2 Transfer & Verification Protocol (Per File — Both Copy & Crop Modes)
For each `BackupItem`:
1. **Local Hash Calculation**: Compute the file's **SHA-256** checksum and exact byte size by streaming from local storage (never loading entire files into RAM).
2. **Pre-Flight Remote Check (Idempotency / Resume)**:
   - Ensure the remote `{source}/{YYYY}/{MM}` directory exists under `{base_path}/{device_name}` (creating intermediate directories as needed).
   - Check if the target file already exists at `{destination}/{source}/{YYYY}/{MM}/{filename}`.
   - If it exists: verify remote byte size and read back remote SHA-256.
     - If `remoteSize == localSize` AND `remoteHash == localHash`: mark as **Already Verified / Skipped** (safe to delete locally in Crop Mode).
     - If sizes or hashes differ: do **not** overwrite a different file blindly; disambiguate the target filename (e.g., `<stem>_<shortHash>.<ext>`) so no distinct file is lost.
3. **Atomic Upload via Temporary File**:
   - Stream local file in chunks to `<target>.uback.tmp` (removing any stale `.uback.tmp` first).
   - Explicitly flush and close the remote file handle.
4. **Mandatory Full SHA-256 Read-Back Verification (Always On)**:
   - Re-query remote metadata and verify `remoteTempSize == localSize`.
   - **Read back** the uploaded `.uback.tmp` file over SMB in streaming chunks and compute its **SHA-256** hash.
   - Confirm `remoteHash == localHash` (enforced in **both Copy and Crop modes**).
   - If verification fails: delete `<target>.uback.tmp` on the server and treat the attempt as failed.
5. **Commit (Rename & Timestamp)**:
   - Atomically rename `<target>.uback.tmp` -> `<target>` on the SMB server.
   - Set remote `lastModified` timestamp to match the source file (best-effort if server permits).
   - Confirm `<target>` exists with expected size.
6. **Retries & Reconnection**:
   - Retry transient SMB/network failures with exponential backoff (e.g., up to 3 attempts per file), re-establishing the SMB session if dropped.
7. **Strict Local Deletion Gate (Crop Mode Only)**:
   - Uses Android **`MANAGE_EXTERNAL_STORAGE` ("All files access")** permission (personal sideloaded app) so verified files can be deleted automatically one-by-one without batch system confirmation popups.
   - `cleanUpItem(item)` is invoked **strictly and immediately only after** steps 4 & 5 succeed (or step 2 confirms an exact hash match).
   - After deleting the local file, notify Android MediaStore (`MediaScannerConnection` / MediaStore delete) so Samsung Gallery refreshes immediately without leaving ghost thumbnails.
   - If a file fails verification or transfer, the local file is **never** deleted, and the engine logs the failure and continues with the remaining files.

---

## 7. Architecture & Interface Design

Keep the core backup engine decoupled from specific media sources so future exporters can be added cleanly.

```dart
enum BackupMode { copy, crop }

class BackupLimit {
  final int? maxFiles; // Oldest X files
  final int? maxBytes; // Oldest files up to X bytes (converted from MB)
  const BackupLimit({this.maxFiles, this.maxBytes});
}

class BackupItem {
  final String id;
  final String fileName;
  final String localPath;
  final String sourceFolder; // Sanitized origin folder, e.g. "camera", "screenshots"
  final int sizeBytes;
  final DateTime createdAt; // Used for oldest-first sorting and YYYY/MM pathing
  final String mimeType;
  const BackupItem({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.sourceFolder,
    required this.sizeBytes,
    required this.createdAt,
    required this.mimeType,
  });
}

/// Contract all Media Exporters must implement.
/// Phase 1 implements `ImageVideoMediaExporter` only.
abstract class MediaExporter {
  /// User-friendly title for the UI (e.g., "Photos & Videos").
  String get mediaTypeName;

  /// Discovers local files sorted oldest-first (ascending by createdAt),
  /// optionally constrained by [limit]. Does NOT load thumbnails or previews.
  Future<List<BackupItem>> discoverItems({BackupLimit? limit});

  /// Streams [item] over SMB to [destinationPath], performs mandatory
  /// post-transfer verification (size + SHA-256 read-back), and commits it.
  /// Returns `true` ONLY when transfer and integrity verification succeed.
  Future<bool> backupItem(BackupItem item, String destinationPath);

  /// Safely deletes the local file. Strictly invoked ONLY after
  /// `backupItem` confirms a verified backup.
  Future<bool> cleanUpItem(BackupItem item);
}
```

### Phase 1 Concrete Exporter
- `ImageVideoMediaExporter`:
  - Queries Android MediaStore for Images and Videos from **Camera** (`DCIM/Camera`) and **Screenshots** (`DCIM/Screenshots` and `Pictures/Screenshots`) only (no thumbnail generation), respecting the user's Camera/Screenshots toggles in Settings. WhatsApp and other folders are excluded in Phase 1.
  - Requests Android `MANAGE_EXTERNAL_STORAGE` ("All files access") along with `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, and `POST_NOTIFICATIONS` (for the Foreground Service notification) so Crop Mode can delete verified files immediately and silently.
  - Sorts results oldest-first (`createdAt` ascending) and applies optional `BackupLimit` (`maxFiles` or `maxBytes`).

---

## 8. Development, Testing & Deployment Workflow

- **Tooling (`mise`)**:
  - Manage Flutter/Dart/Java/Android toolchain versions and project tasks via `mise.toml` at the repo root.
  - Provide `mise` tasks to parse `config.toml`, inject `--dart-define` values, run tests, build APKs, and deploy.
- **Automated Testing & Emulator Verification**:
  - Unit tests covering device-name sanitization, oldest-first sorting, count/MB batch limiting, config precedence, and post-transfer verification state machine (including simulated SMB corruption/truncation/retry cases).
  - Run and verify the app on a local **Android Emulator** in this development environment.
- **Physical Device Deployment (Samsung via Wireless ADB)**:
  - Detect the connected Samsung device via Wireless ADB (`adb devices`).
  - Provide a one-command build + install workflow (e.g., `mise run deploy-device`) that injects `config.toml` defaults, compiles the APK, and installs/launches it automatically on the wireless-ADB-connected Samsung phone.
