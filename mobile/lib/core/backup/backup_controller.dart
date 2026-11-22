import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../config/custom_folder_config.dart';
import '../config/smb_destination_config.dart';
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
  bool _disposed = false;
  String? _statusMessage;
  List<BackupItem> _activeRunQueue = const [];
  List<BackupItem> _resumableQueue = const [];
  List<BackupItem> _failedItems = const [];
  CheckpointCursor? _checkpointCursor;
  int _completedInActiveRun = 0;

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

  List<SmbDestinationConfig> _pendingExtraDestinations = const [];
  List<BackupItem> _multiDestItems = const [];

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
  List<BackupItem> get resumableQueue => _resumableQueue;
  List<BackupItem> get failedItems => _failedItems;
  bool get canRetryErrors => !_progress.isActive && _failedItems.isNotEmpty;
  bool get canContinueFromStopped =>
      !_progress.isActive && (_resumableQueue.isNotEmpty || _checkpointCursor != null);
  int get resumableFileCount => _resumableQueue.isNotEmpty
      ? _resumableQueue.length
      : (_checkpointCursor?.remainingFiles ?? 0);
  int get resumableTotalBytes => _resumableQueue.isNotEmpty
      ? _resumableQueue.fold<int>(0, (sum, i) => sum + i.sizeBytes)
      : (_checkpointCursor?.remainingBytes ?? 0);

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
    // 1. Immediately attach progress stream & query live service status FIRST so reopening
    // the app while BackupForegroundService is running renders live progress immediately.
    _progressSub?.cancel();
    _progressSub = _bridge.progressStream().listen((event) {
      _progress = event;
      _updateCheckpointFromProgress(event);
      if (event.state == BackupRunState.completed && _pendingExtraDestinations.isNotEmpty) {
        final nextDest = _pendingExtraDestinations.first;
        _pendingExtraDestinations = _pendingExtraDestinations.sublist(1);
        final nextMode = _pendingExtraDestinations.isEmpty ? mode : BackupMode.copy;
        unawaited(
          activeDestination.startBackup(
            settings: nextDest.toAppSettings(_settings),
            mode: nextMode,
            deviceFolder: resolvedDeviceFolder,
            items: _multiDestItems,
          ),
        );
        return;
      }
      if (event.state == BackupRunState.cancelled || event.state == BackupRunState.error) {
        _pendingExtraDestinations = const [];
        _multiDestItems = const [];
      }
      notifyListeners();
      if (event.state == BackupRunState.completed ||
          event.state == BackupRunState.cancelled ||
          event.state == BackupRunState.error) {
        refreshSourceStats();
      }
    });
    try {
      _progress = await _bridge.getBackupStatus();
    } catch (_) {}
    notifyListeners();

    // 2. Load persisted settings & lightweight checkpoint cursor.
    _settings = await _settingsRepo.load();
    _resumableQueue = await _settingsRepo.loadCheckpointQueue();
    _checkpointCursor = await _settingsRepo.loadCheckpointCursor();
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

    _initialized = true;
    notifyListeners();

    // Never launch a concurrent full-device MediaStore/filesystem scan while a backup is running!
    if (_permissions.hasMedia && !_progress.isActive) {
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

  void _updateCheckpointFromProgress(BackupProgress event) {
    if (_activeRunQueue.isEmpty) return;
    if (event.errors.isNotEmpty) {
      final failedNames = event.errors.map((e) => e.fileName).toSet();
      final matched = _activeRunQueue.where((i) => failedNames.contains(i.fileName)).toList();
      if (matched.isNotEmpty) {
        _failedItems = List.unmodifiable(matched);
      }
    }
    final done = (event.transferred + event.skipped).clamp(0, _activeRunQueue.length);
    if (done > _completedInActiveRun) {
      _completedInActiveRun = done;
    }

    if (event.state == BackupRunState.completed &&
        event.failed == 0 &&
        _completedInActiveRun >= _activeRunQueue.length) {
      _activeRunQueue = const [];
      _resumableQueue = const [];
      _checkpointCursor = null;
      _completedInActiveRun = 0;
      unawaited(_settingsRepo.clearCheckpointQueue());
      return;
    }

    // While actively running, keep tracking O(1) integer [_completedInActiveRun] with ZERO
    // list allocations or SharedPreferences JSON serialization. Only slice and persist
    // when the backup pauses, cancels/stops, or finishes with errors!
    final shouldCommitCheckpoint = event.state == BackupRunState.paused ||
        event.state == BackupRunState.cancelled ||
        event.state == BackupRunState.error ||
        (event.state == BackupRunState.completed && _completedInActiveRun < _activeRunQueue.length);

    if (shouldCommitCheckpoint &&
        _completedInActiveRun > 0 &&
        _completedInActiveRun < _activeRunQueue.length) {
      final remainingSlice = _activeRunQueue
          .sublist(_completedInActiveRun)
          .where((i) => !i.isSnapshot)
          .toList();
      _resumableQueue = List.unmodifiable(remainingSlice);
      if (_resumableQueue.isNotEmpty) {
        _checkpointCursor = CheckpointCursor(
          cursorCreatedAtMs: _resumableQueue.first.createdAt.millisecondsSinceEpoch,
          cursorFileName: _resumableQueue.first.fileName,
          remainingFiles: _resumableQueue.length,
          remainingBytes: _resumableQueue.fold<int>(0, (sum, i) => sum + i.sizeBytes),
        );
      } else {
        _checkpointCursor = null;
      }
      unawaited(_settingsRepo.saveCheckpointQueue(_resumableQueue));
    }
  }

  Future<void> _pollActiveBackupStatus() async {
    try {
      final latest = await _bridge.getBackupStatus();
      // Do not overwrite Dart-side 'scanning' phase before native service has started.
      if (_progress.state == BackupRunState.scanning && latest.state == BackupRunState.idle) {
        return;
      }
      final wasActive = _progress.isActive;
      _progress = latest;
      _updateCheckpointFromProgress(latest);
      notifyListeners();
      if (wasActive && !latest.isActive && _permissions.hasMedia) {
        unawaited(refreshSourceStats());
      }
    } catch (_) {}
  }

  /// Called when the app returns to the foreground after screen unlock or app switching.
  /// Immediately syncs live progress from [BackupForegroundService] and avoids redundant
  /// MediaStore re-scans while a backup is actively running.
  Future<void> onAppResumed() async {
    await _pollActiveBackupStatus();
    try {
      _permissions = await _bridge.checkPermissions();
      notifyListeners();
    } catch (_) {}
    if (_permissions.hasMedia && !_progress.isActive) {
      unawaited(refreshSourceStats());
    }
  }

  Future<void> refreshPermissions() async {
    _permissions = await _bridge.checkPermissions();
    notifyListeners();
    if (_permissions.hasMedia && !_progress.isActive) {
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
      _sourceStats = await _bridge.getSourceStats(
        customFolders: _settings.customFolders,
        whatsappKey: _settings.whatsappKey,
      );
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
    final keyChanged = updated.whatsappKey != _settings.whatsappKey;
    _settings = updated;
    _rebuildMediaSources();
    await _settingsRepo.save(updated);
    _connectionResult = null;
    notifyListeners();
    if (keyChanged && _permissions.hasMedia) {
      unawaited(refreshSourceStats());
    }
  }

  Future<AppSettings> resetSettingsToDefaults() async {
    _settings = await _settingsRepo.resetToDefaults();
    _activeRunQueue = const [];
    _resumableQueue = const [];
    _checkpointCursor = null;
    _completedInActiveRun = 0;
    _rebuildMediaSources();
    _connectionResult = null;
    notifyListeners();
    if (_permissions.hasMedia) {
      unawaited(refreshSourceStats());
    }
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
        _activeRunQueue = const [];
        _resumableQueue = const [];
        _checkpointCursor = null;
        _completedInActiveRun = 0;
        await _settingsRepo.clearCheckpointQueue();
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

      await _launchPlannedItems(planned);
    } catch (e) {
      _progress = BackupProgress(
        state: BackupRunState.error,
        stage: 'error',
        errors: [BackupErrorEntry(fileName: 'Backup', message: e.toString())],
      );
      notifyListeners();
    }
  }

  Future<bool> _validateReadyForBackup({required String mediaRequiredMessage}) async {
    final dest = activeDestination;
    if (!dest.isConfigured(_settings)) {
      _statusMessage = 'Configure ${dest.displayName} in Settings before backing up.';
      notifyListeners();
      return false;
    }

    _permissions = await _bridge.checkPermissions();
    if (!_permissions.hasMedia) {
      _permissions = await _bridge.requestMediaPermissions();
      if (!_permissions.hasMedia) {
        _statusMessage = mediaRequiredMessage;
        notifyListeners();
        return false;
      }
    }

    if (mode == BackupMode.crop && !_permissions.hasAllFiles) {
      _statusMessage =
          'Crop Mode requires "All files access" permission so verified files can be deleted automatically.';
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Retries only the files that failed in the most recent backup run.
  Future<void> retryErrors() async {
    if (_progress.isActive || _failedItems.isEmpty) return;
    _statusMessage = null;

    if (!await _validateReadyForBackup(
      mediaRequiredMessage: 'Media permission is required to retry failed files.',
    )) {
      return;
    }

    final toRetry = List<BackupItem>.of(_failedItems);
    _failedItems = const [];
    try {
      await _launchPlannedItems(toRetry);
    } catch (e) {
      _progress = BackupProgress(
        state: BackupRunState.error,
        stage: 'error',
        errors: [BackupErrorEntry(fileName: 'Backup', message: e.toString())],
      );
      notifyListeners();
    }
  }

  /// Continues a stopped or interrupted backup directly from the remaining checkpoint queue
  /// (or lightweight cursor for huge multi-thousand-file queues).
  Future<void> continueBackup() async {
    if (_progress.isActive || !canContinueFromStopped) return;
    _statusMessage = null;

    if (!await _validateReadyForBackup(
      mediaRequiredMessage: 'Media permission is required to continue backup.',
    )) {
      return;
    }

    try {
      if (_resumableQueue.isNotEmpty) {
        await _launchPlannedItems(List<BackupItem>.of(_resumableQueue));
        return;
      }
      final cursor = _checkpointCursor;
      if (cursor != null) {
        _progress = const BackupProgress(
          state: BackupRunState.scanning,
          stage: 'scanning',
        );
        notifyListeners();
        final allPlanned = await _exporter.discoverItems(limit: currentLimit);
        final resumed = allPlanned.where(cursor.includes).toList();
        if (resumed.isEmpty) {
          _checkpointCursor = null;
          await _settingsRepo.clearCheckpointQueue();
          _progress = const BackupProgress(
            state: BackupRunState.completed,
            stage: 'completed',
          );
          notifyListeners();
          return;
        }
        await _launchPlannedItems(resumed);
      }
    } catch (e) {
      _progress = BackupProgress(
        state: BackupRunState.error,
        stage: 'error',
        errors: [BackupErrorEntry(fileName: 'Backup', message: e.toString())],
      );
      notifyListeners();
    }
  }

  Future<void> _launchPlannedItems(List<BackupItem> items) async {
    _activeRunQueue = List.unmodifiable(items);
    _failedItems = const [];
    _completedInActiveRun = 0;
    _resumableQueue = List.unmodifiable(items.where((i) => !i.isSnapshot));
    if (_resumableQueue.isNotEmpty) {
      _checkpointCursor = CheckpointCursor(
        cursorCreatedAtMs: _resumableQueue.first.createdAt.millisecondsSinceEpoch,
        cursorFileName: _resumableQueue.first.fileName,
        remainingFiles: _resumableQueue.length,
        remainingBytes: _resumableQueue.fold<int>(0, (sum, i) => sum + i.sizeBytes),
      );
    } else {
      _checkpointCursor = null;
    }
    await _settingsRepo.saveCheckpointQueue(_resumableQueue);

    final totalBytes = items.fold<int>(0, (sum, i) => sum + i.sizeBytes);
    _progress = BackupProgress(
      state: BackupRunState.running,
      stage: 'connecting',
      total: items.length,
      remaining: items.length,
      totalBytes: totalBytes,
    );
    notifyListeners();

    final enabledDests = _settings.enabledSmbDestinations;
    final firstSettings =
        enabledDests.isNotEmpty ? enabledDests.first.toAppSettings(_settings) : _settings;
    _pendingExtraDestinations =
        enabledDests.length > 1 ? List.unmodifiable(enabledDests.sublist(1)) : const [];
    _multiDestItems = enabledDests.length > 1 ? List.unmodifiable(items) : const [];
    // Strict Deletion Gate: when multiple destinations are enabled, only run Crop deletion on the final destination.
    final firstMode = _pendingExtraDestinations.isEmpty ? mode : BackupMode.copy;

    await activeDestination.startBackup(
      settings: firstSettings,
      mode: firstMode,
      deviceFolder: resolvedDeviceFolder,
      items: items,
    );
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
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _progressSub?.cancel();
    super.dispose();
  }
}
