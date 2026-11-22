import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

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

class _AdaptiveFakeBridge implements NativeBackupBridge {
  @override
  Future<String> getDeviceName() async => 'Galaxy Z Fold';
  @override
  Future<String> getAppVersion() async => '1.2.9';
  @override
  Future<PermissionState> checkPermissions() async =>
      const PermissionState(hasMedia: true, hasAllFiles: true, hasNotifications: true);
  @override
  Future<PermissionState> requestMediaPermissions() => checkPermissions();
  @override
  Future<PermissionState> requestSnapshotPermissions(Set<String> snapshotSources) =>
      checkPermissions();
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
  }) async =>
      const [];
  @override
  Future<Map<String, MediaSourceStats>> getSourceStats({
    List<CustomFolderConfig> customFolders = const [],
    String? whatsappKey,
  }) async =>
      const {
        'camera.images': MediaSourceStats(fileCount: 25, totalBytes: 50 * 1024 * 1024),
        'recordings': MediaSourceStats(fileCount: 3, totalBytes: 2 * 1024 * 1024),
      };
  @override
  Future<ConnectionTestResult> testConnection(AppSettings settings) async =>
      const ConnectionTestResult(ok: true, message: 'OK');
  @override
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  }) async {}
  @override
  Future<void> pauseBackup() async {}
  @override
  Future<void> resumeBackup() async {}
  @override
  Future<void> stopBackup() async {}
  @override
  Future<BackupProgress> getBackupStatus() async => const BackupProgress();
  @override
  Stream<BackupProgress> progressStream() => const Stream.empty();
}

Future<BackupController> _makeController() async {
  final controller = BackupController(
    settingsRepo: AppSettingsRepository(
      plainStore: InMemoryKeyValueStore(),
      secureStore: InMemoryKeyValueStore(),
      defaults: const AppSettings(
        host: '192.168.1.100',
        port: 445,
        share: 'safe',
        basePath: 'local/phone',
        username: 'user',
        password: 'pw',
        domain: '',
        deviceFolderOverride: '',
      ),
    ),
    bridge: _AdaptiveFakeBridge(),
  );
  await controller.init();
  return controller;
}

void main() {
  testWidgets('Landscape phone (840x390) renders side-by-side two-pane layout with zero overflow',
      (tester) async {
    tester.view.physicalSize = const Size(840, 390);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = await _makeController();
    await tester.pumpWidget(UBackApp(controller: controller));
    await tester.pumpAndSettle();

    final modeRect = tester.getRect(find.byKey(AppTestKeys.modeCopy));
    final sourcesRect = tester.getRect(find.byKey(AppTestKeys.sourceToggle('camera')));
    expect(sourcesRect.left, greaterThan(modeRect.right));
    expect(tester.takeException(), isNull);

    // Settings screen in landscape also renders two-pane cleanly
    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();
    final hostRect = tester.getRect(find.byKey(AppTestKeys.settingsHost));
    final browseRect = tester.getRect(find.byKey(AppTestKeys.settingsBrowseCustomFolder));
    expect(browseRect.left, greaterThan(hostRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Foldable dual-screen with physical vertical hinge avoids hinge completely',
      (tester) async {
    const screenSize = Size(884, 1104);
    tester.view.physicalSize = screenSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const verticalHinge = DisplayFeature(
      bounds: Rect.fromLTWH(430, 0, 24, 1104),
      type: DisplayFeatureType.hinge,
      state: DisplayFeatureState.postureFlat,
    );

    final controller = await _makeController();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: screenSize,
          displayFeatures: [verticalHinge],
        ),
        child: UBackApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Left pane controls stay strictly left of hinge (x <= 430); right pane sources stay right of hinge (x >= 454)
    final startRect = tester.getRect(find.byKey(AppTestKeys.startBackup));
    final sourcesSummaryRect = tester.getRect(find.byKey(AppTestKeys.mediaSourcesSummary));
    expect(startRect.right, lessThanOrEqualTo(430.0));
    expect(sourcesSummaryRect.left, greaterThanOrEqualTo(454.0));
    expect(tester.takeException(), isNull);

    // Settings screen also places SMB fields left of hinge and Custom Folders right of hinge
    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();
    final shareRect = tester.getRect(find.byKey(AppTestKeys.settingsShare));
    final browseRect = tester.getRect(find.byKey(AppTestKeys.settingsBrowseCustomFolder));
    expect(shareRect.right, lessThanOrEqualTo(430.0));
    expect(browseRect.left, greaterThanOrEqualTo(454.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Narrow foldable cover screen (280x720, 1.2x text scale) renders single-column with zero overflow',
      (tester) async {
    tester.view.physicalSize = const Size(280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = await _makeController();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
        child: UBackApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    final modeRect = tester.getRect(find.byKey(AppTestKeys.modeCopy));
    final sourcesRect = tester.getRect(find.byKey(AppTestKeys.mediaSourcesSummary));
    expect(sourcesRect.top, greaterThan(modeRect.bottom));
    expect(tester.takeException(), isNull);
  });
}
