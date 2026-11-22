import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../config/custom_folder_config.dart';
import 'media_exporter.dart';
import 'media_source.dart';

/// Result returned by Android's native Storage Access Framework folder picker.
class FolderPickResult {
  final String? relativePath;
  final String? error;

  const FolderPickResult({this.relativePath, this.error});

  bool get hasPath => relativePath != null && relativePath!.trim().isNotEmpty;

  factory FolderPickResult.fromMap(Map<Object?, Object?> map) => FolderPickResult(
        relativePath: map['relativePath'] as String?,
        error: map['error'] as String?,
      );
}

/// Abstraction over the Android native Kotlin bridge (`MethodChannel` + `EventChannel`).
/// Easily fakeable in unit and widget tests.
abstract class NativeBackupBridge {
  Future<String> getDeviceName();
  Future<String> getAppVersion();
  Future<PermissionState> checkPermissions();
  Future<PermissionState> requestMediaPermissions();
  Future<PermissionState> requestSnapshotPermissions(Set<String> snapshotSources);
  Future<void> openAllFilesAccessSettings();
  Future<FolderPickResult?> pickFolder();
  Future<List<BackupItem>> discoverMedia({
    required Set<String> enabledSourceIds,
    List<CustomFolderConfig> customFolders = const [],
    int? perSourceLimit,
    String? whatsappKey,
  });
  Future<Map<String, MediaSourceStats>> getSourceStats({
    List<CustomFolderConfig> customFolders = const [],
    String? whatsappKey,
  });
  Future<ConnectionTestResult> testConnection(AppSettings settings);
  Future<void> startBackup({
    required AppSettings settings,
    required BackupMode mode,
    required String deviceFolder,
    required List<BackupItem> items,
  });
  Future<void> pauseBackup();
  Future<void> resumeBackup();
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
  Future<PermissionState> requestSnapshotPermissions(Set<String> snapshotSources) async {
    if (snapshotSources.isEmpty) return checkPermissions();
    final res = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'requestSnapshotPermissions',
      {'sources': snapshotSources.toList()},
    );
    return res == null ? const PermissionState() : PermissionState.fromMap(res);
  }

  @override
  Future<void> openAllFilesAccessSettings() async {
    await _methodChannel.invokeMethod<void>('openAllFilesAccessSettings');
  }

  @override
  Future<FolderPickResult?> pickFolder() async {
    final res = await _methodChannel.invokeMapMethod<Object?, Object?>('pickFolder');
    return res == null ? null : FolderPickResult.fromMap(res);
  }

  @override
  Future<List<BackupItem>> discoverMedia({
    required Set<String> enabledSourceIds,
    List<CustomFolderConfig> customFolders = const [],
    int? perSourceLimit,
    String? whatsappKey,
  }) async {
    final raw = await _methodChannel.invokeListMethod<Object?>(
      'discoverMedia',
      {
        'enabledSources': enabledSourceIds.toList(),
        'customFolders': customFolders.map((f) => f.toMap()).toList(),
        'perSourceLimit': ?perSourceLimit,
        if (whatsappKey != null && whatsappKey.trim().isNotEmpty) 'whatsappKey': whatsappKey.trim(),
      },
    );
    if (raw == null) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(BackupItem.fromMap)
        .toList();
  }

  @override
  Future<Map<String, MediaSourceStats>> getSourceStats({
    List<CustomFolderConfig> customFolders = const [],
    String? whatsappKey,
  }) async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'getSourceStats',
      {
        'customFolders': customFolders.map((f) => f.toMap()).toList(),
        if (whatsappKey != null && whatsappKey.trim().isNotEmpty) 'whatsappKey': whatsappKey.trim(),
      },
    );
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
  Future<void> pauseBackup() async {
    await _methodChannel.invokeMethod<void>('pauseBackup');
  }

  @override
  Future<void> resumeBackup() async {
    await _methodChannel.invokeMethod<void>('resumeBackup');
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

  static Map<String, String?> _parseTelegramAuth(Map<Object?, Object?>? raw) => {
        'state': raw?['state']?.toString() ?? 'uninitialized',
        'error': raw?['error']?.toString(),
      };

  static Future<Map<String, String?>> telegramGetAuthState(int apiId, String apiHash) async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'telegramGetAuthState',
      {'apiId': apiId, 'apiHash': apiHash},
    );
    return _parseTelegramAuth(raw);
  }

  static Future<Map<String, String?>> telegramSendPhone(String phone) async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'telegramSendPhone',
      {'phone': phone},
    );
    return _parseTelegramAuth(raw);
  }

  static Future<Map<String, String?>> telegramSendCode(String code) async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'telegramSendCode',
      {'code': code},
    );
    return _parseTelegramAuth(raw);
  }

  static Future<Map<String, String?>> telegramSendPassword(String password) async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'telegramSendPassword',
      {'password': password},
    );
    return _parseTelegramAuth(raw);
  }

  static Future<Map<String, String?>> telegramLogout() async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>('telegramLogout');
    return _parseTelegramAuth(raw);
  }

  static Future<Map<String, dynamic>> testWhatsApp(String whatsappKey) async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'testWhatsApp',
      {'whatsappKey': whatsappKey},
    );
    return {
      'ok': raw?['ok'] == true,
      'message': raw?['message']?.toString() ?? 'Unknown status',
    };
  }
}
