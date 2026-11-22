import 'dart:convert';

import 'app_config.dart';

/// Configuration for an SMB NAS backup destination.
class SmbDestinationConfig {
  final String id;
  final String name;
  final bool enabled;
  final String host;
  final int port;
  final String share;
  final String basePath;
  final String username;
  final String password;
  final String domain;

  const SmbDestinationConfig({
    required this.id,
    required this.name,
    this.enabled = true,
    required this.host,
    this.port = 445,
    required this.share,
    this.basePath = '',
    this.username = '',
    this.password = '',
    this.domain = '',
  });

  bool get isConfigured => host.trim().isNotEmpty && share.trim().isNotEmpty;

  String get displaySummary {
    final cleanBase = basePath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    final suffix = cleanBase.isEmpty ? '' : '/$cleanBase';
    final portPart = port == 445 ? '' : ':$port';
    return 'smb://${host.trim()}$portPart/${share.trim()}$suffix';
  }

  SmbDestinationConfig copyWith({
    String? id,
    String? name,
    bool? enabled,
    String? host,
    int? port,
    String? share,
    String? basePath,
    String? username,
    String? password,
    String? domain,
  }) =>
      SmbDestinationConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        host: host ?? this.host,
        port: port ?? this.port,
        share: share ?? this.share,
        basePath: basePath ?? this.basePath,
        username: username ?? this.username,
        password: password ?? this.password,
        domain: domain ?? this.domain,
      );

  /// Projects this destination onto [base] so native SMB calls can execute against it.
  AppSettings toAppSettings(AppSettings base) => base.copyWith(
        destinationType: 'smb_nas',
        host: host.trim(),
        port: port,
        share: share.trim(),
        basePath: basePath.trim(),
        username: username.trim(),
        password: password,
        domain: domain.trim(),
      );

  /// Public metadata (no credentials) for plain SharedPreferences storage.
  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'host': host,
        'port': port,
        'share': share,
        'basePath': basePath,
        'domain': domain,
      };

  factory SmbDestinationConfig.fromPublicJson(
    Map<String, dynamic> map, {
    String username = '',
    String password = '',
  }) =>
      SmbDestinationConfig(
        id: (map['id'] ?? '').toString(),
        name: (map['name'] ?? '').toString(),
        enabled: map['enabled'] != false,
        host: (map['host'] ?? '').toString(),
        port: (map['port'] is int)
            ? map['port'] as int
            : int.tryParse((map['port'] ?? '445').toString()) ?? 445,
        share: (map['share'] ?? '').toString(),
        basePath: (map['basePath'] ?? '').toString(),
        domain: (map['domain'] ?? '').toString(),
        username: username,
        password: password,
      );

  static String encodePublicList(List<SmbDestinationConfig> list) =>
      jsonEncode(list.map((e) => e.toPublicJson()).toList());

  static List<Map<String, dynamic>> decodePublicMaps(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }
}
