import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/backup_controller.dart';
import 'package:uback/core/backup/media_exporter.dart';
import 'package:uback/core/backup/native_bridge.dart';
import 'package:uback/core/config/app_config.dart';
import 'package:uback/core/testing/test_keys.dart';
import 'package:uback/main.dart';

class _FakeBridge implements NativeBackupBridge {
  final StreamController<BackupProgress> _progressCtrl =
      StreamController<BackupProgress>.broadcast();

  List<BackupItem> lastStartedItems = [];
  BackupMode? lastStartedMode;

  @override
  Future<String> getDeviceName() async => "Rodrigo's Phone";

  @override
  Future<String> getAppVersion() async => '1.0.0+1';

  @override
  Future<PermissionState> checkPermissions() async =>
      const PermissionState(hasMedia: true, hasAllFiles: true, hasNotifications: true);

  @override
  Future<PermissionState> requestMediaPermissions() => checkPermissions();

  @override
  Future<void> openAllFilesAccessSettings() async {}

  @override
  Future<List<BackupItem>> discoverMedia({
    required bool includeCamera,
    required bool includeScreenshots,
  }) async {
    return [
      if (includeCamera)
        BackupItem(
          id: 'c1',
          fileName: 'IMG_2023.jpg',
          localPath: '/sdcard/DCIM/Camera/IMG_2023.jpg',
          sourceFolder: 'camera',
          sizeBytes: 1024,
          createdAt: DateTime(2023, 1, 1),
          mimeType: 'image/jpeg',
        ),
      if (includeScreenshots)
        BackupItem(
          id: 's1',
          fileName: 'SS_2024.png',
          localPath: '/sdcard/DCIM/Screenshots/SS_2024.png',
          sourceFolder: 'screenshots',
          sizeBytes: 2048,
          createdAt: DateTime(2024, 5, 1),
          mimeType: 'image/png',
        ),
    ];
  }

  @override
  Future<Map<String, int>> getSourceCounts() async => {'camera': 1, 'screenshots': 1};

  @override
  Future<ConnectionTestResult> testConnection(AppSettings settings) async =>
      ConnectionTestResult(ok: true, message: 'Connected to smb://${settings.host}/${settings.share}');

  @override
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  }) async {
    lastStartedMode = mode;
    lastStartedItems = items;
    _progressCtrl.add(
      BackupProgress(
        state: BackupRunState.completed,
        stage: 'completed',
        total: items.length,
        transferred: items.length,
        skipped: 0,
        failed: 0,
        remaining: 0,
        bytesTransferred: items.fold(0, (s, i) => s + i.sizeBytes),
        totalBytes: items.fold(0, (s, i) => s + i.sizeBytes),
      ),
    );
  }

  @override
  Future<void> stopBackup() async {}

  @override
  Future<BackupProgress> getBackupStatus() async => const BackupProgress();

  @override
  Stream<BackupProgress> progressStream() => _progressCtrl.stream;
}

void main() {
  testWidgets('Home and Settings UI expose testIds, zero image previews, and drive backup',
      (tester) async {
    final bridge = _FakeBridge();
    final repo = AppSettingsRepository(
      plainStore: InMemoryKeyValueStore(),
      secureStore: InMemoryKeyValueStore(),
      defaults: const AppSettings(
        host: '192.168.1.10',
        port: 445,
        share: 'safe',
        basePath: 'local/phone',
        username: 'user',
        password: 'pw',
        domain: '',
        deviceFolderOverride: '',
        includeCamera: true,
        includeScreenshots: true,
      ),
    );
    final controller = BackupController(settingsRepo: repo, bridge: bridge);
    await controller.init();

    await tester.pumpWidget(UBackApp(controller: controller));
    await tester.pumpAndSettle();

    // Verify app logo + version label exist, and zero media file previews exist
    expect(find.byKey(AppTestKeys.appLogo), findsOneWidget);
    expect(find.byKey(AppTestKeys.appVersion), findsOneWidget);
    expect(find.text('UBack v1.0.0+1'), findsOneWidget);
    final fileImages = find.byWidgetPredicate((w) => w is Image && w.image is FileImage);
    expect(fileImages, findsNothing);

    // Verify sanitized destination preview
    expect(
      find.textContaining('smb://192.168.1.10:445/safe/local/phone/rodrigo/{camera|screenshots}'),
      findsOneWidget,
    );

    // Test connection via testId
    await tester.tap(find.byKey(AppTestKeys.testConnection));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.connectionStatusBanner), findsOneWidget);
    expect(find.textContaining('Connected to smb://192.168.1.10/safe'), findsOneWidget);

    // Select Limit: Oldest 1 file
    await tester.tap(find.byKey(AppTestKeys.limitFiles));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppTestKeys.limitValueInput), '1');
    await tester.pumpAndSettle();

    // Start Copy Backup
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await tester.pumpAndSettle();

    expect(bridge.lastStartedMode, BackupMode.copy);
    expect(bridge.lastStartedItems.map((e) => e.id).toList(), ['c1']);
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '1');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '1');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');

    // Open Settings and verify toggles + fields exist by testId
    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.settingsHost), findsOneWidget);
    expect(find.byKey(AppTestKeys.settingsSourceCamera), findsOneWidget);
    expect(find.byKey(AppTestKeys.settingsSourceScreenshots), findsOneWidget);
    expect(find.byKey(AppTestKeys.settingsSave), findsOneWidget);
  });
}
