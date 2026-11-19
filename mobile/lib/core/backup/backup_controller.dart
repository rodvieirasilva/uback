import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'backup_planner.dart';
import 'image_video_media_exporter.dart';
import 'media_exporter.dart';
import 'media_source.dart';
import 'native_bridge.dart';

class BackupController extends ChangeNotifier {
  final AppSettingsRepository _settingsRepo;
  final NativeBackupBridge _bridge;
  late final List<MediaSource> _mediaSources;
  late final ImageVideoMediaExporter _exporter;

  StreamSubscription<BackupProgress>? _progressSub;

  AppSettings _settings = CompileTimeDefaults.toSettings();
  String _detectedDeviceName = 'android';
  String _appVersion = CompileTimeDefaults.appVersion;
  PermissionState _permissions = const PermissionState();
  Map<String, MediaSourceStats> _sourceStats = const {};
  bool _estimatingStats = false;
  bool _hasEstimatedStats = false;
  BackupMode _mode = BackupMode.copy;
  BackupLimitType _limitType = BackupLimitType.all;
  int _limitValue = 100;
  BackupProgress _progress = const BackupProgress();
  ConnectionTestResult? _connectionResult;
  bool _testingConnection = false;
  bool _initialized = false;
  String? _statusMessage;

  BackupController({
    required this._settingsRepo,
    required this._bridge,
    List<MediaSource>? mediaSources,
  }) {
    _mediaSources = List.unmodifiable(mediaSources ?? defaultMediaSources(_bridge));
    _exporter = ImageVideoMediaExporter(
      bridge: _bridge,
      settingsProvider: () => _settings,
      deviceFolderProvider: () => resolvedDeviceFolder,
    );
  }

  AppSettings get settings => _settings;
  List<MediaSource> get mediaSources => _mediaSources;
  String get detectedDeviceName => _detectedDeviceName;
  String get appVersion => _appVersion;
  String get resolvedDeviceFolder => _settings.resolvedDeviceFolder(_detectedDeviceName);
  String get destinationPreview => _settings.destinationPreview(_detectedDeviceName);
  PermissionState get permissions => _permissions;
  Map<String, MediaSourceStats> get sourceStats => _sourceStats;
  bool get estimatingStats => _estimatingStats;
  bool get hasEstimatedStats => _hasEstimatedStats;
  BackupMode get mode => _mode;
  BackupLimitType get limitType => _limitType;
  int get limitValue => _limitValue;
  BackupProgress get progress => _progress;
  ConnectionTestResult? get connectionResult => _connectionResult;
  bool get testingConnection => _testingConnection;
  bool get initialized => _initialized;
  String? get statusMessage => _statusMessage;
  MediaExporter get exporter => _exporter;

  int get selectedFileCount {
    var total = 0;
    for (final src in _mediaSources) {
      if (_settings.isSourceEnabled(src.id)) {
        total += _sourceStats[src.id]?.fileCount ?? 0;
      }
    }
    return total;
  }

  int get selectedTotalBytes {
    var total = 0;
    for (final src in _mediaSources) {
      if (_settings.isSourceEnabled(src.id)) {
        total += _sourceStats[src.id]?.totalBytes ?? 0;
      }
    }
    return total;
  }

  BackupLimit? get currentLimit {
    return switch (_limitType) {
      BackupLimitType.all => null,
      BackupLimitType.files => BackupLimit(maxFiles: _limitValue > 0 ? _limitValue : 1),
      BackupLimitType.megabytes =>
        BackupLimit(maxBytes: (_limitValue > 0 ? _limitValue : 1) * 1024 * 1024),
    };
  }

  Future<void> init() async {
    _settings = await _settingsRepo.load();
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

  void setMode(BackupMode mode) {
    if (_progress.isActive) return;
    _mode = mode;
    _statusMessage = null;
    notifyListeners();
  }

  Future<void> toggleSource(String sourceId, bool enabled) async {
    if (_progress.isActive) return;
    final next = Set<String>.of(_settings.enabledSourceIds);
    if (enabled) {
      next.add(sourceId);
    } else {
      next.remove(sourceId);
    }
    _settings = _settings.copyWith(enabledSourceIds: next);
    _statusMessage = null;
    notifyListeners();
    await _settingsRepo.save(_settings);
  }

  void setLimitType(BackupLimitType type) {
    if (_progress.isActive) return;
    _limitType = type;
    if (type == BackupLimitType.files && _limitValue <= 0) {
      _limitValue = 100;
    } else if (type == BackupLimitType.megabytes && _limitValue <= 0) {
      _limitValue = 500;
    }
    notifyListeners();
  }

  void setLimitValue(int value) {
    if (_progress.isActive) return;
    _limitValue = value;
    notifyListeners();
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

  Future<void> refreshSourceStats() async {
    if (_estimatingStats) return;
    _estimatingStats = true;
    notifyListeners();
    try {
      _sourceStats = await _bridge.getSourceStats();
      _hasEstimatedStats = true;
    } catch (_) {
      // Keep previous estimate if query fails transiently.
    } finally {
      _estimatingStats = false;
      notifyListeners();
    }
  }

  Future<void> saveSettings(AppSettings updated) async {
    _settings = updated;
    await _settingsRepo.save(updated);
    _connectionResult = null;
    notifyListeners();
  }

  Future<AppSettings> resetSettingsToDefaults() async {
    _settings = await _settingsRepo.resetToDefaults();
    _connectionResult = null;
    notifyListeners();
    return _settings;
  }

  Future<ConnectionTestResult> testConnection([AppSettings? overrideSettings]) async {
    final target = overrideSettings ?? _settings;
    if (!target.isConfigured) {
      const res = ConnectionTestResult(
        ok: false,
        message: 'Configure SMB Host and Share in Settings first.',
      );
      _connectionResult = res;
      notifyListeners();
      return res;
    }

    _testingConnection = true;
    _connectionResult = null;
    notifyListeners();

    try {
      final res = await _bridge.testConnection(target);
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

    if (!_settings.isConfigured) {
      _statusMessage = 'Configure SMB Host and Share in Settings before backing up.';
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

    if (_mode == BackupMode.crop && !_permissions.hasAllFiles) {
      _statusMessage =
          'Crop Mode requires "All files access" permission so verified files can be deleted automatically.';
      notifyListeners();
      return;
    }

    _progress = const BackupProgress(
      state: BackupRunState.scanning,
      stage: 'scanning',
    );
    notifyListeners();

    try {
      final discovered = await _exporter.discoverItems();
      final planned = BackupPlanner.plan(discovered, limit: currentLimit);

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

      await _bridge.startBackup(
        settings: _settings,
        mode: _mode,
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

  Future<void> stopBackup() async {
    await _bridge.stopBackup();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }
}
