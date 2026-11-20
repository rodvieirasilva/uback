enum BackupMode { copy, crop }

enum BackupLimitType { all, files, megabytes }

class BackupLimit {
  final int? maxFiles;
  final int? maxBytes;

  const BackupLimit({this.maxFiles, this.maxBytes});

  bool get isUnlimited => maxFiles == null && maxBytes == null;
}

class BackupItem {
  final String id;
  final String? contentUri;
  final String fileName;
  final String localPath;
  final String sourceId; // Leaf source id, e.g. "camera.images", "whatsapp.sent.videos"
  final String sourceFolder; // Remote subpath, e.g. "camera", "whatsapp/sent/videos"
  final int sizeBytes;
  final DateTime createdAt; // Used for oldest-first sorting and YYYY/MM pathing
  final String mimeType;
  final bool isSnapshot;

  const BackupItem({
    required this.id,
    this.contentUri,
    required this.fileName,
    required this.localPath,
    String? sourceId,
    required this.sourceFolder,
    required this.sizeBytes,
    required this.createdAt,
    required this.mimeType,
    this.isSnapshot = false,
  }) : sourceId = sourceId ?? sourceFolder;

  factory BackupItem.fromMap(Map<Object?, Object?> map) {
    final createdAtMs = (map['createdAtMs'] as num?)?.toInt() ?? 0;
    final folder = (map['sourceFolder'] as String?) ?? 'camera';
    return BackupItem(
      id: (map['id'] as String?) ?? '',
      contentUri: map['contentUri'] as String?,
      fileName: (map['fileName'] as String?) ?? '',
      localPath: (map['localPath'] as String?) ?? '',
      sourceId: (map['sourceId'] as String?) ?? folder,
      sourceFolder: folder,
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      mimeType: (map['mimeType'] as String?) ?? 'application/octet-stream',
      isSnapshot: (map['isSnapshot'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'contentUri': contentUri,
        'fileName': fileName,
        'localPath': localPath,
        'sourceId': sourceId,
        'sourceFolder': sourceFolder,
        'sizeBytes': sizeBytes,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        'mimeType': mimeType,
        'isSnapshot': isSnapshot,
      };
}

class BackupErrorEntry {
  final String fileName;
  final String message;

  const BackupErrorEntry({
    required this.fileName,
    required this.message,
  });

  factory BackupErrorEntry.fromMap(Map<Object?, Object?> map) => BackupErrorEntry(
        fileName: (map['fileName'] as String?) ?? 'Unknown',
        message: (map['message'] as String?) ?? 'Unknown error',
      );
}

enum BackupRunState { idle, scanning, running, paused, completed, cancelled, error }

class BackupProgress {
  final BackupRunState state;
  final String stage;
  final int total;
  final int transferred;
  final int skipped;
  final int failed;
  final int remaining;
  final int bytesTransferred;
  final int totalBytes;
  final int elapsedMs;
  final int? etaMs;
  final String currentFile;
  final List<BackupErrorEntry> errors;

  const BackupProgress({
    this.state = BackupRunState.idle,
    this.stage = 'idle',
    this.total = 0,
    this.transferred = 0,
    this.skipped = 0,
    this.failed = 0,
    this.remaining = 0,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.elapsedMs = 0,
    this.etaMs,
    this.currentFile = '',
    this.errors = const [],
  });

  bool get isPaused => state == BackupRunState.paused;

  bool get isActive =>
      state == BackupRunState.scanning ||
      state == BackupRunState.running ||
      state == BackupRunState.paused;

  double get fraction {
    if (totalBytes > 0) {
      return (bytesTransferred / totalBytes).clamp(0.0, 1.0);
    }
    if (total > 0) {
      return ((transferred + skipped + failed) / total).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  factory BackupProgress.fromMap(Map<Object?, Object?> map) {
    final stateStr = (map['state'] as String?) ?? 'idle';
    final runState = switch (stateStr) {
      'scanning' => BackupRunState.scanning,
      'running' => BackupRunState.running,
      'paused' => BackupRunState.paused,
      'completed' => BackupRunState.completed,
      'cancelled' => BackupRunState.cancelled,
      'error' => BackupRunState.error,
      _ => BackupRunState.idle,
    };

    final rawErrors = (map['errors'] as List?) ?? const [];
    final errors = rawErrors
        .whereType<Map<Object?, Object?>>()
        .map(BackupErrorEntry.fromMap)
        .toList();

    final rawEta = (map['etaMs'] as num?)?.toInt();
    return BackupProgress(
      state: runState,
      stage: (map['stage'] as String?) ?? 'idle',
      total: (map['total'] as num?)?.toInt() ?? 0,
      transferred: (map['transferred'] as num?)?.toInt() ?? 0,
      skipped: (map['skipped'] as num?)?.toInt() ?? 0,
      failed: (map['failed'] as num?)?.toInt() ?? 0,
      remaining: (map['remaining'] as num?)?.toInt() ?? 0,
      bytesTransferred: (map['bytesTransferred'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
      etaMs: rawEta != null && rawEta >= 0 ? rawEta : null,
      currentFile: (map['currentFile'] as String?) ?? '',
      errors: errors,
    );
  }
}

class ConnectionTestResult {
  final bool ok;
  final String message;

  const ConnectionTestResult({required this.ok, required this.message});
}

class PermissionState {
  final bool hasMedia;
  final bool hasAllFiles;
  final bool hasNotifications;

  const PermissionState({
    this.hasMedia = false,
    this.hasAllFiles = false,
    this.hasNotifications = false,
  });

  factory PermissionState.fromMap(Map<Object?, Object?> map) => PermissionState(
        hasMedia: (map['hasMedia'] as bool?) ?? false,
        hasAllFiles: (map['hasAllFiles'] as bool?) ?? false,
        hasNotifications: (map['hasNotifications'] as bool?) ?? false,
      );
}

/// Contract all Media Exporters must implement.
abstract class MediaExporter {
  /// Stable identifier used for persisting the last active exporter.
  String get id;

  /// User-friendly title for the UI (e.g., "Selected Media Sources").
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
