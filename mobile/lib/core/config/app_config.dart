import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/path_sanitizer.dart';

/// Compile-time defaults injected via `--dart-define-from-file=dart_defines.json`
/// generated from local (gitignored) `config.toml`.
class CompileTimeDefaults {
  static const String host = String.fromEnvironment('UBACK_SMB_HOST', defaultValue: '');
  static const String portStr = String.fromEnvironment('UBACK_SMB_PORT', defaultValue: '445');
  static const String share = String.fromEnvironment('UBACK_SMB_SHARE', defaultValue: '');
  static const String basePath = String.fromEnvironment('UBACK_SMB_BASE_PATH', defaultValue: '');
  static const String username = String.fromEnvironment('UBACK_SMB_USERNAME', defaultValue: '');
  static const String password = String.fromEnvironment('UBACK_SMB_PASSWORD', defaultValue: '');
  static const String domain = String.fromEnvironment('UBACK_SMB_DOMAIN', defaultValue: '');
  static const String e2eDeviceOverride =
      String.fromEnvironment('UBACK_E2E_DEVICE_OVERRIDE', defaultValue: '');
  static const String appVersion =
      String.fromEnvironment('UBACK_APP_VERSION', defaultValue: '1.0.0+1');

  static AppSettings toSettings() {
    return AppSettings(
      host: host,
      port: int.tryParse(portStr) ?? 445,
      share: share,
      basePath: basePath,
      username: username,
      password: password,
      domain: domain,
      deviceFolderOverride: e2eDeviceOverride,
      enabledSourceIds: const {'camera', 'screenshots'},
    );
  }
}

class AppSettings {
  final String host;
  final int port;
  final String share;
  final String basePath;
  final String username;
  final String password;
  final String domain;
  final String deviceFolderOverride;
  final Set<String> enabledSourceIds;

  const AppSettings({
    required this.host,
    required this.port,
    required this.share,
    required this.basePath,
    required this.username,
    required this.password,
    required this.domain,
    required this.deviceFolderOverride,
    this.enabledSourceIds = const {'camera', 'screenshots'},
  });

  bool isSourceEnabled(String sourceId) => enabledSourceIds.contains(sourceId);

  bool get isConfigured => host.trim().isNotEmpty && share.trim().isNotEmpty;

  String resolvedDeviceFolder(String detectedDeviceName) {
    final raw = deviceFolderOverride.trim().isNotEmpty
        ? deviceFolderOverride.trim()
        : detectedDeviceName;
    return PathSanitizer.sanitizeDeviceName(raw);
  }

  String destinationPreview(String detectedDeviceName) {
    final h = host.trim().isEmpty ? '<host>' : host.trim();
    final s = share.trim().isEmpty ? '<share>' : share.trim();
    final b = basePath.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    final d = resolvedDeviceFolder(detectedDeviceName);
    final prefix = b.isEmpty ? 'smb://$h:$port/$s/$d' : 'smb://$h:$port/$s/$b/$d';
    final sortedSources = enabledSourceIds.toList()..sort();
    final sourceSeg = switch (sortedSources.length) {
      0 => '<select-source>',
      1 => sortedSources.first,
      _ => '{${sortedSources.join('|')}}',
    };
    return '$prefix/$sourceSeg/YYYY/MM';
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
    String? host,
    int? port,
    String? share,
    String? basePath,
    String? username,
    String? password,
    String? domain,
    String? deviceFolderOverride,
    Set<String>? enabledSourceIds,
  }) {
    return AppSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      share: share ?? this.share,
      basePath: basePath ?? this.basePath,
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      deviceFolderOverride: deviceFolderOverride ?? this.deviceFolderOverride,
      enabledSourceIds: enabledSourceIds ?? this.enabledSourceIds,
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

/// Manages runtime settings persistence with fallback to compile-time defaults.
class AppSettingsRepository {
  static const _kHost = 'uback_smb_host';
  static const _kPort = 'uback_smb_port';
  static const _kShare = 'uback_smb_share';
  static const _kBasePath = 'uback_smb_base_path';
  static const _kDomain = 'uback_smb_domain';
  static const _kDeviceOverride = 'uback_device_override';
  static const _kEnabledSources = 'uback_enabled_sources';

  static const _kSecretUser = 'uback_smb_username';
  static const _kSecretPass = 'uback_smb_password';

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

  Future<AppSettings> load() async {
    final host = await _plainStore.read(_kHost);
    final portStr = await _plainStore.read(_kPort);
    final share = await _plainStore.read(_kShare);
    final basePath = await _plainStore.read(_kBasePath);
    final domain = await _plainStore.read(_kDomain);
    final deviceOverride = await _plainStore.read(_kDeviceOverride);
    final enabledSourcesRaw = await _plainStore.read(_kEnabledSources);

    final enabledSourceIds = enabledSourcesRaw != null
        ? enabledSourcesRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
        : _defaults.enabledSourceIds;

    String? username;
    String? password;
    try {
      username = await _secureStore.read(_kSecretUser);
      password = await _secureStore.read(_kSecretPass);
    } catch (_) {
      // Fallback safely to compile-time defaults if keystore read fails on fresh/emulator device
    }

    return AppSettings(
      host: host ?? _defaults.host,
      port: int.tryParse(portStr ?? '') ?? _defaults.port,
      share: share ?? _defaults.share,
      basePath: basePath ?? _defaults.basePath,
      username: username ?? _defaults.username,
      password: password ?? _defaults.password,
      domain: domain ?? _defaults.domain,
      deviceFolderOverride: deviceOverride ?? _defaults.deviceFolderOverride,
      enabledSourceIds: enabledSourceIds,
    );
  }

  Future<void> save(AppSettings settings) async {
    await _plainStore.write(_kHost, settings.host.trim());
    await _plainStore.write(_kPort, settings.port.toString());
    await _plainStore.write(_kShare, settings.share.trim());
    await _plainStore.write(_kBasePath, settings.basePath.trim());
    await _plainStore.write(_kDomain, settings.domain.trim());
    await _plainStore.write(_kDeviceOverride, settings.deviceFolderOverride.trim());
    final sortedSources = settings.enabledSourceIds.toList()..sort();
    await _plainStore.write(_kEnabledSources, sortedSources.join(','));

    await _secureStore.write(_kSecretUser, settings.username.trim());
    await _secureStore.write(_kSecretPass, settings.password);
  }

  Future<AppSettings> resetToDefaults() async {
    for (final key in [
      _kHost,
      _kPort,
      _kShare,
      _kBasePath,
      _kDomain,
      _kDeviceOverride,
      _kEnabledSources,
    ]) {
      await _plainStore.delete(key);
    }
    try {
      await _secureStore.delete(_kSecretUser);
      await _secureStore.delete(_kSecretPass);
    } catch (_) {}
    return _defaults;
  }
}
