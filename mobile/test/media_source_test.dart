import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/media_exporter.dart';
import 'package:uback/core/backup/media_source.dart';
import 'package:uback/core/backup/native_bridge.dart';
import 'package:uback/core/config/app_config.dart';
import 'package:uback/core/config/custom_folder_config.dart';

class _NoopBridge implements NativeBackupBridge {
  @override
  Future<PermissionState> checkPermissions() async => const PermissionState();
  @override
  Future<List<BackupItem>> discoverMedia({
    required Set<String> enabledSourceIds,
    List<CustomFolderConfig> customFolders = const [],
    int? perSourceLimit,
  }) async =>
      const [];
  @override
  Future<String> getAppVersion() async => '1.2.0+3';
  @override
  Future<BackupProgress> getBackupStatus() async => const BackupProgress();
  @override
  Future<String> getDeviceName() async => 'android';
  @override
  Future<Map<String, MediaSourceStats>> getSourceStats({
    List<CustomFolderConfig> customFolders = const [],
  }) async =>
      const {};
  @override
  Future<void> openAllFilesAccessSettings() async {}
  @override
  Stream<BackupProgress> progressStream() => const Stream.empty();
  @override
  Future<PermissionState> requestMediaPermissions() async => const PermissionState();
  @override
  Future<PermissionState> requestSnapshotPermissions(Set<String> snapshotSources) async =>
      const PermissionState();
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
      const ConnectionTestResult(ok: true, message: 'ok');
}

void main() {
  final bridge = _NoopBridge();
  final sources = defaultMediaSources(bridge);

  test('defaultMediaSources defines all 11 built-in hierarchical trees', () {
    expect(sources.map((s) => s.id).toList(), [
      'camera',
      'screenshots',
      'screen_recordings',
      'whatsapp',
      'whatsapp_business',
      'telegram',
      'editors',
      'recordings',
      'documents',
      'downloads',
      'snapshots',
    ]);

    final camera = sources.firstWhere((s) => s.id == 'camera');
    expect(camera.leafIds, {'camera.images', 'camera.videos', 'camera.raw'});

    final whatsapp = sources.firstWhere((s) => s.id == 'whatsapp');
    expect(whatsapp.children.map((c) => c.id).toList(), ['whatsapp.received', 'whatsapp.sent']);
    expect(whatsapp.leafIds, {
      'whatsapp.received.images',
      'whatsapp.received.videos',
      'whatsapp.received.audios',
      'whatsapp.received.documents',
      'whatsapp.sent.images',
      'whatsapp.sent.videos',
      'whatsapp.sent.audios',
      'whatsapp.sent.documents',
    });

    final snapshots = sources.firstWhere((s) => s.id == 'snapshots');
    expect(snapshots.leafIds, snapshotSourceIds);
  });

  test('opt-in noisy/sensitive sources start disabled by default', () {
    expect(defaultEnabledMediaSourceIds.contains('downloads.media'), isFalse);
    expect(defaultEnabledMediaSourceIds.contains('downloads.documents'), isFalse);
    expect(defaultEnabledMediaSourceIds.contains('downloads.other'), isFalse);
    expect(defaultEnabledMediaSourceIds.contains('whatsapp_business.received.images'), isFalse);
    expect(defaultEnabledMediaSourceIds.contains('telegram.images'), isFalse);
    expect(defaultEnabledMediaSourceIds.contains('snapshots.contacts'), isFalse);
    expect(defaultEnabledMediaSourceIds.contains('snapshots.sms'), isFalse);
    expect(defaultEnabledMediaSourceIds.contains('snapshots.call_logs'), isFalse);
  });

  test('buildMediaSources appends Custom Folders group when configured', () {
    final custom = [
      CustomFolderConfig.create(relativePath: '/sdcard/DJI/Media/', displayName: 'Drone'),
    ];
    final withCustom = buildMediaSources(bridge, customFolders: custom);
    final group = withCustom.last;
    expect(group.id, 'custom');
    expect(group.children.length, 1);
    expect(group.children.first.id, 'custom.dji-media');
    expect(group.children.first.displayName, 'Drone');
    expect(group.children.first.subtitle, 'DJI/Media');
    expect(group.children.first.destinationSlug, 'custom/dji-media');
  });

  test('tri-state selectionState and recursive aggregateStats roll up accurately', () {
    final whatsapp = sources.firstWhere((s) => s.id == 'whatsapp');
    final stats = {
      'whatsapp.received.images': const MediaSourceStats(fileCount: 10, totalBytes: 1000),
      'whatsapp.received.audios': const MediaSourceStats(fileCount: 5, totalBytes: 500),
      'whatsapp.received.documents': const MediaSourceStats(fileCount: 3, totalBytes: 1500),
      'whatsapp.sent.videos': const MediaSourceStats(fileCount: 2, totalBytes: 4000),
    };

    final total = whatsapp.aggregateStats(stats);
    expect(total.fileCount, 20);
    expect(total.totalBytes, 7000);

    expect(whatsapp.selectionState(whatsapp.leafIds), isTrue);
    expect(whatsapp.selectionState(const {}), isFalse);
    expect(whatsapp.selectionState(const {'whatsapp.sent.videos'}), isNull);
  });
}
