import 'media_exporter.dart';

/// Orders discovered items oldest-first and applies optional file-count or byte-size batch limits.
abstract final class BackupPlanner {
  static List<BackupItem> plan(List<BackupItem> items, {BackupLimit? limit}) {
    final sorted = List<BackupItem>.of(items)
      ..sort((a, b) {
        final cmpDate = a.createdAt.compareTo(b.createdAt);
        if (cmpDate != 0) return cmpDate;
        final cmpName = a.fileName.compareTo(b.fileName);
        if (cmpName != 0) return cmpName;
        return a.id.compareTo(b.id);
      });

    if (limit == null || limit.isUnlimited) {
      return sorted;
    }

    var result = sorted;

    if (limit.maxFiles != null) {
      final cap = limit.maxFiles!;
      if (cap <= 0) return const [];
      if (result.length > cap) {
        result = result.sublist(0, cap);
      }
    }

    if (limit.maxBytes != null) {
      final capBytes = limit.maxBytes!;
      if (capBytes <= 0) return const [];
      final bounded = <BackupItem>[];
      var accumulated = 0;
      for (final item in result) {
        if (bounded.isEmpty) {
          // Always include at least the single oldest file so backup never deadlocks
          // if one video is larger than the chosen MB budget.
          bounded.add(item);
          accumulated += item.sizeBytes;
          if (accumulated >= capBytes) break;
        } else if (accumulated + item.sizeBytes <= capBytes) {
          bounded.add(item);
          accumulated += item.sizeBytes;
        } else {
          break;
        }
      }
      result = bounded;
    }

    return result;
  }
}
