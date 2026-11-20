import '../config/app_config.dart';
import 'media_exporter.dart';
import 'native_bridge.dart';

/// Extensible contract for backup destinations (e.g., SMB NAS today; SFTP, S3,
/// WebDAV, or local USB drives in the future).
abstract class BackupDestination {
  /// Stable config identifier, e.g. `"smb_nas"`.
  String get id;

  /// Human-readable name displayed in Settings, e.g. `"SMB NAS"`.
  String get displayName;

  /// Short transport summary, e.g. `"Local network SMB2/SMB3 share"`.
  String get description;

  /// Whether the active [settings] contain enough details to connect.
  bool isConfigured(AppSettings settings);

  /// Tests connectivity and write/path access against this destination.
  Future<ConnectionTestResult> testConnection(AppSettings settings);

  /// Starts a verified transfer of [items] to this destination.
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  });

  /// Pauses an in-flight transfer cleanly without cancelling.
  Future<void> pauseBackup();

  /// Resumes a paused transfer.
  Future<void> resumeBackup();

  /// Safely requests cancellation of an in-flight transfer.
  Future<void> stopBackup();
}

/// Active destination implementation transferring files over SMB2/SMB3 via native `smbj`.
class SmbNasDestination implements BackupDestination {
  static const String typeId = 'smb_nas';

  final NativeBackupBridge _bridge;

  SmbNasDestination(this._bridge);

  @override
  String get id => typeId;

  @override
  String get displayName => 'SMB NAS';

  @override
  String get description => 'SMB2/SMB3 network share with SHA-256 read-back verification';

  @override
  bool isConfigured(AppSettings settings) =>
      settings.host.trim().isNotEmpty && settings.share.trim().isNotEmpty;

  @override
  Future<ConnectionTestResult> testConnection(AppSettings settings) =>
      _bridge.testConnection(settings);

  @override
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  }) =>
      _bridge.startBackup(
        settings: settings,
        mode: mode,
        deviceFolder: deviceFolder,
        items: items,
      );

  @override
  Future<void> pauseBackup() => _bridge.pauseBackup();

  @override
  Future<void> resumeBackup() => _bridge.resumeBackup();

  @override
  Future<void> stopBackup() => _bridge.stopBackup();
}

/// Registry of supported destinations selectable from compile-time or runtime config.
class DestinationRegistry {
  final List<BackupDestination> _destinations;

  DestinationRegistry(List<BackupDestination> destinations)
      : _destinations = List.unmodifiable(destinations);

  factory DestinationRegistry.defaults(NativeBackupBridge bridge) =>
      DestinationRegistry([SmbNasDestination(bridge)]);

  List<BackupDestination> get all => _destinations;

  BackupDestination resolve(String id) {
    for (final dest in _destinations) {
      if (dest.id == id) return dest;
    }
    return _destinations.first;
  }
}
