import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'backup_planner.dart';
import 'image_video_media_exporter.dart';
import 'media_exporter.dart';
import 'native_bridge.dart';

class BackupController extends ChangeNotifier {
  final AppSettingsRepository _settingsRepo;
  final NativeBackupBridge _bridge;
  late final ImageVideoMediaExporter _exporter;

  StreamSubscription<BackupProgress>? _progressSub;

  AppSettings _settings = CompileTimeDefaults.toSettings();
  String _detectedDeviceName = 'android';
  String _appVersion = CompileTimeDefaults.appVersion;
  PermissionState _permissions = const PermissionState();
  Map<String, int> _sourceCounts = const {'camera': 0, 'screenshots': 0};
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
  }) {
    _exporter = ImageVideoMediaExporter(
      bridge: _bridge,
      settingsProvider: () => _settings,
      deviceFolderProvider: () => resolvedDeviceFolder,
    );
  }

  AppSettings get settings => _settings;
  String get detectedDeviceName => _detectedDeviceName;
  String get appVersion => _appVersion;
  String get resolvedDeviceFolder => _settings.resolvedDeviceFolder(_detectedDeviceName);
  String get destinationPreview => _settings.destinationPreview(_detectedDeviceName);
  PermissionState get permissions => _permissions;
  Map<String, int> get sourceCounts => _sourceCounts;
  BackupMode get mode => _mode;
  BackupLimitType get limitType => _limitType;
  int get limitValue => _limitValue;
  BackupProgress get progress => _progress;
  ConnectionTestResult? get connectionResult => _connectionResult;
  bool get testingConnection => _testingConnection;
  bool get initialized => _initialized;
  String? get statusMessage => _statusMessage;
  MediaExporter get exporter => _exporter;

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
        refreshSourceCounts();
      }
    });

    _initialized = true;
    notifyListeners();

    if (_permissions.hasMedia) {
      await refreshSourceCounts();
    }
  }

  void setMode(BackupMode mode) {
    if (_progress.isActive) return;
    _mode = mode;
    _statusMessage = null;
    notifyListeners();
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
      await refreshSourceCounts();
    }
  }

  Future<void> requestMediaPermissions() async {
    _permissions = await _bridge.requestMediaPermissions();
    notifyListeners();
    if (_permissions.hasMedia) {
      await refreshSourceCounts();
    }
  }

  Future<void> openAllFilesAccessSettings() async {
    await _bridge.openAllFilesAccessSettings();
  }

  Future<void> refreshSourceCounts() async {
    try {
      _sourceCounts = await _bridge.getSourceCounts();
      notifyListeners();
    } catch (_) {}
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

    if (!_settings.includeCamera && !_settings.includeScreenshots) {
      _statusMessage = 'Enable at least one source (Camera or Screenshots) in Settings.';
      notifyListeners();
      return;
    }

    _permissions = await _bridge.checkPermissions();
    if (!_permissions.hasMedia) {
      _permissions = await _bridge.requestMediaPermissions();
      if (!_permissions.hasMedia) {
        _statusMessage = 'Media permission is required to scan Camera & Screenshots.';
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
        _statusMessage = 'No Camera or Screenshots media found to back up.';
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
