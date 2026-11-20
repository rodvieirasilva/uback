import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/backup_destination.dart';
import 'package:uback/core/backup/media_exporter.dart';
import 'package:uback/core/backup/media_source.dart';
import 'package:uback/core/config/app_config.dart';
import 'package:uback/core/config/custom_folder_config.dart';

void main() {
  const compileDefaults = AppSettings(
    destinationType: SmbNasDestination.typeId,
    host: '192.168.1.50',
    port: 445,
    share: 'safe',
    basePath: 'local/phone',
    username: 'default_user',
    password: 'default_password',
    domain: '',
    deviceFolderOverride: '',
    enabledSourceIds: defaultEnabledMediaSourceIds,
  );

  test('loads compile-time defaults when storage is empty', () async {
    final repo = AppSettingsRepository(
      plainStore: InMemoryKeyValueStore(),
      secureStore: InMemoryKeyValueStore(),
      defaults: compileDefaults,
    );

    final loaded = await repo.load();
    expect(loaded.destinationType, SmbNasDestination.typeId);
    expect(loaded.lastExporterId, 'unified_media_exporter');
    expect(loaded.lastMode, BackupMode.copy);
    expect(loaded.lastLimitType, BackupLimitType.all);
    expect(loaded.lastLimitValue, 100);
    expect(loaded.mediaSourcesExpanded, isTrue);
    expect(loaded.expandedSourceGroupIds, isEmpty);
    expect(loaded.customFolders, isEmpty);
    expect(loaded.host, '192.168.1.50');
    expect(loaded.username, 'default_user');
    expect(loaded.password, 'default_password');
    expect(loaded.enabledSourceIds, defaultEnabledMediaSourceIds);
  });

  test('migrates legacy camera source id to camera images, videos, and raw', () async {
    final plain = InMemoryKeyValueStore();
    await plain.write('uback_enabled_sources', 'camera,screenshots');
    final repo = AppSettingsRepository(
      plainStore: plain,
      secureStore: InMemoryKeyValueStore(),
      defaults: compileDefaults,
    );

    final loaded = await repo.load();
    expect(
      loaded.enabledSourceIds,
      {'camera.images', 'camera.videos', 'camera.raw', 'screenshots'},
    );
  });

  test('persists full session state, custom folders, toggles, and resets cleanly to defaults', () async {
    final plain = InMemoryKeyValueStore();
    final secure = InMemoryKeyValueStore();
    final repo = AppSettingsRepository(
      plainStore: plain,
      secureStore: secure,
      defaults: compileDefaults,
    );

    final dji = CustomFolderConfig.create(relativePath: 'DJI/Media', displayName: 'DJI Drone');
    final custom = compileDefaults.copyWith(
      lastExporterId: 'unified_media_exporter',
      lastMode: BackupMode.crop,
      lastLimitType: BackupLimitType.files,
      lastLimitValue: 25,
      mediaSourcesExpanded: false,
      expandedSourceGroupIds: {'camera', 'whatsapp.sent'},
      host: '10.0.0.99',
      port: 4455,
      username: 'alice',
      password: 'secret',
      enabledSourceIds: {'camera.images', 'recordings', 'downloads.documents', dji.id},
      customFolders: [dji],
    );
    await repo.save(custom);

    final reloaded = await repo.load();
    expect(reloaded.lastExporterId, 'unified_media_exporter');
    expect(reloaded.lastMode, BackupMode.crop);
    expect(reloaded.lastLimitType, BackupLimitType.files);
    expect(reloaded.lastLimitValue, 25);
    expect(reloaded.mediaSourcesExpanded, isFalse);
    expect(reloaded.expandedSourceGroupIds, {'camera', 'whatsapp.sent'});
    expect(reloaded.host, '10.0.0.99');
    expect(reloaded.port, 4455);
    expect(reloaded.username, 'alice');
    expect(reloaded.password, 'secret');
    expect(
      reloaded.enabledSourceIds,
      {'camera.images', 'recordings', 'downloads.documents', 'custom.dji-media'},
    );
    expect(reloaded.customFolders.length, 1);
    expect(reloaded.customFolders.first.relativePath, 'DJI/Media');
    expect(reloaded.customFolders.first.displayName, 'DJI Drone');

    final restored = await repo.resetToDefaults();
    expect(restored.host, '192.168.1.50');
    expect(restored.lastMode, BackupMode.copy);
    expect(restored.lastLimitType, BackupLimitType.all);
    expect(restored.customFolders, isEmpty);
    expect(restored.enabledSourceIds, defaultEnabledMediaSourceIds);

    final afterReset = await repo.load();
    expect(afterReset.host, '192.168.1.50');
    expect(afterReset.password, 'default_password');
    expect(afterReset.lastMode, BackupMode.copy);
    expect(afterReset.customFolders, isEmpty);
    expect(afterReset.enabledSourceIds, defaultEnabledMediaSourceIds);
  });
}
