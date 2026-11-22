import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uback/core/config/app_config.dart';
import 'package:uback/core/config/smb_destination_config.dart';
import 'package:uback/core/testing/test_keys.dart';
import 'package:uback/ui/widgets/destinations_section.dart';

void main() {
  test('SmbDestinationConfig serializes public metadata and projects to AppSettings', () {
    const dest = SmbDestinationConfig(
      id: 'smb_1',
      name: 'Offsite NAS',
      enabled: true,
      host: '10.0.0.50',
      port: 445,
      share: 'backup',
      basePath: '/phones/',
      username: 'alice',
      password: 'secret',
      domain: 'WORKGROUP',
    );

    expect(dest.isConfigured, isTrue);
    expect(dest.displaySummary, 'smb://10.0.0.50/backup/phones');

    final encoded = SmbDestinationConfig.encodePublicList([dest]);
    expect(encoded, isNot(contains('secret')));
    expect(encoded, isNot(contains('alice')));

    final maps = SmbDestinationConfig.decodePublicMaps(encoded);
    expect(maps, hasLength(1));
    final restored = SmbDestinationConfig.fromPublicJson(
      maps.first,
      username: 'alice',
      password: 'secret',
    );
    expect(restored.id, 'smb_1');
    expect(restored.name, 'Offsite NAS');
    expect(restored.host, '10.0.0.50');
    expect(restored.share, 'backup');

    final base = CompileTimeDefaults.toSettings();
    final projected = restored.toAppSettings(base);
    expect(projected.host, '10.0.0.50');
    expect(projected.share, 'backup');
    expect(projected.username, 'alice');
    expect(projected.password, 'secret');
  });

  test('AppSettingsRepository persists extra SMB destinations and Telegram password', () async {
    final plain = InMemoryKeyValueStore();
    final secure = InMemoryKeyValueStore();
    final repo = AppSettingsRepository(plainStore: plain, secureStore: secure);

    const extra = SmbDestinationConfig(
      id: 'smb_2',
      name: 'Secondary NAS',
      enabled: true,
      host: '192.168.1.99',
      port: 445,
      share: 'media',
      basePath: 'phone',
      username: 'bob',
      password: 'pw2',
    );

    final settings = CompileTimeDefaults.toSettings().copyWith(
      host: '192.168.1.10',
      share: 'primary',
      primaryDestinationEnabled: true,
      extraDestinations: const [extra],
      telegramApiId: '12345',
      telegramApiHash: 'hash123',
      telegramPassword: '2fa_password',
    );

    await repo.save(settings);
    final loaded = await repo.load();

    expect(loaded.telegramApiId, '12345');
    expect(loaded.telegramApiHash, 'hash123');
    expect(loaded.telegramPassword, '2fa_password');
    expect(loaded.primaryDestinationEnabled, isTrue);
    expect(loaded.extraDestinations, hasLength(1));
    expect(loaded.extraDestinations.first.name, 'Secondary NAS');
    expect(loaded.extraDestinations.first.username, 'bob');
    expect(loaded.extraDestinations.first.password, 'pw2');
    expect(loaded.enabledSmbDestinations, hasLength(2));

    final reset = await repo.resetToDefaults();
    expect(reset.extraDestinations, isEmpty);
  });

  testWidgets('ExtraDestinationsSection supports add, toggle, test, and remove', (tester) async {
    var list = <SmbDestinationConfig>[];
    SmbDestinationConfig? tested;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: ExtraDestinationsSection(
                destinations: list,
                onChanged: (updated) => setState(() => list = updated),
                onTest: (d) async => tested = d,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(AppTestKeys.settingsAddDestination));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'NAS 2');
    await tester.enterText(fields.at(1), '10.0.0.20');
    await tester.enterText(fields.at(3), 'archive');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(list, hasLength(1));
    final id = list.first.id;
    expect(find.text('NAS 2'), findsOneWidget);

    await tester.tap(find.byKey(AppTestKeys.settingsDestinationTest(id)));
    await tester.pump();
    expect(tested?.host, '10.0.0.20');

    await tester.tap(find.byKey(AppTestKeys.settingsDestinationToggle(id)));
    await tester.pumpAndSettle();
    expect(list.first.enabled, isFalse);

    await tester.tap(find.byKey(AppTestKeys.settingsDestinationRemove(id)));
    await tester.pumpAndSettle();
    expect(list, isEmpty);
  });
}
