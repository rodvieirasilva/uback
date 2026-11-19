import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uback/core/backup/backup_controller.dart';
import 'package:uback/core/backup/media_exporter.dart';
import 'package:uback/core/backup/media_source.dart';
import 'package:uback/core/backup/native_bridge.dart';
import 'package:uback/core/config/app_config.dart';
import 'package:uback/core/testing/test_keys.dart';
import 'package:uback/main.dart';

class _FakeBridge implements NativeBackupBridge {
  final StreamController<BackupProgress> _progressCtrl =
      StreamController<BackupProgress>.broadcast();
  final Completer<Map<String, MediaSourceStats>>? delayedStats;

  List<BackupItem> lastStartedItems = [];
  BackupMode? lastStartedMode;

  _FakeBridge({this.delayedStats});

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
  Future<List<BackupItem>> discoverMedia({required Set<String> enabledSourceIds}) async {
    return [
      if (enabledSourceIds.contains('camera'))
        BackupItem(
          id: 'c1',
          fileName: 'IMG_2023.jpg',
          localPath: '/sdcard/DCIM/Camera/IMG_2023.jpg',
          sourceFolder: 'camera',
          sizeBytes: 1024,
          createdAt: DateTime(2023, 1, 1),
          mimeType: 'image/jpeg',
        ),
      if (enabledSourceIds.contains('screenshots'))
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
  Future<Map<String, MediaSourceStats>> getSourceStats() async {
    if (delayedStats != null) return delayedStats!.future;
    return const {
      'camera': MediaSourceStats(fileCount: 1, totalBytes: 1024),
      'screenshots': MediaSourceStats(fileCount: 1, totalBytes: 2048),
    };
  }

  @override
  Future<ConnectionTestResult> testConnection(AppSettings settings) async => ConnectionTestResult(
        ok: true,
        message: 'Connected to smb://${settings.host}/${settings.share}',
      );

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

AppSettingsRepository _makeRepo() => AppSettingsRepository(
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
        enabledSourceIds: {'camera', 'screenshots'},
      ),
    );

void main() {
  testWidgets('Home exposes MediaSource toggles with live impact, zero previews, and no phase jargon',
      (tester) async {
    final bridge = _FakeBridge();
    final controller = BackupController(settingsRepo: _makeRepo(), bridge: bridge);
    await controller.init();

    await tester.pumpWidget(UBackApp(controller: controller));
    await tester.pumpAndSettle();

    // App logo + version label exist; zero media file previews; zero "Phase" jargon
    expect(find.byKey(AppTestKeys.appLogo), findsOneWidget);
    expect(find.byKey(AppTestKeys.appVersion), findsOneWidget);
    expect(find.text('UBack v1.0.0+1'), findsOneWidget);
    expect(find.textContaining('PHASE'), findsNothing);
    expect(find.textContaining('Phase'), findsNothing);
    final fileImages = find.byWidgetPredicate((w) => w is Image && w.image is FileImage);
    expect(fileImages, findsNothing);

    // Live estimate reflects both Camera (1.0 KB) + Screenshots (2.0 KB) = 2 files • 3.0 KB
    expect(
      tester.widget<Text>(find.byKey(AppTestKeys.mediaSourcesSummary)).data,
      'Selected: 2 files • 3.0 KB',
    );
    expect(
      find.textContaining('smb://192.168.1.10:445/safe/local/phone/rodrigo/{camera|screenshots}'),
      findsOneWidget,
    );

    // Toggle Screenshots OFF on Home screen -> immediate impact update!
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceToggle('screenshots')));
    await tester.tap(find.byKey(AppTestKeys.sourceToggle('screenshots')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(AppTestKeys.mediaSourcesSummary)).data,
      'Selected: 1 files • 1.0 KB',
    );
    expect(
      find.textContaining('smb://192.168.1.10:445/safe/local/phone/rodrigo/camera/YYYY/MM'),
      findsOneWidget,
    );

    // Start Copy Backup -> only Camera item backed up
    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await tester.pumpAndSettle();

    expect(bridge.lastStartedMode, BackupMode.copy);
    expect(bridge.lastStartedItems.map((e) => e.id).toList(), ['c1']);
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '1');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '1');

    // Open Settings -> no Phase jargon and clean connection/permissions fields
    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.settingsHost), findsOneWidget);
    expect(find.byKey(AppTestKeys.settingsSave), findsOneWidget);
    expect(find.textContaining('PHASE'), findsNothing);
    expect(find.textContaining('Phase'), findsNothing);
  });

  testWidgets('Shows non-blocking estimating indicator while slow MediaStore scan runs',
      (tester) async {
    final completer = Completer<Map<String, MediaSourceStats>>();
    final bridge = _FakeBridge(delayedStats: completer);
    final controller = BackupController(settingsRepo: _makeRepo(), bridge: bridge);
    await controller.init();

    await tester.pumpWidget(UBackApp(controller: controller));
    await tester.pump();

    // Estimating spinner is shown while MediaStore query is still pending
    expect(find.byKey(AppTestKeys.mediaSourcesEstimating), findsOneWidget);
    expect(find.text('Estimating size...'), findsOneWidget);

    // User can STILL toggle a media source while estimation is running!
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceToggle('camera')));
    await tester.tap(find.byKey(AppTestKeys.sourceToggle('camera')));
    await tester.pump();
    expect(controller.settings.isSourceEnabled('camera'), isFalse);

    // Once estimation resolves, summary shows impact of remaining enabled source (Screenshots)
    completer.complete(const {
      'camera': MediaSourceStats(fileCount: 500, totalBytes: 500 * 1024 * 1024),
      'screenshots': MediaSourceStats(fileCount: 10, totalBytes: 5 * 1024 * 1024),
    });
    await tester.pumpAndSettle();

    expect(find.byKey(AppTestKeys.mediaSourcesEstimating), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(AppTestKeys.mediaSourcesSummary)).data,
      'Selected: 10 files • 5.0 MB',
    );
  });
}
