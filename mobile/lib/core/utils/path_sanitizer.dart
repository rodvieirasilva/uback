/// Path & naming utilities matching the UBack Mobile Specification.
abstract final class PathSanitizer {
  /// Sanitizes a hardware/user device name into a clean lowercase folder segment.
  ///
  /// Rules:
  /// - Remove all occurrences of `'s` or `’s` (case-insensitive).
  /// - Remove the word `phone` (case-insensitive).
  /// - Remove all whitespace and invalid path characters.
  /// - Convert to lowercase.
  ///
  /// Examples:
  /// - `"Jaqueline's Phone"` -> `"jaqueline"`
  /// - `"Rodrigo's phone"` -> `"rodrigo"`
  static String sanitizeDeviceName(String raw) {
    var result = raw.trim();
    // Remove straight and curly possessive `'s`
    result = result.replaceAll(RegExp(r"['’]s\b", caseSensitive: false), '');
    // Also remove any stray `'s` even without trailing word boundary
    result = result.replaceAll(RegExp(r"['’]s", caseSensitive: false), '');
    // Remove the word "phone" (case-insensitive)
    result = result.replaceAll(RegExp(r'phone', caseSensitive: false), '');
    // Remove all whitespace
    result = result.replaceAll(RegExp(r'\s+'), '');
    // Keep only safe path characters (alphanumeric, hyphen, underscore)
    result = result.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    result = result.toLowerCase();
    return result.isEmpty ? 'android' : result;
  }

  /// Sanitizes a source folder/bucket name into a lowercase hyphenated segment.
  ///
  /// Examples:
  /// - `"Camera"` -> `"camera"`
  /// - `"Screenshots"` -> `"screenshots"`
  /// - `"WhatsApp Images"` -> `"whatsapp-images"`
  static String sanitizeSourceFolder(String raw) {
    var result = raw.trim().toLowerCase();
    result = result.replaceAll(RegExp(r'[\s_/\\]+'), '-');
    result = result.replaceAll(RegExp(r'[^a-z0-9-]'), '');
    result = result.replaceAll(RegExp(r'-{2,}'), '-');
    result = result.replaceAll(RegExp(r'^-+|-+$'), '');
    return result.isEmpty ? 'other' : result;
  }

  /// Builds the share-relative remote directory path:
  /// `{basePath}/{deviceFolder}/{sourceFolder...}/{YYYY}/{MM}`
  static String buildRelativeRemoteDir({
    required String basePath,
    required String deviceFolder,
    required String sourceFolder,
    required DateTime createdAt,
  }) {
    final yyyy = createdAt.year.toString().padLeft(4, '0');
    final mm = createdAt.month.toString().padLeft(2, '0');
    final sourceSegments = sourceFolder
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .map(sanitizeSourceFolder)
        .toList();
    final parts = <String>[
      ...basePath.replaceAll('\\', '/').split('/').where((s) => s.trim().isNotEmpty),
      sanitizeDeviceName(deviceFolder),
      if (sourceSegments.isEmpty) 'other' else ...sourceSegments,
      yyyy,
      mm,
    ];
    return parts.join('/');
  }

  /// Appends a short hash suffix before the file extension to avoid overwriting
  /// a different file with the same name.
  static String disambiguateFileName(String fileName, String shortHash) {
    final dot = fileName.lastIndexOf('.');
    if (dot > 0 && dot < fileName.length - 1) {
      return '${fileName.substring(0, dot)}_$shortHash${fileName.substring(dot)}';
    }
    return '${fileName}_$shortHash';
  }

  /// Formats byte counts cleanly for lightweight text-only UI counters.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var idx = 0;
    while (value >= 1024 && idx < units.length - 1) {
      value /= 1024;
      idx++;
    }
    if (idx == 0) return '$bytes B';
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[idx]}';
  }
}
