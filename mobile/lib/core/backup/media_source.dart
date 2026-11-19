import 'media_exporter.dart';
import 'native_bridge.dart';

/// Aggregated file count and estimated total size for a [MediaSource].
class MediaSourceStats {
  final int fileCount;
  final int totalBytes;

  const MediaSourceStats({
    this.fileCount = 0,
    this.totalBytes = 0,
  });

  factory MediaSourceStats.fromMap(Map<Object?, Object?> map) => MediaSourceStats(
        fileCount: (map['count'] as num?)?.toInt() ?? 0,
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      );
}

/// Extensible contract for backup media sources (e.g., Camera, Screenshots,
/// and future sources such as WhatsApp, Documents, etc.).
abstract class MediaSource {
  /// Stable unique identifier (also persisted in settings), e.g. `"camera"`.
  String get id;

  /// Human-readable label displayed in the UI, e.g. `"Camera"`.
  String get displayName;

  /// Short folder hint shown beneath the title, e.g. `"DCIM/Camera"`.
  String get subtitle;

  /// Remote folder slug under `{base_path}/{device_name}/`, e.g. `"camera"`.
  String get destinationSlug;

  /// Discovers items belonging only to this media source (no thumbnails/previews).
  Future<List<BackupItem>> discoverItems();
}

/// Camera photos and videos (`DCIM/Camera`).
class CameraMediaSource implements MediaSource {
  final NativeBackupBridge _bridge;

  CameraMediaSource(this._bridge);

  @override
  String get id => 'camera';

  @override
  String get displayName => 'Camera';

  @override
  String get subtitle => 'DCIM/Camera';

  @override
  String get destinationSlug => 'camera';

  @override
  Future<List<BackupItem>> discoverItems() =>
      _bridge.discoverMedia(enabledSourceIds: {id});
}

/// Device screenshots (`DCIM/Screenshots` and `Pictures/Screenshots`).
class ScreenshotsMediaSource implements MediaSource {
  final NativeBackupBridge _bridge;

  ScreenshotsMediaSource(this._bridge);

  @override
  String get id => 'screenshots';

  @override
  String get displayName => 'Screenshots';

  @override
  String get subtitle => 'DCIM & Pictures/Screenshots';

  @override
  String get destinationSlug => 'screenshots';

  @override
  Future<List<BackupItem>> discoverItems() =>
      _bridge.discoverMedia(enabledSourceIds: {id});
}

/// Default registry of available [MediaSource] implementations.
List<MediaSource> defaultMediaSources(NativeBackupBridge bridge) => [
      CameraMediaSource(bridge),
      ScreenshotsMediaSource(bridge),
    ];
