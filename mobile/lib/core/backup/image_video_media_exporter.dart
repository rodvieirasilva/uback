import '../config/app_config.dart';
import 'backup_planner.dart';
import 'media_exporter.dart';
import 'native_bridge.dart';

/// Phase 1 concrete MediaExporter covering Camera and Screenshots (Images & Videos only).
/// Never generates thumbnails or previews.
class ImageVideoMediaExporter implements MediaExporter {
  final NativeBackupBridge _bridge;
  final AppSettings Function() _settingsProvider;
  final String Function() _deviceFolderProvider;

  ImageVideoMediaExporter({
    required this._bridge,
    required this._settingsProvider,
    required this._deviceFolderProvider,
  });

  @override
  String get mediaTypeName => 'Camera & Screenshots';

  @override
  Future<List<BackupItem>> discoverItems({BackupLimit? limit}) async {
    final settings = _settingsProvider();
    final discovered = await _bridge.discoverMedia(
      enabledSourceIds: settings.enabledSourceIds,
    );
    return BackupPlanner.plan(discovered, limit: limit);
  }

  @override
  Future<bool> backupItem(BackupItem item, String destinationPath) async {
    // Batch execution on Android runs inside BackupForegroundService via `startBackup`.
    // Single-item delegation starts a 1-item verified transfer on the foreground service.
    await _bridge.startBackup(
      settings: _settingsProvider(),
      mode: BackupMode.copy,
      deviceFolder: _deviceFolderProvider(),
      items: [item],
    );
    await for (final progress in _bridge.progressStream()) {
      if (progress.state == BackupRunState.completed) {
        return progress.failed == 0;
      }
      if (progress.state == BackupRunState.error || progress.state == BackupRunState.cancelled) {
        return false;
      }
    }
    return false;
  }

  @override
  Future<bool> cleanUpItem(BackupItem item) async {
    // On Android production runs, cleanup is executed atomically inside BackupForegroundService
    // strictly after post-transfer SHA-256 verification succeeds.
    return false;
  }
}
