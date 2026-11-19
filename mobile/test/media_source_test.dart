import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/media_exporter.dart';
import 'package:uback/core/backup/media_source.dart';
import 'package:uback/core/backup/native_bridge.dart';
import 'package:uback/core/config/app_config.dart';

class _NoopBridge implements NativeBackupBridge {
  @override
  Future<PermissionState> checkPermissions() async => const PermissionState();
  @override
  Future<List<BackupItem>> discoverMedia({
    required Set<String> enabledSourceIds,
    int? perSourceLimit,
  }) async =>
      const [];
  @override
  Future<String> getAppVersion() async => '1.1.0+2';
  @override
  Future<BackupProgress> getBackupStatus() async => const BackupProgress();
  @override
  Future<String> getDeviceName() async => 'android';
  @override
  Future<Map<String, MediaSourceStats>> getSourceStats() async => const {};
  @override
  Future<void> openAllFilesAccessSettings() async {}
  @override
  Stream<BackupProgress> progressStream() => const Stream.empty();
  @override
  Future<PermissionState> requestMediaPermissions() async => const PermissionState();
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
  final sources = defaultMediaSources(_NoopBridge());

  test('defaultMediaSources defines hierarchical Camera, Screenshots, WhatsApp, and Recordings', () {
    expect(sources.map((s) => s.id).toList(), ['camera', 'screenshots', 'whatsapp', 'recordings']);

    final camera = sources[0];
    expect(camera.leafIds, {'camera.images', 'camera.videos'});

    final whatsapp = sources[2];
    expect(whatsapp.children.map((c) => c.id).toList(), ['whatsapp.received', 'whatsapp.sent']);
    expect(whatsapp.leafIds, {
      'whatsapp.received.images',
      'whatsapp.received.videos',
      'whatsapp.received.audios',
      'whatsapp.sent.images',
      'whatsapp.sent.videos',
      'whatsapp.sent.audios',
    });
  });

  test('tri-state selectionState and recursive aggregateStats roll up accurately', () {
    final whatsapp = sources[2];
    final stats = {
      'whatsapp.received.images': const MediaSourceStats(fileCount: 10, totalBytes: 1000),
      'whatsapp.received.audios': const MediaSourceStats(fileCount: 5, totalBytes: 500),
      'whatsapp.sent.videos': const MediaSourceStats(fileCount: 2, totalBytes: 4000),
    };

    final total = whatsapp.aggregateStats(stats);
    expect(total.fileCount, 17);
    expect(total.totalBytes, 5500);

    expect(whatsapp.selectionState(whatsapp.leafIds), isTrue);
    expect(whatsapp.selectionState(const {}), isFalse);
    expect(whatsapp.selectionState(const {'whatsapp.sent.videos'}), isNull);
  });
}
