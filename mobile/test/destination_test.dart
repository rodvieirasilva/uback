import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/backup_controller.dart';
import 'package:uback/core/backup/backup_destination.dart';
import 'package:uback/core/backup/media_exporter.dart';
import 'package:uback/core/backup/media_source.dart';
import 'package:uback/core/backup/native_bridge.dart';
import 'package:uback/core/config/app_config.dart';

class _CustomDestination implements BackupDestination {
  bool tested = false;
  bool started = false;

  @override
  String get id => 'custom_cloud';

  @override
  String get displayName => 'Custom Cloud';

  @override
  String get description => 'Test pluggable destination';

  @override
  bool isConfigured(AppSettings settings) => true;

  @override
  Future<ConnectionTestResult> testConnection(AppSettings settings) async {
    tested = true;
    return const ConnectionTestResult(ok: true, message: 'Custom Cloud OK');
  }

  @override
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  }) async {
    started = true;
  }

  @override
  Future<void> stopBackup() async {}
}

class _StubBridge implements NativeBackupBridge {
  @override
  Future<PermissionState> checkPermissions() async =>
      const PermissionState(hasMedia: true, hasAllFiles: true, hasNotifications: true);
  @override
  Future<List<BackupItem>> discoverMedia({
    required Set<String> enabledSourceIds,
    int? perSourceLimit,
  }) async =>
      [
        BackupItem(
          id: '1',
          fileName: 'a.jpg',
          localPath: '/sdcard/DCIM/Camera/a.jpg',
          sourceId: 'camera.images',
          sourceFolder: 'camera',
          sizeBytes: 128,
          createdAt: DateTime(2024, 1, 1),
          mimeType: 'image/jpeg',
        ),
      ];
  @override
  Future<String> getAppVersion() async => '1.1.0+2';
  @override
  Future<BackupProgress> getBackupStatus() async => const BackupProgress();
  @override
  Future<String> getDeviceName() async => 'rodrigo';
  @override
  Future<Map<String, MediaSourceStats>> getSourceStats() async => const {};
  @override
  Future<void> openAllFilesAccessSettings() async {}
  @override
  Stream<BackupProgress> progressStream() => const Stream.empty();
  @override
  Future<PermissionState> requestMediaPermissions() => checkPermissions();
  @override
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  }) async {}
  @override
  Future<void> stopBackup() async {}
  @override
  Future<ConnectionTestResult> testConnection(AppSettings settings) async =>
      const ConnectionTestResult(ok: true, message: 'SMB OK');
}

void main() {
  test('DestinationRegistry resolves configured destination and delegates backup operations', () async {
    final bridge = _StubBridge();
    final custom = _CustomDestination();
    final registry = DestinationRegistry([SmbNasDestination(bridge), custom]);

    final repo = AppSettingsRepository(
      plainStore: InMemoryKeyValueStore(),
      secureStore: InMemoryKeyValueStore(),
      defaults: const AppSettings(
        destinationType: 'custom_cloud',
        host: '',
        port: 445,
        share: '',
        basePath: '',
        username: '',
        password: '',
        domain: '',
        deviceFolderOverride: '',
      ),
    );

    final controller = BackupController(
      settingsRepo: repo,
      bridge: bridge,
      destinations: registry,
    );
    await controller.init();

    expect(controller.activeDestination.id, 'custom_cloud');
    final conn = await controller.testConnection();
    expect(conn.ok, isTrue);
    expect(custom.tested, isTrue);

    await controller.startBackup();
    expect(custom.started, isTrue);
  });
}
