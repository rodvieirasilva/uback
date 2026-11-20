import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/backup_controller.dart';
import 'package:uback/core/backup/media_exporter.dart';
import 'package:uback/core/backup/media_source.dart';
import 'package:uback/core/backup/native_bridge.dart';
import 'package:uback/core/config/app_config.dart';
import 'package:uback/core/config/custom_folder_config.dart';
import 'package:uback/core/testing/test_keys.dart';
import 'package:uback/main.dart';

class _InteractiveFakeBridge implements NativeBackupBridge {
  final StreamController<BackupProgress> _progressCtrl =
      StreamController<BackupProgress>.broadcast();
  PermissionState permissions;
  ConnectionTestResult nextConnResult;
  FolderPickResult? nextFolderPickResult;
  bool openedAllFiles = false;
  bool pausedBackup = false;
  bool resumedBackup = false;
  bool stoppedBackup = false;
  BackupProgress latestPolledStatus = const BackupProgress();
  int getSourceStatsCalls = 0;
  List<BackupItem> discoveredItems;

  _InteractiveFakeBridge({
    this.permissions = const PermissionState(hasMedia: true, hasAllFiles: true),
    this.nextConnResult = const ConnectionTestResult(ok: true, message: 'Connected OK'),
    this.discoveredItems = const [],
  });

  void emitProgress(BackupProgress progress) => _progressCtrl.add(progress);

  @override
  Future<String> getDeviceName() async => 'Test Phone';
  @override
  Future<String> getAppVersion() async => '1.2.4';
  @override
  Future<PermissionState> checkPermissions() async => permissions;
  @override
  Future<PermissionState> requestMediaPermissions() async {
    permissions = PermissionState(
      hasMedia: true,
      hasAllFiles: permissions.hasAllFiles,
      hasNotifications: true,
    );
    return permissions;
  }

  @override
  Future<PermissionState> requestSnapshotPermissions(Set<String> snapshotSources) async =>
      permissions;
  @override
  Future<void> openAllFilesAccessSettings() async {
    openedAllFiles = true;
  }

  @override
  Future<FolderPickResult?> pickFolder() async => nextFolderPickResult;

  @override
  Future<List<BackupItem>> discoverMedia({
    required Set<String> enabledSourceIds,
    List<CustomFolderConfig> customFolders = const [],
    int? perSourceLimit,
    String? whatsappKey,
  }) async =>
      discoveredItems;

  @override
  Future<Map<String, MediaSourceStats>> getSourceStats({
    List<CustomFolderConfig> customFolders = const [],
    String? whatsappKey,
  }) async {
    getSourceStatsCalls++;
    return const {'camera.images': MediaSourceStats(fileCount: 2, totalBytes: 2048)};
  }

  @override
  Future<ConnectionTestResult> testConnection(AppSettings settings) async => nextConnResult;

  @override
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  }) async {
    _progressCtrl.add(
      BackupProgress(
        state: BackupRunState.running,
        stage: 'transferring',
        total: items.length,
        transferred: 0,
        remaining: items.length,
        currentFile: items.first.fileName,
        totalBytes: items.fold(0, (s, i) => s + i.sizeBytes),
        elapsedMs: 84000,
        etaMs: 126000,
      ),
    );
  }

  @override
  Future<void> pauseBackup() async {
    pausedBackup = true;
    _progressCtrl.add(
      const BackupProgress(
        state: BackupRunState.paused,
        stage: 'paused',
        total: 1,
        remaining: 1,
      ),
    );
  }

  @override
  Future<void> resumeBackup() async {
    resumedBackup = true;
    _progressCtrl.add(
      const BackupProgress(
        state: BackupRunState.running,
        stage: 'resuming',
        total: 1,
        remaining: 1,
      ),
    );
  }

  @override
  Future<void> stopBackup() async {
    stoppedBackup = true;
    _progressCtrl.add(const BackupProgress(state: BackupRunState.cancelled, stage: 'cancelled'));
  }

  @override
  Future<BackupProgress> getBackupStatus() async => latestPolledStatus;

  @override
  Stream<BackupProgress> progressStream() => _progressCtrl.stream;
}

AppSettingsRepository _repo({String host = '192.168.1.10', String share = 'safe'}) =>
    AppSettingsRepository(
      plainStore: InMemoryKeyValueStore(),
      secureStore: InMemoryKeyValueStore(),
      defaults: AppSettings(
        host: host,
        port: 445,
        share: share,
        basePath: 'local/phone',
        username: 'user',
        password: 'pw',
        domain: '',
        deviceFolderOverride: '',
      ),
    );

void main() {
  testWidgets('PermissionsAlertCard shows missing media and all-files buttons and invokes bridge',
      (tester) async {
    final bridge = _InteractiveFakeBridge(
      permissions: const PermissionState(hasMedia: false, hasAllFiles: false),
    );
    final controller = BackupController(settingsRepo: _repo(), bridge: bridge);
    await controller.init();
    await controller.setMode(BackupMode.crop);

    await tester.pumpWidget(UBackApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(AppTestKeys.grantMediaPerm), findsOneWidget);
    expect(find.byKey(AppTestKeys.grantAllFilesPerm), findsOneWidget);

    await tester.tap(find.byKey(AppTestKeys.grantMediaPerm));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.grantMediaPerm), findsNothing);

    await tester.tap(find.byKey(AppTestKeys.grantAllFilesPerm));
    await tester.pumpAndSettle();
    expect(bridge.openedAllFiles, isTrue);
  });

  testWidgets('ErrorLogSheet displays transfer errors and Stop button cancels active backup',
      (tester) async {
    final bridge = _InteractiveFakeBridge(
      discoveredItems: [
        BackupItem(
          id: '1',
          fileName: 'IMG_1.jpg',
          localPath: '/sdcard/DCIM/Camera/IMG_1.jpg',
          sourceId: 'camera.images',
          sourceFolder: 'camera',
          sizeBytes: 2048,
          createdAt: DateTime(2024, 1, 1),
          mimeType: 'image/jpeg',
        ),
      ],
    );
    final controller = BackupController(settingsRepo: _repo(), bridge: bridge);
    await controller.init();

    await tester.pumpWidget(UBackApp(controller: controller));
    await tester.pumpAndSettle();

    // Start backup -> enters running state (with Elapsed + ETA) -> Pause -> Resume -> Stop
    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.pauseBackup), findsOneWidget);
    expect(find.byKey(AppTestKeys.stopBackup), findsOneWidget);
    expect(find.text('Elapsed: 01:24'), findsOneWidget);
    expect(find.text('ETA: ~02:06'), findsOneWidget);

    await tester.ensureVisible(find.byKey(AppTestKeys.pauseBackup));
    await tester.tap(find.byKey(AppTestKeys.pauseBackup));
    await tester.pumpAndSettle();
    expect(bridge.pausedBackup, isTrue);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('ETA: Paused'), findsOneWidget);
    expect(find.byKey(AppTestKeys.resumeBackup), findsOneWidget);

    await tester.ensureVisible(find.byKey(AppTestKeys.resumeBackup));
    await tester.tap(find.byKey(AppTestKeys.resumeBackup));
    await tester.pumpAndSettle();
    expect(bridge.resumedBackup, isTrue);
    expect(find.byKey(AppTestKeys.pauseBackup), findsOneWidget);

    await tester.ensureVisible(find.byKey(AppTestKeys.stopBackup));
    await tester.tap(find.byKey(AppTestKeys.stopBackup));
    await tester.pumpAndSettle();
    expect(bridge.stoppedBackup, isTrue);

    // Emit failed transfer progress -> tap View Errors -> verify sheet content
    bridge.emitProgress(
      const BackupProgress(
        state: BackupRunState.completed,
        stage: 'completed',
        total: 1,
        transferred: 0,
        failed: 1,
        remaining: 0,
        errors: [BackupErrorEntry(fileName: 'IMG_1.jpg', message: 'SHA-256 read-back failed')],
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.errorLogBtn));
    await tester.tap(find.byKey(AppTestKeys.errorLogBtn));
    await tester.pumpAndSettle();

    expect(find.byKey(AppTestKeys.errorLogList), findsOneWidget);
    expect(find.text('IMG_1.jpg'), findsOneWidget);
    expect(find.text('SHA-256 read-back failed'), findsOneWidget);
  });

  testWidgets('SettingsScreen supports Test Connection banner, Save, Reset, and Custom Folder removal',
      (tester) async {
    final bridge = _InteractiveFakeBridge(
      nextConnResult: const ConnectionTestResult(ok: false, message: 'SMB auth rejected'),
    );
    final controller = BackupController(settingsRepo: _repo(), bridge: bridge);
    await controller.init();

    await tester.pumpWidget(UBackApp(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();

    // Test failed connection banner
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsTestConnection));
    await tester.tap(find.byKey(AppTestKeys.settingsTestConnection));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.connectionStatusBanner), findsOneWidget);
    expect(find.text('SMB auth rejected'), findsOneWidget);

    // Test succeeded connection banner
    bridge.nextConnResult = const ConnectionTestResult(ok: true, message: 'SMB connected OK');
    await tester.tap(find.byKey(AppTestKeys.settingsTestConnection));
    await tester.pumpAndSettle();
    expect(find.text('SMB connected OK'), findsOneWidget);

    // Browse folder error -> shows inline error message
    bridge.nextFolderPickResult = const FolderPickResult(
      error: 'Please select a specific subfolder instead of the root of internal storage.',
    );
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsBrowseCustomFolder));
    await tester.tap(find.byKey(AppTestKeys.settingsBrowseCustomFolder));
    await tester.pumpAndSettle();
    expect(find.textContaining('select a specific subfolder'), findsOneWidget);

    // Browse folder success -> auto-fills path & display name -> Add & remove
    bridge.nextFolderPickResult = const FolderPickResult(relativePath: 'GoPro/Hero12');
    await tester.tap(find.byKey(AppTestKeys.settingsBrowseCustomFolder));
    await tester.pumpAndSettle();
    expect(find.text('GoPro/Hero12'), findsOneWidget);
    expect(find.text('Hero12'), findsOneWidget);

    await tester.ensureVisible(find.byKey(AppTestKeys.settingsAddCustomFolder));
    await tester.tap(find.byKey(AppTestKeys.settingsAddCustomFolder));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.settingsRemoveCustomFolder('custom.gopro-hero12')), findsOneWidget);

    await tester.tap(find.byKey(AppTestKeys.settingsRemoveCustomFolder('custom.gopro-hero12')));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.settingsRemoveCustomFolder('custom.gopro-hero12')), findsNothing);

    // Edit host + WhatsApp 64-digit key -> Save -> reopen -> Reset to defaults
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsHost));
    await tester.enterText(find.byKey(AppTestKeys.settingsHost), '10.0.0.55');
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsWhatsappKey));
    await tester.enterText(
      find.byKey(AppTestKeys.settingsWhatsappKey),
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsSave));
    await tester.tap(find.byKey(AppTestKeys.settingsSave));
    await tester.pumpAndSettle();
    expect(controller.settings.host, '10.0.0.55');
    expect(
      controller.settings.whatsappKey,
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );

    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();
    // Wait for the "Settings saved" SnackBar to clear so it does not overlay bottom buttons in landscape.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsResetDefaults));
    await tester.tap(find.byKey(AppTestKeys.settingsResetDefaults));
    await tester.pumpAndSettle();
    expect(controller.settings.host, '192.168.1.10');
    expect(controller.settings.whatsappKey, '');
  });

  test('BackupController guards unconfigured destination, empty sources, crop perm, MB limit, and empty discovery',
      () async {
    final unconfigured = BackupController(
      settingsRepo: _repo(host: '', share: ''),
      bridge: _InteractiveFakeBridge(),
    );
    await unconfigured.init();
    await unconfigured.startBackup();
    expect(unconfigured.statusMessage, contains('Configure SMB NAS'));

    final noSources = BackupController(
      settingsRepo: _repo(),
      bridge: _InteractiveFakeBridge(),
    );
    await noSources.init();
    await noSources.saveSettings(noSources.settings.copyWith(enabledSourceIds: const {}));
    await noSources.startBackup();
    expect(noSources.statusMessage, contains('Enable at least one'));

    final noAllFiles = BackupController(
      settingsRepo: _repo(),
      bridge: _InteractiveFakeBridge(
        permissions: const PermissionState(hasMedia: true, hasAllFiles: false),
      ),
    );
    await noAllFiles.init();
    await noAllFiles.setMode(BackupMode.crop);
    await noAllFiles.startBackup();
    expect(noAllFiles.statusMessage, contains('All files access'));

    final emptyDiscovery = BackupController(
      settingsRepo: _repo(),
      bridge: _InteractiveFakeBridge(discoveredItems: const []),
    );
    await emptyDiscovery.init();
    await emptyDiscovery.setLimitType(BackupLimitType.megabytes);
    await emptyDiscovery.setLimitValue(50);
    expect(emptyDiscovery.currentLimit?.maxBytes, 50 * 1024 * 1024);
    await emptyDiscovery.startBackup();
    expect(emptyDiscovery.statusMessage, contains('No files found'));

    // Verify onAppResumed() syncs active backup progress from native service after screen lock / app switch
    // without triggering redundant MediaStore scans while active, then refreshes stats once completed.
    final resumeBridge = _InteractiveFakeBridge();
    final resumeCtrl = BackupController(settingsRepo: _repo(), bridge: resumeBridge);
    await resumeCtrl.init();
    final scansAfterInit = resumeBridge.getSourceStatsCalls;

    resumeBridge.latestPolledStatus = const BackupProgress(
      state: BackupRunState.running,
      stage: 'uploading',
      total: 10,
      transferred: 6,
      remaining: 4,
      elapsedMs: 45000,
      etaMs: 30000,
      currentFile: 'VID_2025.mp4',
    );
    await resumeCtrl.onAppResumed();
    expect(resumeCtrl.progress.state, BackupRunState.running);
    expect(resumeCtrl.progress.transferred, 6);
    expect(resumeCtrl.progress.currentFile, 'VID_2025.mp4');
    // Must NOT re-scan MediaStore while backup is active
    expect(resumeBridge.getSourceStatsCalls, scansAfterInit);

    resumeBridge.latestPolledStatus = const BackupProgress(
      state: BackupRunState.completed,
      stage: 'completed',
      total: 10,
      transferred: 10,
      remaining: 0,
    );
    await resumeCtrl.onAppResumed();
    expect(resumeCtrl.progress.state, BackupRunState.completed);
    expect(resumeBridge.getSourceStatsCalls, greaterThan(scansAfterInit));
    resumeCtrl.dispose();
  });
}
