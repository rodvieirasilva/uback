import 'dart:convert';

import '../utils/path_sanitizer.dart';

/// User-defined folder under external storage (e.g. `DJI/Media`, `GoPro`, `Scans`)
/// exposed as a first-class toggleable [MediaSource].
class CustomFolderConfig {
  final String id;
  final String slug;
  final String displayName;
  final String relativePath;

  const CustomFolderConfig({
    required this.id,
    required this.slug,
    required this.displayName,
    required this.relativePath,
  });

  factory CustomFolderConfig.create({
    required String relativePath,
    String? displayName,
  }) {
    final cleanRel = relativePath
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/storage/emulated/\d+/'), '')
        .replaceFirst(RegExp(r'^/sdcard/'), '')
        .replaceAll(RegExp(r'^/+|/+$'), '');
    final fallbackName = cleanRel.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'Custom';
    final name = (displayName != null && displayName.trim().isNotEmpty)
        ? displayName.trim()
        : fallbackName;
    final slug = PathSanitizer.sanitizeSourceFolder(cleanRel.replaceAll('/', '-'));
    return CustomFolderConfig(
      id: 'custom.$slug',
      slug: slug,
      displayName: name,
      relativePath: cleanRel,
    );
  }

  factory CustomFolderConfig.fromMap(Map<String, dynamic> map) => CustomFolderConfig(
        id: (map['id'] as String?) ?? '',
        slug: (map['slug'] as String?) ?? 'custom',
        displayName: (map['displayName'] as String?) ?? 'Custom',
        relativePath: (map['relativePath'] as String?) ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'slug': slug,
        'displayName': displayName,
        'relativePath': relativePath,
      };

  static String encodeList(List<CustomFolderConfig> folders) =>
      jsonEncode(folders.map((f) => f.toMap()).toList());

  static List<CustomFolderConfig> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(CustomFolderConfig.fromMap)
          .where((f) => f.id.isNotEmpty && f.relativePath.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
