import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/backup_engine.dart';
import 'package:uback/core/backup/media_exporter.dart';

class _FakeMediaExporter implements MediaExporter {
  final List<BackupItem> items;
  final Set<String> failVerificationIds;
  final List<String> backedUpPaths = [];
  final List<String> cleanedUpIds = [];

  _FakeMediaExporter(this.items, {this.failVerificationIds = const {}});

  @override
  String get id => 'fake_exporter';

  @override
  String get mediaTypeName => 'Fake';

  @override
  Future<List<BackupItem>> discoverItems({BackupLimit? limit}) async => items;

  @override
  Future<bool> backupItem(BackupItem item, String destinationPath) async {
    backedUpPaths.add('$destinationPath/${item.fileName}');
    if (failVerificationIds.contains(item.id)) {
      return false;
    }
    return true;
  }

  @override
  Future<bool> cleanUpItem(BackupItem item) async {
    cleanedUpIds.add(item.id);
    return true;
  }
}

void main() {
  final sampleItems = [
    BackupItem(
      id: '2',
      fileName: 'IMG_NEW.jpg',
      localPath: '/sdcard/DCIM/Camera/IMG_NEW.jpg',
      sourceFolder: 'camera',
      sizeBytes: 2000,
      createdAt: DateTime(2025, 5, 10),
      mimeType: 'image/jpeg',
    ),
    BackupItem(
      id: '1',
      fileName: 'SS_OLD.png',
      localPath: '/sdcard/DCIM/Screenshots/SS_OLD.png',
      sourceFolder: 'screenshots',
      sizeBytes: 1000,
      createdAt: DateTime(2023, 2, 1),
      mimeType: 'image/png',
    ),
  ];

  test('Copy Mode transfers oldest-first into {device}/{source}/{YYYY}/{MM} and never deletes', () async {
    final exporter = _FakeMediaExporter(sampleItems);
    final engine = BackupEngine(exporter: exporter);

    final result = await engine.run(
      mode: BackupMode.copy,
      basePath: 'local/phone',
      deviceFolder: "Rodrigo's Phone",
    );

    expect(result.state, BackupRunState.completed);
    expect(result.transferred, 2);
    expect(result.failed, 0);
    expect(result.remaining, 0);
    expect(exporter.backedUpPaths, [
      'local/phone/rodrigo/screenshots/2023/02/SS_OLD.png',
      'local/phone/rodrigo/camera/2025/05/IMG_NEW.jpg',
    ]);
    expect(exporter.cleanedUpIds, isEmpty);
  });

  test('Crop Mode strictly skips deletion when post-transfer verification fails', () async {
    final exporter = _FakeMediaExporter(sampleItems, failVerificationIds: {'1'});
    final engine = BackupEngine(exporter: exporter);

    final result = await engine.run(
      mode: BackupMode.crop,
      basePath: 'local/phone',
      deviceFolder: 'rodrigo',
    );

    expect(result.state, BackupRunState.completed);
    expect(result.transferred, 1);
    expect(result.failed, 1);
    expect(result.remaining, 0);
    // File '1' failed verification -> MUST NOT be deleted! Only '2' is deleted.
    expect(exporter.cleanedUpIds, ['2']);
    expect(result.errors.single.fileName, 'SS_OLD.png');
  });

  test('Crop Mode NEVER deletes read-only sources such as WhatsApp Chat Databases', () async {
    final items = [
      ...sampleItems,
      BackupItem(
        id: 'wa_db',
        fileName: 'msgstore.db.crypt15',
        localPath: '/sdcard/Android/media/com.whatsapp/WhatsApp/Databases/msgstore.db.crypt15',
        sourceId: 'whatsapp.databases',
        sourceFolder: 'whatsapp/databases',
        sizeBytes: 4096,
        createdAt: DateTime(2024, 6, 1),
        mimeType: 'application/octet-stream',
        isReadOnly: true,
      ),
    ];
    final exporter = _FakeMediaExporter(items);
    final engine = BackupEngine(exporter: exporter);

    final result = await engine.run(
      mode: BackupMode.crop,
      basePath: 'local/phone',
      deviceFolder: 'rodrigo',
    );

    expect(result.state, BackupRunState.completed);
    expect(result.transferred, 3);
    expect(result.failed, 0);
    // Normal verified files ('1', '2') are deleted, while read-only 'wa_db' is NEVER deleted!
    expect(exporter.cleanedUpIds, ['1', '2']);
    expect(exporter.backedUpPaths, contains('local/phone/rodrigo/whatsapp/databases/2024/06/msgstore.db.crypt15'));
  });
}
