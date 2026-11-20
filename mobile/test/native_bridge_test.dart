import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/media_exporter.dart';
import 'package:uback/core/backup/media_source.dart';
import 'package:uback/core/backup/native_bridge.dart';
import 'package:uback/core/config/app_config.dart';
import 'package:uback/core/config/custom_folder_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('uback/native');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getDeviceName':
          return 'Galaxy S23 FE';
        case 'getAppVersion':
          return '1.2.1+4';
        case 'checkPermissions':
        case 'requestMediaPermissions':
        case 'requestSnapshotPermissions':
          return {'hasMedia': true, 'hasAllFiles': true, 'hasNotifications': false};
        case 'openAllFilesAccessSettings':
        case 'startBackup':
        case 'stopBackup':
          return null;
        case 'pickFolder':
          return {'relativePath': 'DJI/Media'};
        case 'discoverMedia':
          return [
            {
              'id': 'item-1',
              'contentUri': 'content://media/external/images/media/1',
              'fileName': 'IMG_001.jpg',
              'localPath': '/sdcard/DCIM/Camera/IMG_001.jpg',
              'sourceId': 'camera.images',
              'sourceFolder': 'camera',
              'sizeBytes': 2048,
              'createdAtMs': DateTime(2024, 3, 15).millisecondsSinceEpoch,
              'mimeType': 'image/jpeg',
              'isSnapshot': false,
            },
            {
              'id': 'snap-1',
              'fileName': 'contacts_20240315.vcf',
              'localPath': '/data/user/0/uback/cache/contacts_20240315.vcf',
              'sourceId': 'snapshots.contacts',
              'sourceFolder': 'snapshots/contacts',
              'sizeBytes': 512,
              'createdAtMs': DateTime(2024, 3, 15).millisecondsSinceEpoch,
              'mimeType': 'text/vcard',
              'isSnapshot': true,
            },
          ];
        case 'getSourceStats':
          return {
            'camera.images': {'count': 42, 'totalBytes': 102400},
            'custom.dji': {'count': 3, 'totalBytes': 9000},
          };
        case 'testConnection':
          return {'ok': true, 'message': 'Connected to smb://nas/safe'};
        case 'getBackupStatus':
          return {
            'state': 'running',
            'stage': 'verifying',
            'total': 10,
            'transferred': 4,
            'skipped': 1,
            'failed': 1,
            'remaining': 4,
            'currentFile': 'IMG_005.jpg',
            'bytesTransferred': 4096,
            'totalBytes': 10240,
            'errorMessage': null,
            'errors': [
              {'fileName': 'BAD.jpg', 'message': 'SHA-256 mismatch'},
            ],
          };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('MethodChannelNativeBridge serializes all method calls and deserializes responses', () async {
    final bridge = MethodChannelNativeBridge();
    final custom = [CustomFolderConfig.create(relativePath: 'DJI', displayName: 'DJI')];
    const settings = AppSettings(
      host: '192.168.1.10',
      port: 445,
      share: 'safe',
      basePath: 'local/phone',
      username: 'user',
      password: 'pw',
      domain: '',
      deviceFolderOverride: '',
    );

    expect(await bridge.getDeviceName(), 'Galaxy S23 FE');
    expect(await bridge.getAppVersion(), '1.2.1+4');

    final perms = await bridge.checkPermissions();
    expect(perms.hasMedia, isTrue);
    expect(perms.hasAllFiles, isTrue);
    expect(perms.hasNotifications, isFalse);

    await bridge.requestMediaPermissions();
    await bridge.requestSnapshotPermissions({'snapshots.contacts'});
    await bridge.openAllFilesAccessSettings();
    final picked = await bridge.pickFolder();
    expect(picked?.hasPath, isTrue);
    expect(picked?.relativePath, 'DJI/Media');

    final items = await bridge.discoverMedia(
      enabledSourceIds: {'camera.images', 'snapshots.contacts'},
      customFolders: custom,
      perSourceLimit: 5,
    );
    expect(items.length, 2);
    expect(items.first.toMap()['fileName'], 'IMG_001.jpg');
    expect(items.last.isSnapshot, isTrue);
    expect(items.last.toMap()['isSnapshot'], isTrue);

    final stats = await bridge.getSourceStats(customFolders: custom);
    expect(stats['camera.images']?.fileCount, 42);
    expect(stats['custom.dji']?.totalBytes, 9000);

    final conn = await bridge.testConnection(settings);
    expect(conn.ok, isTrue);
    expect(conn.message, contains('smb://nas/safe'));

    await bridge.startBackup(
      settings: settings,
      mode: BackupMode.crop,
      deviceFolder: 'galaxy-s23-fe',
      items: items,
    );
    await bridge.stopBackup();

    final status = await bridge.getBackupStatus();
    expect(status.state, BackupRunState.running);
    expect(status.isActive, isTrue);
    expect(status.transferred + status.skipped + status.failed, 6);
    expect(status.fraction, closeTo(0.4, 0.001));
    expect(status.errors.length, 1);
    expect(status.errors.first.fileName, 'BAD.jpg');

    // Verify all expected method channel invocations occurred
    expect(
      calls.map((c) => c.method).toList(),
      containsAll([
        'getDeviceName',
        'getAppVersion',
        'checkPermissions',
        'requestMediaPermissions',
        'requestSnapshotPermissions',
        'openAllFilesAccessSettings',
        'discoverMedia',
        'getSourceStats',
        'testConnection',
        'startBackup',
        'stopBackup',
        'getBackupStatus',
      ]),
    );
  });

  test('BackupProgress.fromMap handles all states and edge cases', () {
    for (final pair in [
      ('idle', BackupRunState.idle),
      ('scanning', BackupRunState.scanning),
      ('running', BackupRunState.running),
      ('completed', BackupRunState.completed),
      ('cancelled', BackupRunState.cancelled),
      ('error', BackupRunState.error),
      ('unknown_state', BackupRunState.idle),
    ]) {
      final p = BackupProgress.fromMap({'state': pair.$1, 'total': 0});
      expect(p.state, pair.$2);
      expect(p.fraction, 0.0);
    }

    final countFraction = BackupProgress.fromMap({
      'state': 'running',
      'total': 4,
      'transferred': 2,
      'skipped': 1,
      'failed': 0,
    });
    expect(countFraction.fraction, closeTo(0.75, 0.001));

    final s = MediaSourceStats.fromMap({'count': 3, 'totalBytes': 1234});
    expect(s.fileCount, 3);
    expect(s.totalBytes, 1234);
  });
}
