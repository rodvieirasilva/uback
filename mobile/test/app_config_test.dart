import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/config/app_config.dart';

void main() {
  const compileDefaults = AppSettings(
    host: '192.168.1.50',
    port: 445,
    share: 'safe',
    basePath: 'local/phone',
    username: 'default_user',
    password: 'default_password',
    domain: '',
    deviceFolderOverride: '',
    enabledSourceIds: {'camera', 'screenshots'},
  );

  test('loads compile-time defaults when storage is empty', () async {
    final repo = AppSettingsRepository(
      plainStore: InMemoryKeyValueStore(),
      secureStore: InMemoryKeyValueStore(),
      defaults: compileDefaults,
    );

    final loaded = await repo.load();
    expect(loaded.host, '192.168.1.50');
    expect(loaded.username, 'default_user');
    expect(loaded.password, 'default_password');
    expect(loaded.enabledSourceIds, {'camera', 'screenshots'});
  });

  test('runtime saved settings override defaults and reset restores defaults', () async {
    final plain = InMemoryKeyValueStore();
    final secure = InMemoryKeyValueStore();
    final repo = AppSettingsRepository(
      plainStore: plain,
      secureStore: secure,
      defaults: compileDefaults,
    );

    final custom = compileDefaults.copyWith(
      host: '10.0.0.99',
      port: 4455,
      username: 'rodrigo',
      password: 'secret',
      enabledSourceIds: {'camera'},
    );
    await repo.save(custom);

    final reloaded = await repo.load();
    expect(reloaded.host, '10.0.0.99');
    expect(reloaded.port, 4455);
    expect(reloaded.username, 'rodrigo');
    expect(reloaded.password, 'secret');
    expect(reloaded.enabledSourceIds, {'camera'});
    expect(
      reloaded.destinationPreview("Rodrigo's Phone"),
      'smb://10.0.0.99:4455/safe/local/phone/rodrigo/camera/YYYY/MM',
    );

    final restored = await repo.resetToDefaults();
    expect(restored.host, '192.168.1.50');
    expect(restored.username, 'default_user');
    expect(restored.enabledSourceIds, {'camera', 'screenshots'});

    final afterReset = await repo.load();
    expect(afterReset.host, '192.168.1.50');
    expect(afterReset.password, 'default_password');
    expect(afterReset.enabledSourceIds, {'camera', 'screenshots'});
  });
}
