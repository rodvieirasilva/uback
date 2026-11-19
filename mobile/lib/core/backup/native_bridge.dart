import 'package:flutter/services.dart';

import '../config/app_config.dart';
import 'media_exporter.dart';
import 'media_source.dart';

/// Abstraction over the Android native Kotlin bridge (`MethodChannel` + `EventChannel`).
/// Easily fakeable in unit and widget tests.
abstract class NativeBackupBridge {
  Future<String> getDeviceName();
  Future<String> getAppVersion();
  Future<PermissionState> checkPermissions();
  Future<PermissionState> requestMediaPermissions();
  Future<void> openAllFilesAccessSettings();
  Future<List<BackupItem>> discoverMedia({
    required Set<String> enabledSourceIds,
    int? perSourceLimit,
  });
  Future<Map<String, MediaSourceStats>> getSourceStats();
  Future<ConnectionTestResult> testConnection(AppSettings settings);
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  });
  Future<void> stopBackup();
  Future<BackupProgress> getBackupStatus();
  Stream<BackupProgress> progressStream();
}

class MethodChannelNativeBridge implements NativeBackupBridge {
  static const MethodChannel _methodChannel = MethodChannel('uback/native');
  static const EventChannel _eventChannel = EventChannel('uback/progress');

  @override
  Future<String> getDeviceName() async {
    final name = await _methodChannel.invokeMethod<String>('getDeviceName');
    return (name == null || name.trim().isEmpty) ? 'android' : name.trim();
  }

  @override
  Future<String> getAppVersion() async {
    final version = await _methodChannel.invokeMethod<String>('getAppVersion');
    return (version == null || version.trim().isEmpty)
        ? CompileTimeDefaults.appVersion
        : version.trim();
  }

  @override
  Future<PermissionState> checkPermissions() async {
    final res = await _methodChannel.invokeMapMethod<Object?, Object?>('checkPermissions');
    return res == null ? const PermissionState() : PermissionState.fromMap(res);
  }

  @override
  Future<PermissionState> requestMediaPermissions() async {
    final res = await _methodChannel.invokeMapMethod<Object?, Object?>('requestMediaPermissions');
    return res == null ? const PermissionState() : PermissionState.fromMap(res);
  }

  @override
  Future<void> openAllFilesAccessSettings() async {
    await _methodChannel.invokeMethod<void>('openAllFilesAccessSettings');
  }

  @override
  Future<List<BackupItem>> discoverMedia({
    required Set<String> enabledSourceIds,
    int? perSourceLimit,
  }) async {
    final raw = await _methodChannel.invokeListMethod<Object?>(
      'discoverMedia',
      {
        'enabledSources': enabledSourceIds.toList(),
        'perSourceLimit': ?perSourceLimit,
      },
    );
    if (raw == null) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(BackupItem.fromMap)
        .toList();
  }

  @override
  Future<Map<String, MediaSourceStats>> getSourceStats() async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>('getSourceStats');
    if (raw == null) return const {};
    final out = <String, MediaSourceStats>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is Map<Object?, Object?>) {
        out[key] = MediaSourceStats.fromMap(value);
      }
    }
    return out;
  }

  @override
  Future<ConnectionTestResult> testConnection(AppSettings settings) async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'testConnection',
      settings.toSmbMap(),
    );
    if (raw == null) {
      return const ConnectionTestResult(ok: false, message: 'No response from native SMB engine');
    }
    return ConnectionTestResult(
      ok: (raw['ok'] as bool?) ?? false,
      message: (raw['message'] as String?) ?? '',
    );
  }

  @override
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  }) async {
    await _methodChannel.invokeMethod<void>('startBackup', {
      'smbConfig': settings.toSmbMap(),
      'mode': mode == BackupMode.crop ? 'crop' : 'copy',
      'deviceFolder': deviceFolder,
      'items': items.map((e) => e.toMap()).toList(),
    });
  }

  @override
  Future<void> stopBackup() async {
    await _methodChannel.invokeMethod<void>('stopBackup');
  }

  @override
  Future<BackupProgress> getBackupStatus() async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>('getBackupStatus');
    return raw == null ? const BackupProgress() : BackupProgress.fromMap(raw);
  }

  @override
  Stream<BackupProgress> progressStream() {
    return _eventChannel.receiveBroadcastStream().map((event) {
      if (event is Map<Object?, Object?>) {
        return BackupProgress.fromMap(event);
      }
      return const BackupProgress();
    });
  }
}
