import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uback/core/backup/backup_controller.dart';
import 'package:uback/core/backup/media_exporter.dart';
import 'package:uback/core/backup/media_source.dart';
import 'package:uback/core/backup/native_bridge.dart';
import 'package:uback/core/config/app_config.dart';
import 'package:uback/core/config/custom_folder_config.dart';
import 'package:uback/core/testing/test_keys.dart';
import 'package:uback/main.dart';

class _FakeBridge implements NativeBackupBridge {
  final StreamController<BackupProgress> _progressCtrl =
      StreamController<BackupProgress>.broadcast();
  final Completer<Map<String, MediaSourceStats>>? delayedStats;
  final Map<String, MediaSourceStats>? customStats;

  List<BackupItem> lastStartedItems = [];
  BackupMode? lastStartedMode;
  int? lastPerSourceLimit;
  List<CustomFolderConfig> lastCustomFolders = [];
  bool requestedSnapshotPermissions = false;

  _FakeBridge({this.delayedStats, this.customStats});

  @override
  Future<String> getDeviceName() async => 'Pixel Phone';

  @override
  Future<String> getAppVersion() async => '1.2.5';

  @override
  Future<PermissionState> checkPermissions() async =>
      const PermissionState(hasMedia: true, hasAllFiles: true, hasNotifications: true);

  @override
  Future<PermissionState> requestMediaPermissions() => checkPermissions();

  @override
  Future<PermissionState> requestSnapshotPermissions(Set<String> snapshotSources) async {
    requestedSnapshotPermissions = true;
    return checkPermissions();
  }

  @override
  Future<void> openAllFilesAccessSettings() async {}

  @override
  Future<FolderPickResult?> pickFolder() async => null;

  @override
  Future<List<BackupItem>> discoverMedia({
    required Set<String> enabledSourceIds,
    List<CustomFolderConfig> customFolders = const [],
    int? perSourceLimit,
    String? whatsappKey,
  }) async {
    lastPerSourceLimit = perSourceLimit;
    lastCustomFolders = customFolders;
    return [
      if (enabledSourceIds.contains('camera.images'))
        BackupItem(
          id: 'c_img',
          fileName: 'IMG_2023.jpg',
          localPath: '/sdcard/DCIM/Camera/IMG_2023.jpg',
          sourceId: 'camera.images',
          sourceFolder: 'camera',
          sizeBytes: 1024,
          createdAt: DateTime(2023, 1, 1),
          mimeType: 'image/jpeg',
        ),
      if (enabledSourceIds.contains('camera.videos'))
        BackupItem(
          id: 'c_vid',
          fileName: 'VID_2024.mp4',
          localPath: '/sdcard/DCIM/Camera/VID_2024.mp4',
          sourceId: 'camera.videos',
          sourceFolder: 'camera',
          sizeBytes: 4096,
          createdAt: DateTime(2024, 1, 1),
          mimeType: 'video/mp4',
        ),
      if (enabledSourceIds.contains('whatsapp.sent.audios'))
        BackupItem(
          id: 'wa_sa',
          fileName: 'AUD-2022.opus',
          localPath:
              '/sdcard/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio/Sent/AUD-2022.opus',
          sourceId: 'whatsapp.sent.audios',
          sourceFolder: 'whatsapp/sent/audios',
          sizeBytes: 2048,
          createdAt: DateTime(2022, 6, 1),
          mimeType: 'audio/opus',
        ),
      if (enabledSourceIds.contains('recordings'))
        BackupItem(
          id: 'rec_1',
          fileName: 'Voice_001.m4a',
          localPath: '/sdcard/Recordings/Voice_001.m4a',
          sourceId: 'recordings',
          sourceFolder: 'recordings',
          sizeBytes: 3072,
          createdAt: DateTime(2023, 6, 1),
          mimeType: 'audio/mp4',
        ),
    ];
  }

  @override
  Future<Map<String, MediaSourceStats>> getSourceStats({
    List<CustomFolderConfig> customFolders = const [],
    String? whatsappKey,
  }) async {
    lastCustomFolders = customFolders;
    if (delayedStats != null) return delayedStats!.future;
    final stats = <String, MediaSourceStats>{
      ...(customStats ??
          const {
            'camera.images': MediaSourceStats(fileCount: 1, totalBytes: 1024),
            'camera.videos': MediaSourceStats(fileCount: 1, totalBytes: 4096),
            'whatsapp.sent.audios': MediaSourceStats(fileCount: 1, totalBytes: 2048),
            'whatsapp.deltas': MediaSourceStats(statusNote: 'Set 64-digit key in Settings'),
            'recordings': MediaSourceStats(fileCount: 1, totalBytes: 3072),
            'snapshots.contacts': MediaSourceStats(permissionRequired: true),
            'snapshots.sms': MediaSourceStats(permissionRequired: true),
            'snapshots.call_logs': MediaSourceStats(permissionRequired: true),
          }),
    };
    for (final folder in customFolders) {
      stats.putIfAbsent(
        folder.id,
        () => const MediaSourceStats(fileCount: 2, totalBytes: 8192),
      );
    }
    return stats;
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
  Future<void> pauseBackup() async {}

  @override
  Future<void> resumeBackup() async {}

  @override
  Future<void> stopBackup() async {}

  @override
  Future<BackupProgress> getBackupStatus() async => const BackupProgress();

  @override
  Stream<BackupProgress> progressStream() => _progressCtrl.stream;
}

AppSettingsRepository _makeRepo({
  InMemoryKeyValueStore? plainStore,
  InMemoryKeyValueStore? secureStore,
}) =>
    AppSettingsRepository(
      plainStore: plainStore ?? InMemoryKeyValueStore(),
      secureStore: secureStore ?? InMemoryKeyValueStore(),
      defaults: const AppSettings(
        host: '192.168.1.10',
        port: 445,
        share: 'safe',
        basePath: 'local/phone',
        username: 'user',
        password: 'pw',
        domain: '',
        deviceFolderOverride: '',
        enabledSourceIds: defaultEnabledMediaSourceIds,
      ),
    );

void main() {
  testWidgets(
      'Home removes destination banner, supports collapsible hierarchical sources & sub-items, and orders globally oldest-first',
      (tester) async {
    final bridge = _FakeBridge();
    final controller = BackupController(settingsRepo: _makeRepo(), bridge: bridge);
    await controller.init();

    await tester.pumpWidget(UBackApp(controller: controller));
    await tester.pumpAndSettle();

    // Destination oldest-first banner removed; logo + version present; zero phase jargon; zero file previews
    expect(find.textContaining('DESTINATION (OLDEST FIRST'), findsNothing);
    expect(find.byKey(AppTestKeys.appLogo), findsOneWidget);
    expect(find.text('UBack v1.2.5'), findsOneWidget);
    expect(find.textContaining('Phase'), findsNothing);
    expect(find.textContaining('PHASE'), findsNothing);
    final fileImages = find.byWidgetPredicate((w) => w is Image && w.image is FileImage);
    expect(fileImages, findsNothing);

    // Total across Camera (1+1) + WhatsApp Sent Audio (1) + Recordings (1) = 4 files • 10.0 KB
    expect(
      tester.widget<Text>(find.byKey(AppTestKeys.mediaSourcesSummary)).data,
      'Selected: 4 files • 10.0 KB',
    );

    // Expand Camera -> toggle Videos OFF -> immediate live impact (3 files • 6.0 KB) + tri-state Camera checkbox
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceExpand('camera')));
    await tester.tap(find.byKey(AppTestKeys.sourceExpand('camera')));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceToggle('camera.images')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('camera.videos')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('camera.raw')), findsOneWidget);

    await tester.tap(find.byKey(AppTestKeys.sourceToggle('camera.videos')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(AppTestKeys.mediaSourcesSummary)).data,
      'Selected: 3 files • 6.0 KB',
    );
    expect(tester.widget<Checkbox>(find.byKey(AppTestKeys.sourceToggle('camera'))).value, isNull);

    // Expand WhatsApp -> expand Sent -> verify Audios & Documents sub-items exist
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceExpand('whatsapp')));
    await tester.tap(find.byKey(AppTestKeys.sourceExpand('whatsapp')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceExpand('whatsapp.sent')));
    await tester.tap(find.byKey(AppTestKeys.sourceExpand('whatsapp.sent')));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceToggle('whatsapp.sent.audios')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('whatsapp.sent.documents')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(AppTestKeys.sourceStats('whatsapp.deltas'))).data,
      'Set 64-digit key in Settings',
    );

    // Device Snapshots shows clear permission indicator before permissions are granted
    expect(
      tester.widget<Text>(find.byKey(AppTestKeys.sourceStats('snapshots'))).data,
      'Permission required • Toggle to grant',
    );

    // Enabling Device Snapshots triggers snapshot permission request
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceToggle('snapshots')));
    await tester.tap(find.byKey(AppTestKeys.sourceToggle('snapshots')));
    await tester.pumpAndSettle();
    expect(bridge.requestedSnapshotPermissions, isTrue);

    // Collapse the entire Media Sources list cleanly
    await tester.ensureVisible(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.tap(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsNothing);

    // Select Limit: Oldest 2 files -> global oldest across WhatsApp Sent Audio (2022) & Camera Image (2023)
    await tester.ensureVisible(find.byKey(AppTestKeys.limitFiles));
    await tester.tap(find.byKey(AppTestKeys.limitFiles));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppTestKeys.limitValueInput), '2');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await tester.pumpAndSettle();

    expect(bridge.lastPerSourceLimit, 2);
    expect(bridge.lastStartedItems.map((e) => e.id).toList(), ['wa_sa', 'c_img']);

    // Open Settings -> verify Destination Type & Custom Folders section exist
    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.settingsDestinationType), findsOneWidget);
    expect(find.text('SMB NAS'), findsOneWidget);

    // Add a custom folder in Settings and verify it appears on HomeScreen
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsCustomFolderPath));
    await tester.enterText(find.byKey(AppTestKeys.settingsCustomFolderPath), 'DJI/Media');
    await tester.enterText(find.byKey(AppTestKeys.settingsCustomFolderName), 'Drone');
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsAddCustomFolder));
    await tester.tap(find.byKey(AppTestKeys.settingsAddCustomFolder));
    await tester.pumpAndSettle();

    expect(find.byKey(AppTestKeys.settingsRemoveCustomFolder('custom.dji-media')), findsOneWidget);

    // Navigate back to HomeScreen, expand Media Sources, and verify Custom Folders shows up
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.tap(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceToggle('custom')), findsOneWidget);
  });

  testWidgets('Full session state (mode, limit, toggles, collapse state, custom folders) restores on app restart',
      (tester) async {
    final plain = InMemoryKeyValueStore();
    final secure = InMemoryKeyValueStore();

    // Session 1: configure Crop mode, Oldest 7 files, toggle off Recordings, enable Downloads, expand Camera, add custom folder
    final controller1 = BackupController(
      settingsRepo: _makeRepo(plainStore: plain, secureStore: secure),
      bridge: _FakeBridge(),
    );
    await controller1.init();
    await controller1.setMode(BackupMode.crop);
    await controller1.setLimitType(BackupLimitType.files);
    await controller1.setLimitValue(7);
    await controller1.toggleSourceGroupExpanded('camera');
    await controller1.toggleSourceNode(
      controller1.mediaSources.firstWhere((s) => s.id == 'recordings'),
      false,
    );
    await controller1.toggleSourceNode(
      controller1.mediaSources.firstWhere((s) => s.id == 'downloads'),
      true,
    );
    await controller1.addCustomFolder(relativePath: 'Obsidian', displayName: 'Notes Vault');
    await controller1.setMediaSourcesExpanded(false);

    // Session 2: brand new controller reading from the same persistent storage
    final controller2 = BackupController(
      settingsRepo: _makeRepo(plainStore: plain, secureStore: secure),
      bridge: _FakeBridge(),
    );
    await controller2.init();

    expect(controller2.mode, BackupMode.crop);
    expect(controller2.limitType, BackupLimitType.files);
    expect(controller2.limitValue, 7);
    expect(controller2.mediaSourcesExpanded, isFalse);
    expect(controller2.expandedSourceGroupIds, contains('camera'));
    expect(controller2.settings.isSourceEnabled('recordings'), isFalse);
    expect(controller2.settings.isSourceEnabled('downloads.media'), isTrue);
    expect(controller2.settings.customFolders.map((f) => f.id), ['custom.obsidian']);
    expect(controller2.settings.isSourceEnabled('custom.obsidian'), isTrue);

    await tester.pumpWidget(UBackApp(controller: controller2));
    await tester.pumpAndSettle();

    expect(find.text('7'), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsNothing);
  });

  testWidgets('Narrow screen (320px, 1.3x text scale) renders with zero right overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final bridge = _FakeBridge(
      customStats: const {
        'camera.images': MediaSourceStats(fileCount: 99999, totalBytes: 128 * 1024 * 1024 * 1024),
        'recordings': MediaSourceStats(fileCount: 1234, totalBytes: 2 * 1024 * 1024 * 1024),
      },
    );
    final controller = BackupController(settingsRepo: _makeRepo(), bridge: bridge);
    await controller.init();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: UBackApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Shows non-blocking estimating indicator while slow MediaStore scan runs',
      (tester) async {
    final completer = Completer<Map<String, MediaSourceStats>>();
    final bridge = _FakeBridge(delayedStats: completer);
    final controller = BackupController(settingsRepo: _makeRepo(), bridge: bridge);
    await controller.init();

    await tester.pumpWidget(UBackApp(controller: controller));
    await tester.pump();

    expect(find.byKey(AppTestKeys.mediaSourcesEstimating), findsOneWidget);
    expect(find.text('Estimating size...'), findsOneWidget);

    // User can toggle Camera OFF while estimation is still running
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceToggle('camera')));
    await tester.tap(find.byKey(AppTestKeys.sourceToggle('camera')));
    await tester.pump();
    expect(controller.settings.isSourceEnabled('camera.images'), isFalse);
    expect(controller.settings.isSourceEnabled('camera.videos'), isFalse);
    expect(controller.settings.isSourceEnabled('camera.raw'), isFalse);

    completer.complete(const {
      'camera.images': MediaSourceStats(fileCount: 500, totalBytes: 500 * 1024 * 1024),
      'recordings': MediaSourceStats(fileCount: 10, totalBytes: 5 * 1024 * 1024),
    });
    await tester.pumpAndSettle();

    expect(find.byKey(AppTestKeys.mediaSourcesEstimating), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(AppTestKeys.mediaSourcesSummary)).data,
      'Selected: 10 files • 5.0 MB',
    );
  });
}
