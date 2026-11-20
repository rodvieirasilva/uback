import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../config/custom_folder_config.dart';
import 'backup_destination.dart';
import 'image_video_media_exporter.dart';
import 'media_exporter.dart';
import 'media_source.dart';
import 'native_bridge.dart';

class BackupController extends ChangeNotifier {
  final AppSettingsRepository _settingsRepo;
  final NativeBackupBridge _bridge;
  final List<MediaSource>? _customInjectedSources;
  late final DestinationRegistry _destinations;
  late List<MediaSource> _mediaSources;
  late final ImageVideoMediaExporter _exporter;

  StreamSubscription<BackupProgress>? _progressSub;

  AppSettings _settings = CompileTimeDefaults.toSettings();
  String _detectedDeviceName = 'android';
  String _appVersion = CompileTimeDefaults.appVersion;
  PermissionState _permissions = const PermissionState();
  Map<String, MediaSourceStats> _sourceStats = const {};
  bool _estimatingStats = false;
  bool _statsRefreshQueued = false;
  bool _hasEstimatedStats = false;
  BackupProgress _progress = const BackupProgress();
  ConnectionTestResult? _connectionResult;
  bool _testingConnection = false;
  bool _initialized = false;
  String? _statusMessage;

  BackupController({
    required this._settingsRepo,
    required this._bridge,
    DestinationRegistry? destinations,
    List<MediaSource>? mediaSources,
  }) : _customInjectedSources = mediaSources {
    _destinations = destinations ?? DestinationRegistry.defaults(_bridge);
    _mediaSources = List.unmodifiable(
      mediaSources ?? buildMediaSources(_bridge, customFolders: _settings.customFolders),
    );
    _exporter = ImageVideoMediaExporter(
      bridge: _bridge,
      settingsProvider: () => _settings,
      deviceFolderProvider: () => resolvedDeviceFolder,
    );
  }

  AppSettings get settings => _settings;
  List<BackupDestination> get availableDestinations => _destinations.all;
  BackupDestination get activeDestination => _destinations.resolve(_settings.destinationType);
  List<MediaSource> get mediaSources => _mediaSources;
  String get detectedDeviceName => _detectedDeviceName;
  String get appVersion => _appVersion;
  String get appVersionLabel => CompileTimeDefaults.formatVersionLabel(_appVersion);
  String get resolvedDeviceFolder => _settings.resolvedDeviceFolder(_detectedDeviceName);
  PermissionState get permissions => _permissions;
  Map<String, MediaSourceStats> get sourceStats => _sourceStats;
  bool get estimatingStats => _estimatingStats;
  bool get hasEstimatedStats => _hasEstimatedStats;
  BackupMode get mode => _settings.lastMode;
  BackupLimitType get limitType => _settings.lastLimitType;
  int get limitValue => _settings.lastLimitValue;
  String get lastExporterId => _settings.lastExporterId;
  bool get mediaSourcesExpanded => _settings.mediaSourcesExpanded;
  Set<String> get expandedSourceGroupIds => _settings.expandedSourceGroupIds;
  BackupProgress get progress => _progress;
  ConnectionTestResult? get connectionResult => _connectionResult;
  bool get testingConnection => _testingConnection;
  bool get initialized => _initialized;
  String? get statusMessage => _statusMessage;
  MediaExporter get exporter => _exporter;

  void _rebuildMediaSources() {
    if (_customInjectedSources != null) return;
    _mediaSources = List.unmodifiable(
      buildMediaSources(_bridge, customFolders: _settings.customFolders),
    );
  }

  Set<String> get _allRegisteredLeafIds {
    final ids = <String>{};
    for (final src in _mediaSources) {
      ids.addAll(src.leafIds);
    }
    return ids;
  }

  int get selectedFileCount {
    var total = 0;
    for (final leafId in _allRegisteredLeafIds) {
      if (_settings.isSourceEnabled(leafId)) {
        total += _sourceStats[leafId]?.fileCount ?? 0;
      }
    }
    return total;
  }

  int get selectedTotalBytes {
    var total = 0;
    for (final leafId in _allRegisteredLeafIds) {
      if (_settings.isSourceEnabled(leafId)) {
        total += _sourceStats[leafId]?.totalBytes ?? 0;
      }
    }
    return total;
  }

  BackupLimit? get currentLimit {
    return switch (limitType) {
      BackupLimitType.all => null,
      BackupLimitType.files => BackupLimit(maxFiles: limitValue > 0 ? limitValue : 1),
      BackupLimitType.megabytes =>
        BackupLimit(maxBytes: (limitValue > 0 ? limitValue : 1) * 1024 * 1024),
    };
  }

  Future<void> init() async {
    _settings = await _settingsRepo.load();
    _rebuildMediaSources();

    try {
      _detectedDeviceName = await _bridge.getDeviceName();
    } catch (_) {
      _detectedDeviceName = 'android';
    }
    try {
      _appVersion = await _bridge.getAppVersion();
    } catch (_) {
      _appVersion = CompileTimeDefaults.appVersion;
    }
    try {
      _permissions = await _bridge.checkPermissions();
    } catch (_) {}
    try {
      _progress = await _bridge.getBackupStatus();
    } catch (_) {}

    _progressSub?.cancel();
    _progressSub = _bridge.progressStream().listen((event) {
      _progress = event;
      notifyListeners();
      if (event.state == BackupRunState.completed ||
          event.state == BackupRunState.cancelled ||
          event.state == BackupRunState.error) {
        refreshSourceStats();
      }
    });

    _initialized = true;
    notifyListeners();

    if (_permissions.hasMedia) {
      unawaited(refreshSourceStats());
    }
  }

  Future<void> _persistSession(AppSettings updated) async {
    _settings = updated;
    notifyListeners();
    await _settingsRepo.save(updated);
  }

  Future<void> setMode(BackupMode nextMode) async {
    if (_progress.isActive) return;
    _statusMessage = null;
    await _persistSession(_settings.copyWith(lastMode: nextMode));
  }

  Future<void> setLimitType(BackupLimitType type) async {
    if (_progress.isActive) return;
    var nextVal = _settings.lastLimitValue;
    if (type == BackupLimitType.files && nextVal <= 0) {
      nextVal = 100;
    } else if (type == BackupLimitType.megabytes && nextVal <= 0) {
      nextVal = 500;
    }
    await _persistSession(
      _settings.copyWith(lastLimitType: type, lastLimitValue: nextVal),
    );
  }

  Future<void> setLimitValue(int value) async {
    if (_progress.isActive || value <= 0) return;
    await _persistSession(_settings.copyWith(lastLimitValue: value));
  }

  Future<void> setMediaSourcesExpanded(bool expanded) async {
    await _persistSession(_settings.copyWith(mediaSourcesExpanded: expanded));
  }

  Future<void> toggleSourceGroupExpanded(String groupId) async {
    final next = Set<String>.of(_settings.expandedSourceGroupIds);
    if (!next.remove(groupId)) {
      next.add(groupId);
    }
    await _persistSession(_settings.copyWith(expandedSourceGroupIds: next));
  }

  /// Toggles either a single leaf [MediaSource] or an entire hierarchical group
  /// and persists the selection immediately for the next session.
  Future<void> toggleSourceNode(MediaSource source, bool enabled) async {
    if (_progress.isActive) return;
    final next = Set<String>.of(_settings.enabledSourceIds);
    if (enabled) {
      next.addAll(source.leafIds);
    } else {
      next.removeAll(source.leafIds);
    }
    _statusMessage = null;
    await _persistSession(_settings.copyWith(enabledSourceIds: next));

    // If user enabled any snapshot source, proactively request its runtime permission so stats update.
    if (enabled) {
      final newlyEnabledSnapshots = source.leafIds.intersection(snapshotSourceIds);
      if (newlyEnabledSnapshots.isNotEmpty) {
        await _bridge.requestSnapshotPermissions(newlyEnabledSnapshots);
        unawaited(refreshSourceStats());
      }
    }
  }

  Future<void> addCustomFolder({
    required String relativePath,
    String? displayName,
  }) async {
    final cleanPath = relativePath.trim();
    if (cleanPath.isEmpty) return;
    final created = CustomFolderConfig.create(
      relativePath: cleanPath,
      displayName: displayName,
    );
    final updatedFolders = [
      ..._settings.customFolders.where((f) => f.id != created.id),
      created,
    ];
    final nextEnabled = Set<String>.of(_settings.enabledSourceIds)..add(created.id);
    _settings = _settings.copyWith(
      customFolders: updatedFolders,
      enabledSourceIds: nextEnabled,
    );
    _rebuildMediaSources();
    notifyListeners();
    await _settingsRepo.save(_settings);
    unawaited(refreshSourceStats());
  }

  Future<void> removeCustomFolder(String folderId) async {
    final updatedFolders = _settings.customFolders.where((f) => f.id != folderId).toList();
    final nextEnabled = Set<String>.of(_settings.enabledSourceIds)..remove(folderId);
    _settings = _settings.copyWith(
      customFolders: updatedFolders,
      enabledSourceIds: nextEnabled,
    );
    _rebuildMediaSources();
    notifyListeners();
    await _settingsRepo.save(_settings);
    unawaited(refreshSourceStats());
  }

  Future<void> refreshPermissions() async {
    _permissions = await _bridge.checkPermissions();
    notifyListeners();
    if (_permissions.hasMedia) {
      unawaited(refreshSourceStats());
    }
  }

  Future<void> requestMediaPermissions() async {
    _permissions = await _bridge.requestMediaPermissions();
    notifyListeners();
    if (_permissions.hasMedia) {
      unawaited(refreshSourceStats());
    }
  }

  Future<void> openAllFilesAccessSettings() async {
    await _bridge.openAllFilesAccessSettings();
  }

  Future<FolderPickResult?> pickCustomFolder() => _bridge.pickFolder();

  Future<void> refreshSourceStats() async {
    if (_estimatingStats) {
      _statsRefreshQueued = true;
      return;
    }
    _estimatingStats = true;
    notifyListeners();
    try {
      _sourceStats = await _bridge.getSourceStats(customFolders: _settings.customFolders);
      _hasEstimatedStats = true;
    } catch (_) {
      // Keep previous estimate if query fails transiently.
    } finally {
      _estimatingStats = false;
      notifyListeners();
      if (_statsRefreshQueued) {
        _statsRefreshQueued = false;
        unawaited(refreshSourceStats());
      }
    }
  }

  Future<void> saveSettings(AppSettings updated) async {
    _settings = updated;
    _rebuildMediaSources();
    await _settingsRepo.save(updated);
    _connectionResult = null;
    notifyListeners();
  }

  Future<AppSettings> resetSettingsToDefaults() async {
    _settings = await _settingsRepo.resetToDefaults();
    _rebuildMediaSources();
    _connectionResult = null;
    notifyListeners();
    return _settings;
  }

  Future<ConnectionTestResult> testConnection([AppSettings? overrideSettings]) async {
    final target = overrideSettings ?? _settings;
    final dest = _destinations.resolve(target.destinationType);
    if (!dest.isConfigured(target)) {
      final res = ConnectionTestResult(
        ok: false,
        message: 'Configure ${dest.displayName} in Settings first.',
      );
      _connectionResult = res;
      notifyListeners();
      return res;
    }

    _testingConnection = true;
    _connectionResult = null;
    notifyListeners();

    try {
      final res = await dest.testConnection(target);
      _connectionResult = res;
      return res;
    } catch (e) {
      final res = ConnectionTestResult(ok: false, message: e.toString());
      _connectionResult = res;
      return res;
    } finally {
      _testingConnection = false;
      notifyListeners();
    }
  }

  Future<void> startBackup() async {
    if (_progress.isActive) return;
    _statusMessage = null;

    final dest = activeDestination;
    if (!dest.isConfigured(_settings)) {
      _statusMessage = 'Configure ${dest.displayName} in Settings before backing up.';
      notifyListeners();
      return;
    }

    if (_settings.enabledSourceIds.isEmpty) {
      _statusMessage = 'Enable at least one media source before starting backup.';
      notifyListeners();
      return;
    }

    _permissions = await _bridge.checkPermissions();
    if (!_permissions.hasMedia) {
      _permissions = await _bridge.requestMediaPermissions();
      if (!_permissions.hasMedia) {
        _statusMessage = 'Media permission is required to scan your selected sources.';
        notifyListeners();
        return;
      }
    }

    final activeSnapshots = _settings.enabledSourceIds.intersection(snapshotSourceIds);
    if (activeSnapshots.isNotEmpty) {
      await _bridge.requestSnapshotPermissions(activeSnapshots);
    }

    if (mode == BackupMode.crop && !_permissions.hasAllFiles) {
      _statusMessage =
          'Crop Mode requires "All files access" permission so verified files can be deleted automatically.';
      notifyListeners();
      return;
    }

    // Persist last used exporter/config right as the session starts.
    await _persistSession(
      _settings.copyWith(lastExporterId: _exporter.id),
    );

    _progress = const BackupProgress(
      state: BackupRunState.scanning,
      stage: 'scanning',
    );
    notifyListeners();

    try {
      final planned = await _exporter.discoverItems(limit: currentLimit);

      if (planned.isEmpty) {
        _progress = const BackupProgress(
          state: BackupRunState.completed,
          stage: 'completed',
          total: 0,
          transferred: 0,
          skipped: 0,
          failed: 0,
          remaining: 0,
          bytesTransferred: 0,
          totalBytes: 0,
        );
        _statusMessage = 'No files found in the selected media sources.';
        notifyListeners();
        return;
      }

      final totalBytes = planned.fold<int>(0, (sum, i) => sum + i.sizeBytes);
      _progress = BackupProgress(
        state: BackupRunState.running,
        stage: 'connecting',
        total: planned.length,
        remaining: planned.length,
        totalBytes: totalBytes,
      );
      notifyListeners();

      await dest.startBackup(
        settings: _settings,
        mode: mode,
        deviceFolder: resolvedDeviceFolder,
        items: planned,
      );
    } catch (e) {
      _progress = BackupProgress(
        state: BackupRunState.error,
        stage: 'error',
        errors: [BackupErrorEntry(fileName: 'Backup', message: e.toString())],
      );
      notifyListeners();
    }
  }

  Future<void> pauseBackup() async {
    await activeDestination.pauseBackup();
  }

  Future<void> resumeBackup() async {
    await activeDestination.resumeBackup();
  }

  Future<void> stopBackup() async {
    await activeDestination.stopBackup();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }
}
