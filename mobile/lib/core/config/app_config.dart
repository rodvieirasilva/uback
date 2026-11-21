import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backup/backup_destination.dart';
import '../backup/media_exporter.dart';
import '../backup/media_source.dart';
import '../utils/path_sanitizer.dart';
import 'custom_folder_config.dart';

/// Compile-time defaults injected via `--dart-define-from-file=dart_defines.json`
/// generated from local (gitignored) `config.toml`.
class CompileTimeDefaults {
  static const String destinationType =
      String.fromEnvironment('UBACK_DESTINATION_TYPE', defaultValue: SmbNasDestination.typeId);
  static const String host = String.fromEnvironment('UBACK_SMB_HOST', defaultValue: '');
  static const String portStr = String.fromEnvironment('UBACK_SMB_PORT', defaultValue: '445');
  static const String share = String.fromEnvironment('UBACK_SMB_SHARE', defaultValue: '');
  static const String basePath = String.fromEnvironment('UBACK_SMB_BASE_PATH', defaultValue: '');
  static const String username = String.fromEnvironment('UBACK_SMB_USERNAME', defaultValue: '');
  static const String password = String.fromEnvironment('UBACK_SMB_PASSWORD', defaultValue: '');
  static const String domain = String.fromEnvironment('UBACK_SMB_DOMAIN', defaultValue: '');
  static const String whatsappKey =
      String.fromEnvironment('UBACK_WHATSAPP_KEY', defaultValue: '');
  static const String e2eDeviceOverride =
      String.fromEnvironment('UBACK_E2E_DEVICE_OVERRIDE', defaultValue: '');
  static const String appVersion =
      String.fromEnvironment('UBACK_APP_VERSION', defaultValue: '1.2.8');
  static const String buildDate =
      String.fromEnvironment('UBACK_BUILD_DATE', defaultValue: '');
  static const String gitSha =
      String.fromEnvironment('UBACK_GIT_SHA', defaultValue: '');

  /// Formats the user-facing version footer without any `+buildNumber` suffix,
  /// appending the release date and short commit SHA when available:
  /// e.g. `UBack v1.2.2 • 2026-11-20 • 23bb0c1`.
  static String formatVersionLabel(
    String rawVersion, {
    String? buildDateOverride,
    String? gitShaOverride,
  }) {
    final cleanVersion = rawVersion.split('+').first.trim();
    final parts = <String>['UBack v${cleanVersion.isEmpty ? '1.0.0' : cleanVersion}'];
    final date = (buildDateOverride ?? buildDate).trim();
    final sha = (gitShaOverride ?? gitSha).trim();
    if (date.isNotEmpty) parts.add(date);
    if (sha.isNotEmpty) parts.add(sha);
    return parts.join(' • ');
  }

  static AppSettings toSettings() {
    return AppSettings(
      destinationType: destinationType.isEmpty ? SmbNasDestination.typeId : destinationType,
      host: host,
      port: int.tryParse(portStr) ?? 445,
      share: share,
      basePath: basePath,
      username: username,
      password: password,
      domain: domain,
      whatsappKey: whatsappKey,
      deviceFolderOverride: e2eDeviceOverride,
      enabledSourceIds: defaultEnabledMediaSourceIds,
    );
  }
}

class AppSettings {
  final String destinationType;
  final String lastExporterId;
  final BackupMode lastMode;
  final BackupLimitType lastLimitType;
  final int lastLimitValue;
  final bool mediaSourcesExpanded;
  final Set<String> expandedSourceGroupIds;
  final String host;
  final int port;
  final String share;
  final String basePath;
  final String username;
  final String password;
  final String domain;
  final String whatsappKey;
  final String deviceFolderOverride;
  final Set<String> enabledSourceIds;
  final List<CustomFolderConfig> customFolders;

  const AppSettings({
    this.destinationType = SmbNasDestination.typeId,
    this.lastExporterId = 'unified_media_exporter',
    this.lastMode = BackupMode.copy,
    this.lastLimitType = BackupLimitType.all,
    this.lastLimitValue = 100,
    this.mediaSourcesExpanded = true,
    this.expandedSourceGroupIds = const {},
    required this.host,
    required this.port,
    required this.share,
    required this.basePath,
    required this.username,
    required this.password,
    required this.domain,
    this.whatsappKey = '',
    required this.deviceFolderOverride,
    this.enabledSourceIds = defaultEnabledMediaSourceIds,
    this.customFolders = const [],
  });

  bool isSourceEnabled(String sourceId) => enabledSourceIds.contains(sourceId);

  bool get isConfigured => host.trim().isNotEmpty && share.trim().isNotEmpty;

  String resolvedDeviceFolder(String detectedDeviceName) {
    final raw = deviceFolderOverride.trim().isNotEmpty
        ? deviceFolderOverride.trim()
        : detectedDeviceName;
    return PathSanitizer.sanitizeDeviceName(raw);
  }

  Map<String, dynamic> toSmbMap() => {
        'host': host.trim(),
        'port': port,
        'share': share.trim(),
        'basePath': basePath.trim(),
        'username': username.trim(),
        'password': password,
        'domain': domain.trim(),
      };

  AppSettings copyWith({
    String? destinationType,
    String? lastExporterId,
    BackupMode? lastMode,
    BackupLimitType? lastLimitType,
    int? lastLimitValue,
    bool? mediaSourcesExpanded,
    Set<String>? expandedSourceGroupIds,
    String? host,
    int? port,
    String? share,
    String? basePath,
    String? username,
    String? password,
    String? domain,
    String? whatsappKey,
    String? deviceFolderOverride,
    Set<String>? enabledSourceIds,
    List<CustomFolderConfig>? customFolders,
  }) {
    return AppSettings(
      destinationType: destinationType ?? this.destinationType,
      lastExporterId: lastExporterId ?? this.lastExporterId,
      lastMode: lastMode ?? this.lastMode,
      lastLimitType: lastLimitType ?? this.lastLimitType,
      lastLimitValue: lastLimitValue ?? this.lastLimitValue,
      mediaSourcesExpanded: mediaSourcesExpanded ?? this.mediaSourcesExpanded,
      expandedSourceGroupIds: expandedSourceGroupIds ?? this.expandedSourceGroupIds,
      host: host ?? this.host,
      port: port ?? this.port,
      share: share ?? this.share,
      basePath: basePath ?? this.basePath,
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      whatsappKey: whatsappKey ?? this.whatsappKey,
      deviceFolderOverride: deviceFolderOverride ?? this.deviceFolderOverride,
      enabledSourceIds: enabledSourceIds ?? this.enabledSourceIds,
      customFolders: customFolders ?? this.customFolders,
    );
  }
}

abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SharedPrefsStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

class SecureKeyValueStore implements KeyValueStore {
  final FlutterSecureStorage _storage;

  SecureKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// Persists full session configuration (destination, exporter, mode, batch limit,
/// collapsible UI state, source toggles, custom folders, and credentials) with
/// fallback to compile-time defaults.
class AppSettingsRepository {
  static const _kDestinationType = 'uback_destination_type';
  static const _kLastExporterId = 'uback_last_exporter_id';
  static const _kLastMode = 'uback_last_mode';
  static const _kLastLimitType = 'uback_last_limit_type';
  static const _kLastLimitValue = 'uback_last_limit_value';
  static const _kMediaSourcesExpanded = 'uback_media_sources_expanded';
  static const _kExpandedGroups = 'uback_expanded_source_groups';
  static const _kHost = 'uback_smb_host';
  static const _kPort = 'uback_smb_port';
  static const _kShare = 'uback_smb_share';
  static const _kBasePath = 'uback_smb_base_path';
  static const _kDomain = 'uback_smb_domain';
  static const _kDeviceOverride = 'uback_device_override';
  static const _kEnabledSources = 'uback_enabled_sources';
  static const _kCustomFolders = 'uback_custom_folders';
  static const _kCheckpointQueue = 'uback_checkpoint_queue';
  static const _kCheckpointCursor = 'uback_checkpoint_cursor';

  static const _kSecretUser = 'uback_smb_username';
  static const _kSecretPass = 'uback_smb_password';
  static const _kSecretWhatsappKey = 'uback_whatsapp_key';

  final KeyValueStore _plainStore;
  final KeyValueStore _secureStore;
  final AppSettings _defaults;

  AppSettingsRepository({
    KeyValueStore? plainStore,
    KeyValueStore? secureStore,
    AppSettings? defaults,
  })  : _plainStore = plainStore ?? SharedPrefsStore(),
        _secureStore = secureStore ?? SecureKeyValueStore(),
        _defaults = defaults ?? CompileTimeDefaults.toSettings();

  AppSettings get compileTimeDefaults => _defaults;

  static Set<String> _migrateLegacySources(Set<String> raw) {
    final migrated = <String>{};
    for (final id in raw) {
      if (id == 'camera') {
        migrated.addAll({'camera.images', 'camera.videos', 'camera.raw'});
      } else {
        migrated.add(id);
      }
    }
    return migrated;
  }

  static BackupMode _parseMode(String? raw, BackupMode fallback) => switch (raw) {
        'copy' => BackupMode.copy,
        'crop' => BackupMode.crop,
        _ => fallback,
      };

  static BackupLimitType _parseLimitType(String? raw, BackupLimitType fallback) => switch (raw) {
        'all' => BackupLimitType.all,
        'files' => BackupLimitType.files,
        'megabytes' => BackupLimitType.megabytes,
        _ => fallback,
      };

  static Set<String> _parseCsvSet(String raw) =>
      raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

  Future<AppSettings> load() async {
    final destinationType = await _plainStore.read(_kDestinationType);
    final lastExporterId = await _plainStore.read(_kLastExporterId);
    final lastModeRaw = await _plainStore.read(_kLastMode);
    final lastLimitTypeRaw = await _plainStore.read(_kLastLimitType);
    final lastLimitValueRaw = await _plainStore.read(_kLastLimitValue);
    final mediaExpandedRaw = await _plainStore.read(_kMediaSourcesExpanded);
    final expandedGroupsRaw = await _plainStore.read(_kExpandedGroups);
    final host = await _plainStore.read(_kHost);
    final portStr = await _plainStore.read(_kPort);
    final share = await _plainStore.read(_kShare);
    final basePath = await _plainStore.read(_kBasePath);
    final domain = await _plainStore.read(_kDomain);
    final deviceOverride = await _plainStore.read(_kDeviceOverride);
    final enabledSourcesRaw = await _plainStore.read(_kEnabledSources);
    final customFoldersRaw = await _plainStore.read(_kCustomFolders);

    final enabledSourceIds = enabledSourcesRaw != null
        ? _migrateLegacySources(_parseCsvSet(enabledSourcesRaw))
        : _defaults.enabledSourceIds;

    final expandedGroups = expandedGroupsRaw != null
        ? _parseCsvSet(expandedGroupsRaw)
        : _defaults.expandedSourceGroupIds;

    final customFolders = customFoldersRaw != null
        ? CustomFolderConfig.decodeList(customFoldersRaw)
        : _defaults.customFolders;

    String? username;
    String? password;
    String? whatsappKey;
    try {
      username = await _secureStore
          .read(_kSecretUser)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      password = await _secureStore
          .read(_kSecretPass)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      whatsappKey = await _secureStore
          .read(_kSecretWhatsappKey)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {
      // Fallback safely to compile-time defaults if keystore read fails or times out
    }

    return AppSettings(
      destinationType: destinationType ?? _defaults.destinationType,
      lastExporterId: lastExporterId ?? _defaults.lastExporterId,
      lastMode: _parseMode(lastModeRaw, _defaults.lastMode),
      lastLimitType: _parseLimitType(lastLimitTypeRaw, _defaults.lastLimitType),
      lastLimitValue: int.tryParse(lastLimitValueRaw ?? '') ?? _defaults.lastLimitValue,
      mediaSourcesExpanded:
          mediaExpandedRaw != null ? mediaExpandedRaw == 'true' : _defaults.mediaSourcesExpanded,
      expandedSourceGroupIds: expandedGroups,
      host: host ?? _defaults.host,
      port: int.tryParse(portStr ?? '') ?? _defaults.port,
      share: share ?? _defaults.share,
      basePath: basePath ?? _defaults.basePath,
      username: username ?? _defaults.username,
      password: password ?? _defaults.password,
      domain: domain ?? _defaults.domain,
      whatsappKey: whatsappKey ?? _defaults.whatsappKey,
      deviceFolderOverride: deviceOverride ?? _defaults.deviceFolderOverride,
      enabledSourceIds: enabledSourceIds,
      customFolders: customFolders,
    );
  }

  Future<void> save(AppSettings settings) async {
    await _plainStore.write(_kDestinationType, settings.destinationType);
    await _plainStore.write(_kLastExporterId, settings.lastExporterId);
    await _plainStore.write(_kLastMode, settings.lastMode.name);
    await _plainStore.write(_kLastLimitType, settings.lastLimitType.name);
    await _plainStore.write(_kLastLimitValue, settings.lastLimitValue.toString());
    await _plainStore.write(_kMediaSourcesExpanded, settings.mediaSourcesExpanded.toString());
    final sortedExpanded = settings.expandedSourceGroupIds.toList()..sort();
    await _plainStore.write(_kExpandedGroups, sortedExpanded.join(','));
    await _plainStore.write(_kHost, settings.host.trim());
    await _plainStore.write(_kPort, settings.port.toString());
    await _plainStore.write(_kShare, settings.share.trim());
    await _plainStore.write(_kBasePath, settings.basePath.trim());
    await _plainStore.write(_kDomain, settings.domain.trim());
    await _plainStore.write(_kDeviceOverride, settings.deviceFolderOverride.trim());
    final sortedSources = settings.enabledSourceIds.toList()..sort();
    await _plainStore.write(_kEnabledSources, sortedSources.join(','));
    await _plainStore.write(
      _kCustomFolders,
      CustomFolderConfig.encodeList(settings.customFolders),
    );

    await _secureStore.write(_kSecretUser, settings.username.trim());
    await _secureStore.write(_kSecretPass, settings.password);
    await _secureStore.write(_kSecretWhatsappKey, settings.whatsappKey.trim());
  }

  Future<AppSettings> resetToDefaults() async {
    for (final key in [
      _kDestinationType,
      _kLastExporterId,
      _kLastMode,
      _kLastLimitType,
      _kLastLimitValue,
      _kMediaSourcesExpanded,
      _kExpandedGroups,
      _kHost,
      _kPort,
      _kShare,
      _kBasePath,
      _kDomain,
      _kDeviceOverride,
      _kEnabledSources,
      _kCustomFolders,
      _kCheckpointQueue,
      _kCheckpointCursor,
    ]) {
      await _plainStore.delete(key);
    }
    try {
      await _secureStore.delete(_kSecretUser);
      await _secureStore.delete(_kSecretPass);
      await _secureStore.delete(_kSecretWhatsappKey);
    } catch (_) {}
    return _defaults;
  }

  /// Purges any legacy inline checkpoint queue from SharedPreferences so startup never stalls.
  Future<List<BackupItem>> loadCheckpointQueue() async {
    await _plainStore.delete(_kCheckpointQueue);
    return const [];
  }

  /// Loads the lightweight O(1) checkpoint cursor (< 200 bytes).
  Future<CheckpointCursor?> loadCheckpointCursor() async {
    await _plainStore.delete(_kCheckpointQueue);
    final raw = await _plainStore.read(_kCheckpointCursor);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<Object?, Object?>) {
        return CheckpointCursor.fromMap(decoded);
      }
      return null;
    } catch (_) {
      await _plainStore.delete(_kCheckpointCursor);
      return null;
    }
  }

  /// Persists ONLY a tiny O(1) cursor (< 200 bytes) when a backup starts, pauses, or stops
  /// (never storing a multi-megabyte JSON file list in SharedPreferences).
  Future<void> saveCheckpointQueue(List<BackupItem> items) async {
    await _plainStore.delete(_kCheckpointQueue);
    final persistable = items.where((i) => !i.isSnapshot).toList();
    if (persistable.isEmpty) {
      await clearCheckpointQueue();
      return;
    }
    final first = persistable.first;
    final totalBytes = persistable.fold<int>(0, (sum, i) => sum + i.sizeBytes);
    final cursor = CheckpointCursor(
      cursorCreatedAtMs: first.createdAt.millisecondsSinceEpoch,
      cursorFileName: first.fileName,
      remainingFiles: persistable.length,
      remainingBytes: totalBytes,
    );
    await _plainStore.write(_kCheckpointCursor, jsonEncode(cursor.toMap()));
  }

  Future<void> clearCheckpointQueue() async {
    await _plainStore.delete(_kCheckpointQueue);
    await _plainStore.delete(_kCheckpointCursor);
  }
}

/// Lightweight O(1) persistent checkpoint cursor (< 200 bytes JSON) used to resume
/// huge multi-thousand-file backup queues across app restarts without storing megabytes in SharedPreferences.
class CheckpointCursor {
  final int cursorCreatedAtMs;
  final String cursorFileName;
  final int remainingFiles;
  final int remainingBytes;

  const CheckpointCursor({
    required this.cursorCreatedAtMs,
    required this.cursorFileName,
    required this.remainingFiles,
    required this.remainingBytes,
  });

  factory CheckpointCursor.fromMap(Map<Object?, Object?> map) => CheckpointCursor(
        cursorCreatedAtMs: (map['cursorCreatedAtMs'] as num?)?.toInt() ?? 0,
        cursorFileName: (map['cursorFileName'] as String?) ?? '',
        remainingFiles: (map['remainingFiles'] as num?)?.toInt() ?? 0,
        remainingBytes: (map['remainingBytes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'cursorCreatedAtMs': cursorCreatedAtMs,
        'cursorFileName': cursorFileName,
        'remainingFiles': remainingFiles,
        'remainingBytes': remainingBytes,
      };

  /// Returns true if [item] is at or after this stopped cursor in global oldest-first order.
  bool includes(BackupItem item) {
    final itemMs = item.createdAt.millisecondsSinceEpoch;
    if (itemMs > cursorCreatedAtMs) return true;
    if (itemMs < cursorCreatedAtMs) return false;
    return item.fileName.compareTo(cursorFileName) >= 0;
  }
}
